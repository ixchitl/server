#!/usr/bin/env bash
# e2e 测试公共函数库
# 被 test_*.sh source，提供 token 管理、断言、工具函数

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# ====== Token 管理 ======

# 用 admin basicAuth 直接创建一个 client，返回 clientToken
# 不用 /auth/local/login，因为那条路径要靠 cookie 传 token，curl 处理起来更脆
get_admin_client_token() {
  local name="e2e-admin-${TEST_RUN_ID}-$RANDOM"
  local resp
  resp=$(curl -s -X POST "$BASE/client" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$name\"}")
  echo "$resp" | jq -r '.token'
}

# 用 clientToken 创建应用，返回 appToken
create_app_token() {
  local client_token=$1
  local name=${2:-"E2E App ${TEST_RUN_ID}"}
  local resp
  resp=$(curl -s -X POST "$BASE/application" \
    -H "X-Gotify-Key: $client_token" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$name\",\"description\":\"e2e test\"}")
  echo "$resp" | jq -r '.token'
}

# 用 clientToken 创建应用，返回应用 ID
create_app_id() {
  local client_token=$1
  local name=${2:-"E2E App ${TEST_RUN_ID}"}
  local resp
  resp=$(curl -s -X POST "$BASE/application" \
    -H "X-Gotify-Key: $client_token" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$name\",\"description\":\"e2e test\"}")
  echo "$resp" | jq -r '.id'
}

# 创建应用，一次返回 "id token"
# 🔴 必须用这个而不是分别调 create_app_id + create_app_token——
#    那样会建出两个不同的应用，导致「发消息用 A 的 token、删除 B」这类假失败
# 用法：read -r APP_ID APP_TOKEN <<< "$(create_app "$TOK" "名字")"
create_app() {
  local client_token=$1
  local name=${2:-"E2E App ${TEST_RUN_ID}"}
  curl -s -X POST "$BASE/application" \
    -H "X-Gotify-Key: $client_token" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$name\",\"description\":\"e2e test\"}" \
    | jq -r '"\(.id) \(.token)"'
}

# 创建一个测试用户，返回 user id
create_test_user() {
  local admin_token=$1
  local username=$2
  local password=${3:-"testpass123"}
  local resp
  resp=$(curl -s -X POST "$BASE/user" \
    -H "X-Gotify-Key: $admin_token" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$username\",\"pass\":\"$password\",\"admin\":false}")
  echo "$resp" | jq -r '.id'
}

# 用 test 用户登录获取 clientToken
get_user_client_token() {
  local username=$1
  local password=${2:-"testpass123"}
  local name="e2e-user-${TEST_RUN_ID}-$RANDOM"
  local resp
  resp=$(curl -s -X POST "$BASE/client" \
    -u "$username:$password" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$name\"}")
  echo "$resp" | jq -r '.token'
}

# ====== HTTP 请求封装 ======

# 发 GET 请求，返回 "body\nstatus_code"
http_get() {
  local url=$1
  local token=${2:-}
  local hdr=""
  [ -n "$token" ] && hdr="-H X-Gotify-Key:$token"
  curl -s -w '\n%{http_code}' $hdr "$BASE$url"
}

# 发 POST 请求
http_post() {
  local url=$1
  local body=$2
  local token=${3:-}
  local hdr="-H Content-Type:application/json"
  [ -n "$token" ] && hdr="$hdr -H X-Gotify-Key:$token"
  curl -s -w '\n%{http_code}' -X POST "$BASE$url" $hdr -d "$body"
}

# 发 PUT 请求
http_put() {
  local url=$1
  local body=$2
  local token=${3:-}
  local hdr="-H Content-Type:application/json"
  [ -n "$token" ] && hdr="$hdr -H X-Gotify-Key:$token"
  curl -s -w '\n%{http_code}' -X PUT "$BASE$url" $hdr -d "$body"
}

# 发 DELETE 请求
http_delete() {
  local url=$1
  local token=${2:-}
  local hdr=""
  [ -n "$token" ] && hdr="-H X-Gotify-Key:$token"
  curl -s -w '\n%{http_code}' -X DELETE "$BASE$url" $hdr
}

# 用 basicAuth 发请求
# Login 端点 consumes application/x-www-form-urlencoded，用 form 编码
http_basic() {
  local method=$1
  local url=$2
  local body=${3:-}
  local user=$4
  local pass=$5
  if [ "$method" = "GET" ] || [ "$method" = "DELETE" ]; then
    curl -s -w '\n%{http_code}' -X "$method" "$BASE$url" -u "$user:$pass"
  else
    curl -s -w '\n%{http_code}' -X "$method" "$BASE$url" -u "$user:$pass" \
      -H 'Content-Type: application/x-www-form-urlencoded' -d "$body"
  fi
}

# ====== elevated 路由专用 ======

# 🔴 以下 5 条路由必须提权，普通 clientToken 调会得 403
#    "session not elevated, use basic auth or call /client:elevate"
#    权威清单见 router/router.go 的 clientElevated 分组：
#      POST   /client/:id/elevate
#      DELETE /application/:id
#      PUT    /application/:id/security
#      DELETE /client/:id
#      POST   /current/user/password
# 实测结论：直接用 admin basicAuth 最简且可靠（返 200）；
#          走 /client/:id/elevate 提权路径实测返 400，没必要绕
http_elevated() {
  local method=$1 url=$2 body=${3:-}
  if [ -z "$body" ]; then
    curl -s -w '\n%{http_code}' -X "$method" "$BASE$url" -u "$ADMIN_USER:$ADMIN_PASS"
  else
    curl -s -w '\n%{http_code}' -X "$method" "$BASE$url" -u "$ADMIN_USER:$ADMIN_PASS" \
      -H 'Content-Type: application/json' -d "$body"
  fi
}

# ====== 断言函数 ======

# 提取 HTTP 状态码（最后一行）
get_code() {
  echo "$1" | tail -1
}

# 提取响应 body（去掉最后一行状态码）
get_body() {
  echo "$1" | head -n -1
}

# 断言 HTTP 状态码
assert_http_code() {
  local resp=$1 expected=$2
  local actual=$(get_code "$resp")
  [ "$actual" = "$expected" ] || fail "HTTP code: expected $expected, got $actual
  Body: $(get_body "$resp")"
}

# 断言 JSON 字段值
assert_json() {
  local jq_expr=$1 expected=$2 resp=$3
  local body=$(get_body "$resp")
  local actual=$(echo "$body" | jq -r "$jq_expr" 2>/dev/null)
  [ "$actual" = "$expected" ] || fail "JSON $jq_expr: expected '$expected', got '$actual'
  Body: $body"
}

# 断言 JSON 字段非空
assert_json_not_empty() {
  local jq_expr=$1 resp=$2
  local body=$(get_body "$resp")
  local actual=$(echo "$body" | jq -r "$jq_expr" 2>/dev/null)
  [ -n "$actual" ] && [ "$actual" != "null" ] || fail "JSON $jq_expr: expected non-empty, got '$actual'"
}

# 断言响应体包含某字符串
assert_contains() {
  local needle=$1 resp=$2
  local body=$(get_body "$resp")
  echo "$body" | grep -q "$needle" || fail "Expected '$needle' in body, but not found.
  Body: $body"
}

# 断言响应体不包含某字符串
assert_not_contains() {
  local needle=$1 resp=$2
  local body=$(get_body "$resp")
  echo "$body" | grep -q "$needle" && fail "Found '$needle' but should not be present.
  Body: $body" || true
}

# 断言 JSON 字段不存在或为空
# 🔴 不能直接拿 jq -r 的输出跟 "" 比：字段缺失时 jq -r 输出的是字面量 null，
#    跟空串比会判成「非空」——这是一个真实踩过的假失败（token 安全类用例）
assert_json_empty() {
  local jq_expr=$1 resp=$2
  local body=$(get_body "$resp")
  local actual=$(echo "$body" | jq -r "$jq_expr // \"\"" 2>/dev/null)
  [ -z "$actual" ] || fail "JSON $jq_expr: expected empty/absent, got '$actual'
  Body: $body"
}

# 断言 JSON 数组长度
assert_array_length() {
  local expected=$1 resp=$2
  local body=$(get_body "$resp")
  local actual=$(echo "$body" | jq 'length' 2>/dev/null)
  [ "$actual" = "$expected" ] || fail "Array length: expected $expected, got $actual
  Body: $body"
}

# ====== 结果函数 ======

pass() {
  echo "  ✅ PASS: $1"
}

fail() {
  echo "  ❌ FAIL: $1" >&2
  exit 1
}

# ====== 清理与 trap ======

# 删除指定 token 的所有应用和消息（脚本中途想清场时用）
cleanup_user_data() {
  local token=$1
  curl -s -o /dev/null -X DELETE "$BASE/message" -H "X-Gotify-Key: $token" 2>/dev/null || true
  curl -s -H "X-Gotify-Key: $token" "$BASE/application" 2>/dev/null \
    | jq -r '.[]?.id' 2>/dev/null | while read -r id; do
    [ -n "$id" ] && [ "$id" != "null" ] && \
      curl -s -o /dev/null -u "$ADMIN_USER:$ADMIN_PASS" \
        -X DELETE "$BASE/application/$id" 2>/dev/null || true
  done
}

# 删除所有 client（会让正在使用的 token 失效，只能最后做）
cleanup_clients() {
  curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/client" 2>/dev/null \
    | jq -r '.[]?.id' 2>/dev/null | while read -r id; do
    [ -n "$id" ] && [ "$id" != "null" ] && \
      curl -s -o /dev/null -u "$ADMIN_USER:$ADMIN_PASS" \
        -X DELETE "$BASE/client/$id" 2>/dev/null || true
  done
}

# 🔴 统一 teardown：由 trap 触发，保证断言失败 / Ctrl-C / 超时中断时也会执行
#
# 设计要点：
#   ① 全程用 admin basicAuth，不依赖脚本内的 token 变量——
#      即使脚本在拿 token 之前就挂了，清理照样能跑
#   ② 幂等：重复调用无副作用，所有请求失败均忽略
#   ③ 保留 admin 用户（最后一个 admin 受保护，删不掉）
#   ④ client 放最后删，因为删了会让前面几步用的 token 失效
#
# ⚠️ 会清空全部测试数据，因此用例必须串行执行（run.sh 保证这一点）
_TEARDOWN_DONE=0

teardown() {
  local rc=$?
  [ "$_TEARDOWN_DONE" = "1" ] && return $rc
  _TEARDOWN_DONE=1
  set +e

  # ① 消息（一次删全部）
  curl -s -o /dev/null -u "$ADMIN_USER:$ADMIN_PASS" -X DELETE "$BASE/message"

  # ② 应用（DELETE /application/:id 需提权，所以用 basicAuth）
  curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/application" \
    | jq -r '.[]?.id' 2>/dev/null | while read -r id; do
    [ -n "$id" ] && curl -s -o /dev/null -u "$ADMIN_USER:$ADMIN_PASS" \
      -X DELETE "$BASE/application/$id"
  done

  # ③ 非 admin 用户
  curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user" \
    | jq -r --arg admin "$ADMIN_USER" '.[]? | select(.name != $admin) | .id' 2>/dev/null \
    | while read -r id; do
    [ -n "$id" ] && curl -s -o /dev/null -u "$ADMIN_USER:$ADMIN_PASS" \
      -X DELETE "$BASE/user/$id"
  done

  # ④ client（删完 token 就废了，放最后）
  curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/client" \
    | jq -r '.[]?.id' 2>/dev/null | while read -r id; do
    [ -n "$id" ] && curl -s -o /dev/null -u "$ADMIN_USER:$ADMIN_PASS" \
      -X DELETE "$BASE/client/$id"
  done

  # ⑤ 脚本可定义 custom_teardown 补充自己的清理
  if declare -f custom_teardown >/dev/null 2>&1; then
    custom_teardown
  fi

  return $rc
}

# source 本文件即自动注册，脚本无需重复写 trap
trap teardown EXIT INT TERM

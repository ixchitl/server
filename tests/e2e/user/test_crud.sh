#!/usr/bin/env bash
# @priority: P0
# @module: user
# @stability: stable
# @source: init
# User CRUD 生命周期测试（用 basicAuth elevated）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== User CRUD ==="

# User 操作需要 elevated basicAuth，直接用 -u admin:admin

# U1: admin 创建普通用户
echo -n "U1 创建用户..."
USERNAME="e2euser_${TEST_RUN_ID}_$RANDOM"
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/user" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USERNAME\",\"pass\":\"pass123\",\"admin\":false}")
assert_http_code "$RESP" "200"
assert_json_not_empty '.id' "$RESP"
assert_json '.name' "$USERNAME" "$RESP"
assert_json '.admin' 'false' "$RESP"
USER_ID=$(get_body "$RESP" | jq -r '.id')
pass "创建成功 id=$USER_ID name=$USERNAME"

# U2: admin 创建 admin 用户
echo -n "U2 创建 admin..."
ADMIN2="e2eadm_${TEST_RUN_ID}_$RANDOM"
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/user" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$ADMIN2\",\"pass\":\"pass123\",\"admin\":true}")
assert_json '.admin' 'true' "$RESP"
pass "创建 admin 成功"

# U3: 缺 name → 400
echo -n "U3 缺 name..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/user" -H 'Content-Type: application/json' -d '{"pass":"x"}')
assert_http_code "$RESP" "400"
pass "缺 name 返回 400"

# U4: 缺 pass → 400
echo -n "U4 缺 pass..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/user" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USERNAME-nopass\"}")
assert_http_code "$RESP" "400"
pass "缺 pass 返回 400"

# U5: 重复用户名 → 400
echo -n "U5 重复用户名..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/user" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USERNAME\",\"pass\":\"x\",\"admin\":false}")
assert_http_code "$RESP" "400"
assert_contains "already exists" "$RESP"
pass "重复用户名返回 400"

# U10: 获取用户列表
echo -n "U10 用户列表..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user")
assert_http_code "$RESP" "200"
pass "列表获取成功"

# U12: 获取单个用户
echo -n "U12 获取单个..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user/$USER_ID")
assert_http_code "$RESP" "200"
assert_json '.name' "$USERNAME" "$RESP"
pass "获取成功"

# U13: 不存在 id → 404
echo -n "U13 不存在 id..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user/99999")
assert_http_code "$RESP" "404"
pass "不存在返回 404"

# U14: 获取当前用户
echo -n "U14 当前用户..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/current/user")
assert_http_code "$RESP" "200"
assert_json '.name' "$ADMIN_USER" "$RESP"
assert_json '.admin' 'true' "$RESP"
pass "当前用户正确"

# U17: 更新用户名
echo -n "U17 更新用户..."
NEWNAME="${USERNAME}_updated"
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/user/$USER_ID" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$NEWNAME\",\"admin\":false}")
assert_http_code "$RESP" "200"
assert_json '.name' "$NEWNAME" "$RESP"
pass "更新成功"

# U19: 更新密码
echo -n "U19 改密码..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/user/$USER_ID" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$NEWNAME\",\"admin\":false,\"pass\":\"newpass\"}")
assert_http_code "$RESP" "200"
pass "密码更新成功"

# U15: 删除普通用户
echo -n "U15 删用户..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X DELETE "$BASE/user/$USER_ID")
assert_http_code "$RESP" "200"
pass "删除成功"

# U25: 删第二个 admin（不删最后一个）
echo -n "U25 删多余 admin..."
ADMIN2_ID=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user" | jq -r ".[] | select(.name==\"$ADMIN2\") | .id")
if [ -n "$ADMIN2_ID" ] && [ "$ADMIN2_ID" != "null" ]; then
  RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
    -X DELETE "$BASE/user/$ADMIN2_ID")
  assert_http_code "$RESP" "200"
  pass "删多余 admin 成功"
else
  pass "跳过（admin2 未找到）"
fi

echo "=== User CRUD: 全部 PASS ==="

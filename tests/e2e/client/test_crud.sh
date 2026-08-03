#!/usr/bin/env bash
# @priority: P0
# @module: client
# @stability: stable
# @source: init
# Client CRUD 生命周期测试
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Client CRUD ==="

ADMIN_TOKEN=$(get_admin_client_token)

# C1: 正常创建
echo -n "C1 创建 client..."
RESP=$(http_post /client '{"name":"My Phone"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json_not_empty '.id' "$RESP"
assert_json_not_empty '.token' "$RESP"
assert_json '.name' 'My Phone' "$RESP"
CLIENT_ID=$(get_body "$RESP" | jq -r '.id')
pass "创建成功 id=$CLIENT_ID"

# C2: 带过期时间
echo -n "C2 带过期时间..."
RESP=$(http_post /client '{"name":"Temp","expiresAfterInactivitySeconds":3600}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "带过期时间创建成功"

# C3: 永不过期
echo -n "C3 永不过期..."
RESP=$(http_post /client '{"name":"Perm","expiresAfterInactivitySeconds":0}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "永不过期创建成功"

# C4: 缺 name → 400
echo -n "C4 缺 name..."
RESP=$(http_post /client '{}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "400"
pass "缺 name 返回 400"

# C7: 获取列表
echo -n "C7 获取列表..."
RESP=$(http_get /client "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
COUNT=$(get_body "$RESP" | jq 'length')
[ "$COUNT" -ge 3 ] || fail "应至少 3 个 client，实际 $COUNT"
pass "列表 $COUNT 个 client"

# C8: token 被清除
# 源码：model/client.go 的 Token 字段带 json:"token,omitempty"，
#       列表接口不返回它 → jq 取到的是字面量 null，不是空串
echo -n "C8 token 安全..."
RESP=$(http_get /client "$ADMIN_TOKEN")
assert_json_empty '.[0].token' "$RESP"
pass "列表 token 已清除"

# C10: 更新名称
echo -n "C10 更新名称..."
RESP=$(http_put /client/$CLIENT_ID '{"name":"New Name"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json '.name' 'New Name' "$RESP"
pass "更新成功"

# C12: 不存在 id → 404
echo -n "C12 不存在 id..."
RESP=$(http_put /client/99999 '{"name":"X"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "404"
pass "不存在返回 404"

# C14: 删除 client（DELETE /client/:id 需提权）
echo -n "C14 删除 client..."
RESP=$(http_elevated DELETE "/client/$CLIENT_ID")
assert_http_code "$RESP" "200"
pass "删除成功"

# C15: 删后 token 失效
# 源码：client.go DeleteClient() → NotifyDeleted + DeleteClientByID
#   client 被删后 token 不再存在 → handleClient → nil → skip → abort401
echo -n "C15 token 失效..."
# 创建一个专门的 client 保存其 token
RESP=$(http_post /client '{"name":"Delete Token Test"}' "$ADMIN_TOKEN")
DEL_CLIENT_ID=$(get_body "$RESP" | jq -r '.id')
DEL_CLIENT_TOKEN=$(get_body "$RESP" | jq -r '.token')
# 先验证 token 可用
RESP=$(http_get /application "$DEL_CLIENT_TOKEN")
assert_http_code "$RESP" "200"
# 删除该 client
RESP=$(http_elevated DELETE "/client/$DEL_CLIENT_ID")
assert_http_code "$RESP" "200"
# 验证旧 token 失效
RESP=$(http_get /application "$DEL_CLIENT_TOKEN")
assert_http_code "$RESP" "401"
pass "删后 token 失效（401）"

# C16: 不存在 id 删除 → 404
echo -n "C16 不存在 id..."
RESP=$(http_elevated DELETE "/client/99999")
assert_http_code "$RESP" "404"
pass "不存在返回 404"

# C18: 完整生命周期（创建→使用→更新→删除→token失效）
echo -n "C18 完整生命周期..."
RESP=$(http_post /client '{"name":"Lifecycle"}' "$ADMIN_TOKEN")
LC_ID=$(get_body "$RESP" | jq -r '.id')
LC_TOKEN=$(get_body "$RESP" | jq -r '.token')
# 使用
RESP=$(http_get /application "$LC_TOKEN")
assert_http_code "$RESP" "200"
# 更新
RESP=$(http_put /client/$LC_ID '{"name":"Updated"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json '.name' 'Updated' "$RESP"
# 删除
RESP=$(http_elevated DELETE "/client/$LC_ID")
assert_http_code "$RESP" "200"
# 验证 token 失效
RESP=$(http_get /application "$LC_TOKEN")
assert_http_code "$RESP" "401"
pass "完整生命周期通过（删后 401）"

echo "=== Client CRUD: 全部 PASS ==="

#!/usr/bin/env bash
# @priority: P0
# @module: auth
# @stability: stable
# @source: init
# 4 级认证权限矩阵测试（8 条用例）
# 源码依据：auth/authentication.go
#   RequireClient → handleClient→nil→skip + handleUser→skip → abort401
#   RequireElevatedClient → 同上 + checkClientElevated→NotElevated→403
#   RequireAdmin → checkUserAdmin→Forbidden→403
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Auth 权限矩阵 ==="

# 准备 tokens
ADMIN_TOKEN=$(get_admin_client_token)
APP_TOKEN=$(create_app_token "$ADMIN_TOKEN" "Matrix Test App")

# X1: appToken 发消息 → 200
echo -n "X1 appToken POST /message..."
RESP=$(http_post /message '{"message":"hello"}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
pass "appToken 能发消息"

# X2: appToken 读消息 → 401（RequireClient 路由，appToken 不被识别为 clientToken）
echo -n "X2 appToken GET /message..."
RESP=$(http_get /message "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "appToken 不能读消息（401）"

# X3: appToken 创建应用 → 401（RequireClient 路由）
echo -n "X3 appToken POST /application..."
RESP=$(http_post /application '{"name":"Hack"}' "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "appToken 不能管理应用（401）"

# X4: appToken 删应用 → 401（RequireElevatedClient 路由，appToken 不被识别）
echo -n "X4 appToken DELETE /application/1..."
RESP=$(http_delete /application/1 "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "appToken 不能删应用（401）"

# X5: 无认证 POST /message → 401（RequireApplicationOrClient 无匹配）
echo -n "X5 无认证 POST /message..."
RESP=$(http_post /message '{"message":"hi"}' "")
assert_http_code "$RESP" "401"
pass "无认证不能发消息（401）"

# X6: 无认证 POST /application → 401（RequireClient 无匹配）
echo -n "X6 无认证 POST /application..."
RESP=$(http_post /application '{"name":"X"}' "")
assert_http_code "$RESP" "401"
pass "无认证不能管理应用（401）"

# X7: 非admin clientToken GET /user → 403（RequireAdmin → checkUserAdmin→Forbidden）
echo -n "X7 非admin GET /user..."
# 创建非admin用户
USERNAME="e2enonadmin_${TEST_RUN_ID}_$RANDOM"
curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$BASE/user" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USERNAME\",\"pass\":\"pass123\",\"admin\":false}" > /dev/null
NONADMIN_TOKEN=$(get_user_client_token "$USERNAME" "pass123")
RESP=$(http_get /user "$NONADMIN_TOKEN")
assert_http_code "$RESP" "403"
pass "非admin 不能访问 /user（403）"

# X8: clientToken DELETE /application → 403（RequireElevatedClient → checkClientElevated→NotElevated）
echo -n "X8 非提权 DELETE /application..."
RESP=$(http_delete /application/1 "$ADMIN_TOKEN")
assert_http_code "$RESP" "403"
pass "非提权 clientToken 不能删应用（403）"


echo "=== Auth 权限矩阵: 全部 PASS ==="

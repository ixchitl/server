#!/usr/bin/env bash
# @priority: P0
# @module: auth
# @stability: stable
# @source: init
# 登录/登出生命周期测试（11 条用例）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Auth 登录/登出 ==="

# A1: 正确凭据登录
echo -n "A1 正确凭据登录..."
RESP=$(http_basic POST /auth/local/login "name=e2e-login-test" "$ADMIN_USER" "$ADMIN_PASS")
assert_http_code "$RESP" "200"
assert_json '.name' "$ADMIN_USER" "$RESP"
assert_json '.admin' 'true' "$RESP"
assert_json_not_empty '.clientId' "$RESP"
pass "登录成功，返回 clientId"

# A2: 登录后 token 能用（用 login 返回的 clientId 获取 admin clientToken）
echo -n "A2 admin clientToken 可用..."
ADMIN_TOKEN=$(get_admin_client_token)
RESP=$(http_get /application "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "clientToken 调 GET /application 成功"

# A3: 错误密码
echo -n "A3 错误密码登录..."
RESP=$(http_basic POST /auth/local/login "name=x" "$ADMIN_USER" "wrongpass")
assert_http_code "$RESP" "401"
pass "错误密码返回 401"

# A4: 不存在的用户
echo -n "A4 不存在的用户..."
RESP=$(http_basic POST /auth/local/login "name=x" "nosuchuser123" "pass")
assert_http_code "$RESP" "401"
pass "不存在用户返回 401"

# A5: 无 Basic Auth header
echo -n "A5 无认证 header..."
RESP=$(http_post /auth/local/login '{"name":"x"}' "")
assert_http_code "$RESP" "401"
pass "无 header 返回 401"

# A6: 空用户名（Basic Auth 解析失败）
# 源码：session.go Login() → ctx.Request.BasicAuth() 返回 ok=false → 401
echo -n "A6 空用户名..."
RESP=$(curl -s -w '\n%{http_code}' -X POST "$BASE/auth/local/login" \
  -H "Authorization: Basic " 2>/dev/null)
assert_http_code "$RESP" "401"
pass "空用户名返回 401"

# A11: 完整生命周期（登录→使用→登出→token失效）
# 源码：session.go Logout() → DeleteClientByID(client.ID) → client 被删 → 旧 token 401
echo -n "A11 登录→使用→登出→失效..."
CLIENT_TOKEN=$(get_admin_client_token)
# 使用 token 验证可用
RESP=$(http_get /application "$CLIENT_TOKEN")
assert_http_code "$RESP" "200"
# 登出（该 client 被删除）
RESP=$(http_post /auth/logout "" "$CLIENT_TOKEN")
assert_http_code "$RESP" "200"
# 验证：旧 token 调 GET /application 必须 401（client 已被删除）
RESP=$(http_get /application "$CLIENT_TOKEN")
assert_http_code "$RESP" "401"
pass "登录→使用→登出→token 失效（401）"

# A12: 登出后 session cookie 失效
# 源码：session.go Logout() → DeleteClientByID → client 被删 → cookie 中的 token 无效
#   auth.go handleClient() → GetClientByToken → nil → skip → abort401
echo -n "A12 session 生命周期..."
COOKIE_FILE="/tmp/e2e-cookie-${TEST_RUN_ID}"
RESP=$(curl -s -w '\n%{http_code}' -c "$COOKIE_FILE" \
  -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$BASE/auth/local/login" \
  -H 'Content-Type: application/x-www-form-urlencoded' -d "name=e2e-session")
assert_http_code "$RESP" "200"
# 用 cookie 调 API
RESP=$(curl -s -w '\n%{http_code}' -b "$COOKIE_FILE" "$BASE/current/user")
assert_http_code "$RESP" "200"
# 登出
RESP=$(curl -s -w '\n%{http_code}' -b "$COOKIE_FILE" -X POST "$BASE/auth/logout")
assert_http_code "$RESP" "200"
# 登出后 cookie 失效：client 已被删除，cookie 中的 token 不再有效
RESP=$(curl -s -w '\n%{http_code}' -b "$COOKIE_FILE" "$BASE/current/user")
assert_http_code "$RESP" "401"
pass "session 登出后 cookie 失效（401）"
rm -f "$COOKIE_FILE"

# A10: appToken 登出应 401
# 源码：/auth/logout 路由用 RequireClient，appToken 不被识别为 clientToken
#   handleClient → GetClientByToken → nil → skip → abort401
echo -n "A10 appToken 登出..."
APP_TOKEN=$(create_app_token "$ADMIN_TOKEN" "Logout Test App")
RESP=$(http_post /auth/logout "" "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "appToken 登出被拒（401）"


echo "=== Auth: 全部 PASS ==="

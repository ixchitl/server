#!/usr/bin/env bash
# @priority: P1
# @module: application
# @stability: stable
# @source: init
# 应用 Token 变更测试（更新 token → 旧失效 → 新可用）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Application Token 变更 ==="

ADMIN_TOKEN=$(get_admin_client_token)
# 一次创建拿 id+token：后面要用 APP_ID 改 security、再用 APP_TOKEN 验失效，
# 必须是同一个应用，分开调会建出两个就测不到东西
read -r APP_ID APP_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "Token Change App")"

# P26: 重新生成 token
# 源码：application.go UpdateApplicationSecurity()
#   请求体字段是 regenerateToken(bool)，不是 token
#   响应体：{"regenerateToken":{"token":"新token"}}
echo -n "P26 重新生成 token..."
RESP=$(http_elevated PUT "/application/$APP_ID/security" '{"regenerateToken":true}')
assert_http_code "$RESP" "200"
# 从响应体提取新 token
NEW_APP_TOKEN=$(get_body "$RESP" | jq -r '.regenerateToken.token')
[ -n "$NEW_APP_TOKEN" ] && [ "$NEW_APP_TOKEN" != "null" ] || fail "响应应包含新 token"
pass "token 重新生成成功，新 token 已获取"

# P27: 旧 token 失效
# 源码：app.Token 被替换为新 token，旧 token 在 DB 中不存在
#   auth.go handleApplication() → GetApplicationByToken(旧token) → nil → skip → abort401
echo -n "P27 旧 token 失效..."
RESP=$(http_post /message '{"message":"should fail"}' "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "旧 token 已失效（401）"

# P28: 新 token 可用
echo -n "P28 新 token 可用..."
RESP=$(http_post /message '{"message":"new token works","title":"new token"}' "$NEW_APP_TOKEN")
assert_http_code "$RESP" "200"
assert_json '.message' 'new token works' "$RESP"
pass "新 token 发消息成功"


echo "=== Application Token 变更: 全部 PASS ==="

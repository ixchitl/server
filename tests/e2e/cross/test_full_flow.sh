#!/usr/bin/env bash
# @priority: P0
# @module: cross
# @stability: stable
# @source: init
# 端到端完整流程（覆盖全部 4 级认证）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Cross: 完整端到端流程 ==="

# ① 无认证健康检查
echo -n "① health..."
RESP=$(curl -s -w '\n%{http_code}' "$BASE/health")
assert_http_code "$RESP" "200"
pass "无认证健康检查"

# ② basicAuth 登录创建 client
echo -n "② login..."
ADMIN_TOKEN=$(get_admin_client_token)
[ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "null" ] || fail "登录失败"
pass "basicAuth 登录获取 clientToken"

# ③ clientToken 创建应用获取 appToken
echo -n "③ create app..."
read -r APP_ID APP_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "E2E Full Flow App")"
[ -n "$APP_TOKEN" ] && [ "$APP_TOKEN" != "null" ] || fail "创建应用失败"
pass "clientToken 创建应用获取 appToken"

# ④ appToken 发消息
echo -n "④ send message..."
RESP=$(http_post /message '{"message":"e2e full flow","title":"Test","priority":3}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
MSG_ID=$(get_body "$RESP" | jq -r '.id')
assert_json '.message' 'e2e full flow' "$RESP"
pass "appToken 发消息成功 id=$MSG_ID"

# ⑤ clientToken 读消息
echo -n "⑤ read message..."
RESP=$(http_get /message "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
MSG_COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$MSG_COUNT" -ge 1 ] || fail "应有至少 1 条消息"
pass "clientToken 读消息成功 $MSG_COUNT 条"

# ⑥ clientToken 删消息
echo -n "⑥ delete message..."
RESP=$(http_delete /message/$MSG_ID "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "clientToken 删消息成功"

# ⑦ 删应用（需提权）
echo -n "⑦ delete app..."
RESP=$(http_elevated DELETE "/application/$APP_ID")
assert_http_code "$RESP" "200"
pass "删应用成功"

# ⑧ 验证 appToken 失效
# 源码：DELETE /application/:id 删除应用记录，appToken 对应的 application 不再存在
#   auth.go handleApplication() → GetApplicationByToken → nil → skip
#   POST /message 路由 RequireApplicationOrClient → 全部 skip → abort401
echo -n "⑧ appToken invalid..."
RESP=$(http_post /message '{"message":"should fail"}' "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "旧 appToken 已失效（401）"


echo "=== Cross: 完整端到端流程 PASS ==="
echo ""
echo "🎉 全部 e2e 测试完成！"

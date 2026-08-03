#!/usr/bin/env bash
# @priority: P1
# @module: application
# @stability: stable
# @source: init
# 级联删除测试（删应用 → 消息也被删 + token 失效）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Application 级联删除 ==="

ADMIN_TOKEN=$(get_admin_client_token)

# P24: 删应用级联删消息
echo -n "P24 级联删消息..."
# 一次创建拿 id+token，保证发消息和删除针对的是同一个应用
read -r APP_ID APP_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "Cascade Test App")"

# 发 3 条消息
for i in 1 2 3; do
  http_post /message "{\"message\":\"msg $i\"}" "$APP_TOKEN" > /dev/null
done

# 确认有 3 条消息
RESP=$(http_get /message "$ADMIN_TOKEN")
MSG_COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$MSG_COUNT" -ge 3 ] || fail "应至少 3 条消息，实际 $MSG_COUNT"

# 删除应用（DELETE /application/:id 需提权，走 basicAuth）
RESP=$(http_elevated DELETE "/application/$APP_ID")
assert_http_code "$RESP" "200"

# 验证消息也被删除
RESP=$(http_get /message "$ADMIN_TOKEN")
MSG_AFTER=$(get_body "$RESP" | jq -r '.messages | length')
[ "$MSG_AFTER" = "0" ] || fail "消息应被级联删除，实际剩 $MSG_AFTER 条"
pass "删应用后消息也被删除"

# P25: 删后 appToken 失效
# 源码：DeleteApplicationByID 删除应用记录，appToken 对应的 application 不再存在
#   auth.go handleApplication() → GetApplicationByToken → nil → skip
#   POST /message 路由 RequireApplicationOrClient → 全部 skip → abort401
echo -n "P25 appToken 失效..."
RESP=$(http_post /message '{"message":"should fail"}' "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "旧 appToken 已失效（401）"


echo "=== Application 级联删除: 全部 PASS ==="


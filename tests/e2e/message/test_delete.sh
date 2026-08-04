#!/usr/bin/env bash
# @priority: P0
# @module: message
# @stability: stable
# @source: init
# 删除消息测试（删全部/删单条/删应用消息）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Message 删除 ==="

ADMIN_TOKEN=$(get_admin_client_token)
read -r APP_ID APP_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "Delete Test App")"

# M37: 删全部消息
echo -n "M37 删全部..."
for i in 1 2 3 4 5; do http_post /message "{\"message\":\"del $i\",\"title\":\"del\"}" "$APP_TOKEN" > /dev/null; done
RESP=$(http_delete /message "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "删全部成功"

# M38: 删后确认空
echo -n "M38 确认空..."
RESP=$(http_get /message "$ADMIN_TOKEN")
COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$COUNT" = "0" ] || fail "应 0 条消息，实际 $COUNT"
pass "已清空"

# M40: 删单条
echo -n "M40 删单条..."
RESP=$(http_post /message '{"message":"single","title":"single"}' "$APP_TOKEN")
MSG_ID=$(get_body "$RESP" | jq -r '.id')
RESP=$(http_delete /message/$MSG_ID "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "删单条成功"

# M41: 删后确认
echo -n "M41 确认删除..."
RESP=$(http_get /message "$ADMIN_TOKEN")
assert_not_contains "\"id\":$MSG_ID" "$RESP"
pass "已从列表消失"

# M42: 不存在 id → 404
echo -n "M42 不存在 id..."
RESP=$(http_delete /message/99999 "$ADMIN_TOKEN")
assert_http_code "$RESP" "404"
pass "不存在返回 404"

# M44: 删应用消息
echo -n "M44 删应用消息..."
for i in 1 2 3; do http_post /message "{\"message\":\"app del $i\",\"title\":\"app del\"}" "$APP_TOKEN" > /dev/null; done
RESP=$(http_delete /application/$APP_ID/message "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
RESP=$(http_get /application/$APP_ID/message "$ADMIN_TOKEN")
COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$COUNT" = "0" ] || fail "应用消息应清空，实际 $COUNT"
pass "应用消息已清空"

# M46: 不存在的应用 → 404
echo -n "M46 不存在应用..."
RESP=$(http_delete /application/99999/message "$ADMIN_TOKEN")
assert_http_code "$RESP" "404"
pass "不存在返回 404"

echo "=== Message 删除: 全部 PASS ==="


#!/usr/bin/env bash
# @priority: P1
# @module: message
# @stability: stable
# @source: init
# 按应用过滤消息测试
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Message 过滤 ==="

ADMIN_TOKEN=$(get_admin_client_token)
# 一次创建拿 id+token，避开 create_app_id/create_app_token 分开调会建出两个应用的坑
read -r APP1_ID APP1_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "Filter App 1")"
read -r APP2_ID APP2_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "Filter App 2")"

# 各发 2 条
for i in 1 2; do http_post /message "{\"message\":\"app1 msg $i\",\"title\":\"app1\"}" "$APP1_TOKEN" > /dev/null; done
for i in 1 2; do http_post /message "{\"message\":\"app2 msg $i\",\"title\":\"app2\"}" "$APP2_TOKEN" > /dev/null; done

# M32: 正常获取
echo -n "M32 获取应用消息..."
RESP=$(http_get "/application/$APP1_ID/message" "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$COUNT" = "2" ] || fail "app1 应有 2 条消息，实际 $COUNT"
pass "app1 返回 $COUNT 条"

# M33: 只返回该应用消息
echo -n "M33 不串数据..."
RESP=$(http_get "/application/$APP2_ID/message" "$ADMIN_TOKEN")
COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$COUNT" = "2" ] || fail "app2 应有 2 条消息，实际 $COUNT"
pass "app2 返回 $COUNT 条"

# M34: 不存在的应用 → 404
echo -n "M34 不存在应用..."
RESP=$(http_get "/application/99999/message" "$ADMIN_TOKEN")
assert_http_code "$RESP" "404"
pass "不存在返回 404"

echo "=== Message 过滤: 全部 PASS ==="

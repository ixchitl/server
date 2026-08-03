#!/usr/bin/env bash
# @priority: P0
# @module: message
# @stability: stable
# @source: init
# 分页测试（limit/since 边界值 + 完整分页流程）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Message 分页 ==="

ADMIN_TOKEN=$(get_admin_client_token)
APP_TOKEN=$(create_app_token "$ADMIN_TOKEN" "Page Test App")

# 发 5 条消息
for i in 1 2 3 4 5; do
  http_post /message "{\"message\":\"page test $i\"}" "$APP_TOKEN" > /dev/null
done

# M19: 默认分页
echo -n "M19 默认分页..."
RESP=$(http_get /message "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json_not_empty '.paging.limit' "$RESP"
pass "默认分页结构正确"

# M20: 限制条数
echo -n "M20 limit=2..."
RESP=$(http_get "/message?limit=2" "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
COUNT=$(get_body "$RESP" | jq -r '.messages | length')
# 源码：buildWithPaging 用 Limit+1 查询，超 Limit 则截断为 Limit 并设 next
# 发了 5 条消息，limit=2 应精确返回 2 条
[ "$COUNT" = "2" ] || fail "limit=2 应精确 2 条，实际 $COUNT"
pass "limit=2 返回 $COUNT 条"

# M22: limit=0 → 400
echo -n "M22 limit=0..."
RESP=$(http_get "/message?limit=0" "$ADMIN_TOKEN")
assert_http_code "$RESP" "400"
pass "limit=0 返回 400"

# M23: limit=201 → 400
echo -n "M23 limit=201..."
RESP=$(http_get "/message?limit=201" "$ADMIN_TOKEN")
assert_http_code "$RESP" "400"
pass "limit=201 返回 400"

# M25: 无认证 → 401
echo -n "M25 无认证..."
RESP=$(http_get /message "")
assert_http_code "$RESP" "401"
pass "无认证返回 401"

# M27: limit=1（最小值）
echo -n "M27 limit=1..."
RESP=$(http_get "/message?limit=1" "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$COUNT" -le 1 ] || fail "limit=1 应最多 1 条，实际 $COUNT"
pass "limit=1 返回 $COUNT 条"

# M28: limit=200（最大值）
echo -n "M28 limit=200..."
RESP=$(http_get "/message?limit=200" "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "limit=200 正常"

# M31: 完整分页流程
# 源码：buildWithPaging() → next = ctx.Request.URL.Path + "?" + query.Encode()
#   next 格式应为 /message?limit=2&since=XXX
echo -n "M31 完整分页..."
ALL_IDS=""
RESP=$(http_get "/message?limit=2" "$ADMIN_TOKEN")
IDS=$(get_body "$RESP" | jq -r '.messages[].id' | tr '\n' ',')
ALL_IDS="$IDS"
# 验证 paging.next 存在且格式正确（应以 /message?limit=2&since= 开头）
NEXT=$(get_body "$RESP" | jq -r '.paging.next')
[ "$NEXT" != "" ] && [ "$NEXT" != "null" ] || fail "应有 next 页，实际 '$NEXT'"
echo "$NEXT" | grep -q '^/message?limit=2&since=[0-9]\+$' || fail "next 格式应为 /message?limit=2&since=数字，实际 '$NEXT'"
# 验证 paging.since 等于返回的最后一条消息的 id
LAST_ID=$(get_body "$RESP" | jq -r '.messages[-1].id')
PAGING_SINCE=$(get_body "$RESP" | jq -r '.paging.since')
[ "$PAGING_SINCE" = "$LAST_ID" ] || fail "paging.since 应等于最后一条消息 id $LAST_ID，实际 $PAGING_SINCE"
# 翻第二页
RESP=$(curl -s -w '\n%{http_code}' -H "X-Gotify-Key: $ADMIN_TOKEN" "${BASE}${NEXT}")
IDS=$(get_body "$RESP" | jq -r '.messages[].id' | tr '\n' ',')
ALL_IDS="$ALL_IDS$IDS"
NEXT=$(get_body "$RESP" | jq -r '.paging.next')
if [ "$NEXT" != "" ] && [ "$NEXT" != "null" ]; then
  # 翻第三页
  RESP=$(curl -s -w '\n%{http_code}' -H "X-Gotify-Key: $ADMIN_TOKEN" "${BASE}${NEXT}")
  IDS=$(get_body "$RESP" | jq -r '.messages[].id' | tr '\n' ',')
  ALL_IDS="$ALL_IDS$IDS"
fi
# 统计不同 id 数，应精确 5 条
UNIQUE=$(echo "$ALL_IDS" | tr ',' '\n' | grep -v '^$' | sort -u | wc -l)
[ "$UNIQUE" = "5" ] || fail "分页应取到 5 条，实际 $UNIQUE"
pass "分页取到 $UNIQUE 条消息，next URL 格式正确"


echo "=== Message 分页: 全部 PASS ==="

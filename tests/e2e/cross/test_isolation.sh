#!/usr/bin/env bash
# @priority: P1
# @module: cross
# @stability: stable
# @source: init
# 权限隔离测试（用户 A 看不到用户 B 的数据）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Cross: 权限隔离 ==="

USER_A="e2eisoA_${TEST_RUN_ID}_$RANDOM"
USER_B="e2eisoB_${TEST_RUN_ID}_$RANDOM"

# 创建两个用户
curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$BASE/user" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USER_A\",\"pass\":\"pass\",\"admin\":false}" > /dev/null
curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$BASE/user" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USER_B\",\"pass\":\"pass\",\"admin\":false}" > /dev/null

# 两个用户各自创建 clientToken
TOKEN_A=$(get_user_client_token "$USER_A" "pass")
TOKEN_B=$(get_user_client_token "$USER_B" "pass")

# 用户 A 建应用（id 和 token 一次拿齐，X2/X3/X5 共用同一个应用）
read -r APP_A_ID APP_A_TOKEN <<< "$(create_app "$TOKEN_A" "Isolation App A")"

# X2: 用户 B 看不到 A 的应用
echo -n "X2 应用隔离..."
RESP=$(http_get /application "$TOKEN_B")
assert_http_code "$RESP" "200"
assert_not_contains "\"id\":$APP_A_ID" "$RESP"
pass "B 看不到 A 的应用"

# X5: 用户 B 访问 A 的应用消息 → 404
# 源码：message.go GetMessagesWithApplication()
#   app.UserID != auth.GetUserID(ctx) → 404（不泄露存在性）
#   注意：GET /application/:id 路由不存在，会返回 NoRoute 404
#   正确测试应调 GET /application/:id/message 这个实际路由
echo -n "X5 404 而非 403..."
RESP=$(http_get "/application/$APP_A_ID/message" "$TOKEN_B")
assert_http_code "$RESP" "404"
pass "B 访问 A 的应用消息返回 404（不泄露存在性）"

# X3: 消息隔离
echo -n "X3 消息隔离..."
http_post /message '{"message":"A private msg"}' "$APP_A_TOKEN" > /dev/null
RESP=$(http_get /message "$TOKEN_B")
MSG_COUNT=$(get_body "$RESP" | jq -r '.messages | length')
[ "$MSG_COUNT" = "0" ] || fail "B 不应有消息，实际 $MSG_COUNT"
pass "B 看不到 A 的消息"

# 清理两个测试用户
# 🔴 循环变量不能叫 UID——那是 bash 内置的只读变量，赋值会直接报
#    "UID: readonly variable" 并以非 0 退出，把整个用例拖成失败
for u in "$USER_A" "$USER_B"; do
  TEST_USER_ID=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user" | jq -r ".[] | select(.name==\"$u\") | .id")
  [ -n "$TEST_USER_ID" ] && [ "$TEST_USER_ID" != "null" ] && \
    curl -s -o /dev/null -u "$ADMIN_USER:$ADMIN_PASS" -X DELETE "$BASE/user/$TEST_USER_ID" || true
done

echo "=== Cross: 权限隔离 PASS ==="

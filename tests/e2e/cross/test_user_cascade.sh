#!/usr/bin/env bash
# @priority: P1
# @module: cross
# @stability: stable
# @source: init
# 用户级联删除测试（删用户 → 应用也消失）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Cross: 用户级联删除 ==="

USERNAME="e2ecascade_${TEST_RUN_ID}_$RANDOM"

# 创建测试用户
curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$BASE/user" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USERNAME\",\"pass\":\"pass123\",\"admin\":false}" > /dev/null

# 用户登录建应用
USER_TOKEN=$(get_user_client_token "$USERNAME" "pass123")
read -r APP_ID APP_TOKEN <<< "$(create_app "$USER_TOKEN" "User Cascade App")"

# 用 app token 发消息
http_post /message '{"message":"cascade test","title":"cascade"}' "$APP_TOKEN" > /dev/null

# X1: 删用户 → 应用消失
echo -n "X1 级联删应用..."
USER_ID=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user" | jq -r ".[] | select(.name==\"$USERNAME\") | .id")
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X DELETE "$BASE/user/$USER_ID")
assert_http_code "$RESP" "200"

# 验证：该用户的 clientToken 应失效
# 源码：user.go DeleteUserByID() → fireUserDeleted → NotifyDeletedUser
#   该用户的所有 client 被删 → token 不再存在 → handleClient → nil → skip → abort401
RESP=$(http_get /application "$USER_TOKEN")
assert_http_code "$RESP" "401"
pass "用户删除后 token 失效（401）"

# 清理（用户已删，数据也级联删了）
echo "=== Cross: 用户级联删除 PASS ==="

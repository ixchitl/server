#!/usr/bin/env bash
# @priority: P0
# @module: user
# @stability: stable
# @source: init
# 修改密码测试（改密码 → 新密码登录）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== User 密码 ==="

USERNAME="e2epass_${TEST_RUN_ID}_$RANDOM"

# 创建测试用户
curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X POST "$BASE/user" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$USERNAME\",\"pass\":\"oldpass\",\"admin\":false}" > /dev/null

# U21: 正常改密码
echo -n "U21 改密码..."
RESP=$(curl -s -w '\n%{http_code}' -u "$USERNAME:oldpass" \
  -X POST "$BASE/current/user/password" -H 'Content-Type: application/json' \
  -d '{"pass":"newpass123"}')
assert_http_code "$RESP" "200"
pass "改密码成功"

# U22: 新密码登录
echo -n "U22 新密码登录..."
RESP=$(curl -s -w '\n%{http_code}' -u "$USERNAME:newpass123" \
  -X POST "$BASE/client" -H 'Content-Type: application/json' \
  -d '{"name":"pass-test"}')
assert_http_code "$RESP" "200"
pass "新密码登录成功"

# U23: 旧密码应失败
echo -n "U23 旧密码失败..."
RESP=$(curl -s -w '\n%{http_code}' -u "$USERNAME:oldpass" \
  -X POST "$BASE/client" -H 'Content-Type: application/json' \
  -d '{"name":"old-pass-test"}')
assert_http_code "$RESP" "401"
pass "旧密码已失效"

# 清理（用 admin 删用户）
USER_ID=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user" | jq -r ".[] | select(.name==\"$USERNAME\") | .id")
[ -n "$USER_ID" ] && [ "$USER_ID" != "null" ] && \
  curl -sf -u "$ADMIN_USER:$ADMIN_PASS" -X DELETE "$BASE/user/$USER_ID" > /dev/null || true

echo "=== User 密码: 全部 PASS ==="

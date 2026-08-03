#!/usr/bin/env bash
# @priority: P1
# @module: user
# @stability: stable
# @source: init
# Admin 保护测试（不能删最后一个 admin）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== User Admin 保护 ==="

# 获取当前 admin 列表
ADMIN_IDS=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$BASE/user" | jq -r '.[] | select(.admin==true) | .id')
ADMIN_COUNT=$(echo "$ADMIN_IDS" | grep -c .)

if [ "$ADMIN_COUNT" -eq 1 ]; then
  # U24: 只剩 1 个 admin，不能删
  echo -n "U24 不能删最后 admin..."
  ADMIN_ID=$(echo "$ADMIN_IDS" | head -1)
  RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
    -X DELETE "$BASE/user/$ADMIN_ID")
  assert_http_code "$RESP" "400"
  assert_contains "last admin" "$RESP"
  pass "不能删最后一个 admin"
elif [ "$ADMIN_COUNT" -ge 2 ]; then
  # U25: 有多个 admin，能删非最后一个
  # 源码：user.go DeleteUserByID() → adminCount > 1 → 正常删除 → 200
  echo -n "U25 删多余 admin..."
  EXTRA_ADMIN_ID=$(echo "$ADMIN_IDS" | tail -1)
  RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
    -X DELETE "$BASE/user/$EXTRA_ADMIN_ID")
  assert_http_code "$RESP" "200"
  pass "删多余 admin 成功（200）"
else
  echo "  ⚠️ 跳过：无法确定 admin 数量"
fi

echo "=== User Admin 保护: 全部 PASS ==="

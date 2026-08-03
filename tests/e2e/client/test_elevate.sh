#!/usr/bin/env bash
# @priority: P1
# @module: client
# @stability: stable
# @source: init
# 客户端提权测试
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Client 提权 ==="

ADMIN_TOKEN=$(get_admin_client_token)

# C19: 正常提权（用 basicAuth）
# 源码：client.go ElevateClient()
#   请求体 ElevateRequest { DurationSeconds int binding:"required" }
#   成功返回 ctx.Status(204)
echo -n "C19 提权..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/client" -H 'Content-Type: application/json' \
  -d '{"name":"Elevate Test"}')
CLIENT_ID=$(get_body "$RESP" | jq -r '.id')
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/client/$CLIENT_ID/elevate" -H 'Content-Type: application/json' \
  -d '{"durationSeconds":900}')
assert_http_code "$RESP" "204"
pass "提权成功（204）"

# C21: 不存在的 client → 404
# 源码：client.go ElevateClient() → client==nil → 404
#   注意：必须发合法的 durationSeconds 才能过 Bind，否则先 400
echo -n "C21 不存在 client..."
RESP=$(curl -s -w '\n%{http_code}' -u "$ADMIN_USER:$ADMIN_PASS" \
  -X POST "$BASE/client/99999/elevate" -H 'Content-Type: application/json' \
  -d '{"durationSeconds":900}')
assert_http_code "$RESP" "404"
pass "不存在返回 404"

echo "=== Client 提权: 全部 PASS ==="

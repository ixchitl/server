#!/usr/bin/env bash
# @priority: P0
# @module: health
# @stability: stable
# @source: init
# 健康检查测试（4 条用例）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Health 健康检查 ==="

# H1: 正常健康检查
echo -n "H1 正常健康检查..."
RESP=$(curl -s -w '\n%{http_code}' "$BASE/health")
assert_http_code "$RESP" "200"
assert_json '.health' 'green' "$RESP"
assert_json '.database' 'green' "$RESP"
assert_json_not_empty '.version' "$RESP"
V=$(curl -s "$BASE/version" | jq -r '.version')
assert_json '.version' "$V" "$RESP"
assert_json '.uptime > 0' 'true' "$RESP"
assert_json '.version | type' 'string' "$RESP"
assert_json '.uptime | type' 'number' "$RESP"
pass "health=green database=green"

# H3: 带 token 访问（不校验认证）
echo -n "H3 带多余 token 访问..."
RESP=$(curl -s -w '\n%{http_code}' -H "X-Gotify-Key: fake-token" "$BASE/health")
assert_http_code "$RESP" "200"
pass "带 token 也返回 200"

# H4: 服务可达性（间接验证，K8s readiness 用这个端点）
echo -n "H4 服务启动后可访问..."
RESP=$(curl -s -w '\n%{http_code}' --connect-timeout 5 "$BASE/health")
assert_http_code "$RESP" "200"
pass "服务可达"

echo "=== Health: 全部 PASS ==="

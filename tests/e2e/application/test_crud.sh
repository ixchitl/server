#!/usr/bin/env bash
# @priority: P0
# @module: application
# @stability: stable
# @source: init
# Application CRUD 生命周期测试（17 条用例）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Application CRUD ==="

ADMIN_TOKEN=$(get_admin_client_token)

# P1: 正常创建
echo -n "P1 正常创建..."
RESP=$(http_post /application '{"name":"CRUD Test App"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json_not_empty '.id' "$RESP"
assert_json '.name' 'CRUD Test App' "$RESP"
assert_json '.internal' 'false' "$RESP"
APP_ID=$(get_body "$RESP" | jq -r '.id')
pass "创建成功 id=$APP_ID"

# P2: 带全部字段
echo -n "P2 全字段创建..."
RESP=$(http_post /application '{"name":"Full App","description":"desc","defaultPriority":5,"sortKey":"a1"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json '.name' 'Full App' "$RESP"
assert_json '.description' 'desc' "$RESP"
assert_json '.defaultPriority' '5' "$RESP"
pass "全字段正确"

# P3: 默认值验证
echo -n "P3 默认值..."
RESP=$(http_post /application '{"name":"Default App"}' "$ADMIN_TOKEN")
assert_json '.defaultPriority' '0' "$RESP"
pass "defaultPriority 默认 0"

# P4: 缺 name → 400
echo -n "P4 缺 name..."
RESP=$(http_post /application '{"description":"no name"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "400"
pass "缺 name 返回 400"

# P5: name 空字符串 → 400
echo -n "P5 name 空字符串..."
RESP=$(http_post /application '{"name":""}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "400"
pass "空 name 返回 400"

# P6: appToken 创建 → 401
# 源码：POST /application 路由用 RequireClient，appToken 不被识别为 clientToken
#   handleClient → nil → skip → abort401
echo -n "P6 appToken 调用..."
APP_TOKEN=$(create_app_token "$ADMIN_TOKEN" "AppToken Test")
RESP=$(http_post /application '{"name":"Hack"}' "$APP_TOKEN")
assert_http_code "$RESP" "401"
pass "appToken 返回 401"

# P7: 无认证 → 401
echo -n "P7 无认证..."
RESP=$(http_post /application '{"name":"X"}' "")
assert_http_code "$RESP" "401"
pass "无认证返回 401"

# P8: priority 负数（无校验，应 200）
echo -n "P8 priority 负数..."
RESP=$(http_post /application '{"name":"Neg Prio","defaultPriority":-1}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "负数 priority 不报错"

# P10: 获取列表
echo -n "P10 获取列表..."
RESP=$(http_get /application "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
# 应有至少 3 个应用（前面创建的）
COUNT=$(get_body "$RESP" | jq 'length')
[ "$COUNT" -ge 3 ] || fail "列表应有至少 3 个应用，实际 $COUNT"
pass "列表 $COUNT 个应用"

# P12: 列表中 token 被清除
# 源码：model/application.go 的 Token 字段带 json:"token,omitempty"，
#       列表接口不返回它 → jq 取到的是字面量 null，不是空串
echo -n "P12 token 安全..."
RESP=$(http_get /application "$ADMIN_TOKEN")
assert_json_empty '.[0].token' "$RESP"
pass "列表 token 已清除"

# P14: 更新名称
echo -n "P14 更新名称..."
RESP=$(http_put /application/$APP_ID '{"name":"Updated App"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json '.name' 'Updated App' "$RESP"
pass "更新成功"

# P16: sortKey 空时不覆盖
# 源码：application.go UpdateApplication() → if applicationParams.SortKey != "" { app.SortKey = ... }
#   传空 sortKey 不覆盖原值
# 需要先创建一个带 sortKey 的应用，再更新不带 sortKey，验证 sortKey 保留
echo -n "P16 sortKey 保留..."
RESP=$(http_post /application '{"name":"SortKey App","sortKey":"z9"}' "$ADMIN_TOKEN")
SORT_APP_ID=$(get_body "$RESP" | jq -r '.id')
assert_json '.sortKey' 'z9' "$RESP"
# 更新时传空 sortKey
RESP=$(http_put /application/$SORT_APP_ID '{"name":"Updated SortKey App","sortKey":""}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
# 验证 sortKey 仍为原值 z9
assert_json '.sortKey' 'z9' "$RESP"
pass "sortKey 空值不覆盖（保持 z9）"

# P17: 不存在的 id → 404
echo -n "P17 不存在的 id..."
RESP=$(http_put /application/99999 '{"name":"X"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "404"
pass "不存在返回 404"

# P20: 删除应用（需提权，详见 common.sh 的 http_elevated）
echo -n "P20 删除应用..."
RESP=$(http_elevated DELETE "/application/$APP_ID")
assert_http_code "$RESP" "200"
pass "删除成功"

# P21: 删除后确认不在列表
echo -n "P21 删除后确认..."
RESP=$(http_get /application "$ADMIN_TOKEN")
assert_not_contains "\"id\":$APP_ID" "$RESP"
pass "已从列表消失"

# P22: 不存在的 id 删除 → 404
echo -n "P22 删不存在..."
RESP=$(http_elevated DELETE "/application/99999")
assert_http_code "$RESP" "404"
pass "不存在返回 404"


echo "=== Application CRUD: 全部 PASS ==="

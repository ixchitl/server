#!/usr/bin/env bash
# @priority: P0
# @module: message
# @stability: stable
# @source: init
# 发送消息正向+负向+边界测试（18 条用例）
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Message 发送 ==="

ADMIN_TOKEN=$(get_admin_client_token)
read -r APP_ID APP_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "Send Test App")"

# M1: appToken 正常发消息
echo -n "M1 正常发消息..."
RESP=$(http_post /message '{"message":"hello world"}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
assert_json '.message' 'hello world' "$RESP"
assert_json_not_empty '.id' "$RESP"
assert_json_not_empty '.date' "$RESP"
pass "发消息成功"

# M2: 带 title 和 priority
echo -n "M2 带 title+priority..."
RESP=$(http_post /message '{"message":"hi","title":"Alert","priority":5}' "$APP_TOKEN")
assert_json '.title' 'Alert' "$RESP"
assert_json '.priority' '5' "$RESP"
pass "title 和 priority 正确"

# M3: 不传 title → 默认应用名
echo -n "M3 title 默认应用名..."
RESP=$(http_post /message '{"message":"no title"}' "$APP_TOKEN")
assert_json '.title' 'Send Test App' "$RESP"
pass "title 默认为应用名"

# M4: 不传 priority → 默认应用 defaultPriority
echo -n "M4 priority 默认值..."
RESP=$(http_post /message '{"message":"no prio"}' "$APP_TOKEN")
assert_json '.priority' '0' "$RESP"
pass "priority 默认为 0"

# M5: 带 extras
echo -n "M5 extras..."
RESP=$(http_post /message '{"message":"x","extras":{"a::b::c":{"v":1}}}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
pass "extras 接受"

# M6: clientToken 发消息（需 appid）
echo -n "M6 clientToken 发消息..."
RESP=$(http_post /message "{\"message\":\"from client\",\"appid\":$APP_ID}" "$ADMIN_TOKEN")
assert_http_code "$RESP" "200"
pass "clientToken 发消息成功"

# M7: markdown 内容
echo -n "M7 markdown..."
RESP=$(http_post /message '{"message":"**bold** and [link](http://x)"}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
pass "markdown 接受"

# M8: 缺 message → 400
echo -n "M8 缺 message..."
RESP=$(http_post /message '{"title":"no msg"}' "$APP_TOKEN")
assert_http_code "$RESP" "400"
pass "缺 message 返回 400"

# M9: message 空字符串 → 400
echo -n "M9 空消息..."
RESP=$(http_post /message '{"message":""}' "$APP_TOKEN")
assert_http_code "$RESP" "400"
pass "空 message 返回 400"

# M10: clientToken 缺 appid → 400
echo -n "M10 缺 appid..."
RESP=$(http_post /message '{"message":"hi"}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "400"
assert_contains "appid" "$RESP"
pass "缺 appid 返回 400"

# M11: clientToken 不存在 appid → 400
echo -n "M11 不存在 appid..."
RESP=$(http_post /message '{"message":"hi","appid":99999}' "$ADMIN_TOKEN")
assert_http_code "$RESP" "400"
pass "不存在 appid 返回 400"

# M13: 无认证 → 401
echo -n "M13 无认证..."
RESP=$(http_post /message '{"message":"hi"}' "")
assert_http_code "$RESP" "401"
pass "无认证返回 401"

# M14: appToken 传 appid 被忽略
echo -n "M14 appToken 忽略 appid..."
RESP=$(http_post /message '{"message":"hi","appid":999}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
pass "appToken 忽略 body appid"

# M15: priority 负数（无校验）
echo -n "M15 priority 负数..."
RESP=$(http_post /message '{"message":"neg","priority":-1}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
pass "负数 priority 不报错"

# M16: priority 超大
echo -n "M16 priority 超大..."
RESP=$(http_post /message '{"message":"big","priority":999999}' "$APP_TOKEN")
assert_http_code "$RESP" "200"
pass "超大 priority 不报错"

# M18: title 纯空格 → 默认应用名
echo -n "M18 title 纯空格..."
RESP=$(http_post /message '{"message":"x","title":"   "}' "$APP_TOKEN")
assert_json '.title' 'Send Test App' "$RESP"
pass "纯空格 title 默认应用名"


echo "=== Message 发送: 全部 PASS ==="

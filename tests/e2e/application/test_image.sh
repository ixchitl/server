#!/usr/bin/env bash
# @priority: P2
# @module: application
# @stability: stable
# @source: init
# 应用图标测试（上传 / 删除 / 非图片拒绝）
#
# 源码依据 api/application.go：
#   UploadApplicationImage()  表单键必须是 file；读前 261 字节做 filetype.IsImage 检测；
#                             扩展名必须在 .gif/.png/.jpg/.jpeg 之内
#   RemoveApplicationImage()  app.Image 为空时返 400（没有自定义图标可删）
#   两个端点都在普通 clientAuth 分组，不需要提权
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

echo "=== Application 图标 ==="

WORK_DIR="$(dirname "$0")/.image-tmp-$$"
mkdir -p "$WORK_DIR"

# trap 已由 common.sh 注册，这里只补充自己的临时文件清理
custom_teardown() {
  rm -rf "$WORK_DIR"
}

ADMIN_TOKEN=$(get_admin_client_token)
read -r APP_ID APP_TOKEN <<< "$(create_app "$ADMIN_TOKEN" "Image Test App")"

# 造一个 1x1 的合法 PNG（base64 解出来 67 字节，PNG 魔数在前 8 字节，足够过 filetype 检测）
PNG_FILE="$WORK_DIR/icon.png"
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC' \
  | base64 -d > "$PNG_FILE" 2>/dev/null || \
  printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC' \
  | base64 --decode > "$PNG_FILE"
[ -s "$PNG_FILE" ] || fail "PNG 测试文件生成失败（base64 解码不可用）"

# 造一个非图片文件
TXT_FILE="$WORK_DIR/notimage.txt"
echo "this is definitely not an image" > "$TXT_FILE"

# P29: 上传图标
echo -n "P29 上传图标..."
RESP=$(curl -s -w '\n%{http_code}' -X POST "$BASE/application/$APP_ID/image" \
  -H "X-Gotify-Key: $ADMIN_TOKEN" -F "file=@$PNG_FILE")
assert_http_code "$RESP" "200"
IMG_AFTER=$(get_body "$RESP" | jq -r '.image')
# 上传成功后 image 不再是默认图，而是 image/<hash>.png
[ "$IMG_AFTER" != "static/defaultapp.png" ] || fail "image 仍为默认值，上传未生效：$IMG_AFTER"
assert_contains '.png' "$RESP"
pass "上传成功，image=$IMG_AFTER"

# P30: 删除图标
# 源码：删除后 app.Image 置空，响应经 withResolvedImage 回落为默认图
echo -n "P30 删除图标..."
RESP=$(curl -s -w '\n%{http_code}' -X DELETE "$BASE/application/$APP_ID/image" \
  -H "X-Gotify-Key: $ADMIN_TOKEN")
assert_http_code "$RESP" "200"
assert_json '.image' 'static/defaultapp.png' "$RESP"
pass "删除成功，image 回落为默认图"

# P31: 上传非图片 → 400
# 源码：filetype.IsImage(head) 为 false → AbortWithError(400, "file must be an image")
echo -n "P31 上传非图片..."
RESP=$(curl -s -w '\n%{http_code}' -X POST "$BASE/application/$APP_ID/image" \
  -H "X-Gotify-Key: $ADMIN_TOKEN" -F "file=@$TXT_FILE")
assert_http_code "$RESP" "400"
pass "非图片被拒（400）"

echo "=== Application 图标: 全部 PASS ==="

#!/usr/bin/env bash
# Gotify e2e 执行器
#
# 一个脚本文件 = 一个 e2e_case（与 v9 §7.2 e2e_cases 表的 file_path 口径一致）
#
# 用法：
#   ./run.sh                                  # 全量
#   ./run.sh --scope message,cross            # 指定模块目录
#   ./run.sh --priority P0                    # 只跑 P0
#   ./run.sh --diff api/message.go,app.go     # 按 diff 自动选范围（smart scope）
#   ./run.sh --list                           # 只列出将要执行的用例，不跑
#   ./run.sh --json /tmp/e2e.json             # 指定结构化报告输出路径
#   ./run.sh --timeout 180                    # 单文件超时秒数（默认 120）
#
# 环境变量：
#   GOTIFY_URL   被测服务地址（默认 http://localhost:8080）
#   ADMIN_USER / ADMIN_PASS
#
# 退出码：0 全部通过 / 1 有失败 / 2 参数错误 / 3 被测服务不可达
#
# ⚠️ 串行执行是硬要求：common.sh 的 teardown 会清空全部测试数据，
#    并行跑会互删对方的资源。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BASE="${GOTIFY_URL:-http://localhost:8080}"
SCOPE=""
PRIORITY=""
DIFF_FILES=""
JSON_OUT=""
TIMEOUT=120
LIST_ONLY=0

ALL_MODULES="health auth application message client user cross"

# ── 参数解析 ────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --scope)    SCOPE="$2"; shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    --diff)     DIFF_FILES="$2"; shift 2 ;;
    --json)     JSON_OUT="$2"; shift 2 ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    --list)     LIST_ONLY=1; shift ;;
    -h|--help)  sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "未知参数: $1（--help 看用法）" >&2; exit 2 ;;
  esac
done

# ── smart scope：diff 文件 → 模块目录 ────────────────────────
# 映射规则与 Gotify-e2e完整测试规格.md 的 Smart Scope 矩阵一致。
# health 恒纳入：4 条冒烟用例几乎零成本，先确认服务活着再谈别的。
map_diff_to_scope() {
  local files="$1" mods="health" full=0
  local IFS=','
  for f in $files; do
    case "$f" in
      */api/message.go|api/message.go)         mods="$mods message" ;;
      */api/application.go|api/application.go) mods="$mods application cross" ;;
      */api/client.go|api/client.go)           mods="$mods client" ;;
      */api/user.go|api/user.go)               mods="$mods user cross" ;;
      */api/session.go|api/session.go)         mods="$mods auth" ;;
      auth/*|*/auth/*)                         mods="$mods auth" ;;
      model/*|*/model/*)                       full=1 ;;
      app.go|*/app.go)                         full=1 ;;
      config/*|*/config/*)                     full=1 ;;
      # 认不出来的改动按最坏情况处理：全量。宁可多跑 2 分钟，不要漏回归
      *)                                       full=1 ;;
    esac
  done
  if [ "$full" = "1" ]; then
    echo "$ALL_MODULES"
  else
    # 去重
    echo "$mods" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' '
  fi
}

if [ -n "$DIFF_FILES" ]; then
  if [ -n "$SCOPE" ]; then
    echo "--scope 与 --diff 不能同时用" >&2; exit 2
  fi
  SCOPE="$(map_diff_to_scope "$DIFF_FILES")"
  SCOPE_REASON="diff 映射: $DIFF_FILES"
elif [ -z "$SCOPE" ]; then
  SCOPE="$ALL_MODULES"
  SCOPE_REASON="全量"
else
  SCOPE="$(echo "$SCOPE" | tr ',' ' ')"
  SCOPE_REASON="显式指定"
fi

# ── 收集待跑文件 ────────────────────────────────────────────
read_meta() {  # read_meta <file> <字段名>
  grep -m1 "^# @$2:" "$1" 2>/dev/null | sed "s/^# @$2:[[:space:]]*//" | tr -d '\r'
}

FILES=""
for m in $SCOPE; do
  [ -d "$m" ] || continue
  for f in "$m"/test_*.sh; do
    [ -f "$f" ] || continue
    if [ -n "$PRIORITY" ]; then
      [ "$(read_meta "$f" priority)" = "$PRIORITY" ] || continue
    fi
    FILES="$FILES $f"
  done
done

if [ -z "${FILES// /}" ]; then
  echo "没有匹配的用例（scope=$SCOPE priority=${PRIORITY:-全部}）" >&2
  exit 2
fi

TOTAL=$(echo $FILES | wc -w | tr -d ' ')

if [ "$LIST_ONLY" = "1" ]; then
  echo "范围：$SCOPE_REASON → $SCOPE"
  printf "%-40s %-4s %-12s %s\n" 文件 优先级 模块 稳定性
  for f in $FILES; do
    printf "%-40s %-4s %-12s %s\n" "$f" \
      "$(read_meta "$f" priority)" "$(read_meta "$f" module)" "$(read_meta "$f" stability)"
  done
  echo "合计 $TOTAL 个用例文件"
  exit 0
fi

# ── 前置：被测服务可达性 ────────────────────────────────────
if ! curl -sf -o /dev/null --max-time 10 "$BASE/health"; then
  echo "❌ 被测服务不可达：$BASE/health" >&2
  echo "   L3_env：先确认服务已就绪再跑用例" >&2
  exit 3
fi

# ── 带超时执行单个文件（macOS 无 timeout 命令，自己实现）────
run_one() {
  local file="$1" logfile="$2"
  bash "$file" > "$logfile" 2>&1 &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$TIMEOUT" ]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# ── 主循环 ──────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════"
echo " 被测服务 : $BASE"
echo " 范围     : $SCOPE_REASON → $SCOPE"
echo " 优先级   : ${PRIORITY:-全部}"
echo " 用例文件 : $TOTAL 个，串行执行，单文件超时 ${TIMEOUT}s"
echo "══════════════════════════════════════════════════════"

# ── 日志临时目录 ────────────────────────────────────────────
# 🔴 必须做失败检查：mktemp 失败时变量为空，后续会把日志写到 /，
#    表现为「18 个用例全部失败」——把环境问题伪装成代码问题，
#    这是 L1/L3 归因最容易被污染的地方，宁可当场退出
make_tmpdir() {
  local d
  d="$(mktemp -d 2>/dev/null)" && [ -n "$d" ] && [ -d "$d" ] && { echo "$d"; return 0; }
  # 回落到脚本目录下（沙箱/受限环境里 /tmp 可能不可写）
  d="$SCRIPT_DIR/.e2e-run/$$"
  mkdir -p "$d" 2>/dev/null && [ -d "$d" ] && { echo "$d"; return 0; }
  return 1
}

if ! TMPDIR_RUN="$(make_tmpdir)"; then
  echo "❌ 无法创建临时目录（mktemp 与 $SCRIPT_DIR/.e2e-run 均失败）" >&2
  echo "   L3_env：先解决可写目录问题，否则结果不可信" >&2
  exit 3
fi

PASSED=0; FAILED=0; TIMEDOUT=0
RESULTS_JSON=""
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_T0=$(date +%s)

for f in $FILES; do
  log="$TMPDIR_RUN/$(echo "$f" | tr '/' '_').log"
  t0=$(date +%s)
  run_one "$f" "$log"; rc=$?
  dur=$(( $(date +%s) - t0 ))

  case $rc in
    0)   result=pass;    PASSED=$((PASSED+1));   mark="✅ PASS" ;;
    124) result=timeout; TIMEDOUT=$((TIMEDOUT+1)); mark="⏱  TIMEOUT" ;;
    *)   result=fail;    FAILED=$((FAILED+1));   mark="❌ FAIL" ;;
  esac

  printf "%-11s %-38s %3ss\n" "$mark" "$f" "$dur"

  if [ "$result" != "pass" ]; then
    # 失败摘要：第一条 FAIL 行，供 Tester 做 L1-L4 归因
    excerpt="$(grep -m1 'FAIL:' "$log" 2>/dev/null || tail -3 "$log" 2>/dev/null)"
    echo "$excerpt" | sed 's/^/            /'
  fi

  esc() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "$1"; }
  RESULTS_JSON="$RESULTS_JSON,
    {\"file_path\":\"$f\",
     \"priority\":\"$(read_meta "$f" priority)\",
     \"module\":\"$(read_meta "$f" module)\",
     \"stability\":\"$(read_meta "$f" stability)\",
     \"result\":\"$result\",
     \"duration_ms\":$((dur * 1000)),
     \"log\":$(esc "$log")}"
done

RUN_DUR=$(( $(date +%s) - RUN_T0 ))

echo "══════════════════════════════════════════════════════"
printf " PASS=%d  FAIL=%d  TIMEOUT=%d  合计=%d  耗时=%ds\n" \
  "$PASSED" "$FAILED" "$TIMEDOUT" "$TOTAL" "$RUN_DUR"
echo "══════════════════════════════════════════════════════"

# ── 结构化报告（供 State Service 的 report_e2e_result 消费）──
if [ -n "$JSON_OUT" ]; then
  {
    echo "{"
    echo "  \"started_at\": \"$STARTED_AT\","
    echo "  \"base_url\": \"$BASE\","
    echo "  \"scope\": \"$SCOPE\","
    echo "  \"scope_reason\": \"$SCOPE_REASON\","
    echo "  \"priority_filter\": \"${PRIORITY:-}\","
    echo "  \"total\": $TOTAL, \"passed\": $PASSED, \"failed\": $FAILED, \"timeout\": $TIMEDOUT,"
    echo "  \"duration_ms\": $((RUN_DUR * 1000)),"
    echo "  \"cases\": [${RESULTS_JSON#,}"
    echo "  ]"
    echo "}"
  } > "$JSON_OUT"
  # 自校验：产出必须是合法 JSON，否则下游解析失败会被误判成 e2e 失败
  if jq empty "$JSON_OUT" 2>/dev/null; then
    echo "结构化报告：$JSON_OUT"
  else
    echo "⚠️  报告 JSON 非法，请检查：$JSON_OUT" >&2
    exit 1
  fi
fi

rm -rf "$TMPDIR_RUN"
rmdir "$SCRIPT_DIR/.e2e-run" 2>/dev/null || true
[ $((FAILED + TIMEDOUT)) -eq 0 ] || exit 1
exit 0

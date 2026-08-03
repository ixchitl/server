# Gotify e2e 测试套件

bash + curl + jq。一个脚本文件 = 一个 e2e_case（对齐 v9 §7.2 `e2e_cases` 表的 `file_path` 口径）。

用例清单与断言依据见 [`../Gotify-e2e完整测试规格.md`](../Gotify-e2e完整测试规格.md)。

## 快速开始

```bash
export GOTIFY_URL=http://localhost:8080     # 被测服务地址
./run.sh                                    # 全量 19 文件 / 128 用例，约 44s
```

## 执行器

```bash
./run.sh --list                             # 只列出将执行的用例
./run.sh --scope message,cross              # 按模块目录
./run.sh --priority P0                      # 按优先级
./run.sh --diff api/message.go              # 按 diff 自动选范围（smart scope）
./run.sh --json report.json                 # 结构化报告（给 report_e2e_result 消费）
./run.sh --timeout 180                      # 单文件超时，默认 120s
```

退出码：`0` 全过 / `1` 有失败 / `2` 参数错 / `3` 被测服务不可达或环境不可用。

**退出码 3 单独分出来是有意的**：服务没起来、临时目录不可写这类问题属 L3 环境层，
不能让它以「所有用例失败」的形式报出去——那会让归因直接跑偏到 L4 代码层。

## 两条硬约束

**① 必须串行。** `lib/common.sh` 的 `teardown` 用 admin basicAuth 清空全部测试数据，
并行执行会互删对方资源。`run.sh` 保证串行。

**② 用例必须自包含。** 自己造数据、自己断言，不依赖上一个脚本的遗留状态。
测试环境每轮重建（gotify 的 SQLite 在容器内，Pod 重建即清零），这是刻意的设计。

## 写用例时的五个坑（都踩过）

| # | 坑 | 正确做法 |
|---|---|---|
| 1 | 尾部写清理，断言一失败就跳过 | **不要自己写清理**，`common.sh` 已注册 `trap teardown EXIT INT TERM`；有额外资源就定义 `custom_teardown` 函数 |
| 2 | 分别调 `create_app_id` 和 `create_app_token` | 那会建出**两个**应用。用 `read -r ID TOKEN <<< "$(create_app "$TOK" "名字")"` |
| 3 | 用普通 clientToken 调提权路由 | 5 条路由必须 `http_elevated`（清单见规格文档），否则 403 |
| 4 | `jq -r '.x.token'` 跟 `""` 比 | 字段缺失时 `jq -r` 输出字面量 `null`。用 `assert_json_empty` |
| 5 | 循环变量取名 `UID` | `UID` 是 bash 内置只读变量，赋值即报错退出。换个名字 |

## 本地起被测服务

集群外没有 docker 时可直接从源码编译：

```bash
cd <gotify-server>
# 🔴 先造两个占位文件，否则 ui.Register 启动即 panic（embed build/* + 运行期读这两个）
mkdir -p ui/build
printf '<!doctype html><html><body>stub %%CONFIG%%</body></html>' > ui/build/index.html
printf '{"name":"Gotify"}' > ui/build/manifest.json

CGO_ENABLED=1 go build -o /tmp/gotify .        # 需 Go 1.26+ 与 gcc/clang（SQLite 走 CGO）
GOTIFY_SERVER_PORT=18080 /tmp/gotify           # 默认端口 80 要 root，换个高端口
```

## 结构化报告字段

```jsonc
{
  "started_at": "...", "base_url": "...",
  "scope": "health message", "scope_reason": "diff 映射: api/message.go",
  "total": 19, "passed": 19, "failed": 0, "timeout": 0, "duration_ms": 44000,
  "cases": [
    { "file_path": "message/test_send.sh", "priority": "P0", "module": "message",
      "stability": "stable", "result": "pass", "duration_ms": 2000, "log": "..." }
  ]
}
```

`result` 取值 `pass` / `fail` / `timeout`。失败时 `log` 保留完整输出，供 L1-L4 归因。

## 基线

2026-08-03 实测：**19/19 PASS，44s**，连跑两遍结果一致。

# 为阿里云 ACR 构建简化的 Dockerfile
#
# 与官方 docker/Dockerfile 的区别（后者无法在 ACR 上构建）：
#   - 不依赖 buildx 的 TARGETPLATFORM 变量与 bash 风格变量替换
#   - 不拉 node:24（BUILD_JS=0 时它只是 mkdir 空目录）
#   - 运行镜像用 debian:bookworm-slim 而非 unstable 的 debian:sid
#
# ── 构建阶段 ──────────────────────────────────────────────
FROM golang:1.26 AS builder

# 国内网络必需，否则 proxy.golang.org 会超时
ENV GOPROXY=https://goproxy.cn,direct
# gotify 用 mattn/go-sqlite3（CGO），必须开
ENV CGO_ENABLED=1

WORKDIR /src

# 先单独下依赖 —— layer cache 让「改代码重新构建」只重编译不重下载
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# ui/build 被 ui/.gitignore 排除，且这两个文件都是必需的：
#   index.html    —— //go:embed build/* 编译期要求目录至少有一个文件
#   manifest.json —— ui.Register() 启动时 box.ReadFile("build/manifest.json")，缺了直接 panic
# 只造 index.html 会「编译成功但容器启动 panic」。
RUN mkdir -p ui/build \
 && echo '<html><body>gotify</body></html>' > ui/build/index.html \
 && echo '{"name":"Gotify","short_name":"Gotify","start_url":"/","display":"standalone"}' > ui/build/manifest.json

RUN go build -ldflags="-s -w" -o /gotify-app app.go

# ── 运行阶段 ──────────────────────────────────────────────
# 不能用 scratch / distroless-static：CGO 动态链接 glibc
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /gotify-app .

ENV GOTIFY_SERVER_PORT=80 GIN_MODE=release
EXPOSE 80

# 健康检查交给 K8s readinessProbe（httpGet /health），此处不设 HEALTHCHECK
ENTRYPOINT ["./gotify-app"]
CMD ["serve"]

# 为阿里云 ACR 构建的 Dockerfile
#
# 设计约束（均为实测结论）：
#   1. 不能用 golang:1.26 —— ACR 构建环境拉 docker.io 超时
#      （debian:bookworm-slim 被 ACR 托管，能秒拉；golang 未托管）
#      故改为 debian 基础镜像 + 从 mirrors.aliyun.com 装 Go
#   2. 不能用 scratch/distroless-static —— CGO(go-sqlite3) 动态链接 glibc
#   3. ui/build 需要 index.html + manifest.json 两个文件，缺一个容器启动即 panic
#   4. 官方 docker/Dockerfile 依赖 buildx TARGETPLATFORM，在 ACR 上跑不了
#
# ── 构建阶段 ──────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

ARG GO_VERSION=1.26.5

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gcc libc6-dev git \
 && rm -rf /var/lib/apt/lists/*

# 从阿里云镜像装 Go（沙箱实测 14.3 MB/s；docker.io 的 golang 镜像拉不到）
RUN curl -sSL --retry 3 "https://mirrors.aliyun.com/golang/go${GO_VERSION}.linux-amd64.tar.gz" \
      -o /tmp/go.tgz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz

ENV PATH=/usr/local/go/bin:$PATH \
    GOPROXY=https://goproxy.cn,direct \
    CGO_ENABLED=1

WORKDIR /src

# 先单独下依赖 —— layer cache 让「改代码重新构建」只重编译不重下载
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# ui/build 被 ui/.gitignore 排除，这两个文件都必需：
#   index.html    —— //go:embed build/* 编译期要求目录至少有一个文件
#   manifest.json —— ui.Register() 启动时 box.ReadFile("build/manifest.json")，缺了 panic
RUN mkdir -p ui/build \
 && echo '<html><body>gotify</body></html>' > ui/build/index.html \
 && echo '{"name":"Gotify","short_name":"Gotify","start_url":"/","display":"standalone"}' > ui/build/manifest.json

RUN go build -ldflags="-s -w" -o /gotify-app app.go

# ── 运行阶段 ──────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /gotify-app .

ENV GOTIFY_SERVER_PORT=80 GIN_MODE=release
EXPOSE 80

# 健康检查交给 K8s readinessProbe（httpGet /health）
ENTRYPOINT ["./gotify-app"]
CMD ["serve"]

# 为阿里云 ACR 构建的 Dockerfile
#
# ACR 构建环境实测约束：
#   1. golang:1.26 拉不到（docker.io i/o timeout）；debian:bookworm-slim 被 ACR
#      托管可秒拉 → 用 debian + 从 mirrors.aliyun.com 装 Go
#   2. ACR 托管的 debian:bookworm-slim 缺 GPG keyring（/usr/share/keyrings/ 与
#      /etc/apt/trusted.gpg.d/ 均为空，debian_version=bookworm/sid），且用老式
#      sources.list 而非 deb822。官方源与阿里云源报完全相同的 NO_PUBKEY，
#      证明问题在客户端而非服务端。
#      → 分两阶段：仅装 debian-archive-keyring 时放开验证，装完立即恢复
#   3. 运行镜像不能用 scratch/distroless-static（CGO 动态链接 glibc）
#   4. ui/build 需要 index.html + manifest.json，缺一个容器启动即 panic

FROM debian:bookworm-slim AS aptbase

# 两阶段修复 keyring：不可信窗口仅限 keyring 包本身
RUN set -eux; \
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do \
      [ -f "$f" ] || continue; \
      sed -i \
        -e 's|https\?://deb.debian.org/debian|http://mirrors.aliyun.com/debian|g' \
        -e 's|https\?://security.debian.org/debian-security|http://mirrors.aliyun.com/debian-security|g' \
        -e 's|^deb |deb [trusted=yes] |' "$f"; \
    done; \
    apt-get -o Acquire::AllowInsecureRepositories=true update; \
    apt-get install -y --allow-unauthenticated --no-install-recommends \
        debian-archive-keyring ca-certificates; \
    # keyring 就位 → 撤掉 trusted=yes，后续所有包恢复签名验证
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do \
      [ -f "$f" ] || continue; \
      sed -i 's| \[trusted=yes\]||g' "$f"; \
    done; \
    apt-get update; \
    echo "### keyring 修复后可用密钥:"; ls -1 /usr/share/keyrings/ || true

# ── 构建阶段 ──────────────────────────────────────────────
FROM aptbase AS builder
ARG GO_VERSION=1.26.5

# 这些包已恢复签名验证
RUN set -eux; \
    apt-get install -y --no-install-recommends gcc libc6-dev curl git; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN set -eux; \
    curl -sSL --retry 3 "https://mirrors.aliyun.com/golang/go${GO_VERSION}.linux-amd64.tar.gz" \
      -o /tmp/go.tgz; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm -f /tmp/go.tgz

ENV PATH=/usr/local/go/bin:$PATH \
    GOPROXY=https://goproxy.cn,direct \
    CGO_ENABLED=1

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# index.html 满足编译期 //go:embed build/*；manifest.json 满足运行期 ui.Register()
RUN set -eux; \
    mkdir -p ui/build; \
    echo '<html><body>gotify</body></html>' > ui/build/index.html; \
    echo '{"name":"Gotify","short_name":"Gotify","start_url":"/","display":"standalone"}' > ui/build/manifest.json

RUN go build -ldflags="-s -w" -o /gotify-app app.go

# ── 运行阶段 ──────────────────────────────────────────────
FROM aptbase

RUN set -eux; \
    apt-get install -y --no-install-recommends curl tzdata; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app
COPY --from=builder /gotify-app .
ENV GOTIFY_SERVER_PORT=80 GIN_MODE=release
EXPOSE 80
ENTRYPOINT ["./gotify-app"]
CMD ["serve"]

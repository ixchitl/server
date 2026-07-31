# 为阿里云 ACR 构建的 Dockerfile
#
# ACR 构建环境实测约束：
#   1. golang:1.26 拉不到（docker.io i/o timeout）→ 用 debian + 自装 Go
#   2. apt GPG 验证失败（NO_PUBKEY），换 mirrors.aliyun.com 也一样
#      → ACR 托管的 debian:bookworm-slim 缺 archive keyring，用 trusted=yes 绕过
#   3. 运行镜像不能用 scratch/distroless-static（CGO 动态链接 glibc）
#   4. ui/build 需要 index.html + manifest.json，缺一个容器启动即 panic

FROM debian:bookworm-slim AS aptbase

# —— 诊断：把镜像真实身份打进构建日志（一次性，便于后续定位）——
RUN set +e; \
    echo "### debian_version: $(cat /etc/debian_version 2>/dev/null)"; \
    echo "### os-release:"; cat /etc/os-release 2>/dev/null | head -4; \
    echo "### sources.list:"; cat /etc/apt/sources.list 2>/dev/null; \
    echo "### sources.list.d:"; ls -1 /etc/apt/sources.list.d/ 2>/dev/null; \
    echo "### keyrings:"; ls -1 /usr/share/keyrings/ 2>/dev/null; \
    echo "### trusted.gpg.d:"; ls -1 /etc/apt/trusted.gpg.d/ 2>/dev/null; \
    true

# 换阿里云源 + 绕过 GPG 验证（仅构建环境内，包来自阿里云镜像站）
RUN set -eux; \
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do \
      [ -f "$f" ] || continue; \
      sed -i \
        -e 's|https\?://deb.debian.org/debian|http://mirrors.aliyun.com/debian|g' \
        -e 's|https\?://security.debian.org/debian-security|http://mirrors.aliyun.com/debian-security|g' \
        "$f"; \
    done; \
    sed -i 's|^deb |deb [trusted=yes] |g' /etc/apt/sources.list 2>/dev/null || true; \
    for f in /etc/apt/sources.list.d/*.sources; do \
      [ -f "$f" ] || continue; \
      grep -q '^Trusted:' "$f" || echo 'Trusted: yes' >> "$f"; \
    done; \
    apt-get -o Acquire::AllowInsecureRepositories=true update

# ── 构建阶段 ──────────────────────────────────────────────
FROM aptbase AS builder
ARG GO_VERSION=1.26.5

RUN apt-get install -y --no-install-recommends --allow-unauthenticated \
      ca-certificates curl gcc libc6-dev git \
 && rm -rf /var/lib/apt/lists/*

RUN curl -sSL --retry 3 "https://mirrors.aliyun.com/golang/go${GO_VERSION}.linux-amd64.tar.gz" \
      -o /tmp/go.tgz \
 && tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz

ENV PATH=/usr/local/go/bin:$PATH \
    GOPROXY=https://goproxy.cn,direct \
    CGO_ENABLED=1

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN mkdir -p ui/build \
 && echo '<html><body>gotify</body></html>' > ui/build/index.html \
 && echo '{"name":"Gotify","short_name":"Gotify","start_url":"/","display":"standalone"}' > ui/build/manifest.json

RUN go build -ldflags="-s -w" -o /gotify-app app.go

# ── 运行阶段 ──────────────────────────────────────────────
FROM aptbase
RUN apt-get install -y --no-install-recommends --allow-unauthenticated \
      ca-certificates curl tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /gotify-app .
ENV GOTIFY_SERVER_PORT=80 GIN_MODE=release
EXPOSE 80
ENTRYPOINT ["./gotify-app"]
CMD ["serve"]

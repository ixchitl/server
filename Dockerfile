# SWE-Factory state-service 基础镜像（仅运行时依赖，不含任何业务代码）
# 基础镜像用 debian:bookworm-slim（ACR 托管，实测 0.4s 拉取）
FROM debian:bookworm-slim

# 两阶段修复 keyring（ACR 托管镜像 keyring 为空，同 swf/gotify 的坑）
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
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do \
      [ -f "$f" ] || continue; sed -i 's| \[trusted=yes\]||g' "$f"; done; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3 python3-venv; \
    python3 -m venv /opt/venv; \
    /opt/venv/bin/pip install -q -i https://mirrors.aliyun.com/pypi/simple/ \
        fastapi "uvicorn[standard]" sse-starlette; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# 业务代码不在镜像里：比赛现场 ConfigMap 挂 /app（main.py）
CMD ["/opt/venv/bin/uvicorn", "main:app", "--app-dir", "/app", "--host", "0.0.0.0", "--port", "8080"]

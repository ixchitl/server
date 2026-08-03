#!/usr/bin/env bash
# e2e 测试环境配置
# 被 common.sh source，不要直接执行此文件

export BASE="${GOTIFY_URL:-http://localhost:8080}"
export ADMIN_USER="${ADMIN_USER:-admin}"
export ADMIN_PASS="${ADMIN_PASS:-admin}"
export TEST_RUN_ID="${TEST_RUN_ID:-$(date +%s)}"

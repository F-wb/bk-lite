#!/usr/bin/env bash
# ==============================================================================
# 盛大运维系统 镜像覆盖层：把前后端镜像指向本项目仓库
#
# 特性：幂等（可反复执行）、带断言（变量名不存在时立即失败，绝不静默跳过）
#
# 用法：
#   bash overlay-images.sh                                  # 使用滚动 tag（:server / :web）
#   SERVER_TAG=server-20261015c WEB_TAG=web-20261015b \
#     bash overlay-images.sh                                # 钉住版本化 tag
#
# 环境变量覆盖：ENV_FILE / ACR / SERVER_TAG / WEB_TAG
#
# 重要：本脚本"故意"采用「断言 + 失败即停」而非「找不到就跳过」。
#      跳过会造成无报错的静默失效——服务照常运行但跑的是基线版前后端，
#      二开功能（品牌、钉钉登录、SSH 终端）整体消失且日志无异常。
#      报错是安全的，静默才是危险的。
# ==============================================================================
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/bk-lite/.env}"
ACR="${ACR:-crpi-qp8pnmdzkajoq92t.cn-hangzhou.personal.cr.aliyuncs.com/fanwenbin/bk-lite}"
SERVER_TAG="${SERVER_TAG:-server}"
WEB_TAG="${WEB_TAG:-web}"

[ -f "$ENV_FILE" ] || { echo "[FATAL] 未找到 $ENV_FILE：基线安装未完成或目录结构已变更" >&2; exit 1; }

# ── 断言：基线必须仍提供这两个变量名 ────────────────────────────────
missing=0
for k in DOCKER_IMAGE_SERVER DOCKER_IMAGE_WEB; do
  grep -qE "^${k}=" "$ENV_FILE" || {
    echo "[FATAL] $ENV_FILE 中缺少变量 $k —— 基线可能已变更命名/结构，请人工核对后再覆盖（见部署手册第五章场景 C）" >&2
    missing=1
  }
done
[ "$missing" -eq 0 ] || exit 1

# ── 备份 + 覆盖（幂等）─────────────────────────────────────────────
cp -a "$ENV_FILE" "${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
sed -i -E "s|^DOCKER_IMAGE_SERVER=.*|DOCKER_IMAGE_SERVER=${ACR}:${SERVER_TAG}|" "$ENV_FILE"
sed -i -E "s|^DOCKER_IMAGE_WEB=.*|DOCKER_IMAGE_WEB=${ACR}:${WEB_TAG}|" "$ENV_FILE"

echo "[OK] 覆盖完成："
grep -E '^DOCKER_IMAGE_(SERVER|WEB)=' "$ENV_FILE"
echo "[提示] 需执行 'cd /opt/bk-lite && docker compose up -d --force-recreate server web' 才生效（restart 不重建容器）"

#!/usr/bin/env bash
# ==============================================================================
# 盛大运维系统 —— 一键全量备份脚本
#
# 备份范围（按数据重要性分级）：
#   [P0] PostgreSQL  主业务库 bklite
#   [P0] PGVector    向量库 metis（独立容器 pgvector）
#   [P1] FalkorDB    CMDB 图数据（RDB 快照）
#   [P2] VictoriaLogs 日志（数据目录打包，可重复采集，失败不阻断）
#   [P2/P3] 数据卷   minio / victoria-metrics / redis / nats（--with-volumes 时启用）
#
# 特性：
#   - 幂等：可反复执行，每次生成独立时间戳目录，用 <备份根>/latest 软链指向最新
#   - 带断言：前置条件不满足立即失败退出（不产生"看起来成功"的假备份）
#   - 完整性：自动生成 SHA256SUMS 与 MANIFEST.txt
#   - 保留策略：自动清理超过 KEEP_DAYS 天的历史备份
#
# 用法：
#   bash backup-all.sh                  # 备份 P0/P1/P2 逻辑数据
#   bash backup-all.sh --with-volumes   # 额外打包数据卷
# 环境变量覆盖：
#   DEPLOY_DIR=/opt/bk-lite  BACKUP_ROOT=/opt/bk-lite/backup  KEEP_DAYS=14
# ==============================================================================
set -uo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/bk-lite}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/bk-lite/backup}"
LOG_FILE="${LOG_FILE:-/var/log/shengda_backup.log}"
KEEP_DAYS="${KEEP_DAYS:-14}"

WITH_VOLUMES=0
for a in "$@"; do
  case "$a" in
    --with-volumes) WITH_VOLUMES=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "未知参数：$a（可用：--with-volumes）"; exit 2 ;;
  esac
done

DATE="$(date +%Y%m%d_%H%M%S)"
DEST="${BACKUP_ROOT}/${DATE}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"; }
die() { log "【失败】$*"; exit 1; }

# ---------- 0. 前置自检 ----------
[ "$(id -u)" -eq 0 ] || die "需要 root 权限执行"
[ -d "${DEPLOY_DIR}" ] || die "部署目录不存在：${DEPLOY_DIR}"
command -v docker >/dev/null || die "未找到 docker 命令"
cd "${DEPLOY_DIR}" || die "无法进入部署目录"

mkdir -p "${BACKUP_ROOT}"
mkdir -p "${DEST}"
[ -w "${BACKUP_ROOT}" ] || die "备份根目录不可写：${BACKUP_ROOT}"

# 读取 .env 单个变量（避免 source 多行证书变量导致的解析异常）
envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2-; }
# 解析 compose 服务名 → 容器 ID（同时兼容 container_name 与 compose-<svc>-1 两种命名）
cid() { docker compose ps -q "$1" 2>/dev/null; }

FALKORDB_PASSWORD="$(envval FALKORDB_PASSWORD)"
[ -n "${FALKORDB_PASSWORD}" ] || die "未在 .env 中找到 FALKORDB_PASSWORD"

# 打包工具容器镜像：复用本机已存在的 postgres 镜像（含 tar/gzip，无需额外拉取）
HELPER_IMAGE="$(docker inspect "$(cid postgres)" --format '{{.Config.Image}}' 2>/dev/null)"
[ -n "${HELPER_IMAGE}" ] || die "无法解析打包工具镜像（postgres 容器未运行？）"

for svc in postgres pgvector falkordb; do
  [ -n "$(cid "$svc")" ] || die "服务『${svc}』未在运行，无法备份（请先 docker compose up -d）"
done

log "========== 备份开始 =========="
log "主机：$(hostname)  部署目录：${DEPLOY_DIR}  目标：${DEST}"
log "可用磁盘：$(df -h "${BACKUP_ROOT}" | awk 'NR==2{print $4}')"

# ---------- 1. [P0] PostgreSQL 主库 bklite ----------
log ">>> [P0] PostgreSQL  bklite"
mkdir -p "${DEST}/postgres"
docker compose exec -T postgres pg_dump -U postgres -Fc -d bklite \
  > "${DEST}/postgres/bklite_${DATE}.dump" || die "bklite 备份失败"
[ -s "${DEST}/postgres/bklite_${DATE}.dump" ] || die "bklite 备份文件为空（异常）"
log "    OK  $(du -h "${DEST}/postgres/bklite_${DATE}.dump" | cut -f1)"

# ---------- 2. [P0] PGVector 向量库 metis ----------
# 注意：本环境中 PGVector 为独立容器 pgvector（非与 postgres 共库），故 exec 到 pgvector
log ">>> [P0] PGVector  metis（容器 pgvector）"
mkdir -p "${DEST}/pgvector"
docker compose exec -T pgvector pg_dump -U postgres -Fc -d metis \
  > "${DEST}/pgvector/metis_${DATE}.dump" || die "metis 备份失败"
[ -s "${DEST}/pgvector/metis_${DATE}.dump" ] || die "metis 备份文件为空（异常）"
log "    OK  $(du -h "${DEST}/pgvector/metis_${DATE}.dump" | cut -f1)"

# ---------- 3. [P1] FalkorDB 图数据 ----------
log ">>> [P1] FalkorDB  CMDB 图数据"
mkdir -p "${DEST}/falkordb"
rcli() { docker compose exec -T falkordb redis-cli -a "${FALKORDB_PASSWORD}" --no-auth-warning "$@" 2>/dev/null | tr -d '\r'; }
LAST_BEFORE="$(rcli LASTSAVE)"
rcli BGSAVE >/dev/null || die "触发 BGSAVE 失败"
for _ in $(seq 1 30); do
  LAST_AFTER="$(rcli LASTSAVE)"
  [ -n "${LAST_AFTER}" ] && [ "${LAST_AFTER}" != "${LAST_BEFORE}" ] && break
  sleep 1
done
[ "${LAST_AFTER:-}" != "${LAST_BEFORE:-}" ] || die "BGSAVE 未在 30s 内完成，请检查 falkordb 状态"
docker compose cp falkordb:/var/lib/falkordb/data/dump.rdb "${DEST}/falkordb/dump_${DATE}.rdb" \
  || die "dump.rdb 复制失败"
log "    OK  $(du -h "${DEST}/falkordb/dump_${DATE}.rdb" | cut -f1)"

# ---------- 4. [P2] VictoriaLogs 数据目录打包（失败不阻断） ----------
# 说明：本环境 VictoriaLogs v1.49.0 不提供 /snapshot/create 在线快照接口，
#       故采用「短暂停服 + 数据目录打包」方式，日志数据可重复采集，风险低。
log ">>> [P2] VictoriaLogs  数据目录打包"
mkdir -p "${DEST}/victorialogs"
docker compose stop victoria-logs >/dev/null 2>&1 || true
if docker run --rm -v compose_victoria-logs:/src:ro -v "${DEST}/victorialogs:/out" "${HELPER_IMAGE}" \
     tar czf "/out/victoria-logs_${DATE}.tar.gz" -C /src . ; then
  log "    OK  victoria-logs_${DATE}.tar.gz  $(du -h "${DEST}/victorialogs/victoria-logs_${DATE}.tar.gz" | cut -f1)"
else
  log "    警告：VictoriaLogs 打包失败（不阻断，日志可重新采集）"
fi
docker compose start victoria-logs >/dev/null 2>&1 || log "    警告：victoria-logs 启动异常，请手动 docker compose up -d victoria-logs"

# ---------- 5. [P2/P3] 可选数据卷打包 ----------
if [ "${WITH_VOLUMES}" -eq 1 ]; then
  log ">>> [P2/P3] 其余数据卷打包"
  mkdir -p "${DEST}/volumes"
  vol_dump() { # $1=卷名  $2=输出文件名
    if docker run --rm -v "$1:/src:ro" -v "${DEST}/volumes:/out" "${HELPER_IMAGE}" \
         tar czf "/out/$2" -C /src . ; then
      log "    OK  $2  $(du -h "${DEST}/volumes/$2" | cut -f1)"
    else
      log "    警告：卷 $1 打包失败（不阻断）"
    fi
  }
  vol_dump compose_minio            "minio_${DATE}.tar.gz"
  vol_dump compose_victoria-metrics "victoria-metrics_${DATE}.tar.gz"
  vol_dump compose_redis            "redis_${DATE}.tar.gz"
  vol_dump compose_nats             "nats_${DATE}.tar.gz"
fi

# ---------- 6. 校验值与清单 ----------
log ">>> 生成 SHA256 校验值与清单"
( cd "${DEST}" && find . -type f ! -name 'SHA256SUMS' ! -name 'MANIFEST.txt' -print0 \
    | sort -z | xargs -0 sha256sum > SHA256SUMS )
{
  echo "盛大运维系统 备份清单 MANIFEST"
  echo "备份时间 : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "主机     : $(hostname)"
  echo "部署目录 : ${DEPLOY_DIR}"
  echo "数据卷   : $([ "${WITH_VOLUMES}" -eq 1 ] && echo 已包含 || echo 未包含)"
  echo "------------------------------------------"
  cat "${DEST}/SHA256SUMS"
} > "${DEST}/MANIFEST.txt"
ln -sfn "${DEST}" "${BACKUP_ROOT}/latest"
log "    OK  ${DEST}/SHA256SUMS"

# ---------- 7. 保留期清理 ----------
log ">>> 清理 ${KEEP_DAYS} 天前的备份"
find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime "+${KEEP_DAYS}" -print 2>/dev/null \
  | while read -r old; do rm -rf "${old}"; log "    已删除 ${old}"; done

# ---------- 8. 汇总 ----------
log "========== 备份完成 =========="
find "${DEST}" -type f | sort | while read -r f; do log "  $(du -h "$f" | cut -f1)  ${f}"; done
log "备份根目录总占用：$(du -sh "${BACKUP_ROOT}" | cut -f1)"
log "最新备份软链：${BACKUP_ROOT}/latest -> ${DEST}"

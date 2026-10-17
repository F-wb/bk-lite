#!/usr/bin/env bash
# ==============================================================================
# 盛大运维系统 —— 数据还原脚本（支持全量或单项还原）
#
# 用法：
#   bash restore-all.sh --from /opt/bk-lite/backup/20261015_120000            # 全量还原
#   bash restore-all.sh --from <dir> --only postgres                           # 仅还原主库
#   bash restore-all.sh --from <dir> --only falkordb,victorialogs              # 多项还原
#   bash restore-all.sh --from <dir> --yes                                     # 跳过交互确认（用于演练/自动化）
#
# 可选范围(--only)：all | postgres | pgvector | falkordb | victorialogs
#
# 安全设计：
#   1) 强制二次确认（除非显式 --yes），防误触
#   2) 还原前校验 SHA256SUMS（文件被篡改/损坏时中止）
#   3) 还原前默认自动执行一次安全备份（可用 SAFETY_BACKUP=0 关闭）
#   4) 关键步骤失败即退出，不做"部分成功"的静默降级
#
# 警告：还原会覆盖现有数据。生产环境执行前务必确认 --from 指向正确的备份。
# ==============================================================================
set -uo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/bk-lite}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/bk-lite/backup}"
LOG_FILE="${LOG_FILE:-/var/log/shengda_restore.log}"
SAFETY_BACKUP="${SAFETY_BACKUP:-1}"

FROM=""; ONLY="all"; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "未知参数：$1"; exit 2 ;;
  esac
done

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"; }
die() { log "【失败】$*"; exit 1; }
want() { # 判断当前 --only 是否包含某组件
  [ "${ONLY}" = "all" ] && return 0
  case ",${ONLY}," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

[ "$(id -u)" -eq 0 ] || die "需要 root 权限执行"
[ -n "${FROM}" ] || die "缺少 --from <备份目录> 参数"
[ -d "${FROM}" ] || die "备份目录不存在：${FROM}"
[ -d "${DEPLOY_DIR}" ] || die "部署目录不存在：${DEPLOY_DIR}"
cd "${DEPLOY_DIR}" || die "无法进入部署目录"

envval() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2-; }
cid() { docker compose ps -q "$1" 2>/dev/null; }
HELPER_IMAGE="$(docker inspect "$(cid postgres)" --format '{{.Config.Image}}' 2>/dev/null)"
FALKORDB_PASSWORD="$(envval FALKORDB_PASSWORD)"

log "========== 还原开始 =========="
log "来源备份：${FROM}"
log "还原范围：${ONLY}"

# ---------- 1. 校验备份完整性 ----------
if [ -f "${FROM}/SHA256SUMS" ]; then
  log ">>> 校验 SHA256SUMS"
  ( cd "${FROM}" && sha256sum -c SHA256SUMS --quiet ) || die "备份文件校验失败（文件损坏或被篡改）"
  log "    OK  全部文件校验通过"
else
  log "    警告：未找到 SHA256SUMS，跳过完整性校验"
fi

# ---------- 2. 定位各项备份文件 ----------
PG_DUMP="$(ls -1t "${FROM}"/postgres/bklite_*.dump 2>/dev/null | head -1)"
PGV_DUMP="$(ls -1t "${FROM}"/pgvector/metis_*.dump 2>/dev/null | head -1)"
FK_RDB="$(ls -1t "${FROM}"/falkordb/*.rdb 2>/dev/null | head -1)"
VL_TAR="$(ls -1t "${FROM}"/victorialogs/*.tar.gz 2>/dev/null | head -1)"
VL_SNAP="$(ls -1dt "${FROM}"/victorialogs/snapshot_* 2>/dev/null | head -1)"; VL_SRC="${VL_TAR:-${VL_SNAP}}"

# ---------- 3. 二次确认 ----------
log "------------------------------------------"
log "即将还原以下内容（覆盖现有数据）："
want postgres     && log "  [P0] PostgreSQL bklite  <-  ${PG_DUMP:-<缺失>}"
want pgvector     && log "  [P0] PGVector   metis   <-  ${PGV_DUMP:-<缺失>}"
want falkordb     && log "  [P1] FalkorDB   图数据   <-  ${FK_RDB:-<缺失>}"
want victorialogs && log "  [P2] VictoriaLogs 日志   <-  ${VL_SRC:-<缺失>}"
log "------------------------------------------"
if [ "${ASSUME_YES}" -ne 1 ]; then
  printf '确认执行请输入大写 YES 回车：'
  read -r ans
  [ "${ans}" = "YES" ] || die "用户取消"
fi

# ---------- 4. 还原前安全备份 ----------
if [ "${SAFETY_BACKUP}" = "1" ] && [ -x "${DEPLOY_DIR}/scripts/backup-all.sh" ]; then
  log ">>> 执行还原前安全备份"
  bash "${DEPLOY_DIR}/scripts/backup-all.sh" || log "    警告：安全备份失败（不阻断，但请人工确认）"
fi

# ---------- 5. 还原 PostgreSQL 主库 bklite ----------
if want postgres; then
  [ -n "${PG_DUMP}" ] || die "未在 ${FROM}/postgres 找到 bklite 备份文件"
  log ">>> [P0] 还原 PostgreSQL bklite"
  log "    停止依赖服务 server / web（释放数据库连接）"
  docker compose stop server web >/dev/null 2>&1 || true
  docker compose exec -T postgres psql -U postgres -q -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='bklite' AND pid<>pg_backend_pid();" >/dev/null
  docker compose exec -T postgres psql -U postgres -q -c "DROP DATABASE IF EXISTS bklite;" || die "删除旧库 bklite 失败"
  docker compose exec -T postgres psql -U postgres -q -c "CREATE DATABASE bklite;" || die "创建新库 bklite 失败"
  cat "${PG_DUMP}" | docker compose exec -T postgres pg_restore -U postgres -d bklite --no-owner --no-acl \
    || log "    警告：pg_restore 返回非零（若仅扩展/权限告警可忽略，请复核下方表数量）"
  TB="$(docker compose exec -T postgres psql -U postgres -d bklite -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '\r')"
  [ "${TB:-0}" -gt 0 ] || die "还原后 bklite 无任何表，还原失败"
  log "    OK  bklite 还原完成，public 表数量=${TB}"
fi

# ---------- 6. 还原 PGVector metis ----------
if want pgvector; then
  [ -n "${PGV_DUMP}" ] || die "未在 ${FROM}/pgvector 找到 metis 备份文件"
  log ">>> [P0] 还原 PGVector metis（容器 pgvector）"
  docker compose exec -T pgvector psql -U postgres -q -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='metis' AND pid<>pg_backend_pid();" >/dev/null 2>&1 || true
  docker compose exec -T pgvector psql -U postgres -q -c "DROP DATABASE IF EXISTS metis;" || die "删除旧库 metis 失败"
  docker compose exec -T pgvector psql -U postgres -q -c "CREATE DATABASE metis;" || die "创建新库 metis 失败"
  docker compose exec -T pgvector psql -U postgres -d metis -q -c \
    "CREATE EXTENSION IF NOT EXISTS vector;" || die "创建 vector 扩展失败"
  cat "${PGV_DUMP}" | docker compose exec -T pgvector pg_restore -U postgres -d metis --no-owner --no-acl \
    || log "    警告：pg_restore 返回非零（请复核下方表数量）"
  TB="$(docker compose exec -T pgvector psql -U postgres -d metis -tAc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '\r')"
  log "    OK  metis 还原完成，public 表数量=${TB:-0}"
fi

# ---------- 7. 还原 FalkorDB ----------
if want falkordb; then
  [ -n "${FK_RDB}" ] || die "未在 ${FROM}/falkordb 找到 RDB 备份文件"
  log ">>> [P1] 还原 FalkorDB"
  docker compose stop falkordb >/dev/null 2>&1 || true
  docker compose cp "${FK_RDB}" falkordb:/var/lib/falkordb/data/dump.rdb || die "复制 dump.rdb 失败"
  # 防御性清理：若存在 AOF 文件会覆盖 RDB 语义，一并清除
  docker run --rm -v compose_falkordb:/fdb "${HELPER_IMAGE}" \
    sh -c 'rm -rf /fdb/appendonly.aof /fdb/appendonlydir' >/dev/null 2>&1 || true
  docker compose start falkordb >/dev/null || die "启动 falkordb 失败"
  sleep 3
  log "    OK  FalkorDB 还原完成（已加载 dump.rdb）"
fi

# ---------- 8. 还原 VictoriaLogs ----------
if want victorialogs; then
  if [ -n "${VL_SRC}" ]; then
    log ">>> [P2] 还原 VictoriaLogs"
    docker compose stop victoria-logs >/dev/null 2>&1 || true
    if [ -n "${VL_TAR}" ]; then
      docker run --rm -v compose_victoria-logs:/vlogs -v "${VL_TAR}:/src.tar.gz:ro" "${HELPER_IMAGE}" \
        sh -c 'rm -rf /vlogs/* && tar xzf /src.tar.gz -C /vlogs' || die "VictoriaLogs 数据写入失败"
    else
      docker run --rm -v compose_victoria-logs:/vlogs -v "${VL_SNAP}:/src:ro" "${HELPER_IMAGE}" \
        sh -c 'rm -rf /vlogs/* && cp -r /src/. /vlogs/' || die "VictoriaLogs 数据写入失败"
    fi
    docker compose start victoria-logs >/dev/null || die "启动 victoria-logs 失败"
    log "    OK  VictoriaLogs 还原完成"
  else
    log "    跳过 VictoriaLogs（未找到备份数据）"
  fi
fi

# ---------- 9. 恢复服务 ----------
log ">>> 启动 server / web"
docker compose up -d server web >/dev/null 2>&1 || log "    警告：server/web 启动异常，请检查 docker compose ps"
sleep 5

# ---------- 10. 还原后校验 ----------
log ">>> 还原后校验"
docker compose ps --format '{{.Name}}  {{.Status}}' | while read -r line; do log "    ${line}"; done
log "    提示：请登录 Web 验证用户/资产/知识库数据是否与备份时点一致"

log "========== 还原完成 =========="

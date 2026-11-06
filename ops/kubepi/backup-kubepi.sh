#!/usr/bin/env bash
# KubePi standalone backup for the 95 production instance.
# Kept separate from /opt/bk-lite/scripts/backup-all.sh on purpose:
#   - that script is the platform's own job and runs WITHOUT --with-volumes;
#     changing its invocation would alter platform behaviour beyond this task.
#   - KubePi data is bbolt: a consistent copy requires the writer to be paused.
# Style follows the house script: assertions, non-empty checks, SHA256SUMS,
# MANIFEST, latest symlink, KEEP_DAYS retention. No silent success.
set -uo pipefail

VOL=kubepi-data
CNAME=kubepi
IMAGE=1panel/kubepi:v2.0.3
APP_DIR=/opt/kubepi
BACKUP_ROOT=/opt/kubepi/backup
LOG_FILE=/var/log/kubepi_backup.log
KEEP_DAYS=14

DATE="$(date +%Y%m%d_%H%M%S)"
DEST="${BACKUP_ROOT}/${DATE}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"; }
die() { log "【失败】$*"; exit 1; }

# ---------- 0. assertions ----------
[ "$(id -u)" -eq 0 ] || die "需要 root"
command -v docker >/dev/null || die "未找到 docker"
docker ps -a --format '{{.Names}}' | grep -qx "${CNAME}" || die "容器 ${CNAME} 不存在"
docker volume ls --format '{{.Name}}' | grep -qx "${VOL}" || die "卷 ${VOL} 不存在"
FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
[ "${FREE_GB:-0}" -ge 5 ] || die "磁盘可用不足 5G（当前 ${FREE_GB}G）"
mkdir -p "${DEST}" || die "无法创建 ${DEST}"
[ -w "${DEST}" ] || die "备份目录不可写"

WAS_RUNNING=0
docker inspect "${CNAME}" --format '{{.State.Running}}' | grep -q true && WAS_RUNNING=1

# always bring the panel back, even if the copy step fails
resume() {
  if [ "${WAS_RUNNING}" -eq 1 ]; then
    docker start "${CNAME}" >/dev/null 2>&1 || log "警告：${CNAME} 启动异常，请人工确认 docker start ${CNAME}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      docker inspect "${CNAME}" --format '{{.State.Running}}' | grep -q true && return 0
      sleep 1
    done
    log "警告：${CNAME} 未在 10s 内回到 running，请人工检查"
  fi
}

# ---------- 1. pause writer, take the copy ----------
log "========== KubePi 备份开始 =========="
log "主机：$(hostname)  卷：${VOL}  目标：${DEST}"
if [ "${WAS_RUNNING}" -eq 1 ]; then
  docker stop -t 10 "${CNAME}" >/dev/null || { resume; die "停止 ${CNAME} 失败，未产生备份"; }
  log "    ${CNAME} 已暂停（bbolt 需冷拷贝，避免撕裂页）"
fi

if ! docker run --rm -v "${VOL}:/src:ro" -v "${DEST}:/out" "${IMAGE}" \
      tar czf "/out/kubepi-data_${DATE}.tar.gz" -C /src . ; then
  resume
  rm -rf "${DEST}"
  die "打包失败，已回滚本次目录"
fi
resume
[ -s "${DEST}/kubepi-data_${DATE}.tar.gz" ] || { rm -rf "${DEST}"; die "备份文件为空（异常）"; }
log "    OK  kubepi-data_${DATE}.tar.gz  $(du -h "${DEST}/kubepi-data_${DATE}.tar.gz" | cut -f1)"

# ---------- 2. carry the deploy definition (small, but restore needs it) ----------
cp -a "${APP_DIR}/docker-compose.yml" "${DEST}/docker-compose.yml.snapshot" \
  && log "    OK  compose 定义已随快照保存" || log "    警告：compose 定义复制失败（不阻断）"

# ---------- 3. verify the archive is readable, not just non-empty ----------
if docker run --rm -v "${DEST}:/in:ro" "${IMAGE}" tar tzf "/in/kubepi-data_${DATE}.tar.gz" >/dev/null 2>&1; then
  log "    OK  归档可解包校验通过"
else
  die "归档解包校验失败：${DEST}/kubepi-data_${DATE}.tar.gz"
fi

# ---------- 4. checksums + manifest + latest ----------
( cd "${DEST}" && find . -type f ! -name 'SHA256SUMS' ! -name 'MANIFEST.txt' -print0 \
    | sort -z | xargs -0 sha256sum > SHA256SUMS ) || die "生成校验值失败"
{
  echo "KubePi 备份清单 MANIFEST"
  echo "备份时间 : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "主机     : $(hostname)"
  echo "卷       : ${VOL}"
  echo "容器状态 : $(docker inspect "${CNAME}" --format '{{.State.Status}}' 2>/dev/null)"
  echo "------------------------------------------"
  cat "${DEST}/SHA256SUMS"
} > "${DEST}/MANIFEST.txt"
ln -sfn "${DEST}" "${BACKUP_ROOT}/latest"
log "    OK  ${DEST}/SHA256SUMS  latest -> ${DEST}"

# ---------- 5. retention ----------
find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime "+${KEEP_DAYS}" -print 2>/dev/null \
  | while read -r old; do rm -rf "${old}"; log "    已删除 ${old}"; done

log "备份根目录总占用：$(du -sh "${BACKUP_ROOT}" | cut -f1)"
log "========== KubePi 备份完成 =========="

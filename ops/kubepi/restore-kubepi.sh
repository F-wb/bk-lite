#!/usr/bin/env bash
# 集群管理面板（实现：KubePi）数据卷还原与还原性校验。
#
# 三种用法：
#   --verify-only          只证明快照可还原：解包到一次性临时卷、与生产库比 md5、删临时卷。不碰生产。
#   --from <快照目录>       真还原：用快照覆盖生产卷 kubepi-data。**会丢生产数据，需人工确认**。
#   任一用法加 --dry-run    只打印将要执行的命令，不执行。
#
# 为什么需要冷拷贝：面板库是 bbolt 单文件 + 独占文件锁，禁止两个实例同时打开同一份数据。
# 因此校验一律用一次性临时卷，绝不用快照再起常驻实例。
set -euo pipefail

DIR=/opt/kubepi
VOL=kubepi-data
CNAME=kubepi
IMG=1panel/kubepi:v2.0.3
TMPVOL=kubepi-restore-test
MODE=""; SNAPSHOT=""; DRYRUN=0

[ "$(id -u)" -eq 0 ] || { echo 'FATAL: 需 root 运行'; exit 1; }   # 断言不许删（沿用平台脚本准则）

while [ $# -gt 0 ]; do
  case "$1" in
    --verify-only) MODE=verify ;;
    --from)        MODE=restore; SNAPSHOT="${2:-}"; shift ;;
    --dry-run)     DRYRUN=1 ;;
    *) echo "FATAL: 未知参数 $1"; exit 1 ;;
  esac; shift
done

[ -n "$MODE" ] || { echo 'FATAL: 必须指定 --verify-only 或 --from <快照目录>'; exit 1; }

run() { if [ "$DRYRUN" -eq 1 ]; then echo "DRY-RUN: $*"; else echo "EXEC: $*"; "$@"; fi; }

latest_snapshot() { ls -1 "$DIR/backup/" | grep -E '^2[0-9]{7}_[0-9]{6}$' | tail -1; }

if [ "$MODE" = verify ]; then
  T="${SNAPSHOT:-$(latest_snapshot)}"
  [ -n "$T" ] && [ -d "$DIR/backup/$T" ] || { echo "FATAL: 快照不存在（当前取到：'$T'）"; exit 1; }
  echo "== 还原性校验：快照 $T =="
  # 临时卷可能因上次中断而残留；先探测再删，保证 --dry-run 下不产生任何真实调用
  if docker volume inspect "$TMPVOL" >/dev/null 2>&1; then run docker volume rm "$TMPVOL"; fi
  run docker volume create "$TMPVOL"
  run docker run --rm -v "$DIR/backup/$T:/in:ro" -v "$TMPVOL:/out" "$IMG" \
      sh -c 'tar xzf /in/kubepi-data_*.tar.gz -C /out && ls -l /out/db'
  echo -n 'restored md5  : '
  run docker run --rm -v "$TMPVOL:/src:ro" "$IMG" md5sum /src/db/kubepi.db
  echo -n 'production md5: '
  run docker run --rm -v "$VOL:/src:ro" "$IMG" md5sum /src/db/kubepi.db
  echo '== 只删除本脚本创建的临时卷，生产卷不动 =='
  if docker volume inspect "$TMPVOL" >/dev/null 2>&1; then run docker volume rm "$TMPVOL"; fi
  run docker inspect "$CNAME" --format 'state={{.State.Status}}'
  exit 0
fi

# ---- restore：破坏性路径，三道闸门 ----
[ -n "$SNAPSHOT" ] && [ -d "$SNAPSHOT" ] \
  || { echo "FATAL: --from 需指向存在的快照目录（如 $DIR/backup/20261106_024001）"; exit 1; }
ls "$SNAPSHOT"/kubepi-data_*.tar.gz >/dev/null 2>&1 \
  || { echo 'FATAL: 快照目录内找不到 kubepi-data_*.tar.gz'; exit 1; }
echo "!! 即将用 $SNAPSHOT 覆盖生产卷 $VOL，现有面板数据（集群导入、账号）将全部丢失 !!"
if [ "$DRYRUN" -ne 1 ]; then
  printf '确认请大写输入 YES：'; read -r A
  [ "$A" = "YES" ] || { echo '已取消'; exit 1; }
fi
run docker stop "$CNAME"
run docker run --rm -v "$SNAPSHOT:/in:ro" -v "$VOL:/out" "$IMG" \
    sh -c 'rm -rf /out/db && tar xzf /in/kubepi-data_*.tar.gz -C /out'
run docker start "$CNAME"
echo '== 还原后校验：入口须 200，且启动日志应出现 current db version（非空库标志）=='
run curl -s -o /dev/null -w 'http %{http_code}\n' --max-time 15 "http://127.0.0.1:18080/kubepi"
docker logs --since 1m "$CNAME" 2>&1 | grep -iE 'current db version|error' | tail -10 || true
echo '还原完成。若 compose 文件本身也丢失，先按 ops/kubepi/docker-compose.yml 重建：'
echo '  install -m 644 cron.d-kubepi-backup /etc/cron.d/kubepi-backup'
echo '  cd /opt/kubepi && docker compose -p kubepi up -d'

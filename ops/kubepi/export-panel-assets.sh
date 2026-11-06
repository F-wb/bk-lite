#!/usr/bin/env bash
# 集群管理面板 · 内容清单导出（M1-4 的固定做法）
#
# 安全前提（不可违反）：
#   1. 绝不打开生产卷 kubepi-data —— bbolt 单文件独占锁，两实例同开会数据分叉。
#   2. 绝不启动第二个面板实例。
#   3. 只读「备份快照的解包副本」，读完即删工作目录。
#   4. 输出不得包含任何令牌、证书或口令内容（脚本已按长度特征过滤）。
#
# 时效提醒：结果反映的是快照时刻，不是实时状态。
#   白天导入的集群要等次晨 02:40 的 cron 才进快照。若需要当前状态，
#   须先手动跑 /opt/kubepi/backup-kubepi.sh（该脚本会短暂停容器约 2 秒，属变更操作，需先告知）。
#
# 用法：在 95 上直接执行，输出为 YAML，人工核对后覆盖 ops/kubepi/panel-assets.yaml
set -u

BK=/opt/kubepi/backup
WORK=/root/kubepi-inv-work

T=$(ls -1 "$BK" | grep -E '^2[0-9]{7}_[0-9]{6}$' | tail -1)
[ -n "$T" ] || { echo 'FATAL: 没找到快照目录'; exit 1; }
ARCHIVE=$(ls "$BK/$T"/kubepi-data_*.tar.gz | tail -1)

rm -rf "$WORK"; mkdir -p "$WORK"
tar xzf "$ARCHIVE" -C "$WORK"
DB=$(find "$WORK" -name 'kubepi.db' | head -1)
[ -n "$DB" ] || { echo 'FATAL: 快照里没有 kubepi.db'; rm -rf "$WORK"; exit 1; }

txt() { tr -c '[:print:]\t' '\n' < "$DB"; }

echo "# 集群管理面板 · 内容清单（快照静态读取导出）"
echo "# 生成时间: $(date -Iseconds)  主机: $(hostname)"
echo "snapshot: \"${T}\""
echo "snapshot_file_md5: \"$(md5sum "$ARCHIVE" | awk '{print $1}')\""
echo "read_method: \"static parse of untarred snapshot copy (no bbolt open, no second instance)\""
echo ""
echo "panel:"
echo "  db_file_size_bytes: $(stat -c %s "$DB")"
echo "  image: \"1panel/kubepi:v2.0.3\""
echo ""
echo "imported_clusters: $(txt | grep -ac 'kind: Config')"
echo "credential_inventory:"
for p in 'kind: Config' 'client-certificate-data' 'client-key-data' 'certificate-authority-data' 'token:' 'insecure-skip-tls-verify'; do
  printf '  %-32s %s\n' "${p// /_}:" "$(txt | grep -ac -- "$p")"
done
echo "api_server_urls:                 # 内网地址非密钥，可入库"
txt | grep -aoE 'server: https://[0-9.:]+' | sed 's/^/  - /' | sort -u || echo "  []"
echo ""
echo "panel_users:"
txt | grep -aoE '"username":"[^"]{1,40}' | sed 's/^"username":"/  - username: /' | sort -u
echo ""
echo "--- 生成后请人工核对再覆盖 ops/kubepi/panel-assets.yaml ---"

rm -rf "$WORK"
[ -e "$WORK" ] && echo 'WARN: 工作目录未清理' || echo '# 工作目录已清理'

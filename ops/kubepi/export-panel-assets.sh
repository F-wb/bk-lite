#!/usr/bin/env bash
# 集群管理面板 · 内容清单导出（M1-4 固定做法）
#
# 安全前提（不可违反）：
#   1. 绝不打开生产卷 kubepi-data —— bbolt 单文件独占锁，两实例同开会数据分叉。
#   2. 绝不启动第二个面板实例。
#   3. 只读「备份快照的解包副本」，读完即删工作目录。
#   4. 输出不得含令牌/证书/口令内容：configFileContent 与 privateKey 一律替换为 <masked>。
#
# ⚠ 检索模式的教训（2026-11-06 连错两轮，务必照此写）：
#   面板不用 kubeconfig 原文存集群，而是自有 JSON 结构：
#     {"kind":"Cluster","name":"121","spec":{"connect":{"forward":{"apiServer":"https://…:6443"}},
#      "authentication":{"mode":"configFile","configFileContent":"<密文>"}},"status":{"version":"v1.36.5"}}
#   因此 `kind: Config`、`server: https://`、`client-certificate-data` 这类 YAML/kubeconfig 风格模式
#   **永远打不中**，会把"有"报成"无"。必须用下面的 JSON 紧凑风格模式。
#
# 时效：结果反映快照时刻。白天新增的集群需先跑一次备份（会停容器约 2 秒，属变更操作）再导出。
#
# 用法：在 95 上执行，输出 YAML；人工核对后覆盖 ops/kubepi/panel-assets.yaml
set -u

BK=/opt/kubepi/backup
WORK=/root/kubepi-inv-work

T=$(ls -1 "$BK" | grep -E '^2[0-9]{7}_[0-9]{6}$' | tail -1)
[ -n "$T" ] || { echo 'FATAL: 没找到快照目录'; exit 1; }
ARCHIVE=$(ls "$BK/$T"/kubepi-data_*.tar.gz | tail -1)

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

rm -rf "$WORK"; mkdir -p "$WORK"
tar xzf "$ARCHIVE" -C "$WORK"
DB=$(find "$WORK" -name 'kubepi.db' | head -1)
[ -n "$DB" ] || { echo 'FATAL: 快照里没有 kubepi.db'; exit 1; }

txt() { tr -c '[:print:]\t' '\n' < "$DB"; }

# 去重必须按 uuid，不能按整行：bbolt 会同时留同一条记录的新旧两个版本（updateAt 不同、
# 旧页未被回收），整行 sort -u 去不掉，会把 2 个集群报成 3 个（2026-11-06 实测踩到）。
# ISO 8601 时间戳字典序==时间序，故直接取每个 uuid 下 updateAt 最大的一条。
CLUSTER_JSON=$(txt | grep -a '"kind":"Cluster"' | awk '
  match($0, /"uuid":"[^"]+"/) { u = substr($0, RSTART+8, RLENGTH-9)
    if (match($0, /"updateAt":"[^"]+"/)) { t = substr($0, RSTART+12, RLENGTH-13) } else { t = "" }
    if (!(u in best) || t > best[u]) { best[u] = t; rec[u] = $0 } }
  END { for (k in rec) print rec[k] }')
N=$(printf '%s\n' "$CLUSTER_JSON" | grep -ac '"kind":"Cluster"' || true)

echo "# 集群管理面板 · 内容清单（快照静态读取导出）"
echo "# 生成时间: $(date -Iseconds)  主机: $(hostname)"
echo "snapshot: \"$T\""
echo "snapshot_file_md5: \"$(md5sum "$ARCHIVE" | awk '{print $1}')\""
echo "read_method: \"static parse of untarred snapshot copy (no bbolt open, no second instance)\""
echo "parse_style: \"KubePi 自有 JSON 结构（kind:Cluster），非 kubeconfig 原文\""
echo ""
echo "db:"
echo "  size_bytes: $(stat -c %s "$DB")"
echo "  buckets: [$(txt | grep -aoE '^(Cluster|ImageRepo|LoginLog|OperationLog|Role|User)$' | sort -u | tr '\n' ' ')]"
echo "  image: \"1panel/kubepi:v2.0.3\""
echo ""
echo "imported_cluster_count: $N          # 按 uuid 去重后的实际个数"
echo "clusters:"
if [ "$N" -gt 0 ]; then
  printf '%s\n' "$CLUSTER_JSON" | while IFS= read -r line; do
    nm=$(printf '%s' "$line" | grep -oE '"name":"[^"]*"' | head -1 | sed 's/"name":"//; s/"$//')
    sv=$(printf '%s' "$line" | grep -oE '"apiServer":"[^"]*"' | head -1 | sed 's/"apiServer":"//; s/"$//')
    md=$(printf '%s' "$line" | grep -oE '"mode":"[^"]*"' | head -1 | sed 's/"mode":"//; s/"$//')
    kv=$(printf '%s' "$line" | grep -oE '"version":"v[^"]*"' | head -1 | sed 's/"version":"//; s/"$//')
    ph=$(printf '%s' "$line" | grep -oE '"phase":"[^"]*"' | head -1 | sed 's/"phase":"//; s/"$//')
    ct=$(printf '%s' "$line" | grep -oE '"createAt":"[^"]*"' | head -1 | sed 's/"createAt":"//; s/"$//')
    uu=$(printf '%s' "$line" | grep -oE '"uuid":"[^"]*"' | head -1 | sed 's/"uuid":"//; s/"$//')
    up=$(printf '%s' "$line" | grep -oE '"updateAt":"[^"]*"' | head -1 | sed 's/"updateAt":"//; s/"$//')
    echo "  - name: \"$nm\""
    echo "    uuid: \"$uu\""
    echo "    last_update: \"$up\""
    echo "    api_server: \"$sv\""
    echo "    auth_mode: \"$md\"          # configFile=粘贴 kubeconfig（内容已加密存于库内，不外泄）"
    echo "    detected_k8s_version: \"$kv\""
    echo "    status_phase: \"$ph\""
    echo "    created_at: \"$ct\""
    echo "    credential_material: \"<masked>\"   # configFileContent / privateKey"
  done
fi
echo ""
echo "panel_users:"
txt | grep -aoE '"username":"[^"]{1,40}"' | sed -E 's/"username":"//; s/"$//' | sort -u | sed 's/^/  - username: /'
echo ""
echo "# 生成后请人工核对再覆盖 ops/kubepi/panel-assets.yaml；本脚本输出禁止直接粘贴未脱敏内容"
cleanup
echo "# 工作目录已清理：$([ -e "$WORK" ] && echo NO || echo YES)"

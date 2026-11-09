#!/usr/bin/env bash
# 备份健康看门狗（检测层）：不看退出码，只看产物是否真的可用。
#
# 为什么需要它（2026-11-09 真实事故）：falkordb 的 BGSAVE 子进程卡死，平台备份脚本在第 3 步 die，
# 连带 SHA256SUMS 与 MANIFEST 不产出，留下一个"看起来存在"的残缺目录。**连续 2 天没人发现**，
# 因为失败只写进了本机日志。脚本退出码是可用的，但没有人（也没有任何机制）在看它。
#
# 三条设计原则：
#   1. 判据是"能不能用来还原"，不是"脚本跑没跑"：必须同时满足 目录齐全 + 文件数达标 + SHA256 可校验 + 新鲜度达标。
#   2. 两个备份任务分别判：平台任务与面板任务的完整产物定义不同（见下面的期望值）。
#   3. 触达方式可插拔：检测与上报解耦。通道未配置时，本脚本仍然把结论写成本机可读的状态文件并以退出码表达，
#      接入渠道只是往下面 notify() 里多打一次 HTTP，不需要改判据。
#
# 配置（可选，缺省则不外发）：root 持有的 /opt/bk-lite/etc/backup-alert.env，内容形如
#   ALERT_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=..."   # 钉钉自定义机器人
#   ALERT_WEBHOOK_SECRET="SEC..."                                            # 加签密钥（钉钉选填）
# 该文件含凭据，**不得入 git**（已在 .gitignore 排除），权限须为 600。
#
# 用法：bash backup-watchdog.sh [--quiet] [--force-alert]
#   退出码 0=全部可用  1=发现问题
# 路径均可用环境变量覆盖，便于在非生产环境做红/绿自测（不需要碰真实备份目录）：
#   WD_PLATFORM_BACKUP / WD_KUBEPI_BACKUP / WD_STATE_FILE / WD_ALERT_CONF
#   WD_MAX_AGE_HOURS / WD_PLATFORM_EXPECT / WD_KUBEPI_EXPECT
set -uo pipefail

PLATFORM_BACKUP="${WD_PLATFORM_BACKUP:-/opt/bk-lite/backup}"
PLATFORM_EXPECT_FILES="${WD_PLATFORM_EXPECT:-6}"   # postgres + pgvector + falkordb + victorialogs + SHA256SUMS + MANIFEST.txt
KUBEPI_BACKUP="${WD_KUBEPI_BACKUP:-/opt/kubepi/backup}"
KUBEPI_EXPECT_FILES="${WD_KUBEPI_EXPECT:-4}"       # kubepi-data_*.tar.gz + docker-compose.yml.snapshot + SHA256SUMS + MANIFEST.txt
MAX_AGE_HOURS="${WD_MAX_AGE_HOURS:-26}"            # 每日任务，超过 26 小时未产出即视为断链（留 2 小时抖动余量）

STATUS_FILE="${WD_STATE_FILE:-/var/lib/bk-lite-backup-watchdog/state}"
CONF="${WD_ALERT_CONF:-/opt/bk-lite/etc/backup-alert.env}"

# 每个备份的**应有项清单**（带路径的 glob）。光说“文件数不足”没意义——
# 必须直接指出缺哪几项，否则运维还得自己 ls（真实事故里 11-08 只报“2<6”，看不出缺的是 falkordb）。
PLATFORM_ITEMS='postgres/*.dump pgvector/*.dump falkordb/*.rdb victorialogs/*.tar.gz SHA256SUMS MANIFEST.txt'
KUBEPI_ITEMS='kubepi-data_*.tar.gz docker-compose.yml.snapshot SHA256SUMS MANIFEST.txt'
QUIET=0; FORCE_ALERT=0
for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1 ;;
    --force-alert) FORCE_ALERT=1 ;;
    *) echo "未知参数: $a"; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$STATUS_FILE")" 2>/dev/null || true

PROBLEMS=(); DETAILS=()

# ---------- 单个备份目录的可用性判据 ----------
check_dir() {
  local label="$1" root="$2" expect="$3" items="$4"
  local latest; latest=$(ls -1 "$root" 2>/dev/null | grep -E '^2[0-9]{7}_[0-9]{6}$' | sort | tail -1)
  if [ -z "$latest" ]; then
    PROBLEMS+=("$label: 备份根目录 $root 下没有任何时间戳产物"); return
  fi
  local dir="$root/$latest"

  # 先算缺哪几项（比“文件数不足”有用得多）
  local missing='' pat
  for pat in $items; do
    ls -G -d $dir/$pat >/dev/null 2>&1 || missing="$missing $pat"
  done
  local n; n=$(find "$dir" -type f 2>/dev/null | wc -l)
  if [ -n "$missing" ]; then
    PROBLEMS+=("$label: 最新产物 $latest 缺少:${missing}（实际文件数 $n / 期望 $expect）—— 不可用于还原"); return
  fi
  if [ "$n" -lt "$expect" ]; then
    PROBLEMS+=("$label: 最新产物 $latest 文件数 $n < 期望 $expect（清单项齐但数目不符，可能残留旧文件）"); return
  fi
  if ! ( cd "$dir" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); then
    PROBLEMS+=("$label: $latest 的 SHA256 校验未通过（文件损坏或被改动）—— 不可用于还原"); return
  fi
  local age_h; age_h=$(( ( $(date +%s) - $(stat -c %Y "$dir") ) / 3600 ))
  if [ "$age_h" -gt "$MAX_AGE_HOURS" ]; then
    PROBLEMS+=("$label: 最新产物已 ${age_h} 小时未更新（> ${MAX_AGE_HOURS}h），定时任务疑似断链")
  fi
  DETAILS+=("$label: OK  目录=$latest 文件数=$n 距上次 ${age_h}h")
}

check_dir "平台备份" "$PLATFORM_BACKUP" "$PLATFORM_EXPECT_FILES" "$PLATFORM_ITEMS"

if [ -d "$KUBEPI_BACKUP" ]; then
  check_dir "面板备份" "$KUBEPI_BACKUP" "$KUBEPI_EXPECT_FILES" "$KUBEPI_ITEMS"
else
  DETAILS+=("面板备份: 本机无 $KUBEPI_BACKUP（非 95 或未部署，跳过）")
fi

# ---------- latest 软链必须指向完整产物（这是最容易误导人的地方）----------
pl=$(readlink "$PLATFORM_BACKUP/latest" 2>/dev/null)
if [ -n "$pl" ] && [ ! -s "$pl/SHA256SUMS" ]; then
  PROBLEMS+=("平台 latest 软链指向的目录没有 SHA256SUMS：$pl")
fi

# ---------- 汇总 ----------
STATUS=0
[ "${#PROBLEMS[@]}" -gt 0 ] && STATUS=1
NOW=$(date -u +'%F %T UTC')
{
  echo "checked_at=$NOW"
  echo "status=$([ $STATUS -eq 0 ] && echo OK || echo ALERT)"
  # 注意：绝不用 ${ARR[@]:-}，空数组时会展开出一个空元素，写出 `ok: ` / `problem: ` 这种空行误导解析。
  n=${#DETAILS[@]}; i=0
  while [ $i -lt $n ]; do echo "ok: ${DETAILS[$i]}"; i=$((i+1)); done
  n=${#PROBLEMS[@]}; i=0
  while [ $i -lt $n ]; do echo "problem: ${PROBLEMS[$i]}"; i=$((i+1)); done
} > "$STATUS_FILE.tmp" 2>/dev/null && mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"

# 【设计点】--quiet 只抑制“正常明细”，**不抑制 ALERT 明细**。
# 否则 cron 里用 --quiet 时，日志就只剩“发不出去”而看不到到底坏了什么，
# 等于把本次事故“失败只写在本地没人看见”的毛病又复制一遍。
if [ $QUIET -eq 0 ]; then
  echo "==== 备份看门狗 @ $NOW ===="
  n=${#DETAILS[@]}; i=0
  while [ $i -lt $n ]; do echo "  OK    ${DETAILS[$i]}"; i=$((i+1)); done
fi
n=${#PROBLEMS[@]}; i=0
while [ $i -lt $n ]; do echo "  ALERT ${PROBLEMS[$i]}"; i=$((i+1)); done
if [ $QUIET -eq 0 ]; then
  [ $n -eq 0 ] && echo "  （无告警）"
  echo "  状态文件：$STATUS_FILE"
fi

# ---------- 触达层（可插拔）----------
notify() {
  [ $STATUS -eq 0 ] && [ $FORCE_ALERT -eq 0 ] && return 0
  if [ ! -f "$CONF" ]; then
    echo "  [notify] 未配置 $CONF —— 检测结论只落本地状态文件，无法送达任何人。" >&2
    return 0
  fi
  # shellcheck disable=SC1090
  . "$CONF"
  if [ -z "${ALERT_WEBHOOK:-}" ]; then
    echo "  [notify] ALERT_WEBHOOK 为空 —— 同上，无法送达。" >&2
    return 0
  fi
  MSG="备份看门狗告警 @ $NOW"$'\n'
  i=0; n=${#PROBLEMS[@]}
  while [ $i -lt $n ]; do MSG="$MSG- ${PROBLEMS[$i]}"$'\n'; i=$((i+1)); done
  MSG="$MSG状态文件：$STATUS_FILE"
  [ $STATUS -eq 0 ] && MSG="备份看门狗（恢复/自检通知）@ $NOW"$'\n  全部产物可用'
  PAYLOAD=$(printf '{"msgtype":"text","text":{"content":"%s"}}' "$(printf '%s' "$MSG" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')")
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H 'Content-Type: application/json' -d "$PAYLOAD" "$ALERT_WEBHOOK")
  echo "  [notify] webhook HTTP $code"
}
notify

exit $STATUS

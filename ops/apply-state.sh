#!/usr/bin/env bash
# ==============================================================================
# 盛大运维系统 期望状态收敛脚本（升级/重跑安装器后的标准动作）
#
# 解决的问题：官方安装器（install.run / bootstrap.sh）每次运行都会整份重写
#   .env，造成两处"状态漂移"：
#     1) DOCKER_IMAGE_SERVER / DOCKER_IMAGE_WEB 被重置回基线镜像
#        → 二开功能（品牌/钉钉/SSH 终端）静默消失
#     2) INSTALL_APPS 被改写为官方默认列表（新版默认含 operation_analysis /
#        rum 等），而本项目精简镜像（extras 仅 .[cmdb,dev]）缺 fitz / mlflow
#        等依赖 → server 启动即 ModuleNotFoundError、容器 Exited(1)
#
# 本脚本把 .env 一次性收敛回本项目"期望状态"：
#   - 前后端镜像指向本项目 ACR（滚动或版本化 tag）
#   - INSTALL_APPS 收敛为已知良好的应用清单（可用 DESIRED_INSTALL_APPS 覆盖）
# 并可顺带清理 Celery beat 表中已摘除应用的残留周期任务（--cleanup-beat）。
#
# 特性：幂等（可反复执行，已收敛时只报"无变更"）、带断言（缺变量即 FATAL，
#       绝不静默跳过）。报错是安全的，静默才是危险的。
#
# 用法：
#   bash apply-state.sh                       # 收敛镜像 + 应用清单（滚动 tag）
#   bash apply-state.sh --cleanup-beat        # 额外清理 beat 残留任务（升级后建议加）
#   SERVER_TAG=server-20261015d WEB_TAG=web-20261015c bash apply-state.sh
#
# 环境变量覆盖：
#   ENV_FILE / ACR / SERVER_TAG / WEB_TAG / DESIRED_INSTALL_APPS / COMPOSE_DIR
#
# 收敛后仍需执行（脚本只改文件/数据，不动容器）：
#   cd /opt/bk-lite && docker compose up -d --force-recreate server web
# ==============================================================================
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/bk-lite/.env}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/bk-lite}"
ACR="${ACR:-crpi-qp8pnmdzkajoq92t.cn-hangzhou.personal.cr.aliyuncs.com/fanwenbin/bk-lite}"
SERVER_TAG="${SERVER_TAG:-server}"
WEB_TAG="${WEB_TAG:-web}"
# 本项目精简镜像（.[cmdb,dev]）验证过的已知良好应用清单（9 个基础应用）。
# 若将来改用官方全量 Dockerfile 构建（见《盛大运维系统_AI模块规划.md》），
# 可传入官方默认列表而无需改脚本。
DESIRED_INSTALL_APPS="${DESIRED_INSTALL_APPS:-system_mgmt,cmdb,monitor,node_mgmt,console_mgmt,alerts,log,job_mgmt,patch_mgmt}"

CLEANUP_BEAT=false
[ "${1:-}" = "--cleanup-beat" ] && CLEANUP_BEAT=true

# 全部已知可选应用（用于推导 beat 清理范围；不在期望清单内的即视为已摘除）
KNOWN_APPS="system_mgmt cmdb monitor node_mgmt console_mgmt alerts log job_mgmt patch_mgmt operation_analysis rum apm mlops opspilot workflow_orchestration cmdb_enterprise"

[ -f "$ENV_FILE" ] || { echo "[FATAL] 未找到 $ENV_FILE：基线安装未完成或目录结构已变更" >&2; exit 1; }

# ── 断言：基线必须仍提供这些变量名 ─────────────────────────────────
missing=0
for k in DOCKER_IMAGE_SERVER DOCKER_IMAGE_WEB INSTALL_APPS; do
  grep -qE "^${k}=" "$ENV_FILE" || {
    echo "[FATAL] $ENV_FILE 中缺少变量 $k —— 基线可能已变更命名/结构，请人工核对后再收敛" >&2
    missing=1
  }
done
[ "$missing" -eq 0 ] || exit 1

cur_server=$(grep -E '^DOCKER_IMAGE_SERVER=' "$ENV_FILE" | head -1 | cut -d= -f2-)
cur_web=$(grep -E '^DOCKER_IMAGE_WEB=' "$ENV_FILE" | head -1 | cut -d= -f2-)
cur_apps=$(grep -E '^INSTALL_APPS=' "$ENV_FILE" | head -1 | sed -E 's/^INSTALL_APPS=//; s/^"//; s/"$//')

want_server="${ACR}:${SERVER_TAG}"
want_web="${ACR}:${WEB_TAG}"

changed=0
if [ "$cur_server" != "$want_server" ] || [ "$cur_web" != "$want_web" ] || [ "$cur_apps" != "$DESIRED_INSTALL_APPS" ]; then
  cp -a "$ENV_FILE" "${ENV_FILE}.bak.state-$(date +%Y%m%d%H%M%S)"
  changed=1
fi

# ── 1) 镜像变量收敛（幂等）─────────────────────────────────────────
[ "$cur_server" != "$want_server" ] && {
  sed -i -E "s|^DOCKER_IMAGE_SERVER=.*|DOCKER_IMAGE_SERVER=${want_server}|" "$ENV_FILE"
  echo "[CHG] DOCKER_IMAGE_SERVER -> ${want_server}"
}
[ "$cur_web" != "$want_web" ] && {
  sed -i -E "s|^DOCKER_IMAGE_WEB=.*|DOCKER_IMAGE_WEB=${want_web}|" "$ENV_FILE"
  echo "[CHG] DOCKER_IMAGE_WEB -> ${want_web}"
}

# ── 2) INSTALL_APPS 收敛（幂等）────────────────────────────────────
if [ "$cur_apps" != "$DESIRED_INSTALL_APPS" ]; then
  sed -i -E "s|^INSTALL_APPS=.*|INSTALL_APPS=\"${DESIRED_INSTALL_APPS}\"|" "$ENV_FILE"
  echo "[CHG] INSTALL_APPS -> ${DESIRED_INSTALL_APPS}"
fi

# ── 断言：收敛结果必须与期望逐字一致（防 sed 不生效/文件异常）──────
new_server=$(grep -E '^DOCKER_IMAGE_SERVER=' "$ENV_FILE" | head -1 | cut -d= -f2-)
new_web=$(grep -E '^DOCKER_IMAGE_WEB=' "$ENV_FILE" | head -1 | cut -d= -f2-)
new_apps=$(grep -E '^INSTALL_APPS=' "$ENV_FILE" | head -1 | sed -E 's/^INSTALL_APPS=//; s/^"//; s/"$//')
ok=1
[ "$new_server" = "$want_server" ] || { echo "[FATAL] DOCKER_IMAGE_SERVER 收敛失败：实际='$new_server'" >&2; ok=0; }
[ "$new_web" = "$want_web" ]       || { echo "[FATAL] DOCKER_IMAGE_WEB 收敛失败：实际='$new_web'" >&2; ok=0; }
[ "$new_apps" = "$DESIRED_INSTALL_APPS" ] || { echo "[FATAL] INSTALL_APPS 收敛失败：实际='$new_apps'" >&2; ok=0; }
[ "$ok" -eq 1 ] || exit 1

if [ "$changed" -eq 0 ]; then
  echo "[OK] 已是期望状态，无变更（幂等）"
else
  echo "[OK] 收敛完成，当前状态："
fi
grep -E '^(DOCKER_IMAGE_SERVER|DOCKER_IMAGE_WEB|INSTALL_APPS)=' "$ENV_FILE"

# ── 3) 可选：清理 beat 表中已摘除应用的残留周期任务 ────────────────
# 背景：Celery beat 用 DatabaseScheduler，任务存 django_celery_beat_periodictask；
#       摘除 app 后旧行不会自动删除，beat 继续投递导致 worker 刷
#       "Received unregistered task" / KeyError。
if [ "$CLEANUP_BEAT" = true ]; then
  disabled=()
  for app in $KNOWN_APPS; do
    case ",${DESIRED_INSTALL_APPS}," in
      *,"${app}",*) : ;;                      # 仍在期望清单，保留
      *) disabled+=("$app") ;;
    esac
  done

  # 组装 SQL：任务路径形如 apps.<app>.xxx（多数）或 <app>.xxx（operation_analysis）
  conds=""
  for app in "${disabled[@]}"; do
    [ -n "$conds" ] && conds="${conds} OR "
    conds="${conds}task LIKE 'apps.${app}.%' OR task LIKE '${app}.%'"
  done

  echo "[..] 清理已摘除应用的 beat 周期任务（${#disabled[@]} 个应用：${disabled[*]}）"
  # shellcheck disable=SC2086
  ( cd "$COMPOSE_DIR" && docker compose exec -T postgres psql -U postgres -d bklite -v ON_ERROR_STOP=1 ) <<SQL
BEGIN;
DELETE FROM django_celery_beat_periodictask WHERE ${conds};
UPDATE django_celery_beat_periodictasks SET last_update = now();
COMMIT;
SQL
  echo "[OK] beat 残留清理完成（若删除后日志仍投递旧任务，restart 一次 server 触发热加载）"
fi

echo "[提示] 需执行 'cd /opt/bk-lite && docker compose up -d --force-recreate server web' 才生效（restart 不重建容器）"

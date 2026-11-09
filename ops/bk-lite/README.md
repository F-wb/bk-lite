# ops/bk-lite · 平台脚本

对应线上：基线目录 `/opt/bk-lite`。**本目录重排不改变线上路径**，只改变仓库里的位置。

| 仓库文件 | 线上位置 | 用途 |
|---|---|---|
| `apply-state.sh` | `/opt/bk-lite/deploy/apply-state.sh` | 幂等收敛：镜像变量 + `INSTALL_APPS`，可带 `--cleanup-beat` 清理调度残留。重跑安装器后**必须**跑它 |
| `backup-all.sh` | `/opt/bk-lite/scripts/backup-all.sh` | 一键备份（P0/P1/P2，可选 `--with-volumes`）。生产由 `/etc/cron.d/shengda-backup` 每日 `30 2 * * *` 调用，**当前未带 `--with-volumes`** |
| `restore-all.sh` | `/opt/bk-lite/scripts/restore-all.sh` | 数据还原（全量 `--from <时间戳>` / 单项，四道安全闸） |
| `overlay-images.sh` | —— | 仅收敛镜像变量的早期脚本，已被 `apply-state.sh` 取代为超集；**保留在位作向后兼容，勿删** |
| `backup-watchdog.sh` | `/opt/bk-lite/scripts/backup-watchdog.sh` | **备份健康看门狗**。判据是“产物能不能用于还原”（目录/清单逐项/SHA256/新鲜度），不是退出码 |
| `cron.d-backup-watchdog` | `/etc/cron.d/backup-watchdog` | 看门狗定时器，`0 3 * * *` UTC（跑在两个备份任务之后）|

### 备份看门狗（为何存它）

2026-11-09 的事故里，备份脚本**确实以非零退出了并写了 `【失败】`**，但连续 2 天没人看见——断言设计再好，没人接收等于没有。看门狗做的事：不信任退出码，只验证**拿去能不能还原**；缺什么直接点名（实测可报出 `缺少: falkordb/*.rdb victorialogs/*.tar.gz SHA256SUMS MANIFEST.txt`）。

```bash
bash ops/bk-lite/backup-watchdog.sh; echo rc=$?      # 随时手动跑；0=可用 1=有问题
cat /var/lib/bk-lite-backup-watchdog/state            # 机器可读的状态结论
```

**触达需要一份不属于仓库的配置**（含凭据，所以不入库）：`/opt/bk-lite/etc/backup-alert.env`，内写 `ALERT_WEBHOOK`（及 `ALERT_WEBHOOK_SECRET`），权限 600。**未配置时看门狗仍然正常检测并写状态文件，但不会送达任何人**——输出会明说这一点，不假装已发。

> 自测：`ops/bk-lite/backup-watchdog.sh` 的所有路径可用 `WD_PLATFORM_BACKUP` 等环境变量覆盖，以便不碰生产目录就完成红/绿验证（含精确复现 11-08 残缺形态的用例）。

同步：

```bash
scp ops/bk-lite/backup-all.sh ops/bk-lite/restore-all.sh root@<host>:/opt/bk-lite/scripts/
scp ops/bk-lite/apply-state.sh root@<host>:/opt/bk-lite/deploy/
ssh root@<host> 'chmod +x /opt/bk-lite/scripts/*.sh /opt/bk-lite/deploy/*.sh'
```

核对是否漂移（只读）：

```bash
ssh root@<host> "md5sum /opt/bk-lite/deploy/apply-state.sh /opt/bk-lite/scripts/backup-all.sh /opt/bk-lite/scripts/restore-all.sh"
```

重排记录：2026-11-06 由 `ops/` 根平铺迁入本子目录（`git mv`，内容零改动）；同期已把全部文档引用改为 `ops/bk-lite/…`。

相关：外挂服务 `ops/kubepi/` 与本目录**同机不同项目**，平台安装器与 `apply-state.sh` 都碰不到它。

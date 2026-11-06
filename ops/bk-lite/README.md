# ops/bk-lite · 平台脚本

对应线上：基线目录 `/opt/bk-lite`。**本目录重排不改变线上路径**，只改变仓库里的位置。

| 仓库文件 | 线上位置 | 用途 |
|---|---|---|
| `apply-state.sh` | `/opt/bk-lite/deploy/apply-state.sh` | 幂等收敛：镜像变量 + `INSTALL_APPS`，可带 `--cleanup-beat` 清理调度残留。重跑安装器后**必须**跑它 |
| `backup-all.sh` | `/opt/bk-lite/scripts/backup-all.sh` | 一键备份（P0/P1/P2，可选 `--with-volumes`）。生产由 `/etc/cron.d/shengda-backup` 每日 `30 2 * * *` 调用，**当前未带 `--with-volumes`** |
| `restore-all.sh` | `/opt/bk-lite/scripts/restore-all.sh` | 数据还原（全量 `--from <时间戳>` / 单项，四道安全闸） |
| `overlay-images.sh` | —— | 仅收敛镜像变量的早期脚本，已被 `apply-state.sh` 取代为超集；**保留在位作向后兼容，勿删** |

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

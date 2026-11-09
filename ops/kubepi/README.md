# ops/kubepi · 集群管理模块（外挂面板）部署资产

模块对外名称 **集群管理**（平台应用宫格里的显示名）。本目录文件描述其实现所依赖的外部服务。
实现名 KubePi 仅在本目录与版本台账中出现，使用者不需要知道它。

## 这是什么

「集群管理」模块的**可执行资产**：编排定义、每日快照备份、还原与还原性校验。
面板本体不由本仓构建——它是第三方镜像，本仓只归档"我们怎么把它跑起来"。

| 文件 | 线上位置 | 说明 |
|---|---|---|
| `docker-compose.yml` | `/opt/kubepi/docker-compose.yml` | **线上原文逐字副本**，非模板。禁止改写为 `${VAR}` 形式；与线上 md5 必须相等 |
| `backup-kubepi.sh` | `/opt/kubepi/backup-kubepi.sh`（`chmod 700`） | 冷拷贝快照（bbolt 需短暂停容器后 tar）；现由每周 cron 触发，升级前可手动跑 |
| `cron.d-kubepi-backup` | `/etc/cron.d/kubepi-backup` | 触发器，**`40 2 * * 0` 每周日 02:40**（2026-11-09 由每日改每周），跑在平台 02:30 之后避免重叠 |
| `restore-kubepi.sh` | 无固定线上位置 | **还原步骤的唯一权威**；文档只引用本脚本，不复制内容 |
| `export-panel-assets.sh` | 无固定线上位置 | 从快照解包静态导出面板内容清单（集群数/凭据形态/账号）。**绝不开生产卷** |
| `panel-assets.yaml` | 无 | 上一次导出的结果。**反映快照时刻而非实时**，看文件头的 `discrepancy` 节 |

## 同步方向（单向，仓库为准）

```bash
# 本地 → 服务器（变更前先比对）
scp ops/kubepi/docker-compose.yml root@10.10.2.95:/opt/kubepi/
scp ops/kubepi/backup-kubepi.sh   root@10.10.2.95:/opt/kubepi/ && \
  ssh root@10.10.2.95 "chmod 700 /opt/kubepi/backup-kubepi.sh"
install -m 644 ops/kubepi/cron.d-kubepi-backup /etc/cron.d/kubepi-backup   # 在服务器上执行

# 服务器 → 仓库：仅用于核对是否漂移，不得把线上未审阅的改动直接落仓
ssh root@10.10.2.95 "md5sum /opt/kubepi/docker-compose.yml /opt/kubepi/backup-kubepi.sh"
```

**校验必须逐字节**（PowerShell 的文本比对会掩盖行尾差异）：

```bash
ssh root@10.10.2.95 "md5sum /opt/kubepi/docker-compose.yml"
md5sum ops/kubepi/docker-compose.yml     # 两者必须相同，当前均为 1217338de068fabbee3c2226561d10fd
```

## 与平台（`ops/bk-lite/`）的关系

- 独立 compose 项目名 `kubepi`、独立网络 `kubepi`、独立卷 `kubepi-data`；与 `/opt/bk-lite` 完全隔离。
- 平台安装器 `install.run` / `bootstrap.sh` / `apply-state.sh` **都碰不到本模块**——这是选择与平台同机混部（95）的前提。
- 平台备份任务 `shengda-backup` 不含本模块；本模块快照由 `kubepi-backup` 独立负责。
- **两者备份同在 95 本机同盘**；面板单容器、快照仅 24K，**异地已决定不做**（台账 M1-3）。面板自动备份已降为每周，重要变更前需手动补一次快照（台账 M1-4b）。
- 生产机运行容器数 = 平台 18 + 本模块 1 = **19**。凡"服务总数应为 18"的巡检判据都要按此理解。

## 禁改项（改了会静默出事）

1. **卷必须保持 `external: true`。** 去掉它，`docker compose -p kubepi down -v` 会直接删掉生产库。
2. **`image` 必须是显式版本号 tag，禁止 `latest`。**
3. **不要给容器加 `--privileged`。** 官方文档写了，但实测不需要；加了只扩大攻击面。
4. **禁止两个实例同时打开同一份数据**（bbolt 单文件 + 独占锁）。要用快照做验证就走 `restore-kubepi.sh --verify-only` 的临时卷路径，不要另起常驻实例。
5. 入口端口 `18080` 变更时，须同步三处：本 compose、平台应用表 `system_mgmt_app`（`id=16`）的 `url`、以及台账；且改 App 表后**已有用户的应用快照不会自动刷新**（见台账 T3）。
6. 本目录所有文件必须 **LF** 行尾——仓库已用 `.gitattributes` 钉住，因为本机 `core.autocrlf=true` 会把检出内容变成 CRLF，`bash` 与 `docker compose` 都会受影响。
7. **不要为了拿到实时清单而去 `docker exec` 读生产库或用库文件起第二个实例**（bbolt 独占锁）。正确做法：先跑一次备份（会停容器约 2 秒，属变更操作，需先告知），再跑 `export-panel-assets.sh` 读新快照。

## 已知行为：重建容器会重置面板运行配置

面板自己的配置文件 `/etc/kubepi/app.yml` 位于**容器可写层**，不在 `kubepi-data` 卷内、也不在快照内。
其中 `jwt.key` 由首次启动随机生成（上游默认该字段为空）。因此：

- **升级镜像或重建容器后，`jwt.key` 会变，所有已登录会话失效，需要重新登录。属预期行为，不是故障。**
- 数据本身（集群导入、账号）在卷里，不受影响。

**红线（带触发条件）**：一旦需要修改 `app.yml` 里任何一个值（`ssl.enable` / `certificate`、`session.expires`、`db.path`），
**同一次变更内必须一并把 `app.yml` 挂载出来持久化 + 进本目录 + 纳入备份脚本**；否则该修改会在下次容器重建时被镜像默认值静默覆盖。
此红线与平台侧"重跑 `install.run` 会静默重写 `.env`"属同一类故障模式：**改了但不落持久层 = 下次重建即丢失**。

## 版本与变更去哪里看

`bk-lite/docs/kubepi/版本与变更台账.md`（上游锚点 / 镜像台账 / 数据配置台账 / 变更台账）。
设计取舍与否决理由在 `docs/bk-lite/盛大运维系统_集群管控集成方案.md`（决策存档，事实部分已迁至台账）。

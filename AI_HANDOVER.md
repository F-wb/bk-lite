# 🤖 多智能体交接文档（AI_HANDOVER）

> **Agent 协作规则（最高优先级）**
> 1. **新会话第一件事：静默通读本文件**，再按需进入第九节的详细手册。
> 2. 用户明确表示"阶段完成/先到这/会话结束"时，**主动更新本文件**（第二节快照 + 第十节日志）后再收尾。
> 3. 本文件保持**精炼聚焦**：只放"当前态、铁律、坑、待办、导航"，不写流水账历史、不复制手册内容（细节一律放各专题手册）。
>
> 含内网地址等字面量，**仅限内部**；外发前脱敏（内网 IP、镜像仓库、GitLab 主机）。

---

## 1. 项目一句话

「盛大运维系统」= 开源运维平台基线（官方安装器部署）+ 少量二开（品牌、钉钉登录、JumpServer SSH 终端），二开以自建前后端镜像经 ACR 覆盖交付。**一期已交付验收；AI 模块评估完成、暂缓实施。**

## 2. 当前状态快照（2026-11-06 收尾于 M3）

| 项 | 值 |
|---|---|
| **本轮节点（先看这一行）** | 「集群管理」模块规范化：spec → M1（资产落仓+台账）→ M2（内容清单）→ **M3（13 项文档补齐）已全部完成并提交**；**M4 / M5 未做**，下一步从 M4 开。详见 §7 待办与 `docs/kubepi/版本与变更台账.md` T4 |
| 外挂模块「集群管理」 | 生产在用（95）：`/opt/kubepi` 独立 compose 项目 `kubepi` + 命名卷 `kubepi-data`（`external: true`）+ 独立备份 cron（02:40，还原已验证）；入口 `http://10.10.2.95:18080/kubepi` 明文 HTTP；**整机容器数 = 平台 18 + 外挂 1 = 19**（`docker compose ps` 口径仍为 18，两者都对） |
| 面板实况（2026-11-06 快照实测） | 已纳管 **2 个集群**：`121`（v1.36.5，官方推荐区间）与 `110`（v1.22.2，**低于官方最低支持 v1.24**，已知情保留）；面板账号仅 `lloyd9527`（口令是否已改**仍无凭证**）；db version 3 / Iris 12.2.11 |
| 仓库目录规范（本轮定下） | **一个服务一个子目录**：可执行资产 `ops/<service>/`（现为 `ops/bk-lite/`、`ops/kubepi/`），模块技术文档 `docs/<service>/`（现为 `docs/kubepi/`）；`ops/` 根不得直接放脚本；规则见 `ops/README.md` |
| 版本可追溯入口 | 事实唯一权威 `docs/kubepi/版本与变更台账.md`（T1 上游锚点 commit `e183085d…` / T2 镜像与实例 / T3 数据配置 / T4 变更史 / M1-1…M1-8）；内容清单 `ops/kubepi/panel-assets.yaml`；决策存档 `盛大运维系统_集群管控集成方案.md` |
| 本轮仓库提交 | 9 个（`chore` 目录重构 / `ops` 面板资产 / `docs` 台账 / `docs` 四份手册首次入库 / DEV-1 / M2 订正 / 运维手册 M3 / 其余四份手册 M3）；**均未 push** |
| 源码 | `bk-lite-master` 仓分支 `shengda/v1.0-custom` @ `b5bc86ab37`（= 上游 `b44a5c92c0` + 631 提交 merge，30 二开文件完整）；服务器构建副本 `/opt/bk-lite-src` 同点 |
| 上游镜像 | `main` = 上游最新 `b44a5c92c0`（2026-11-03 同步，GitHub 与 GitLab 同 hash） |
| 运行环境 | 开发机 192.168.1.11 `/opt/bk-lite`（compose 项目名 `compose`），18 服务全 Up，`https://192.168.1.11/` = 200；磁盘可用 66G（旧镜像已清） |
| 预发布环境 | `https://10.10.2.91/`：跑**官方 latest 镜像**（非二开 ACR 镜像）做全功能试用；模块全部启用，`INSTALL_APPS` = 12 项 + `apm,rum,workflow`，编排引擎 conductor 已部署；`APP_WORKERS=4`。**定位：官方 AI 版试用，无二开版本** |
| 生产环境 | `https://10.10.2.95/`（主机名 ops，15G 内存/273G 磁盘）：**一期已于 2026-11-03 部署上线**——基线安装器 + 公司仓库镜像覆盖，18 服务全 Up、server/web healthy、站点 200；`INSTALL_APPS` 9 应用；品牌已收敛「盛大运维系统」；备份 crontab（每日 02:30）已配置。**接入点已修复（2026-11-03 下午）**：SIDECAR_INIT_TOKEN/SIDECAR_NODE_ID 生成写入 + fusion-collector 重建，`fusion-collector-default`（container）注册成功，CMDB 采集接入点/节点管理自动采集已解锁。**待用户界面操作：钉钉企业登录参数配置（corp_id/appkey/appsecret）、JumpServer 集成实例、排除模块菜单隐藏** |
| 镜像仓库策略 | 构建/中转=个人 ACR `crpi-qp8pnmdzkajoq92t…/fanwenbin/bk-lite`；**部署拉取=公司仓库 `registry.cn-zhangjiakou.aliyuncs.com/shengda/bk-lite`**（双 tag 已同步 `server/web-20261103a` + 滚动 tag，11 与 95 均已 docker login，账号 lloyd9527） |
| 当前镜像 | ACR `:server-20261103a`（33 层，**官方 Dockerfile 原件**，extras 全量含 mlops/opspilot → **AI 就绪**）/ `:web-20261103a`（11 层）；回滚点 `:server-20261015d` / `:web-20261015c` |
| 启用应用（9 个） | `system_mgmt,cmdb,monitor,node_mgmt,console_mgmt,alerts,log,job_mgmt,patch_mgmt` |
| 未启用模块 | 测试机：apm / mlops / opspilot / operation_analysis / rum / workflow（原 workflow_orchestration，上游 3ccc3e336c 已改名）；菜单可见、点击 404 属预期 |
| 模块启用机制 | Django 只为 `.env` 里 `INSTALL_APPS` 列出的 app 注册路由；URL 结构已改为 `api/v1/<app>/` 动态挂载 + 前端 Next.js BFF（`/api/proxy/<app>/...`）；安装器开关持久化在 `common.env`，数值参数必须 `--app-workers=4` |
| 宿主约束 | 内存 7.2G——构建前必须全停容器；**升级前强制备份**（本次迁移至 system_mgmt.0053） |
| 使用文档 | `盛大运维系统_使用文档/` v2（按钮级）共 17 篇（00~16）；**未含截图**；⚠ `17_集群管理.md` **尚未创建**（归 M4，所以现在没往 README 索引里登记，避免死链） |

## 3. 仓库与路径

| 仓库 | 路径 | 说明 |
|---|---|---|
| 源码 fork | `d:\Code\bk-lite\bk-lite-master` | `main`=上游镜像（**禁二开**，GitHub 与 GitLab 同 hash）；`shengda/v1.0-custom`=二开唯一分支；remote `origin`(GitHub 个人 fork) + `upstream`。**GitLab 推送**：`git push origin main` 后再 `git push http://gitlab.ext.sdprint.tech/fanwenbin/bk-lite.git main:main`（HTTP；SSH 22 被代理拦。GitLab main 曾是受保护分支，force push 需网页临时开开关） |
| **交接仓（本文件所在）** | `d:\Code\bk-lite` | 全部专题手册与 `ops/` 脚本已归集于此；remote `gitlab`(内网 HTTP，SSH 22 被代理拦) + `origin`(GitHub)。**推送策略**：完整版推 GitLab 独立分支 `docs/ai-handover`；GitHub 同分支名放脱敏版；源码 main/shengda 归 `bk-lite-master` 仓管，本仓不碰 |
| 文档旧仓 | `d:\Code` | 无 remote；手册与 ops 已迁出，仅留他用目录 |

- 运行态：基线目录 `/opt/bk-lite`；自研脚本线上副本在 `deploy/`（镜像收敛）与 `scripts/`（备份还原）。
- **仓库目录规范（2026-11-06 定）**：运维资产**按服务分目录**——可执行资产 `ops/<service>/`（现为 `ops/bk-lite/`、`ops/kubepi/`），模块技术文档 `docs/<service>/`（现为 `docs/kubepi/`）；`ops/` 根不得直接放脚本（唯一例外是其 `README.md` 本身）。规划产物在 `docs/specs/` 与 `docs/plans/`；产品级手册仍在仓库根。详见 `ops/README.md`。
- 外挂模块「集群管理」（实现为 KubePi，宫格入口）的资产在 `ops/kubepi/`，线上位置 `/opt/kubepi` 与 `/opt/bk-lite` 完全隔离，平台安装器与 `apply-state.sh` 碰不到它；**生产运行容器数 = 平台 18 + 本模块 1 = 19**，凡「应为 18 个 running」的巡检判据需按此理解。
- 交接仓已解除对 `bk-lite-master/` 的跟踪（2026-10-19，`.gitignore` 排除；此前 vendored 跟踪产生 1.7 万条 CRLF/快照漂移噪音，已清除）。提交仍用 pathspec 只提自己的文件。
  > ⚠【2026-11-06 实测推翻】上面“已解除跟踪”**与现状不符**：`git ls-files bk-lite-master/` 仍返回 **17,822** 条，且工作树里该目录大量 M/D——即 `edc98a28` 并未真正生效。`.gitignore` 只屏蔽**未跟踪**文件，对已在索引里的条目无效。详见 §7 仓库治理待办；在它修好前，**严禁 `git commit -a`**。

## 4. 铁律（不得违反）

1. 二开只进 `shengda/v1.0-custom`；冲突只在本机解，服务器只 `pull --ff-only`。
2. 正式手册对外统一"盛大运维系统"命名，不出现上游开源项目名；未启用模块只做前端隐藏，不删代码。
3. 服务器变更类操作（改配置/重启/重建/安装器）先经用户确认；一轮任务只开一次 SSH、命令打包。
4. 镜像自 2026-11-03 起为官方 Dockerfile 全量构建（extras 含 mlops/opspilot，AI 就绪）——**启用 AI 无需重建镜像**，只改 `INSTALL_APPS`（经 `apply-state.sh` 显式传入含 `opspilot,mlops` 的清单）+ 重跑安装器开关；构建一律用官方 `support-files/release/Dockerfile`（`.local` 精简副本已弃用），且构建前须重拉 base（新版含 Brotli CVE 硬断言）。
5. 重跑安装器后必须 `bash /opt/bk-lite/deploy/apply-state.sh --cleanup-beat` 收敛；改 `.env` 后必须 `up -d --force-recreate`。
6. 脚本的 FATAL 断言不许删；基线升级前强制备份（DB 迁移不可逆，数据只能还原）。
7. Git 提交用 pathspec 只提自己的文件；用户未要求不 commit、不 push。

## 5. 升级速查（细则见部署手册第五章）

- **类型一·跟进上游代码（月度，最常见）**：本机 merge → buildx 构建推 ACR → 服务器 `pull` + `up -d --force-recreate server web`。**不重跑安装器**。镜像 main 同步：merge 后 push GitHub + GitLab（见第三节），两边同 hash。**GitHub 自服务器不可达时**：本机 `git bundle create` → scp → 服务器 `git fetch <bundle>`。
- **类型二·升级基线**：备份留证 → 预下载安装器比对变化 → 不带开关重跑（禁 `--clean`）→ `apply-state.sh --cleanup-beat` → `pull && up -d` → 七项校验 → 登记台账。**先在测试机演练**。
- 构建要点：全停容器+prune（旧镜像可 `prune -a` 全清，回滚靠 ACR 版本化 tag）；server 用官方 `Dockerfile`（层数基准 33）、web 用 `web/Dockerfile`（11 层）；先重拉 `server-base:latest` 补 blob + 过 Brotli 断言；`docker buildx build --provenance=false --push`，推送校验只比层数。
- 备份：`/opt/bk-lite/scripts/backup-all.sh`；还原 `restore-all.sh --from <时间戳>`。

## 6. 高频坑（都付过代价）

1. 安装器重跑**整份重写 `.env`**：镜像变量回基线 + INSTALL_APPS 变官方默认（含需 `fitz` 的 operation_analysis）→ 两处漂移，旧 overlay 脚本只盖得住第一处。
2. 容器 healthy、站点 200 **不等于日志无错**；必看 `docker compose logs --since=3m server`。
3. Celery beat 用 DatabaseScheduler：摘应用后残留在表 `django_celery_beat_periodictask`，删行后还须 bump `periodictasks.last_update`（或 restart server）。
4. 回退误启用组件的官方开关：`bash bootstrap.sh --no-opspilot </dev/null>`（不清数据）。
5. vector 反复 Restarting 多是 server 宕的下游症状，server 恢复即自愈。
6. extras 不能只装 `.[cmdb]`（django_extensions 无条件加载，缺了启动即崩）。
7. ~~启用 AI 需弃用 `.local`~~（2026-11-03 已执行：官方 `Dockerfile` 构建，层数基准 33）；`Dockerfile.base.local` 是死代码。
8. PowerShell 5：无 `&&`/heredoc；管道传脚本带 CRLF（需 `tr -d '\r'`）；远程 SQL/复杂命令用 base64 here-string 透传；高频 SSH 会撞 sshd 上限。
9. **模块改名后官方不清理旧 app 记录**：导航会留一个必 404 的幽灵入口；而 `AppViewSet.destroy` 对 `is_build_in=True` 直接拒删（初始化脚本硬编码内置），**界面也删不掉**；需先放开标记再删，且控制台应用卡片是**每用户一份快照**（`console_mgmt_user_app_set`），删 app 行不会自动剔除。
10. 启用 RUM 后 server 会刷 `KeyError: 'apps.rum.tasks.evaluate_rum_alert_policies'`（官方 beat schedule 写了复数，实际注册的是单数 `evaluate_rum_alert_policy`）；评估由 `dispatch_rum_policy_evaluations` 驱动，禁用该行即可；因 reconcile 是 shadow 模式，**server 重启后要复查**。
11. 官方 latest 镜像启全模块要额外 ~10 个容器（conductor JVM、victoria-traces、rum 独立的 redis/minio/victoria-logs/victoria-traces）；16G 机器上很紧张，且**降 `APP_WORKERS` 对 server 占用帮助有限**（大头在 celery/nats_listener/长连接进程）。
12. **上游 URL 结构已重构**（2026-11-03 版本实测）：Django 动态挂载 `api/v1/<app>/`，旧全局 `/api/menu`、`/api/get_login_auth_bindings/` 等**在 Django 侧已不存在**；前端经 Next.js BFF `/api/proxy/<app>/...` 转发（且有 308 去尾斜杠重定向，curl 验证需 `-L`）。验证登录绑定用 `/api/v1/core/api/get_login_auth_bindings/`。traefik web 路由绑 `Host(<IP>)`——用 `curl https://localhost/` 测试会 404，属测试方法问题。
13. 新版官方镜像 supervisor conf 增加 workflow_worker / opspilot 长连接等，但 9 应用模式下 `startup.sh` 只加载对应的子集，不会崩溃循环（实测 supervisor 全 RUNNING）。
14. ~~`SIDECAR_INIT_TOKEN/SIDECAR_NODE_ID` 未定义警告无害~~ **（2026-11-03 推翻）**：这两个变量是 **fusion-collector 容器（=默认云区域接入点）sidecar 的注册凭证**（compose 映射 `SERVER_API_TOKEN ← SIDECAR_INIT_TOKEN`、`SIDECAR_NODEID ← SIDECAR_NODE_ID`）；缺失 → sidecar `FATAL: No API token was configured` → CMDB 采集「接入点」下拉为空 + 节点管理自动采集被阻塞（`区域没有可用接入点`）。**修复**：server 容器 `python manage.py node_token_init --ip <本机IP>`（官方命令，幂等入库）→ node_id+token 写 `.env` → `up -d --force-recreate fusion-collector`（注意依赖链会连带 recreate server）。95 已修复（node_id `07dbf882…`）；11/91 的 .env 双值均为非空。安装器（install.run sha `427a2046…`）**不负责**生成这两个值——全新部署后必须手工补。
15. **install.run 不支持 `--noexec`**：传入后内部 bootstrap.sh 照跑安装流程（重写 `.env` + 碰 compose 文件）。**禁止在目标机上对 install.run 做解包实验**；要看内容先 `bash install.run --noexec --target /tmp/x` 于**非生产机**验证，或干脆不碰。2026-11-03 在 95 上误触发：`.env` 被重写（镜像变量回官方源、INSTALL_APPS 变官方默认 10 项、vector token 清空）——已从运行容器 env 取证恢复（SECRET_KEY/DB_PASSWORD/OPENAPI_PROVIDER_TOKEN 重写前后一致，验证无加密数据损坏），全量恢复 + apply-state 口径收敛完成。
16. **PowerShell 管道 SSH 输出会中途截断且退出码不可信**（高频会话尤甚，多条命令输出只剩前几行但 exit 0）：长脚本一律「base64 落盘到服务器 → `nohup … > /root/xxx.log 2>&1 &` → 轮询日志文件」模式执行；关键结果以新会话读文件为准，不信单次输出。
17. `ops` host 节点是安装器给平台主机自动装的采集器（4 collectors running），属正常；filebeat/auditbeat 因无输入配置报 failing 为噪音。
18. **vector 反复 Restarting（`No sources defined`）真凶是 401**：新版安装器漏写 `SYSTEM_VECTOR_CONFIG_TOKEN`，vector 拉 `/api/v1/log/open_api/system_vector/config/` 401 被解析成空配置退出重启循环——修复：`docker compose exec -T server python manage.py system_vector_token` 生成并**立即**写入 `.env`（重跑命令即失效旧 token）+ `up -d --force-recreate vector`。95 的该 token 2026-11-03 下午曾因误重装 .env 被清空，已从运行容器取证恢复。
19. traefik 基线只发布 443（80/tcp 不暴露宿主机），`http://IP:443` \u660e\u6587\u6253 TLS 端口会 404——**访问必须 `https://IP/` 并信任自签证书**。
20. **外挂面板的库是 bbolt，不是 SQLite**（v2.0.3 依赖 `asdine/storm/v3`）：单文件 + 独占文件锁。后果：① 备份必须冷拷贝（短暂停容器），不能在线 `cp`；② **绝不允许两个实例同时打开同一份数据**（用快照验证请走 `ops/kubepi/restore-kubepi.sh --verify-only` 的临时卷路径）；③ 旧描述“SQLite 型本地库”**已证伪**。
21. **读面板内容时，检索模式必须用面板自有的紧凑 JSON 结构，不是 kubeconfig/YAML 风格**（2026-11-06 连错两轮）：集群记录长这样 `{"kind":"Cluster","name":"121","spec":{"connect":{"forward":{"apiServer":"https://…:6443"}},"authentication":{"mode":"configFile","configFileContent":"<加密>"}},"status":{"version":"v1.36.5","phase":"Completed"}}`。用 `kind: Config`、`server: https://`、`client-certificate-data` 去查会**稳定得到 0 命中，把“有 2 个集群”报成“一个都没导入”**（假阴性比没数据更坏）。另：**去重要按 `uuid` 取 `updateAt` 最新一条**，bbolt 会保留同一记录新旧两版，整行 `sort -u` 会把 2 个报成 3 个。工具已固化：`ops/kubepi/export-panel-assets.sh`。
22. **面板配置 `/etc/kubepi/app.yml` 在容器可写层**（不在 `kubepi-data` 卷内、也不在快照内），其中 `jwt.key` 由首次启动随机生成。所以升级/重建容器后全员会话失效需重新登录——**这是预期，不是故障**。一旦要改该文件里任何值，**必须同批把它挂载出来持久化**，否则下次重建静默回到镜像默认值（与坑 15/18 “install.run 重写 `.env`”同族）。
23. **官方文档写面板要 `--privileged`，实测不需要**；不要加。另：`1panel/kubepi` 镜像在 91 上 `docker.io` 不可达、`docker.m.daocloud.io` 已改白名单制拒绝该镜像，**实测唯一可用源 `hub.rat.dev`**；拉取后必须比对 digest。公司仓库至今**没有** kubepi 镜像的 retag 副本（台账 M1-1）。
24. **外挂服务的脚本不得长期停在 `d:\Code` 根或 `.tmp-*/`**：`.tmp-kubepi/` 一度堆了 40 个探测脚本（gitignore、无版本、无出处说明），面板源码级结论的行号无法对应任何 commit。现在面板相关的一切可执行文件一律进 `ops/kubepi/`；技术文档进 `docs/kubepi/`（规则见 `ops/README.md`）。
25. **Windows 侧两个反复咬人的坑（本批全踩到了）**：① 编辑器写文默认 **CRLF**，入库前必须归一为 LF（compose 曾因 305 字节 vs 线上 289 字节而暴露），且仓库原先无 `.gitattributes` + `core.autocrlf=true`，**重新 clone 会把所有 bash 脚本变 CRLF**——已加窄范围属性钉死；② `ssh root@host "…"` 里的**双引号会被 PowerShell 剥掉**，一旦外层改用单引号嵌套，远端会在解析阶段直接报错（或删除字母 `r` 把 `grep` 变成 `gep`）；复杂命令一律 **scp 脚本落盘后执行**。

## 7. 待办

- [x] 【生产部署】一期上 10.10.2.95（2026-11-03 完成：install.run 基线 `427a2046…` + 公司仓库镜像覆盖 + 品牌 SQL 收敛 + 首备成功 + crontab 每日 02:30）
- [ ] 【用户侧·95 生产】钉钉企业登录参数（corp_id/appkey/appsecret）与 JumpServer 集成实例需在界面重新配置（全新 DB 不继承 11 的运行时配置）；排除模块菜单隐藏（应用管理 UI）
- [ ] 【待决策】异地备份（现备份与生产同机同盘）；测试机 crontab 当前为空
- [ ] 【待决策】SSH 保活（`~/.ssh/config` 加 ServerAliveInterval）
- [ ] 每月第一周跟进上游（运维手册 §6.4）；**启用 AI 现已零门槛**：镜像已含全量依赖，只需重跑安装器 `--opspilot`（随后 `apply-state.sh` 传含 `opspilot,mlops` 的 DESIRED_INSTALL_APPS 收敛）+ UI 配模型服务
- [ ] 【用户侧】给使用文档补界面截图（需可登录的浏览器环境；当前自签证书在受控浏览器无法绕过；`10.10.2.91` 与 `192.168.1.11` 均如此）
- [ ] 【安全】`/api/menu`、`get_bk_settings`、`get_login_auth_bindings`、`/api/auth/providers` 免鉴权可访问（泄露全站菜单树/品牌配置/已接入钉钉登录），待修复；`get_client` 返回 401 说明仅这几个漏了（URL 已重构，需按新路径复核）
- [ ] 【预生产】旧名幽灵应用 `workflow-orchestration` 残留未清（app 1 行 + role 3 + menu 8 + custom_menu_group 1 + admin 应用快照 1 处）；现已按用户决定改为界面隐藏，若顶部导航仍显示则需按残留清单清理（执行前先 pg_dump）
- [ ] 【观察】测试机 server 启动期报 MinIO `cmdb-config-file` 桶缺失（新版功能所需桶未自动创建，~10 条/次启动）；若持续报错需在 MinIO 手动建桶
- [ ] 【观察】预生产 server 容器内存长期占 ~9.9G/15.6G（可用仅 3.3G），怀疑内存增长；继上涨则扩容或定时重建
- [ ] 【集群管理模块·下一步 = M4】新建 `docs/kubepi/架构与部署.md` + 使用文档 `17_集群管理.md`（与其他 16 篇同口径：菜单实测 + `web/src/app/<模块>/locales/zh.json` 按钮文案）+ 对接手册新增一章「外部应用接入：集群管理」；**同一批再回头补 README 索引行与 AI_HANDOVER §9 剩下 2 行**（先登记会造死链，本轮故意没加）
- [ ] 【集群管理模块·M5】集成方案改写为纯决策存档（事实已迁走，需标明保留哪些章节）+ `.tmp-kubepi/` 残留脚本按 `ops/README.md` 规则三分类清理（**`edge-proxy-95.sh` 必须标死或删——反代已拆，不标注会被照着重建**）
- [ ] 【校验方法缺陷·本轮发现】spec §7 与计划 Task 7 的“旧路径引用残留应为 0”这条判据**没写作用域**：跑全局扫描会得到 23，全部来自 `docs/specs`+`docs/plans` 里“描述替换动作本身”的文本（`git mv` 命令、对照表左列），并非活引用。真实手册作用域（根 `*.md` / 使用文档 / `ops/`）实测均为 0。**必须把判据改成“排除 `docs/specs` 与 `docs/plans`”**，否则下个执行者会误判为订正未完成
- [ ] 【集群管理模块】台账待办 M1-1–M1-8 全部有效，见 `docs/kubepi/版本与变更台账.md`；其中 **M1-1**（面板镜像未 retag 进公司仓库，而镜像源已往白名单制收敛）与 **M1-2**（默认口令是否已改无凭证）优先
- [ ] 【仓库治理·高优先】`bk-lite-master/` 仍有 **17,822** 条索引项与 `.gitignore` 冲突（10-19 的 `edc98a28` 声称已解除跟踪但**实际未生效**）：`git status` 长期数千 M/D，**任何 `git commit -a` 都会卷进 1.7 万个 vendored 文件**（与坑册第 1 条同族）。修法：单独批次 `git rm -r --cached bk-lite-master`，验证 `git ls-files bk-lite-master/` 为空；完成后回改本文件 §3 的“已解除跟踪”描述
- [ ] 【行尾】本机与全局 `core.autocrlf=true`；2026-11-06 已新增窄范围 `.gitattributes` 钉住 `*.sh`/`*.yml` 为 LF。**重新 clone 后必须复核 `bash -n` 可过、compose 与线上 md5 相等**

## 8. 接手第一步

1. 读本文件；需要细节再按第九节进手册。
2. 只读核验（一次 SSH 打包）：`docker compose ps`、`.env` 三变量（ACR + 9 应用）、站点 200。
3. 与用户确认任务类型（排障/类型一/类型二/启用 AI/文档），变更类先出计划等确认。

## 9. 详细文档索引（均在交接仓 `d:\Code\bk-lite\`）

| 需要什么 | 看哪份 |
|---|---|
| 二开 30 文件明细、对接记录、镜像台账、构建全流程 | `盛大运维系统_二开改动归档.md` |
| 两类升级 SOP、回滚矩阵、基线变化应对 | `盛大运维系统_部署手册.md`（第五章；`ops/bk-lite/apply-state.sh` 源在 `ops/bk-lite/`） |
| 组件/数据卷、备份还原、巡检、事故案例 §5.4 | `盛大运维系统_运维手册.md` |
| AI 模块（OpsPilot）零分叉启用方案（暂缓） | `盛大运维系统_AI模块规划.md` |
| 需求/架构/钉钉/JumpServer | `盛大运维系统_{需求规格说明书,架构设计文档,钉钉登录对接操作手册,堡垒机对接文档}.md` |
| 按模块的用户操作手册（按钮级，面向最终用户） | `盛大运维系统_使用文档/`（README 索引；00 总览 + 01~09 一期模块 + 10 二开 + 11~16 预生产模块；按钮文案以 `web/src/app/<模块>/locales/zh.json` 为准） |
| 集群图形化管理（外挂模块）的设计取舍与否决理由 | `盛大运维系统_集群管控集成方案.md`（**决策存档**；事实已迁至台账；Provider 扩展包方案**未实施**，实际采用零代码外部应用登记） |
| 集群管理模块的版本·镜像·数据配置·变更史 | `docs/kubepi/版本与变更台账.md`（**事实唯一权威**；可执行资产在 `ops/kubepi/`） |
| Agent 长期记忆 | `c:\Users\Administrator\.trae-cn\memory\projects\-d-Code--p2-57a804f58e1514058492\`（project_memory + 每日 topics） |

## 10. 更新日志

| 日期 | 摘要 |
|---|---|
| 2026-10-17 | 初版；同日按"精炼聚焦"原则重写：去时间线流水账与大表（细节归手册），新增 Agent 协作三规则；手册与 ops 脚本归集到交接仓，GitHub 脱敏分支已推 |
| 2026-10-17 | 内网 GitLab 已推：发现远端 main/shengda 为源码镜像（与本仓历史无关），经用户确认**推为独立分支 `docs/ai-handover`**（HTTP 传输，SSH 22 被代理 reset），不触碰源码镜像分支 |
| 2026-10-23 | 源码镜像治理：查明 GitLab main/shengda 原是 10-10 的 squash 快照（有打包失真、无法 ff），经用户确认 force 覆盖为真历史——main=上游最新 `3bf6df19b4`（GitHub 同步），shengda=`6e0be26b`；GitLab 受保护分支需网页临时开 force push；此后三端同 hash，月度同步=push GitHub+GitLab |
| 2026-10-23 | 产出《使用文档》v2（按钮级）：README + 00 总览 + 9 个启用模块 + 10 二开，约 1900 行；修正 v1 三处实质错误（CMDB 导入为异步任务中心、控制台为应用入口广场、补丁安装固定走 Ansible）；顺带发现免鉴权接口风险（已入待办） |
| 2026-10-23 | 补写 11~16 篇（预生产 `10.10.2.91`，16 模块全启用）：APM/RUM/MLOps/运营分析/OpsPilot/编排中心；同口径（菜单实测 + locales 按钮文案）；README 增加环境覆盖说明 |
| 2026-11-02 | 预生产 91 模块全开：设 `CONDUCTOR_BASE_URL` 后重跑官方安装器 `--opspilot --apm --rum`，`INSTALL_APPS` 12→15 项，新增 conductor/victoria-traces/apm-collector/rum-* 共 9 个容器（19→28）；apm/rum/workflow 接口由 404 转 401，`show_urls` 实测 workflow 100 / apm 104 / rum 70 条路由，新模块表已迁移；`APP_WORKERS` 8→4。**未改任何代码**；变更前备份与留档在 `91:/opt/bk-lite/backup/pre-enable-all-20261102_015432/` |
| 2026-11-02 | 查清两类遗留成因：① 官方 RUM beat 任务名复数失效（已禁用该行，功能由 dispatch 任务承担）② 上游 `3ccc3e336c` 把编排中心改名 `workflow`（含表名），旧路由已删但 DB 旧 app 记录未被清理→导航 404 且界面删不掉；已将 id=9 `is_build_in` 置 false（用户选择界面隐藏）。16 篇与 README 同步去旧写新 |
| 2026-11-03 | **类型一升级 + 构建文件切换**：merge 上游 631 提交（tip `b44a5c92c0`，冲突仅 2 前端文件）→ 三端同 hash → 构建前拉起旧栈强制备份（`20261103_101406`，因发现容器已被外部清空、数据卷完好）→ `compose down` + `prune -a`（磁盘 29G→66G）→ server 改用**官方 Dockerfile**（extras 全量含 mlops/opspilot，**AI 就绪**，层数基准 29→33；Brotli CVE 断言通过）→ 双 tag 推送 → 部署校验全过（站点 200、迁移至 0053、**钉钉登录在新 LoginAuthBinding 链路存活**、beat 零噪音）。GitHub 自服务器不可达改走 git bundle；上游 URL 结构重构为 `api/v1/<app>/` + Next.js BFF（入坑册 12/13）。`apply-state.sh` KNOWN_APPS 同步 workflow 新旧名并存。**生产开启 AI 从此免重建镜像** |
| 2026-11-03 | **一期上生产 95**：环境定版（11 开发/91 预发布官方AI版/95 生产）；镜像双仓库策略确立（个人 ACR 构建 → 公司仓库 `registry.cn-zhangjiakou.aliyuncs.com/shengda/bk-lite` 部署，4 tag 推送完成层数校验 33/11）；95 基线安装（install.run sha256 `427a2046…`，官方镜像拉起后 `apply-state.sh` 收敛为公司仓库镜像 + 9 应用，beat 清 5 行）；**坑：全新 DB 的品牌迁移种子由先跑的官方镜像写入（BlueKing Lite），需 SQL 收敛 portal_name/watermark_text**；备份脚本上 95 + 首备成功 + crontab 每日 02:30；最终 18 服务全 Up、站点 200、品牌「盛大运维系统」生效。**遗留用户侧：95 钉钉参数/JumpServer 实例/菜单隐藏需界面配置** |
| 2026-11-03 | **资源纳管启动 + 接入点修复 + 误装事故**：产出《资源纳管操作手册》《生产环境对接操作手册》（自动发现矩阵/Windows IIS+MSSQL/C# 服务/K8s/ELK/Prometheus 并行策略）。查证「接入点为空」根因 = 安装器不生成 SIDECAR_INIT_TOKEN/SIDECAR_NODE_ID（坑 #14 修正），`node_token_init` 生成写入 + fusion-collector 重建后 `fusion-collector-default`（container）注册成功。**事故**：为查证误用 `bash install.run --noexec` 触发真实安装流程重写 `.env`（坑 #15），已从运行容器 env 取证全量恢复（SECRET_KEY/DB_PASSWORD 一致，无数据损坏），并补回 vector token。附带发现：11 整套容器当前停止（待用户处理）；91 postgres 曾短暂 Not running 需留意 |
| 2026-11-05 | **集群管理模块（KubePi）上生产**：面板从 91 POC 迁至 95（`/opt/kubepi` + 命名卷 `kubepi-data`，`external: true`，非 privileged，55MiB），md5 三处全等；备份闭环（`/etc/cron.d/kubepi-backup` 02:40）+ 还原校验全等；91 试用实例彻底删除；前置反代评估后拆除（直连 18080 明文）。平台侧以**零代码外部应用**接入（应用表 `id=16 · 集群管理`），**Provider 扩展包方案未实施** |
| 2026-11-06 | **集群管理模块规范化 M1+M2+M3（当日 9 个提交，未 push）**：① **M1** `ops/` 改为按服务分目录（平台 4 脚本 `git mv` 入 `ops/bk-lite/`，新建 `ops/kubepi/`：compose/cron/backup/restore/export/README/panel-assets），订正 4 份文档共 11 处引用；`backup-kubepi.sh` 与《集成方案》《生产环境对接》《资源纳管》《跟进官方代码的固定动作》**发现从未入 git**，首次入库；新增 `docs/kubepi/版本与变更台账.md`（T1–T4 + M1-1…M1-8）；新增窄范围 `.gitattributes`——本机与全局 `core.autocrlf=true` 且原先无属性文件，**重新 clone 会把所有 bash 脚本与 compose 变 CRLF**（即坑 1 的机制根源）。② **M2 面板内容清单导出，连错两轮才对**：先用 kubeconfig/YAML 风格模式（`kind: Config`、`server: https://`、`client-certificate-data`）得出"面板没导入任何集群"的**假阴性**；实际面板用自有紧凑 JSON（`"kind":"Cluster"`、`spec.connect.forward.apiServer`），且 kubeconfig 存于**加密的** `configFileContent`，YAML 风格模式在原理上永远打不中。第二个错：整行 `sort -u` 去重把 2 个集群报成 3 个（bbolt 保留同一记录新旧两版），改按 `uuid` 取 `updateAt` 最新一条。两条限制已写进 `export-panel-assets.sh` 头注与 `panel-assets.yaml` 的 `method_caveats`。实测结论：**已纳管 2 个集群**（121 = v1.36.5 官方推荐区间 / 110 = v1.22.2），面板账号仅 `lloyd9527`。③ **DEV-1 收口**：110 **低于官方最低支持 v1.24** 却已纳管且 `phase=Completed`，决定**保留纳管**并改写集成方案 §1 结论 5 / §2.2 / §8.2（新增"110 纳管风险记录"）/ §14 R3。④ **M3** 运维手册 14 处补齐（含 §4.4 定时任务按生产实况订正：实为 `/etc/cron.d/` 两条且不带 `--with-volumes`，root crontab 为空）；部署手册新增第八章"外挂模块"并重排后续章节号；架构设计文档 §1.3 新增"外挂模块"类 + §9.2.1 生产单机实际布局；使用文档 01/09 补外部应用语义（含 `app=''` 角色短路的开通前必查 SQL）；坑册新增 20–25 六条。**未做**：M4（`docs/kubepi/架构与部署.md`、使用文档 `17_集群管理.md`、对接手册新章、索引 2 行）、M5（集成方案定性为纯决策存档、`.tmp-kubepi` 三分类清理）。**服务器全程只读**，唯一写操作 = 经确认后手动跑一次面板备份（停容器约 2 秒）。**推翻两条旧记载**：`is_build_in` 实为 `false`（故改 url 不回表刷新、但界面可删，集成方案 6.1 第一条论证作废）；`bk-lite-master/` 解除跟踪**实际未生效**（仍 17,822 条索引） |

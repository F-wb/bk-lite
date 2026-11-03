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

## 2. 当前状态快照（2026-11-03）

| 项 | 值 |
|---|---|
| 源码 | `bk-lite-master` 仓分支 `shengda/v1.0-custom` @ `b5bc86ab37`（= 上游 `b44a5c92c0` + 631 提交 merge，30 二开文件完整）；服务器构建副本 `/opt/bk-lite-src` 同点（GitHub 自服务器不可达，经 git bundle 同步） |
| 上游镜像 | `main` = 上游最新 `b44a5c92c0`（2026-11-03 同步，GitHub 与 GitLab 同 hash） |
| 运行环境 | 开发机 192.168.1.11 `/opt/bk-lite`（compose 项目名 `compose`），18 服务全 Up，`https://192.168.1.11/` = 200；磁盘可用 66G（旧镜像已清） |
| 预发布环境 | `https://10.10.2.91/`：跑**官方 latest 镜像**（非二开 ACR 镜像）做全功能试用；模块全部启用，`INSTALL_APPS` = 12 项 + `apm,rum,workflow`，编排引擎 conductor 已部署；`APP_WORKERS=4`。**定位：官方 AI 版试用，无二开版本** |
| 生产环境 | `https://10.10.2.95/`（主机名 ops，15G 内存/273G 磁盘）：**一期已于 2026-11-03 部署上线**——基线安装器 + 公司仓库镜像覆盖，18 服务全 Up、server/web healthy、站点 200；`INSTALL_APPS` 9 应用；品牌已收敛「盛大运维系统」；备份 crontab（每日 02:30）已配置。**待用户界面操作：钉钉企业登录参数配置（corp_id/appkey/appsecret）、JumpServer 集成实例、排除模块菜单隐藏** |
| 镜像仓库策略 | 构建/中转=个人 ACR `crpi-qp8pnmdzkajoq92t…/fanwenbin/bk-lite`；**部署拉取=公司仓库 `registry.cn-zhangjiakou.aliyuncs.com/shengda/bk-lite`**（双 tag 已同步 `server/web-20261103a` + 滚动 tag，11 与 95 均已 docker login，账号 lloyd9527） |
| 当前镜像 | ACR `:server-20261103a`（33 层，**官方 Dockerfile 原件**，extras 全量含 mlops/opspilot → **AI 就绪**）/ `:web-20261103a`（11 层）；回滚点 `:server-20261015d` / `:web-20261015c` |
| 启用应用（9 个） | `system_mgmt,cmdb,monitor,node_mgmt,console_mgmt,alerts,log,job_mgmt,patch_mgmt` |
| 未启用模块 | 测试机：apm / mlops / opspilot / operation_analysis / rum / workflow（原 workflow_orchestration，上游 3ccc3e336c 已改名）；菜单可见、点击 404 属预期 |
| 模块启用机制 | Django 只为 `.env` 里 `INSTALL_APPS` 列出的 app 注册路由；URL 结构已改为 `api/v1/<app>/` 动态挂载 + 前端 Next.js BFF（`/api/proxy/<app>/...`）；安装器开关持久化在 `common.env`，数值参数必须 `--app-workers=4` |
| 宿主约束 | 内存 7.2G——构建前必须全停容器；**升级前强制备份**（本次迁移至 system_mgmt.0053） |
| 使用文档 | `盛大运维系统_使用文档/` v2（按钮级）共 17 篇；**未含截图** |

## 3. 仓库与路径

| 仓库 | 路径 | 说明 |
|---|---|---|
| 源码 fork | `d:\Code\bk-lite\bk-lite-master` | `main`=上游镜像（**禁二开**，GitHub 与 GitLab 同 hash）；`shengda/v1.0-custom`=二开唯一分支；remote `origin`(GitHub 个人 fork) + `upstream`。**GitLab 推送**：`git push origin main` 后再 `git push http://gitlab.ext.sdprint.tech/fanwenbin/bk-lite.git main:main`（HTTP；SSH 22 被代理拦。GitLab main 曾是受保护分支，force push 需网页临时开开关） |
| **交接仓（本文件所在）** | `d:\Code\bk-lite` | 全部专题手册与 `ops/` 脚本已归集于此；remote `gitlab`(内网 HTTP，SSH 22 被代理拦) + `origin`(GitHub)。**推送策略**：完整版推 GitLab 独立分支 `docs/ai-handover`；GitHub 同分支名放脱敏版；源码 main/shengda 归 `bk-lite-master` 仓管，本仓不碰 |
| 文档旧仓 | `d:\Code` | 无 remote；手册与 ops 已迁出，仅留他用目录 |

- 运行态：基线目录 `/opt/bk-lite`；自研脚本线上副本在 `deploy/`（镜像收敛）与 `scripts/`（备份还原）。
- 交接仓已解除对 `bk-lite-master/` 的跟踪（2026-10-19，`.gitignore` 排除；此前 vendored 跟踪产生 1.7 万条 CRLF/快照漂移噪音，已清除）。提交仍用 pathspec 只提自己的文件。

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

## 8. 接手第一步

1. 读本文件；需要细节再按第九节进手册。
2. 只读核验（一次 SSH 打包）：`docker compose ps`、`.env` 三变量（ACR + 9 应用）、站点 200。
3. 与用户确认任务类型（排障/类型一/类型二/启用 AI/文档），变更类先出计划等确认。

## 9. 详细文档索引（均在交接仓 `d:\Code\bk-lite\`）

| 需要什么 | 看哪份 |
|---|---|
| 二开 30 文件明细、对接记录、镜像台账、构建全流程 | `盛大运维系统_二开改动归档.md` |
| 两类升级 SOP、回滚矩阵、基线变化应对 | `盛大运维系统_部署手册.md`（第五章；`ops/apply-state.sh` 源在 `ops/`） |
| 组件/数据卷、备份还原、巡检、事故案例 §5.4 | `盛大运维系统_运维手册.md` |
| AI 模块（OpsPilot）零分叉启用方案（暂缓） | `盛大运维系统_AI模块规划.md` |
| 需求/架构/钉钉/JumpServer | `盛大运维系统_{需求规格说明书,架构设计文档,钉钉登录对接操作手册,堡垒机对接文档}.md` |
| 按模块的用户操作手册（按钮级，面向最终用户） | `盛大运维系统_使用文档/`（README 索引；00 总览 + 01~09 一期模块 + 10 二开 + 11~16 预生产模块；按钮文案以 `web/src/app/<模块>/locales/zh.json` 为准） |
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

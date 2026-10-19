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

## 2. 当前状态快照（2026-10-17）

| 项 | 值 |
|---|---|
| 源码 | `bk-lite-master` 仓分支 `shengda/v1.0-custom` @ `6e0be26b9e`（= 上游 master `371c89c9` + 30 个二开文件）；服务器构建副本 `/opt/bk-lite-src` 同点 |
| 运行环境 | 测试机 192.168.1.11 `/opt/bk-lite`（compose 项目名 `compose`），18 容器全 Up，`https://192.168.1.11/` = 200 |
| 当前镜像 | ACR `:server-20261015d`（29 层）/ `:web-20261015c`（11 层）；回滚点 `:server-20261015c` / `:web-20261015b` |
| 启用应用（9 个） | `system_mgmt,cmdb,monitor,node_mgmt,console_mgmt,alerts,log,job_mgmt,patch_mgmt` |
| 未启用模块 | apm / mlops / opspilot / operation_analysis / rum / workflow_orchestration（菜单可见、点击 404 属预期） |
| 宿主约束 | 内存 7.2G、根分区可用约 21G——构建前必须全停容器 + prune |

## 3. 仓库与路径

| 仓库 | 路径 | 说明 |
|---|---|---|
| 源码 fork | `d:\Code\bk-lite\bk-lite-master` | `main`=上游镜像（**禁二开**）；`shengda/v1.0-custom`=二开唯一分支；remote `origin`(GitHub 个人 fork) + `upstream` |
| **交接仓（本文件所在）** | `d:\Code\bk-lite` | 全部专题手册与 `ops/` 脚本已归集于此；remote `gitlab`(内网 HTTP，SSH 22 被代理拦) + `origin`(GitHub)。**推送策略**：GitLab 仓 main/shengda 是源码镜像（他人维护，**不动**），本仓完整版推为独立分支 `docs/ai-handover`；GitHub 同分支名放脱敏版 |
| 文档旧仓 | `d:\Code` | 无 remote；手册与 ops 已迁出，仅留他用目录 |

- 运行态：基线目录 `/opt/bk-lite`；自研脚本线上副本在 `deploy/`（镜像收敛）与 `scripts/`（备份还原）。
- 交接仓已解除对 `bk-lite-master/` 的跟踪（2026-10-19，`.gitignore` 排除；此前 vendored 跟踪产生 1.7 万条 CRLF/快照漂移噪音，已清除）。提交仍用 pathspec 只提自己的文件。

## 4. 铁律（不得违反）

1. 二开只进 `shengda/v1.0-custom`；冲突只在本机解，服务器只 `pull --ff-only`。
2. 正式手册对外统一"盛大运维系统"命名，不出现上游开源项目名；未启用模块只做前端隐藏，不删代码。
3. 服务器变更类操作（改配置/重启/重建/安装器）先经用户确认；一轮任务只开一次 SSH、命令打包。
4. 当前生产镜像 extras 仅 `.[cmdb,dev]`——**启用任何额外应用前必须先重建全量镜像，顺序不能反**。
5. 重跑安装器后必须 `bash /opt/bk-lite/deploy/apply-state.sh --cleanup-beat` 收敛；改 `.env` 后必须 `up -d --force-recreate`。
6. 脚本的 FATAL 断言不许删；基线升级前强制备份（DB 迁移不可逆，数据只能还原）。
7. Git 提交用 pathspec 只提自己的文件；用户未要求不 commit、不 push。

## 5. 升级速查（细则见部署手册第五章）

- **类型一·跟进上游代码（月度，最常见）**：本机 merge → buildx 构建推 ACR → 服务器 `pull` + `up -d --force-recreate server web`。**不重跑安装器**。
- **类型二·升级基线**：备份留证 → 预下载安装器比对变化 → 不带开关重跑（禁 `--clean`）→ `apply-state.sh --cleanup-beat` → `pull && up -d` → 七项校验 → 登记台账。**先在测试机演练**。
- 构建要点：全停容器+prune；`docker buildx build --provenance=false --push`，先 pull `server-base:latest` 补 blob；推送校验只比层数（server 29 / web 11）。
- 备份：`/opt/bk-lite/scripts/backup-all.sh`；还原 `restore-all.sh --from <时间戳>`。

## 6. 高频坑（都付过代价）

1. 安装器重跑**整份重写 `.env`**：镜像变量回基线 + INSTALL_APPS 变官方默认（含需 `fitz` 的 operation_analysis）→ 两处漂移，旧 overlay 脚本只盖得住第一处。
2. 容器 healthy、站点 200 **不等于日志无错**；必看 `docker compose logs --since=3m server`。
3. Celery beat 用 DatabaseScheduler：摘应用后残留在表 `django_celery_beat_periodictask`，删行后还须 bump `periodictasks.last_update`（或 restart server）。
4. 回退误启用组件的官方开关：`bash bootstrap.sh --no-opspilot </dev/null>`（不清数据）。
5. vector 反复 Restarting 多是 server 宕的下游症状，server 恢复即自愈。
6. extras 不能只装 `.[cmdb]`（django_extensions 无条件加载，缺了启动即崩）。
7. 启用 AI 弃用 `Dockerfile.server.local`，直接用官方 `support-files/release/Dockerfile`（零分叉，层数基准会变）；`Dockerfile.base.local` 是死代码。
8. PowerShell 5：无 `&&`/heredoc；管道传脚本带 CRLF（需 `tr -d '\r'`）；远程 SQL/复杂命令用 base64 here-string 透传；高频 SSH 会撞 sshd 上限。

## 7. 待办

- [ ] 【用户侧】一期排除模块的前端菜单手动隐藏（应用管理 UI）
- [ ] 【待决策】异地备份（现备份与生产同机同盘）；测试机 crontab 当前为空
- [ ] 【待决策】SSH 保活（`~/.ssh/config` 加 ServerAliveInterval）
- [ ] 每月第一周跟进上游（运维手册 §6.4）；启用 AI 时按部署手册场景 E

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
| Agent 长期记忆 | `c:\Users\Administrator\.trae-cn\memory\projects\-d-Code--p2-57a804f58e1514058492\`（project_memory + 每日 topics） |

## 10. 更新日志

| 日期 | 摘要 |
|---|---|
| 2026-10-17 | 初版；同日按"精炼聚焦"原则重写：去时间线流水账与大表（细节归手册），新增 Agent 协作三规则；手册与 ops 脚本归集到交接仓，GitHub 脱敏分支已推 |
| 2026-10-17 | 内网 GitLab 已推：发现远端 main/shengda 为源码镜像（与本仓历史无关），经用户确认**推为独立分支 `docs/ai-handover`**（HTTP 传输，SSH 22 被代理 reset），不触碰源码镜像分支 |

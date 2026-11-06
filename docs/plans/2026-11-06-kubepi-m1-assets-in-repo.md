# 集群管理模块 M1（资产落仓 + 版本台账）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把已在生产运行的「集群管理」模块（实现为 KubePi）的**可执行资产**与**版本/变更追溯**归档进交接仓，使任何人接手都能凭仓库复原现场，不依赖服务器残留与临时脚本堆。

**Architecture:** 本批**不写代码、不改平台、不动线上**，只新增仓库文件与订正既有文档中的路径引用。因此不存在单元测试栈；每个任务的"测试"= **可重复执行的只读校验命令**（`diff` / `md5sum` / `grep` / `git ls-files` / `bash -n`），且校验对象是**线上现状与仓库内容的一致性**——这是文档类任务里唯一有意义的回归判据。计划中唯一的脚本产物 `restore-kubepi.sh` 自带 `--dry-run`，其测试方式就是 dry-run 输出与语法检查，**禁止在实施过程中真跑还原**。

**Tech Stack:** Git（`git mv` / `git ls-files`）、Bash、Docker CLI（仅只读子命令）、PostgreSQL 只读 SELECT、Markdown。

**Spec:** `d:\Code\bk-lite\docs\specs\2026-11-06-kubepi-module-standardization-design.md`（本计划实现其 §3 全部 + §4 全部 + §6 的 M1 行；执行前请连同 spec 一起阅读）

## Global Constraints

- 线上服务器 `10.10.2.95` 本批**只允许只读命令**：`cat` `ls` `md5sum` `docker ps|images|volume ls|inspect` `psql -c "SELECT ..."`。禁止 `apply/create/up/down/restart/rm/edit/write` 到线上（spec §9）。
- 面板 `app.yml` 中启动生成的 `jwt.key` 属密钥，**任何产出文件与文档不得记录其值**（spec §9）。
- 对外命名一律「集群管理」；`KubePi` 仅作为实现名出现在版本台账与附录（spec D3）。
- 不改任何平台代码，因此**不需要重建镜像**，铁律 4 与镜像顺序守则本批不适用（spec §9）。
- `docker-compose.yml` 与 cron 文件必须**逐字**取线上原文入仓，禁止改写为带 `${VAR}` 的模板（spec §3.1）。
- 还原步骤以 `ops/kubepi/restore-kubepi.sh` 为唯一权威，文档只引用不复制（spec §3 目录注释）。
- **提交纪律**：每个任务结尾的 commit 步骤，仅在用户当批已明确同意提交时执行；否则跳过 commit、文件照常落盘，最后统一询问（bk-lite 铁律 7）。
- **严禁 `git commit -a` 与不带 pathspec 的 `git add -A` / `git add .`**。原因见下方「计划级发现」P2：`bk-lite-master/` 仍有 17,822 条索引项与 `.gitignore` 冲突，工树里有大量 M/D 改动；全量 add 会把这 1.7 万个 vendored 文件卷进提交。本计划**所有** `git add` 必须逐个显式列出路径。
- **目录规范（用户指令，凌驾于本计划原有排布）**：一个服务一个子目录。可执行资产进 `ops/<service>/`，模块技术文档进 `docs/<service>/`；`ops/` 根不得直接放文件。目录与服务名用**实现名**（`ops/kubepi/`、`docs/kubepi/`），面向使用者与产品级手册用**模块名**（「集群管理」）。使用文档不拆目录，仍走 `盛大运维系统_使用文档/` 单一册系。
- 所有文件的行尾必须是 LF；`bash` 脚本不得含 CRLF（历史坑：管道传脚本带 `\r` 导致远端静默失败）。

---

## 本计划依赖的已实测事实（全部为 2026-11-06 只读取证结果，直接引用即可）

| 用途 | 值 |
|---|---|
| compose 线上原文 | 289 B，见 Task 1 Step 2 代码块 |
| cron 线上原文 | 见 Task 1 Step 3 代码块 |
| `backup-kubepi.sh` md5 | `4edf74bd1f2b5c429b7b7b87d1847a71`（95 线上 / `bk-lite/ops/` / `.tmp-kubepi/backup-kubepi.sh` / `.tmp-kubepi/backup-kubepi.lf.sh` **四处全等**） |
| 面板镜像 | `1panel/kubepi:v2.0.3`，digest `sha256:9d096b224bf45fe97f510c77913a8ed31c28f7bfe9b59d320b70c2b74eeeb020`，569 MB，ID `9d096b224bf4` |
| 拉取源 | `hub.rat.dev/1panel/kubepi:v2.0.3`（`docker.m.daocloud.io` 已白名单化拒绝；`docker.io` 不可达） |
| 公司仓库 | `registry.cn-zhangjiakou.aliyuncs.com/shengda/` 下**无任何 kubepi 镜像** |
| 卷 | `kubepi-data`，driver `local`，mount `/var/lib/docker/volumes/kubepi-data/_data`，labels 空，compose 内 `external: true` |
| 容器 | `kubepi`，`restart: unless-stopped`，`0.0.0.0:18080->80/tcp`（含 IPv6），非 privileged，唯一挂载即 `kubepi-data` |
| 入口 | `http://10.10.2.95:18080/kubepi` → 200，`<title>KubePi</title>`，`ssl.enable: false` |
| 备份 | `/opt/kubepi/backup/20261106_024001/` 成功，产物 24 K，`latest` 软链在位，日志 `/var/log/kubepi_backup.log` |
| 上游 | `1Panel-dev/KubePi`（`github.com`，默认分支 `master`）· tag `v2.0.3` → commit **`e183085da6e5b74dd17a44a3a6812cbe6dacc652`**（轻量标签直指 commit）· 仓库 `pushed_at` 2026-08-18 |
| 平台登记 | `system_mgmt_app`：`id=16 · name=kubepi · display_name=集群管理 · description=空 · description_cn=空 · icon=ks1 · url=http://10.10.2.95:18080/kubepi · is_build_in=f · tags=["集群管理"]` |
| 自动生成角色 | `system_mgmt_role`：`id=49 · name=user · app=kubepi` |
| 用户应用快照 | `console_mgmt_user_app_set` 仅 1 行（`username=admin`），`app_config_list` 内嵌完整 app 对象含 url |
| 运行容器数 | `docker ps -q \| wc -l` = **19**（平台 compose = 18） |

---

## File Structure（本批新建 / 移动 / 修改）

```
新建目录  bk-lite/ops/bk-lite/            ← 平台自有脚本的家（Task 0）
新建目录  bk-lite/ops/kubepi/             ← 面板资产的家（Task 1）
新建      bk-lite/ops/README.md            ← 目录规范：一个服务一个子目录；ops/ 不得直接放文件（Task 0）
新建      bk-lite/ops/bk-lite/README.md    ← 仓库路径 ↔ 线上路径映射（Task 0）
移动      ops/{apply-state,backup-all,overlay-images,restore-all}.sh → ops/bk-lite/   （git mv，内容不动）
新建      bk-lite/ops/kubepi/docker-compose.yml       ← 线上原文
新建      bk-lite/ops/kubepi/cron.d-kubepi-backup     ← 线上原文 + 安装命令注释
移动      bk-lite/ops/backup-kubepi.sh → bk-lite/ops/kubepi/backup-kubepi.sh   （未跟踪文件，用文件系统移动，见 P1）
新建      bk-lite/ops/kubepi/restore-kubepi.sh        ← 还原 + 校验合一，带 --dry-run
新建      bk-lite/ops/kubepi/README.md                ← 目录定位 / 同步方向 / 禁改项 / D4 红线
新建      bk-lite/docs/kubepi/版本与变更台账.md      ← T1–T4 四张表（模块技术文档进 docs/<service>/，不再堆仓库根）
入库      四份从未进过 git 的手册（见 P3）
修改      9 行共 11 处 `ops/*.sh` 文档引用 → `ops/bk-lite/*.sh`（Task 0 Step 5）
修改      bk-lite/盛大运维系统_集群管控集成方案.md:257      ← 仓库副本路径订正（Task 2）
修改      bk-lite/AI_HANDOVER.md（§3 路径与目录规范 + §7 待办 + §9 索引补 2 行）
```

**目录规范的硬约定**（用户指令：微服务式模块化，避免混淆）：

| 什么 | 放哪 | 例子 |
|---|---|---|
| 某服务的可执行资产 | `ops/<service>/` | `ops/bk-lite/backup-all.sh`、`ops/kubepi/docker-compose.yml` |
| 某服务的技术文档 | `docs/<service>/` | `docs/kubepi/架构与部署.md`、`docs/kubepi/版本与变更台账.md` |
| 产品级手册（面向整个系统） | 仓库根，保持 `盛大运维系统_*.md` | 架构设计文档、运维手册、部署手册 |
| 使用者分册 | `盛大运维系统_使用文档/NN_<模块>.md` 单一册系 | `17_集群管理.md`（**不进 `docs/kubepi/`**） |
| 规划产物 | `docs/specs/`、`docs/plans/` | 本计划 |

为何使用文档不按服务拆：使用者面对的是平台宫格与菜单，不是后端服务；把用户手册按服务拆开，恰恰会制造本次要消除的那种混淆。为何产品级手册不搬家：10 份已入库、互相引用、被 §9 索引，为对称而搬的风险大于收益，且改中文名会违反对外命名铁律。

**spec §3.2 的一处澄清**：spec 要求移位时"同一批改掉集成方案与运维手册两处引用"。已核实**运维手册 §七（L601 起的表格）从未列过 `backup-kubepi.sh`**，故该处不存在坏引用，只有新增需求——新增归 M3。本批只需改 `集成方案:257` 一处（在 Task 2）。

**spec §5.4 的一处澄清**：AI_HANDOVER §9 的 4 行索引不能在 M1 全加（`架构与部署说明`、`17_集群管理` 到 M4 才存在，先索引会造出死链）。M1 只加 2 行（`集群管控集成方案` + `版本与变更台账`），另 2 行随 M4。spec §7 验收判据 #3 属于 M4 完成后的终态，本批按 2 行验收。

---

## 计划级发现（写计划时实测，spec 未预见；改变任务做法但不改范围）

| # | 实测事实 | 对计划的影响 |
|---|---|---|
| **P1** | `ops/backup-kubepi.sh` **不在 git 索引里**（`git ls-files ops/` 只返回 `apply-state.sh` `backup-all.sh` `overlay-images.sh` `restore-all.sh` 四个）。spec §3 称它"已有仓库副本"，严格说是**已有仓库目录下的文件，但从未入库** | Task 2 不能用 `git mv`（源文件未被跟踪，会报错）；改为文件系统移动 + `git add` 新路径 |
| **P2** | `bk-lite-master/` 虽有 `.gitignore` 条目与"已解除跟踪"的提交 `edc98a28`，但 `git ls-files bk-lite-master/ \| wc -l` = **17,822**，且工作树中该目录大量 M/D 显示在 `git status` 里——即 **AI_HANDOVER §3 记载的"解除跟踪"实际未生效** | **本批不修**（改动量与风险远超"规范化补齐"范围，且属仓库治理专项）。但已写成全局约束防止执行时误触；并作为待办记入台账与 AI_HANDOVER §7（Task 5 / Task 6） |
| **P3** | 除集成方案外，`生产环境对接操作手册.md`、`资源纳管操作手册.md`、`跟进官方代码的固定动作.md` **同样从未入库** | Task 2 扩为"归位 + 首次入库"：M1 就把这四份一并纳入版本管理。这正是用户点名要补的"代码仓库"项，且不扩范围（纯仓库动作，零线上风险） |

注：P2 是比 M1 所有条目都更值得知道的坑——一个号称已排除的目录仍在索引里，意味着任何 `commit -a` 都会造成与历史坑册第 1 条同族的 1.7 万条 CRLF/快照漂移噪音。交接时必须提醒。

---

### Task 0: `ops/` 按服务分目录重构 + 11 处文档引用订正

**Files:**
- Create dir: `bk-lite/ops/bk-lite/`, `bk-lite/ops/kubepi/`
- Move: `ops/apply-state.sh` `ops/backup-all.sh` `ops/overlay-images.sh` `ops/restore-all.sh` → `ops/bk-lite/`
- Create: `bk-lite/ops/README.md`, `bk-lite/ops/bk-lite/README.md`
- Modify（共 9 行 11 处：`apply-state` 3 + `backup-all` 4 + `restore-all` 4 + `overlay-images` 0）: `AI_HANDOVER.md:107`、`运维手册.md:7,268,322,605,606,615`、`部署手册.md:141`、`跟进官方代码的固定动作.md:17`

> `overlay-images.sh` 实测命中 **0 处**——它在 `部署手册:141` 只以无前缀的 `overlay-images.sh`（本章）出现。替换循环里保留它是无害的 no-op，但不得为了“让数字对上”去改那些无前缀的提法。

**Interfaces:**
- Consumes: 无（本任务是目录规范的地基，必须最先做）
- Produces: `ops/<service>/` 布局与规范；Task 1–4 写入的 `ops/kubepi/*` 与 Task 5–7 引用的路径均建立在此约定上

- [x] **Step 1: 失败测试——确认脚本仍平铺在 `ops/` 根**

Run（在 `d:\Code`）:
```powershell
git -C bk-lite ls-files ops/
(Get-ChildItem bk-lite\ops -File).Name -join ' '
```
Expected: 两条都只列 4 个脚本且均直接位于 `ops/` 根（`ops/apply-state.sh` 等）；`ops/` 下无子目录。

- [x] **Step 2: 建目录并 git mv（这 4 个已跟踪，可用 git mv）**

```powershell
New-Item -ItemType Directory -Force bk-lite\ops\bk-lite, bk-lite\ops\kubepi | Out-Null
cd d:\Code\bk-lite
git mv ops/apply-state.sh    ops/bk-lite/apply-state.sh
git mv ops/backup-all.sh     ops/bk-lite/backup-all.sh
git mv ops/overlay-images.sh ops/bk-lite/overlay-images.sh
git mv ops/restore-all.sh    ops/bk-lite/restore-all.sh
git -C . status --short ops/
```
Expected: `status` 输出 **恰好 4 行 `R`**（rename），源路径与目标路径一一对应。**不得出现任何 `bk-lite-master/` 路径。**

- [x] **Step 3: 写 `ops/README.md`（目录规范正文）**

```markdown
# ops/ · 按服务分的运维资产

**一个服务一个子目录。`ops/` 根不得直接放文件。** 新接一个服务，就新增一个以该服务实现名命名的子目录，并把它的仓库文件全部放进去。

| 目录 | 对应的线上位置 | 说明 |
|---|---|---|
| `ops/bk-lite/` | `/opt/bk-lite/`（子目录 `deploy/` 与 `scripts/`） | 盛大运维系统平台自身的脚本 |
| `ops/kubepi/` | `/opt/kubepi/` | 集群管理模块（外挂面板）的编排与备份还原资产 |

规则：

1. 目录名用**实现名/服务名**（运维对象就是服务），不用对外产品名。
2. 每个子目录必须自带 `README.md`，至少写：仓库路径 ↔ 线上路径映射、同步方向、禁改项。
3. 仓库→线上是**单向同步**（以仓库为准）；从线上取回只用于核对是否漂移，不得未审阅直接落仓。
4. 脚本一律 LF；带断言且失败即停，**FATAL 断言不许删**（沿用平台脚本准则）。
5. 外挂服务的临时脚本不得长期停留在 `d:\Code` 根目录（验证完即归类或删除）。
```

- [x] **Step 4: 写 `ops/bk-lite/README.md`**

```markdown
# ops/bk-lite · 平台脚本

对应线上：基线目录 `/opt/bk-lite`。**本目录重排不改变线上路径**，仅改变仓库里的位置。

| 仓库文件 | 线上位置 | 用途 |
|---|---|---|
| `apply-state.sh` | `/opt/bk-lite/deploy/apply-state.sh` | 幂等收敛：镜像变量 + `INSTALL_APPS`，可带 `--cleanup-beat` |
| `backup-all.sh` | `/opt/bk-lite/scripts/backup-all.sh` | 一键备份（P0/P1/P2，可选 `--with-volumes`） |
| `restore-all.sh` | `/opt/bk-lite/scripts/restore-all.sh` | 数据还原（全量 / 单项，四道安全闸） |
| `overlay-images.sh` | —— | 仅收敛镜像变量的早期脚本，已被 `apply-state.sh` 取代为超集；**保留在位作向后兼容，勿删** |

同步：

```bash
scp ops/bk-lite/backup-all.sh ops/bk-lite/restore-all.sh root@<host>:/opt/bk-lite/scripts/
scp ops/bk-lite/apply-state.sh root@<host>:/opt/bk-lite/deploy/
ssh root@<host> 'chmod +x /opt/bk-lite/scripts/*.sh /opt/bk-lite/deploy/*.sh'
```

重排记录：2026-11-06 由 `ops/` 根平铺迁入本子目录（`git mv`，内容零改动）；同期已把全部文档引用改为 `ops/bk-lite/…`。
```

- [x] **Step 5: 批量订正 11 处文档引用**

对 4 个文件做同一组替换（只改仓库路径，**不得改 `/opt/bk-lite/...` 线上路径**）：

```powershell
cd d:\Code\bk-lite
$files = @("AI_HANDOVER.md","盛大运维系统_运维手册.md","盛大运维系统_部署手册.md","跟进官方代码的固定动作.md")
foreach ($f in $files) {
  $t = Get-Content -Raw -Encoding UTF8 $f
  foreach ($s in @("apply-state","backup-all","overlay-images","restore-all")) {
    $t = $t -replace "ops/$s\.sh", "ops/bk-lite/$s.sh"
  }
  [IO.File]::WriteAllText((Resolve-Path $f), $t, (New-Object Text.UTF8Encoding $false))
}
```
逐处人工核对清单（替换后这些行应变为下列内容）：

| 文件 | 行 | 现值→目标（只改仓库路径部分） |
|---|---|---|
| `AI_HANDOVER.md` | 107 | `` `ops/apply-state.sh` 源在 `ops/` `` → `` `ops/bk-lite/apply-state.sh` 源在 `ops/bk-lite/` `` |
| `运维手册.md` | 7 | `` `ops/backup-all.sh`…`ops/restore-all.sh`…线上位置 `/opt/bk-lite/scripts/` `` → 仓库路径加 `bk-lite/` 前缀，线上路径不动 |
| `运维手册.md` | 268 | （源文件见 `ops/backup-all.sh`）→（源文件见 `ops/bk-lite/backup-all.sh`） |
| `运维手册.md` | 322 | （源文件见 `ops/restore-all.sh`）→（源文件见 `ops/bk-lite/restore-all.sh`） |
| `运维手册.md` | 605 | 表格第一列 `ops/backup-all.sh` → `ops/bk-lite/backup-all.sh`（第二列 `/opt/bk-lite/scripts/…` 不动） |
| `运维手册.md` | 606 | 同上，`restore-all.sh` |
| `运维手册.md` | 615 | `scp ops/backup-all.sh ops/restore-all.sh 192.168.1.11:/opt/bk-lite/scripts/` → 两个源路径均加 `bk-lite/`，目的端不动 |
| `部署手册.md` | 141 | 源码：仓库 `ops/apply-state.sh` → 仓库 `ops/bk-lite/apply-state.sh`（同句内 `/opt/bk-lite/deploy/apply-state.sh` 不动） |
| `跟进官方代码的固定动作.md` | 17 | `ops/apply-state.sh` → `ops/bk-lite/apply-state.sh` |

注：第 107 行的后半句 `` 源在 `ops/` `` 不会被正则命中（没带 `.sh`），**必须手工改成 `` 源在 `ops/bk-lite/` ``**。

- [x] **Step 6: 校验（四个条件必须同时成立）**

```powershell
cd d:\Code
# 注意：下面所有扫描必须排除 docs/（本计划与 spec 里就含有这些模式串，不排会自匹配误报）
$scan = @(Get-ChildItem bk-lite\*.md -File) + @(Get-ChildItem bk-lite\ops -Recurse -Filter *.md -File) + @(Get-ChildItem bk-lite\盛大运维系统_使用文档 -Filter *.md -File)
echo '① 旧路径应零命中'
($scan | Select-String -Pattern 'ops/(apply-state|backup-all|overlay-images|restore-all)\.sh' | Where-Object { $_.Line -notmatch 'ops/bk-lite/' }).Count
echo '② 新路径应命中 ≥ 11'
($scan | Select-String -Pattern 'ops/bk-lite/[a-z\-]+\.sh' -AllMatches | ForEach-Object { $_.Matches.Value }).Count
echo '③ 不得出现双层前缀'
($scan | Select-String -Pattern 'ops/bk-lite/bk-lite/').Count
echo '④ 线上路径必须一字未改（基线 = 36，口径固定为仅仓库根 *.md）'
(Get-ChildItem bk-lite\*.md -File | Select-String -Pattern '/opt/bk-lite/(deploy|scripts)/[a-z\-]+\.sh' -AllMatches | ForEach-Object { $_.Matches.Value }).Count
echo '⑤ 中文文档不得因写回引入 BOM 或乱码'
$b = [IO.File]::ReadAllBytes((Resolve-Path 'bk-lite\盛大运维系统_运维手册.md'))
"BOM=$($b[0] -eq 0xEF -and $b[1] -eq 0xBB)"
Get-Content -TotalCount 2 -Encoding UTF8 bk-lite\盛大运维系统_运维手册.md
```
Expected: ① = `0`；② ≥ `11`（Step 3/4 写的两个 README 也含新路径，故取≥）；③ = `0`；④ = `36`（Step 1 存下的基线，必须一字未变）；⑤ `BOM=False` 且中文正常显示。

> **陷阱一（实测踩到）**：若扫描范围含 `docs/`，①②③ 会命中本计划自身的命令文本，看起来像缺陷实则自匹配。所以上面的 `$scan` 变量已把 `docs/` 排除，**不要改回 `Get-ChildItem bk-lite -Recurse`**。
>
> **陷阱二（实测踩到）**：④ 的基线 36 是**仅仓库根 `*.md`** 口径实测得到的；Step 3/4 新增的两个 README 自身又写了 6 条线上路径，所以拿 `$scan`（含 `ops/**`）去比会得到 42 并误报为"误改了线上路径"。**④ 必须用上面写死的仓库根口径跑**；逐文件基线：`AI_HANDOVER.md` 2 · `AI模块规划.md` 3 · `运维手册.md` 19 · `部署手册.md` 11 · `集群管控集成方案.md` 1 = 36。

额外硬校：PowerShell 写回必须保持**各文件原有的 BOM 状态**（上述脚本已如此）——历史坑：ps1/文档缺 BOM 或多出 BOM 会导致解析与显示错乱。

- [ ] **Step 7: Commit（需用户已批准提交，否则跳过）**

```bash
git add ops/README.md ops/bk-lite/README.md ops/bk-lite/apply-state.sh ops/bk-lite/backup-all.sh ops/bk-lite/overlay-images.sh ops/bk-lite/restore-all.sh
git rm --cached ops/apply-state.sh ops/backup-all.sh ops/overlay-images.sh ops/restore-all.sh
git add AI_HANDOVER.md 盛大运维系统_运维手册.md 盛大运维系统_部署手册.md 跟进官方代码的固定动作.md
git diff --cached --name-only
git commit -m "chore(ops): 按服务分目录——平台脚本迁入 ops/bk-lite/，并订正全部文档引用"
```
Expected: `git diff --cached --name-only` **不含 `bk-lite-master/` 任何路径**。若 Step 2 的 `git mv` 已自动完成旧路径移除，此处 `git rm --cached` 会报"未匹配任何文件"，属预期，跳过该行即可。

---


### Task 1: `ops/kubepi/` 目录与线上原文落仓（compose + cron）

**Files:**
- Create: `d:\Code\bk-lite\ops\kubepi\docker-compose.yml`
- Create: `d:\Code\bk-lite\ops\kubepi\cron.d-kubepi-backup`

**Interfaces:**
- Consumes: 无
- Produces: `ops/kubepi/` 目录存在；Task 2 的 `git mv` 目标目录、Task 3 与 Task 4 的 README 引用路径均依赖此目录。

- [x] **Step 1: 先跑"失败测试"——确认仓库里确实没有这些文件**

Run（在 `d:\Code`）:
```powershell
git -C bk-lite ls-files ops/kubepi/
```
Expected: **无输出**（空）。若有输出说明已被落仓，停止并核对是否重复执行。

- [x] **Step 2: 写 `ops/kubepi/docker-compose.yml`（逐字，禁止模板化）**

```yaml
services:
  kubepi:
    image: 1panel/kubepi:v2.0.3
    container_name: kubepi
    restart: unless-stopped
    ports:
      - "18080:80"
    volumes:
      - kubepi-data:/var/lib/kubepi
networks:
  default:
    name: kubepi
volumes:
  kubepi-data:
    name: kubepi-data
    external: true
```

文件首行不加注释（保持与线上逐字节一致，便于 `diff` 验收）。

- [x] **Step 3: 写 `ops/kubepi/cron.d-kubepi-backup`**

```
# KubePi 数据每日备份（独立于平台备份任务，02:40 跑在平台 02:30 之后）
# 脚本内部已 tee 到 /var/log/kubepi_backup.log，故此处不再重定向到同一文件（避免行重复）
40 2 * * * root /opt/kubepi/backup-kubepi.sh > /dev/null 2>&1
```

再追加安装说明注释块（安装方式，不改变上面三行的内容）：

```
# 安装： install -m 644 cron.d-kubepi-backup /etc/cron.d/kubepi-backup
# 卸载： rm -f /etc/cron.d/kubepi-backup
# 校验： cat /etc/cron.d/kubepi-backup && tail -20 /var/log/kubepi_backup.log
```

- [x] **Step 4: 跑校验——与线上必须完全一致**

Run:
```powershell
scp root@10.10.2.95:/opt/kubepi/docker-compose.yml $env:TEMP\live-compose.yml
scp root@10.10.2.95:/etc/cron.d/kubepi-backup $env:TEMP\live-cron
git -C bk-lite diff --no-index --ignore-space-at-eol $env:TEMP\live-compose.yml bk-lite\ops\kubepi\docker-compose.yml
git -C bk-lite diff --no-index --ignore-space-at-eol $env:TEMP\live-cron bk-lite\ops\kubepi\cron.d-kubepi-backup
```
Expected: 两条 `diff` 中 compose 必须**零差异**；cron 允许且仅允许 Step 3 追加的安装注释块差异（前 3 行零差异）。若 compose 有差异，以线上为准重写仓库文件，不得反向修改线上。

- [x] **Step 5: 确认无 CRLF**

Run:
```powershell
ssh root@10.10.2.95 "file /opt/kubepi/docker-compose.yml"; Select-String -Path bk-lite\ops\kubepi\* -Pattern "`r" -AllMatches
```
Expected: `file` 报告不含 `CRLF line terminators`；PowerShell 侧无命中。

- [ ] **Step 6: Commit（需用户已批准提交，否则跳过）**

```bash
git add ops/kubepi/docker-compose.yml ops/kubepi/cron.d-kubepi-backup
git commit -m "ops: 集群管理模块 compose 与 cron 原文入仓（此前仅存在于服务器）"
```

---

### Task 2: `backup-kubepi.sh` 归位 + 四份从未入库手册首次入库 + 集成方案路径订正

**Files:**
- Move（文件系统）+ Add（git）: `bk-lite/ops/backup-kubepi.sh` → `bk-lite/ops/kubepi/backup-kubepi.sh`
- Add（git，首次入库）: `bk-lite/盛大运维系统_集群管控集成方案.md`
- Add（git，首次入库）: `bk-lite/盛大运维系统_生产环境对接操作手册.md`
- Add（git，首次入库）: `bk-lite/盛大运维系统_资源纳管操作手册.md`
- Add（git，首次入库）: `bk-lite/跟进官方代码的固定动作.md`
- Modify: `bk-lite/盛大运维系统_集群管控集成方案.md:257`

**Interfaces:**
- Consumes: Task 1 建好的 `ops/kubepi/` 目录
- Produces: 台账 T4 与运维手册（M3）引用的脚本路径 = `ops/kubepi/backup-kubepi.sh`；Task 6 §9 索引的《集群管控集成方案》在本任务后才有仓库实体

- [x] **Step 1: 失败测试——三件事必须同时成立**

Run（在 `d:\Code`）:
```powershell
git -C bk-lite ls-files ops/
Get-ChildItem bk-lite -Filter *.md -File | ForEach-Object { if (git -C bk-lite ls-files -- (Resolve-Path -Relative $_.FullName)) { "TRACKED   $($_.Name)" } else { "UNTRACKED $($_.Name)" } }
Select-String -Path bk-lite\盛大运维系统_集群管控集成方案.md -Pattern 'bk-lite/ops/backup-kubepi\.sh'
```
Expected:
1. `git ls-files ops/` 返回 4 行：`ops/apply-state.sh` `ops/backup-all.sh` `ops/overlay-images.sh` `ops/restore-all.sh`——**没有 `backup-kubepi.sh`**（即 P1）；
2. 第 2 条里 `UNTRACKED` 至少包含《集群管控集成方案》《生产环境对接操作手册》《资源纳管操作手册》与 `跟进官方代码的固定动作.md` 四份（即 P3）；若某份已为 `TRACKED`，则从 Step 5 的 add 清单里去掉它；
3. 第 3 条命中 **1 处，行号 257**，该行现值：

```
| 备份（**已实施**） | 独立任务，**不改平台通用脚本**：`/opt/kubepi/backup-kubepi.sh`（仓库副本 `bk-lite/ops/backup-kubepi.sh`）+ ...
```

- [x] **Step 2: 文件系统移位（不能用 `git mv`，源文件未被跟踪）**

```powershell
Move-Item bk-lite\ops\backup-kubepi.sh bk-lite\ops\kubepi\backup-kubepi.sh
Test-Path bk-lite\ops\backup-kubepi.sh, bk-lite\ops\kubepi\backup-kubepi.sh
```
Expected: `False`（旧位置）、`True`（新位置）。两条必须同时成立。

- [x] **Step 3: 订正集成方案 L257 的仓库副本路径**

将 `bk-lite/ops/backup-kubepi.sh` 改为 `bk-lite/ops/kubepi/backup-kubepi.sh`。**只改这一处路径，同一行其余文字一字不动**（本行含 8.4 的完整流程描述，属 M5 才改写的范围）。

- [x] **Step 4: 校验内容零改动与坏引用已清**

Run:
```powershell
(Get-FileHash -Algorithm MD5 bk-lite\ops\kubepi\backup-kubepi.sh).Hash.ToLower()
ssh root@10.10.2.95 "md5sum /opt/kubepi/backup-kubepi.sh"
Select-String -Path bk-lite\盛大运维系统_集群管控集成方案.md -Pattern 'bk-lite/ops/backup-kubepi\.sh'
```
Expected: 两条 md5 均为 `4edf74bd1f2b5c429b7b7b87d1847a71`（内容零改动）；第三条 **无命中**（旧路径已从文档消失）。

- [x] **Step 5: 首次入库（逐个显式 pathspec，严禁 `-A` / `commit -a`）**

```powershell
cd d:\Code\bk-lite
git add ops/kubepi/backup-kubepi.sh
git add "盛大运维系统_集群管控集成方案.md"
git add "盛大运维系统_生产环境对接操作手册.md"
git add "盛大运维系统_资源纳管操作手册.md"
git add "跟进官方代码的固定动作.md"
Write-Host '--- 暂存区必须干净：只允许本批 5 个路径 ---'
git diff --cached --name-only
```
Expected: `git diff --cached --name-only` 输出 **恰好 5 行**（上列 5 个路径，不多不少）；且**输出中不得出现 `bk-lite-master/` 任何路径**（即 P2 防护）。若出现，立即 `git reset` 重做，不得提交。

- [x] **Step 6: 索引复核**

Run: `git -C bk-lite ls-files ops/`
Expected: 返回 **5 行**，新增 `ops/kubepi/backup-kubepi.sh`；`ops/backup-kubepi.sh` 仍不出现。

- [ ] **Step 7: Commit（需用户已批准提交，否则跳过）**

```bash
git commit -m "chore: 集群管理备份脚本归位 ops/kubepi/；四份长期未入库的专题手册首次入库"
```

---

### Task 3: `ops/kubepi/restore-kubepi.sh`（还原 + 校验合一）

**Files:**
- Create: `d:\Code\bk-lite\ops\kubepi\restore-kubepi.sh`

**Interfaces:**
- Consumes: Task 1 的目录；`ops/kubepi/docker-compose.yml`（还原后 `up -d` 用同一 compose）
- Produces: 还原步骤的**唯一权威**；M3 写运维手册还原节时只能指向本脚本，不得复制内容

- [x] **Step 1: 失败测试——脚本不存在**

Run: `Test-Path bk-lite\ops\kubepi\restore-kubepi.sh`
Expected: `False`

- [x] **Step 2: 写脚本（全文如下）**

```bash
#!/usr/bin/env bash
# 集群管理面板（实现：KubePi）数据卷还原与还原性校验。
#
# 两种模式：
#   --verify-only          只证明快照可还原：解包到一次性临时卷、与生产库比 md5、删临时卷。不碰生产。
#   --from <快照目录>       真还原：用快照覆盖生产卷 kubepi-data。**会丢生产数据，需人工确认**。
#   任一模式加 --dry-run    只打印将要执行的命令，不执行。实施本计划时必须用 --dry-run 测试。
#
# 为什么需要冷拷贝：面板库是 bbolt 单文件 + 独占文件锁，禁止两个实例同时打开同一份数据。
set -euo pipefail

DIR=/opt/kubepi
VOL=kubepi-data
CNAME=kubepi
IMG=1panel/kubepi:v2.0.3
TMPVOL=kubepi-restore-test
MODE=""; SNAPSHOT=""; DRYRUN=0

[ "$(id -u)" -eq 0 ] || { echo 'FATAL: 需 root 运行'; exit 1; }   # 断言不许删（沿用平台脚本准则）

while [ $# -gt 0 ]; do
  case "$1" in
    --verify-only) MODE=verify ;;
    --from)        MODE=restore; SNAPSHOT="${2:-}"; shift ;;
    --dry-run)     DRYRUN=1 ;;
    *) echo "FATAL: 未知参数 $1"; exit 1 ;;
  esac; shift
done

[ -n "$MODE" ] || { echo 'FATAL: 必须指定 --verify-only 或 --from <快照目录>'; exit 1; }

run() { if [ "$DRYRUN" -eq 1 ]; then echo "DRY-RUN: $*"; else echo "EXEC: $*"; "$@"; fi; }

latest_snapshot() { ls -1 "$DIR/backup/" | grep -E '^2[0-9]{7}_[0-9]{6}$' | tail -1; }

if [ "$MODE" = verify ]; then
  T="${SNAPSHOT:-$(latest_snapshot)}"
  [ -n "$T" ] && [ -d "$DIR/backup/$T" ] || { echo "FATAL: 快照不存在（当前取到：'$T'）"; exit 1; }
  echo "== 还原性校验：快照 $T =="
  # 临时卷可能因上次中断而残留；先探测再删，保证 --dry-run 下不产生任何真实调用
  if docker volume inspect "$TMPVOL" >/dev/null 2>&1; then run docker volume rm "$TMPVOL"; fi
  run docker volume create "$TMPVOL"
  run docker run --rm -v "$DIR/backup/$T:/in:ro" -v "$TMPVOL:/out" "$IMG" \
      sh -c 'tar xzf /in/kubepi-data_*.tar.gz -C /out && ls -l /out/db'
  echo -n 'restored md5 : '
  run docker run --rm -v "$TMPVOL:/src:ro" "$IMG" md5sum /src/db/kubepi.db
  echo -n 'production md5: '
  run docker run --rm -v "$VOL:/src:ro" "$IMG" md5sum /src/db/kubepi.db
  echo '== 只删除本脚本创建的临时卷，生产卷不动 =='
  if docker volume inspect "$TMPVOL" >/dev/null 2>&1; then run docker volume rm "$TMPVOL"; fi
  run docker inspect "$CNAME" --format 'state={{.State.Status}}'
  exit 0
fi

# ---- restore：破坏性路径，三道闸门 ----
[ -n "$SNAPSHOT" ] && [ -d "$SNAPSHOT" ] || { echo "FATAL: --from 需指向存在的快照目录（如 $DIR/backup/20261106_024001）"; exit 1; }
ls "$SNAPSHOT"/kubepi-data_*.tar.gz >/dev/null 2>&1 || { echo 'FATAL: 快照目录内找不到 kubepi-data_*.tar.gz'; exit 1; }
echo "!! 即将用 $SNAPSHOT 覆盖生产卷 $VOL，现有面板数据（集群导入、账号）将全部丢失 !!"
[ "$DRYRUN" -eq 1 ] || { printf '确认请大写输入 YES：'; read -r A; [ "$A" = "YES" ] || { echo '已取消'; exit 1; }; }
run docker stop "$CNAME"
run docker run --rm -v "$SNAPSHOT:/in:ro" -v "$VOL:/out" "$IMG" sh -c 'rm -rf /out/db && tar xzf /in/kubepi-data_*.tar.gz -C /out'
run docker start "$CNAME"
echo '== 还原后校验：入口须 200，且启动日志应出现 current db version（非空库标志）=='
run curl -s -o /dev/null -w 'http %{http_code}\n' --max-time 15 http://127.0.0.1:18080/kubepi
run docker logs --since 1m "$CNAME" 2>&1 | grep -iE 'current db version|error' | tail -10
echo "还原完成。若 compose 文件本身也丢失，先按 ops/kubepi/docker-compose.yml 重建：docker compose -p kubepi up -d"
```

- [x] **Step 3: 语法与 LF 校验**

Run:
```powershell
scp bk-lite\ops\kubepi\restore-kubepi.sh root@10.10.2.95:/tmp/rs.sh
ssh root@10.10.2.95 "tr -d '\r' < /tmp/rs.sh > /tmp/rs.lf.sh; bash -n /tmp/rs.lf.sh && echo SYNTAX_OK"
if ((Get-Content -Raw bk-lite\ops\kubepi\restore-kubepi.sh) -match "`r") { 'HAS_CRLF' } else { 'LF_ONLY' }
```
Expected: 依次出现 `SYNTAX_OK`（远端语法检查通过）与 `LF_ONLY`（仓库文件无 CR）。若为 `HAS_CRLF`，先就地修成 LF 再重跑本步。行尾检查放在**本地**做，是因为 PowerShell → ssh 的双层引号会让远端 `grep -c $'\r'` 这类写法不可靠（属已知坑）。

- [x] **Step 4: 用 `--dry-run` 验证两种模式的行为，严禁真跑还原**

Run:
```powershell
ssh root@10.10.2.95 "bash /tmp/rs.lf.sh --verify-only --dry-run"
ssh root@10.10.2.95 "bash /tmp/rs.lf.sh --from /opt/kubepi/backup/20261106_024001 --dry-run"
ssh root@10.10.2.95 "bash /tmp/rs.lf.sh 2>&1; echo rc=$?"
```
Expected:
1. 第一条全部输出以 `DRY-RUN:` 开头，**不出现 `EXEC:`**，且能自动取到最新快照名 `20261106_024001`；
2. 第二条同样全 `DRY-RUN:`，且**先打印覆盖警告**；
3. 第三条打印 `FATAL: 必须指定 --verify-only 或 --from <快照目录>` 且 `rc=1`（缺参必须失败，不许静默跳过——沿用平台脚本"断言即停"准则）。

- [x] **Step 5: 确认线上未因此被改动**

Run:
```powershell
ssh root@10.10.2.95 "docker volume ls | grep -c kubepi-restore-test; docker inspect kubepi --format '{{.State.Status}}'; docker ps -q | wc -l"
```
Expected: `0`（没有残留临时卷）、`running`、`19`。

- [x] **Step 6: 清理临时副本**

Run: `ssh root@10.10.2.95 "rm -f /tmp/rs.sh /tmp/rs.lf.sh"`
（仅删本任务自建的 `/tmp` 副本，不涉及任何既有文件。）

- [ ] **Step 7: Commit（需用户已批准提交，否则跳过）**

```bash
git add ops/kubepi/restore-kubepi.sh
git commit -m "ops: 新增 kubepi 还原与还原性校验脚本（还原步骤唯一权威，带 --dry-run）"
```

---

### Task 4: `ops/kubepi/README.md`

**Files:**
- Create: `d:\Code\bk-lite\ops\kubepi\README.md`

**Interfaces:**
- Consumes: Task 1/2/3 的四个文件名
- Produces: M3 写运维手册 §七 时的权威说明来源（同步方式、禁改项、D4 红线）

- [x] **Step 1: 失败测试**

Run: `Test-Path bk-lite\ops\kubepi\README.md` → Expected `False`

- [x] **Step 2: 写 README（全文如下）**

````markdown
# 集群管理模块 · 外挂服务部署资产

模块对外名称**集群管理**（平台应用宫格里的显示名）。本节文件描述其实现所依赖的外部服务。
实现名 KubePi 仅在本目录与版本台账中出现。

## 这是什么

「集群管理」模块的**可执行资产**：编排定义、备份任务、还原脚本。
面板本体不由本仓构建——它是第三方镜像，本仓只归档"我们怎么把它跑起来"。

| 文件 | 线上位置 | 说明 |
|---|---|---|
| `docker-compose.yml` | `/opt/kubepi/docker-compose.yml` | **线上原文逐字副本**，非模板。禁止改写为 `${VAR}` 形式 |
| `backup-kubepi.sh` | `/opt/kubepi/backup-kubepi.sh` | 每日冷拷贝快照（bbolt 需停容器后 tar） |
| `cron.d-kubepi-backup` | `/etc/cron.d/kubepi-backup` | 触发器，02:40 跑在平台 02:30 之后 |
| `restore-kubepi.sh` | 无固定线上位置 | **还原步骤的唯一权威**；文档只引用本脚本，不复制内容 |

## 同步方向（单向，仓库为准）

```bash
# 本地 → 服务器（变更前先比对）
scp ops/kubepi/docker-compose.yml root@10.10.2.95:/opt/kubepi/
scp ops/kubepi/backup-kubepi.sh   root@10.10.2.95:/opt/kubepi/ && \
ssh root@10.10.2.95 "chmod 700 /opt/kubepi/backup-kubepi.sh"
ssh root@10.10.2.95 "tr -d '\r' < /opt/kubepi/docker-compose.yml > /tmp/c && diff /tmp/c /opt/kubepi/docker-compose.yml"

# 服务器 → 仓库：仅用于核对是否漂移，不得反向把线上未审阅的改动直接落仓
scp root@10.10.2.95:/opt/kubepi/docker-compose.yml /tmp/ && diff /tmp/docker-compose.yml ops/kubepi/docker-compose.yml
```

## 与平台（`/opt/bk-lite`）的关系

- 独立 compose 项目名 `kubepi`、独立网络 `kubepi`、独立卷 `kubepi-data`。
- 平台安装器 `install.run` / `bootstrap.sh` / `apply-state.sh` **都碰不到本目录**，这是选择与平台同机混部的前提。
- 平台备份任务 `shengda-backup` 不含本模块；本模块快照由 `kubepi-backup` 独立负责，**两者备份同在 95 本机同盘**，异地策略属未决项。

## 禁改项（改了会静默出事）

1. **卷必须保持 `external: true`。** 去掉它，`docker compose -p kubepi down -v` 会直接删掉生产库。
2. **`image` 必须是显式版本号 tag，禁止 `latest`。**
3. **不要给容器加 `--privileged`。** 官方文档写了，但实测不需要；加了只扩大攻击面。
4. **禁止两个实例同时打开同一份数据**（bbolt 单文件 + 独占锁）。要用快照做验证就走 `restore-kubepi.sh --verify-only` 的临时卷路径，不要另起常驻实例。
5. 入口端口 `18080` 变更时，须同步三处：本 compose、平台应用表 `system_mgmt_app`（id=16）的 `url`、版本台账 T2/T3。

## 已知行为：重建容器会重置面板运行配置

面板自己的配置文件 `/etc/kubepi/app.yml` 位于**容器可写层**，不在 `kubepi-data` 卷内、也不在快照内。
其中 `jwt.key` 由首次启动随机生成（上游默认为空）。因此：

- **升级镜像或重建容器后，`jwt.key` 会变，所有已登录会话失效，需要重新登录。属预期行为，不是故障。**
- 数据本身（集群导入、账号）在卷里，不受影响。

**红线（触发条件）**：一旦需要修改 `app.yml` 里任何一个值（`ssl.enable`/`certificate`、`session.expires`、`db.path`），
**同一次变更内必须一并把 `app.yml` 挂载出来持久化 + 进本目录 + 纳入备份脚本**；否则该修改会在下次容器重建时被镜像默认值静默覆盖。
此红线与平台侧坑册中"`install.run` 重跑会静默重写 `.env`"属同一类故障模式：改了但不落持久层 = 下次重建即丢失。

## 版本与变更去哪里看

`bk-lite/docs/kubepi/版本与变更台账.md`（上游锚点 / 镜像台账 / 数据配置台账 / 变更台账）。
设计取舍与否决理由在 `bk-lite/盛大运维系统_集群管控集成方案.md`（决策存档，事实部分已迁至台账）。
````

- [x] **Step 3: 校验（三个词必须都能检索到，且不含密钥）**

Run:
```powershell
Select-String -Path bk-lite\ops\kubepi\README.md -Pattern 'external: true','唯一权威','触发条件' | ForEach-Object { "L$($_.LineNumber) OK" }
Get-ChildItem bk-lite\ops\kubepi -File | Select-String -Pattern 'jwt\.key: *[A-Za-z0-9]{8,}'
```
Expected: 第一组三行 `OK`；第二组**无命中**（严禁把真实密钥值或其片段写进文档；模式本身只包字段名，不含任何真实值）。

- [ ] **Step 4: Commit（需用户已批准提交，否则跳过）**

```bash
git add ops/kubepi/README.md
git commit -m "docs: ops/kubepi 目录说明（同步方向、禁改项、app.yml 重建即失效的红线）"
```

---

### Task 5: 版本与变更台账（T1–T4）

**Files:**
- Create: `d:\Code\bk-lite\docs\kubepi\版本与变更台账.md`（目录不存在时先 `New-Item -ItemType Directory -Force bk-lite\docs\kubepi`）

**Interfaces:**
- Consumes: 本计划开头「已实测事实」表的全部值
- Produces: M3/M4 文档引用的版本事实来源；spec §7 验收判据 #5 的被检对象

- [x] **Step 1: 失败测试**

Run: `Test-Path "bk-lite\docs\kubepi\版本与变更台账.md"` → Expected `False`

- [x] **Step 2: 写台账（全文如下，日期与值一律照抄，不得四舍五入 digest）**

```markdown
# 盛大运维系统 · 集群管理模块 版本与变更台账

> 模块对外名称：集群管理（平台应用宫格显示名）。实现为第三方 K8s 图形面板，本模块**无平台代码改动**。
> 本文件是"事实"的唯一权威；选型与否决理由见《盛大运维系统_集群管控集成方案.md》。
> 含内网地址，仅限内部，外发需脱敏。

## T1 上游锚点（不 fork、不改码，仅记锚点）

| 项 | 值 |
|---|---|
| 上游仓库 | `github.com/1Panel-dev/KubePi`（默认分支 `master`，首页 `kubepi.org`，语言 Go） |
| 在用版本 | `v2.0.3` |
| tag 指向 commit | `e183085da6e5b74dd17a44a3a6812cbe6dacc652`（轻量标签，直指 commit，无 peel 对象） |
| 上游发布时间 | 2026-08-18（与仓库 `pushed_at` 一致） |
| 官方支持的 K8s 区间 | 最低 `v1.24`；推荐 `v1.34`–`v1.36`（集成方案 F7 已核实；**下次升级前重新核对官网**） |
| 源码级结论的取证锚点 | 集成方案 F15（`internal/service/v1/ldap/ldap.go` 具体行号）取证于 v2.0.3，即上列 commit。**上游一变，这些行号全部失效** |

## T2 镜像台账

| 项 | 值 |
|---|---|
| 在用镜像 | `1panel/kubepi:v2.0.3` |
| digest | `sha256:9d096b224bf45fe97f510c77913a8ed31c28f7bfe9b59d320b70c2b74eeeb020` |
| 本地 image ID | `9d096b224bf4` · 569 MB |
| 拉取源 | `hub.rat.dev/1panel/kubepi:v2.0.3`（95 实测唯一可用；`docker.io` 不可达，`docker.m.daocloud.io` 已白名单化拒绝该镜像） |
| 是否已 retag 进公司仓库 | **否**（2026-11-06 实测：`registry.cn-zhangjiakou.aliyuncs.com/shengda/` 下无任何 kubepi tag）→ 见待办 M1-1 |
| 部署日期 / 主机 | 2026-11-05 · `10.10.2.95`（主机名 ops），目录 `/opt/kubepi` |
| 运行参数 | `restart: unless-stopped`、非 privileged、`0.0.0.0:18080->80/tcp`（含 IPv6）、唯一挂载 `kubepi-data:/var/lib/kubepi` |
| 数据 | 命名卷 `kubepi-data`（`external: true`）→ `/var/lib/docker/volumes/kubepi-data/_data`；面板配置 `/etc/kubepi/app.yml` **不在卷内、不在快照内**（行为见 `ops/kubepi/README.md`） |
| 入口 | `http://10.10.2.95:18080/kubepi` → 200 · `ssl.enable: false`（明文 HTTP，已知情接受） |
| 回滚点 | **无上一版可回滚**（v2.0.3 是首个生产版本）。回退方式 = 回到第三方入口 + `kubectl` |
| 备份 | `/etc/cron.d/kubepi-backup` `40 2 * * *` → `/opt/kubepi/backup/<时间戳>/`，`latest` 软链，保留 14 天，日志 `/var/log/kubepi_backup.log`；最近成功 2026-11-06 02:40，产物 24 K |

## T3 数据配置台账（平台 `system_mgmt_app`）

本模块在平台侧的唯一变更是在「系统管理 → 应用管理」新增一条外部应用记录，**属数据配置，不是代码改动**，因此不在《二开改动归档》而在本表登记。

当前值（2026-11-06 只读 SELECT 实测）：

| 字段 | 值 |
|---|---|
| `id` | 16 |
| `name` | `kubepi`（此值即 `Role.app`，是授权挂钩） |
| `display_name` | 集群管理 |
| `description` / `description_cn` | 空 |
| `icon` | `ks1` |
| `url` | `http://10.10.2.95:18080/kubepi` |
| `is_build_in` | **`f`（false）** |
| `tags` | `["集群管理"]` |

随该应用自动生成的角色：`system_mgmt_role` `id=49 · name=user · app=kubepi`。

**两条必须知道的操作事实**

1. **改 `url` 是两步活。** 回表刷新的白名单只捞 `is_build_in=True` 的应用（源码 `server/apps/console_mgmt/viewsets/user_app_set.py:100`），本行是 `false` → 改 App 表后**已有用户的应用快照不会刷新**。用户应用快照存在 `console_mgmt_user_app_set.app_config_list`（内嵌完整 app 对象含 url），实测当前仅 1 行（`admin`）。**因此：改地址 = 改 `system_mgmt_app.url` + 重建相关用户的应用快照。**
2. **界面上可以删除。** `AppViewSet.destroy` 只对 `is_build_in=True` 拒删；本行是 `false` → 走界面删除即可，无需先改标记（《集群管控集成方案》附录 F 相反表述已订正）。

回滚（兜底 SQL，仅在界面操作不可用时使用；执行前须先 `pg_dump` 该表并等用户确认）：

```sql
BEGIN;
DELETE FROM system_mgmt_role WHERE app='kubepi';   -- 当前仅 id=49
DELETE FROM system_mgmt_app  WHERE id=16;          -- name=kubepi
COMMIT;
-- 注意：删除 App 行不会自动剔除 console_mgmt_user_app_set 里各用户的应用快照，
--       残留项仍会在宫格显示并 404，需一并清理（参见平台坑册第 9 条）。
```

## T4 变更台账

| 日期 | 变更 | 执行人 | 影响 | 回滚点 |
|---|---|---|---|---|
| 2026-11-04 | 在 91 构建机起 v2.0.3 做 POC，端口 18080，`./data` 持久化 | 运维 | 仅 91，无生产影响 | — |
| 2026-11-05 | 迁至 95 生产：`/opt/kubepi` + 命名卷 `kubepi-data`（`external: true`），冷拷贝经三处 md5 全等校验；启动日志 `current db version: 3` | 运维 | 生产入口生效，容器数 18→19 | 镜像按 tag 删除即可卸载 |
| 2026-11-05 | 前置反代容器评估后**拆除**，回到单容器直连 18080 明文 | 运维 | 少 1 容器（19MiB）、少 2 份配置；失去 TLS | 理由与代价见集成方案 6.1（**其第一条论证已于 11-06 作废，见 T3 事实 1**） |
| 2026-11-05 | 91 试用实例彻底删除（容器/卷/网络/镜像/目录；按标签删镜像，未执行 prune） | 运维 | 消除 bbolt 双实例同开风险 | 不可逆，且无必要 |
| 2026-11-05 | 备份闭环建立：`/etc/cron.d/kubepi-backup` + `backup-kubepi.sh`，保留 14 天，并做还原性校验（临时卷与生产库 md5 全等） | 运维 | 快照仅存 95 本机同盘 | — |
| 日期待考证（首次可观测：2026-11-06 取证） | 平台「应用管理」新增外部应用 `id=16 · 集群管理`（`is_build_in=false`） | 运维 | 宫格出现入口；仅影响应用宫格 | 见 T3 兜底 SQL |
| 2026-11-06 | 本模块资产落仓：`ops/kubepi/`（compose/cron/脚本/README）+ 本台账建立 | 运维 | 纯仓库变更，线上零改动 | `git revert` 对应提交 |
| 2026-11-06 | 发现并处理：备份脚本此前**未被 git 跟踪**；《集群管控集成方案》等四份手册同样从未入库 → 本次首次入库 | 运维 | 纯仓库变更；之前仅存于本地磁盘 | `git revert` 对应提交 |

## 待办（本模块）

| # | 项 | 判据 |
|---|---|---|
| M1-1 | 把 `1panel/kubepi:v2.0.3` retag 推入公司仓库，形成内部源 | `docker pull registry.cn-zhangjiakou.aliyuncs.com/shengda/kubepi:v2.0.3` 成功且 digest 与 T2 一致；否则镜像源白名单化收紧时 95 无法重装 |
| M1-2 | 首次登录确认默认口令已改 | 面板管理员账号非出厂口令（集成方案 P0 未勾项） |
| M1-3 | 快照异地保存策略（当前只在本机 `/opt/kubepi/backup`） | 与既有备份/Resilio Sync 异地策略对齐后定 |
| M1-4 | 面板内容清单（导入的集群、面板账号）导出入仓 | 需从快照在隔离容器只读导出 bbolt，属 `create` 操作，须单独授权（spec §4.2 / M2） |
| M1-5 | `bk-lite-master/` 仍有 **17,822 条索引项**与 `.gitignore` 冲突（提交 `edc98a28` 声称已解除跟踪但未生效），致 `git status` 长期数千 M/D、`commit -a` 极危险 | 属仓库治理专项，**不在本模块范围**：单独批次 `git rm -r --cached bk-lite-master`，验证 `git ls-files bk-lite-master/` 输出为空；做完再更新 AI_HANDOVER §3 的“已解除跟踪”表述 |
```

- [x] **Step 3: 校验台账与线上实况一致（spec §7 判据 #5）**

Run:
```powershell
ssh root@10.10.2.95 "docker inspect --type image 1panel/kubepi:v2.0.3 --format '{{.RepoDigests}}'; docker ps -q | wc -l"
ssh root@10.10.2.95 "docker exec postgres psql -U postgres -d bklite -A -F'|' -c \"select id,name,display_name,url,is_build_in,tags from system_mgmt_app where id=16;\""
```
Expected: digest 输出 `1panel/kubepi@sha256:9d096b224bf45fe97f510c77913a8ed31c28f7bfe9b59d320b70c2b74eeeb020`，逐字符等于 T2；`19`；App 行六列逐字段等于 T3 表值（尤其 `is_build_in` 必须仍为 `f`）。

- [x] **Step 4: 占位符与已知错串扫描**

Run:
```powershell
Select-String -Path "bk-lite\docs\kubepi\版本与变更台账.md" -Pattern 'TBD|TODO|待填|xxxx|\?\?|—待'
Select-String -Path "bk-lite\docs\kubepi\版本与变更台账.md" -Pattern '日期待考证'
```
Expected: 第一条**无命中**（不得残留占位符）。第二条命中 **1 处**且必须保留——那是 T4 中外部应用录入日期，因无可靠取证来源而**故意不填具体日期**（伪造日期比留空更危险）；若执行者能面板操作日志或 `system_mgmt_app` 的创建时间字段拿到确切日期，用真实值替换该格。

- [ ] **Step 5: Commit（需用户已批准提交，否则跳过）**

```bash
git add "docs/kubepi/版本与变更台账.md"
git commit -m "docs: 建立集群管理模块版本与变更台账（上游锚点/镜像/数据配置/变更史，值取自 11-06 只读实测）"
```

---

### Task 6: AI_HANDOVER 索引与路径登记

**Files:**
- Modify: `bk-lite/AI_HANDOVER.md:106-112`（§9 表格追加 2 行）
- Modify: `bk-lite/AI_HANDOVER.md:33-42`（§3 仓库与路径表）

**Interfaces:**
- Consumes: Task 1–5 的产出路径
- Produces: spec §7 验收判据 #3（M1 部分）；下一会话接手的导航入口

- [x] **Step 1: 失败测试——确认台账与集成方案当前都无索引**

Run:
```powershell
Select-String -Path bk-lite\AI_HANDOVER.md -Pattern '集群管控集成方案|版本与变更台账|kubepi'
```
Expected: **无命中**（这正是 spec §5.4 指出的"新文档写了也没人找得到"）。

- [x] **Step 2: 在 §9 表格末尾追加 2 行**

定位 §9 表格最后一行（当前为 `` | Agent 长期记忆 | `c:\Users\Administrator\.trae-cn\memory\...` ``），在其**之前**插入两行（保持"导航类"排在"记忆类"之前）：

```markdown
| 集群图形化管理（外挂模块）设计取舍与否决理由 | `盛大运维系统_集群管控集成方案.md`（**决策存档**；事实已迁至台账，Provider 方案未实施） |
| 集群管理模块的版本·镜像·数据配置·变更史 | `docs/kubepi/版本与变更台账.md`（**事实唯一权威**；可执行资产在 `ops/kubepi/`） |
```

- [x] **Step 3: 在 §3「仓库与路径」表后补一行说明，并在 §7 待办补一条**

在 §3 表下 `- 运行态：基线目录 ...` 那条之后追加：

```markdown
- 外挂模块「集群管理」的部署资产在 `ops/kubepi/`（compose / 备份 cron / 还原脚本），其线上位置 `/opt/kubepi` 与 `/opt/bk-lite` 完全隔离，平台安装器与 `apply-state.sh` 碰不到它；同步方向以仓库为准，见该目录 README。
```

再在 §7 待办列表末尾追加一条（源自计划级发现 P2）：

```markdown
- [ ] 【仓库治理·高优先】`bk-lite-master/` 仍有 17,822 条索引项与 `.gitignore` 冲突（10-19 的 `edc98a28` 声称已解除跟踪但未生效）：`git status` 长期数千 M/D，**任何 `git commit -a` 都会卷进 1.7 万个 vendored 文件**（与坑册第 1 条同族）。修法：单独批次 `git rm -r --cached bk-lite-master` 后验证 `git ls-files bk-lite-master/` 为空；做完回改本节§3 的“已解除跟踪”描述
```

- [x] **Step 4: 校验**

Run:
```powershell
Select-String -Path bk-lite\AI_HANDOVER.md -Pattern '集群管控集成方案|docs/kubepi/版本与变更台账|ops/kubepi/'
```
Expected: 命中 **4 处**（Step 2 两行 + Step 3 的两段各 1 行）。再校验表格结构未被破坏：

```powershell
(Select-String -Path bk-lite\AI_HANDOVER.md -Pattern '^\| ').Count
```
Expected: 与改动前相比 **+2**（仅 §9 表格新增两行；Step 3 追加的是 `- ` 开头的列表行，不计入表格）。若为 +3 说明 Step 3 误写成了表格行，需改回列表。

- [ ] **Step 5: Commit（需用户已批准提交，否则跳过）**

```bash
git add AI_HANDOVER.md
git commit -m "docs: AI_HANDOVER §9 索引集群管理模块两份产物 + §3 登记 ops/kubepi 资产位置"
```

---

### Task 7: M1 批次验收与临时文件收尾

**Files:**
- Delete（本地临时，gitignored）: `d:\Code\.tmp-kubepi\backup-kubepi.sh`、`d:\Code\.tmp-kubepi\backup-kubepi.lf.sh`

**Interfaces:**
- Consumes: Task 1–6 全部产出
- Produces: spec §6 M1 行的"完成判据"证据；M3 的输入

- [x] **Step 1: 跑 M1 的三条验收判据**

Run（在 `d:\Code`）:
```powershell
# 判据一：仓库覆盖
git -C bk-lite ls-files ops/kubepi/
git -C bk-lite ls-files ops/bk-lite/
git -C bk-lite ls-files "ops/*.sh"
# 判据二：compose 与线上零差异（重新取一份线上原文比对）
scp root@10.10.2.95:/opt/kubepi/docker-compose.yml $env:TEMP\check-compose.yml
git -C bk-lite diff --no-index --ignore-space-at-eol $env:TEMP\check-compose.yml bk-lite\ops\kubepi\docker-compose.yml; echo "diff_rc=$LASTEXITCODE"
# 判据三：无密钥泄漏
Get-ChildItem bk-lite\ops -Recurse -File | Select-String -Pattern 'jwt\.key: *[A-Za-z0-9]{8,}'
Select-String -Path "bk-lite\docs\kubepi\版本与变更台账.md" -Pattern 'jwt\.key: *[A-Za-z0-9]{8,}'
```
Expected: 判据一第一个命令返回 **5 个文件**（`docker-compose.yml`、`backup-kubepi.sh`、`cron.d-kubepi-backup`、`restore-kubepi.sh`、`README.md`）；第二个返回 **5 个文件**（4 脚本 + `README.md`）；第三个（直接位于 `ops/` 根的 .sh）**必须为空**；判据二 `diff_rc=0`；判据三**无命中**。

- [x] **Step 2: 线上零改动复核**

Run:
```powershell
ssh root@10.10.2.95 "docker ps -q | wc -l; docker volume ls | grep -c restore-test; ls /opt/kubepi; md5sum /opt/kubepi/backup-kubepi.sh /opt/kubepi/docker-compose.yml"
```
Expected: `19` / `0` / 目录仍只有 `backup  backup-kubepi.sh  docker-compose.yml` / `backup-kubepi.sh` md5 仍为 `4edf74bd1f2b5c429b7b7b87d1847a71`。任何不符说明本批误改了线上，须立即定位并回退。

- [x] **Step 3: 删除已验证一致的临时副本**

`.tmp-kubepi/backup-kubepi.sh` 与 `.tmp-kubepi/backup-kubepi.lf.sh` 的 md5 与仓内文件全等（Task 2 Step 4 已验），属可安全丢弃的重复副本：

```powershell
Remove-Item .tmp-kubepi\backup-kubepi.sh, .tmp-kubepi\backup-kubepi.lf.sh
```
Expected: 两文件不存在。**只删这两个**，`.tmp-kubepi/` 其余文件的取舍属 spec §3.4 的完整三分类，留到 M5 一次性做，本批不扩大范围。

- [ ] **Step 4: 汇报并确认是否提交**

输出：判据一/二/三结果、Step 2 线上复核结果、已新增与已移动的文件清单。
若用户尚未批准提交，此处询问是否执行 Task 1–6 的 commit 步骤（`git log --oneline` 应出现 6 条以内、按任务分粒度的提交）。

---

## Self-Review（本计划对 spec 的覆盖检查，已执行）

**1. Spec coverage（M1 范围）**

| spec 条目 | 对应任务 |
|---|---|
| §3 目录规范（本批新增，用户指令） | **T0**（建 `ops/<service>/` 布局、两份 README、15 处引用订正） |
| §3 目录 5 个文件 | T1（compose、cron）T2（backup 移位）T3（restore）T4（README） |
| §3.2 移位连带动作 | T2 Step 3–4（并澄清运维手册 §七无坏引用，新增归 M3） |
| §3.3 cron 安装命令注释 | T1 Step 3 |
| §3.4 三分类 | **部分**：本批只处理 md5 已验证一致的两个副本（T7 Step 3）；完整三分类留 M5，避免 M1 夹带不可逆删除 |
| §3.5 上游锚点 | T5（T1 表） |
| §4 T1–T4 四张表 | T5 |
| §4.1 两条操作事实 | T5 T3 节 |
| §4.2 面板内容清单 | **不覆盖**（M2，需单独授权），已在 T5 待办 M1-4 挂指针 |
| §5.4 AI_HANDOVER §9 + §3 | T6（§9 按澄清只加 2 行；§6 坑册与 §7 待办留 M3） |
| §6 M1 行完成判据 | T7 Step 1 |

**2. Placeholder scan**：已逐任务扫描，无 TBD/待填/引用不存在符号类占位。两类看似占位、实为故意的东西必须保留：（a）台账 T4 的「日期待考证」格——无可靠取证来源，伪造日期比留空危险，Task 5 Step 4 会验证它刚好命中 1 处；（b）各 Expected 里的具体值——它们是**真实测值**（digest / md5 / 容器数 / 表字段），不是占位。自审过程中已删除三处不合格的占位命令（本地无 docker 的 exec 行、无操作的 `tr < /dev/null` 行、Select-String 不存在的 `-Recurse` 参数），并删除了一处**会泄密**的扫描模式（它把真实 jwt key 的前缀当关键词写了进去）。

**3. 一致性**：`4edf74bd1f2b5c429b7b7b87d1847a71`（Task 2 Step 4 / Task 7 Step 2）、`sha256:9d096b22…`（事实表 / T2 / Task 5 Step 3 / Task 7 判据二）、`e183085da6e5b74dd17a44a3a6812cbe6dacc652`（T1）、`ops/kubepi/` 五文件（Task 1–7 与 Task 7 判据一）、容器数 `19`（Task 3 Step 5 / Task 5 Step 3 / Task 7 Step 2）在各任务间逐字一致。Task 3 脚本里的 `$TMPVOL` / `$VOL` / `$CNAME` / `$IMG` 变量名与 Step 4 的 dry-run 断言互相对应；`--dry-run` 下不得出现 `EXEC:` 这条判据同时覆盖 Step 4 两个模式。

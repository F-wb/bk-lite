# 盛大运维系统 AI 模块规划

> **文档用途**：规划运维平台 **AI 模块**（模块标识 `opspilot`）的定位、能力范围、启用路线与实施方案。
> **文档性质**：⚠️ **规划文档** —— 当前部署**不改造**，本文是面向**后续二开版本**的技术储备与实施依据，不是当前的执行任务。
> **读者**：产品 / 架构 / 运维 / 交付
> **版本日期**：v1.0 · 2026-10-16
> **配套文档**：`盛大运维系统_部署手册.md`（部署模型与镜像覆盖层）、`盛大运维系统_二开改动归档.md`（二开改动清单与台账）、`盛大运维系统_运维手册.md`（日常运维与备份还原）

> ℹ️ 说明：本规划中的目录、仓库地址等字面量与本项目实际部署一致；如需对外分发，请将内网地址（`/opt/bk-lite`、镜像仓库地址、`192.168.1.11`）替换为内部约定值。

---

## 一、结论速览

| 项 | 结论 |
|---|---|
| 当前是否需要改造 | **否**。本文为后续版本规划，当前部署保持基础版不变 |
| AI 模块是否已存在 | 模块代码与前端页面**已随镜像交付**、App 记录在册，仅未启用（前端隐藏 + 后端未纳入 `INSTALL_APPS`） |
| 启用是否与二开冲突 | **零冲突**。二开 30 个改动文件不触及 AI 模块代码 |
| 启用是否可行 | **可行且已核验**：机器侧前置条件 **15/16 通过**，唯一未通过项即"需重建镜像"，属预期 |
| 推荐启用方式 | **零分叉**：弃用精简构建文件，直接用官方 `Dockerfile` 重建后端镜像 |
| 是否依赖 GPU | **不需要**。对接已有模型服务即可，无需部署本地推理服务 |

---

## 二、模块定位与能力

### 2.1 定位

AI 模块是运维平台的**智能化增强层**，独立于核心业务模块（CMDB / 监控 / 告警 / 作业 / 日志 / 补丁等）存在，以旁路方式为平台提供智能能力，**不改变现有模块的运行方式**。

### 2.2 能力范围

依据模块代码的依赖构成（`langchain` / `langgraph` / `browser_use` / `pymupdf` / 向量库 `metis`）判断，其基础能力包括：

| 能力 | 技术依据 |
|---|---|
| 大模型对话与任务编排 | `langchain` / `langgraph` |
| 知识库检索增强（RAG） | 向量库 `metis`（`pgvector`，`vector` 扩展 0.8.1 可用） |
| 文档解析与内容抽取 | `pymupdf`、图像识别相关依赖 |
| 浏览器自动化（智能体执行网页操作） | `browser_use` + `patchright` / Chromium |
| 模型服务管理（供应商配置） | 应用内配置 `vendor` / `api_key` / `base_url` / 模型名 |

> 具体功能菜单与交互以启用后的界面为准；本节依据代码依赖推断，未做功能级验证。

### 2.3 与平台的关系

- AI 模块**独立部署单元**：启用后新增 1 个编排服务（`mlflow`），容器数由 **18 → 20**
- 后端需扩展 Python 依赖（`opspilot` / `mlops` extras），前端页面已在内（无需重建前端）
- 与二开功能（品牌定制、钉钉登录、堡垒机 SSH 终端）**无耦合、无冲突**

---

## 三、当前状态与差距

### 3.1 现状（2026-10-16 实测）

| 项 | 状态 |
|---|---|
| 模块启用状态 | **未启用**（一期排除；模块保留在系统中，由前端「应用管理」控制显示） |
| App 表记录 | 已含 `opspilot` / `mlops` / `workflow-orchestration` —— 启用后可直接放显 |
| 容器数 | 18 个（不含 AI 相关服务） |
| 向量库 | `pgvector` 容器运行中，`metis` 库已建但为空（0 张表）；`vector` 扩展**可用**（实测可 `CREATE EXTENSION`） |
| 后端依赖 | ❌ **缺失**（见 3.2） |
| `INSTALL_APPS` | 不含 `opspilot` / `mlops` |

### 3.2 唯一硬差距：后端镜像缺 AI 依赖

本项目构建文件当初为**瘦身**把依赖裁至 `.[cmdb,dev]`，而官方为 `.[cmdb,dev,mlops,opspilot]`。**运行镜像内实测**：

```
MISS: langchain, langgraph, langchain_openai, browser_use, pymupdf, mlflow
```

> **结论**：启用前**必须重建后端镜像**；仅修改配置（`INSTALL_APPS`）会导致后端容器启动即 `ModuleNotFoundError` 崩溃。

---

## 四、规划路线

| 阶段 | 内容 | 前置 / 触发条件 | 状态 |
|---|---|---|---|
| **P0 基础版** | 现状运行，AI 模块隐藏 | — | ✅ 当前 |
| **P1 技术储备** | 可行性评估、前置条件核验、方案定稿 | — | ✅ **已完成（本文档）** |
| **P2 模型服务对接准备** | 确定已有模型服务的 `base_url` / `api_key` / 模型名；确认服务器到该服务的网络连通；确认 Embedding / Rerank 是否复用已有服务 | **业务侧决策** | ⏳ 待启动 |
| **P3 实施启用** | 重建镜像 → 启用组件 → 覆盖校验 → 界面配置 | P2 完成 + 择期停机窗口 | ⏳ 待启动 |
| **P4 投产与固化** | 模型效果调优、权限与配额、纳入运维台账 | P3 验收通过 | ⏳ 待启动 |

> **P3 属重负载操作**（需停机构建、镜像体积显著增大），必须择期在停机窗口执行，不可在线热切。

---

## 五、启用实施方案（P3 执行细则）

### 5.1 总体思路：零分叉启用

「启用 AI 模块」「追溯上游版本」「二开不冲突」三者不矛盾，且可由**同一个动作**同时满足：

> **弃用精简构建文件，直接用官方 `Dockerfile` 原件构建后端镜像。**

理由：本项目当初裁剪依赖纯为瘦身，而 AI 模块所需的正是官方默认的 `.[cmdb,dev,mlops,opspilot]`；回归官方原件后依赖自动对齐，且上游今后对 `Dockerfile` 的任何改动都会**自动继承**。

**关键洞察**：本项目精简构建文件是官方 `Dockerfile` 的**拷贝分支**，二者仅 2 处差异：

| 行 | 官方 `Dockerfile` | 本项目精简版 |
|---|---|---|
| 26 | `pip3 install -e ".[cmdb,dev,mlops,opspilot]"` | `.[cmdb,dev]` |
| 31-32 | tiktoken 词表预热 | 跳过 |

由于是**拷贝而非引用**，上游改动永远不会流入该文件 → 长期静默漂移。**它本身就是「追溯上游版本」的障碍。**

### 5.2 Phase 1｜构建

```bash
# 1) 构建前标准动作：停业务容器 + 清无用镜像（本机内存/磁盘偏紧，必须停容器）
cd /opt/bk-lite && docker compose stop
docker image prune -f

# 2) 用官方 Dockerfile 构建（关键：不再使用 .local 精简文件）
cd /opt/bk-lite-src/server
docker buildx build --provenance=false \
  --build-arg NEXUS_PYTHON_REPOSITY=https://mirrors.aliyun.com/pypi/simple/ \
  -f support-files/release/Dockerfile \
  -t <本项目ACR>:server -t <本项目ACR>:server-<日期+序号> \
  --push . > /tmp/server-build.log 2>&1 &

# 3) 恢复服务
cd /opt/bk-lite && docker compose up -d
```

- 依赖自动为 `.[cmdb,dev,mlops,opspilot]`，**无需改动任何文件**
- **层数基准会变**（不再是 29）→ 需用层数比对法重新记录
- 镜像体积与构建时间显著上升（见第七章）

### 5.3 Phase 2｜基线补启用（保留数据，不重装）

```bash
# 1) 先留底
bash /opt/bk-lite/scripts/backup-all.sh

# 2) 补启用组件（组合开关 = AI 模块 + MLOps + MLflow，不含本地推理）
cd /opt/bk-lite && bash bootstrap.sh --opspilot

# 3) 【关键】立刻重跑镜像覆盖，否则 .env 中的 ACR 指向被静默重置
bash /opt/bk-lite/deploy/overlay-images.sh

# 4) 重建前后端容器
cd /opt/bk-lite && docker compose up -d --force-recreate server web
```

**校验项**：

| 项 | 期望 |
|---|---|
| 容器数 | 18 → **20**（新增 `mlflow`；未开本地推理时不含 GPU 服务） |
| `INSTALL_APPS` | 含 `opspilot`、`mlops` |
| 前后端镜像 | 仍指向本项目 ACR（`docker ps --filter name=server --format '{{.Image}}'`） |
| `mlflow` 库 | 由脚本自动 `CREATE DATABASE`（无需手工建库） |
| `metis` 库 | 出现模块相关表（迁移已执行）、`vector` 扩展已创建 |
| 后端启动日志 | 无 `ModuleNotFoundError` |

### 5.4 Phase 3｜配置与固化

1. 在 AI 模块界面配置已有模型服务：`vendor` / `api_key` / `base_url` / 模型名；按所用功能另配 **Embedding、Rerank**（均指向已有服务，**不需要本地推理、不需要 GPU**）
2. 前端「应用管理」放显 AI 模块
3. 更新台账：镜像 tag、**新的层数基准**、基线组件状态（基础版 → AI 版）
4. 上游月度跟进流程（见归档 §8.8）**不变**，且因无分叉而不再需要人工比对构建文件

---

## 六、前置条件核验结果（2026-10-16 实测：15 通过 / 1 待修复 / 22 项）

**A. 构建侧**

| # | 检查项 | 结果 |
|---|---|---|
| A1 | `docker buildx` 可用 | ✅ |
| A2 | 官方 `Dockerfile` 存在，L26 = `.[cmdb,dev,mlops,opspilot]` | ✅ |
| A3 | `pyproject.toml` 已定义 `opspilot` / `mlops` extras | ✅ |
| A4 | 官方基础镜像本地存在（digest `59b76c918de0`，13 层，完整） | ✅ |
| A5 | 基础镜像自带**可执行** Chromium（浏览器自动化依赖） | ✅ |
| A6 | tiktoken 预热源可达（`openaipublic.blob.core.windows.net` 返回 HTTP 200） | ✅ |
| A7 | `mlflow` 镜像（官方基线镜像站）可拉取 | ✅ |

**B. 基线补启用侧**

| # | 检查项 | 结果 |
|---|---|---|
| B1 | `bootstrap.sh` 支持 `--opspilot`（组合开关 = AI 模块 + MLOps + MLflow） | ✅ |
| B2 | `/opt/bk-lite/.env` 存在 | ✅ |
| B3 | `.env` 含 `DOCKER_IMAGE_SERVER` / `DOCKER_IMAGE_WEB` | ✅ |
| B4 | `/opt/bk-lite/deploy/overlay-images.sh` 就位且可执行 | ✅ |
| B5 | 编排内含 `mlflow` 定义（`compose/mlflow.yaml`） | ✅ |
| B6 | `bootstrap.sh` 在 `MLFLOW_ENABLED=true` 时自动 `CREATE DATABASE mlflow` | ✅（无需手工建库） |

**C. 运行时侧**

| # | 检查项 | 结果 |
|---|---|---|
| C1 | 18 个容器运行中 | ✅ |
| C2 | 后端镜像含全部 AI 依赖 | ❌ **缺 `langchain`/`langgraph`/`langchain_openai`/`browser_use`/`pymupdf`/`mlflow`** ← 唯一未通过项，由 Phase 1 重建镜像解决 |
| C3 | `postgres` 可达（`mlflow` 库尚未建，补启用时创建） | ✅ |
| C4 | `pgvector` 容器可达，`metis` 库存在 | ✅ |
| C5 | `metis` 内 `vector` 扩展**可用**（0.8.1，实测可建、已回滚不留痕） | ✅ |
| C6 | App 表已含 `opspilot` / `mlops` / `workflow-orchestration` 记录 | ✅ |

**D. 资源与源码**

| # | 检查项 | 结果 |
|---|---|---|
| D1 | 源码分支 `shengda/v1.0-custom` @ `6e0be26b9e`，工作区干净（0 个改动） | ✅ |
| D2 | 磁盘可用 29G / 内存可用 2.7G（停容器后可释放至约 5.7G）/ load 0.03 | ⚠️ 够用但偏紧，构建前**必须停容器** |
| D3 | 当前 `INSTALL_APPS` 不含 `opspilot` / `mlops` | ℹ️ 预期 |

> **核验结论**：**机器侧前置条件全部具备**，唯一未通过项 C2 恰是 Phase 1 要解决的问题。
> **待人工补充（无法代验）**：已有模型服务的 `base_url` + `api_key`，以及**从本服务器到该服务的网络连通性**。

---

## 七、代价与风险

| 项 | 说明 |
|---|---|
| 构建负载 | 依赖含 `langchain`/`langgraph`/`pymupdf`/图像识别/`browser_use`/`scikit-learn`/`tsfresh`/`hyperopt`/`numba`/`mlflow` → 构建时间与镜像体积**显著上升**；本机 7.2G 内存、磁盘剩 29G，**必须停容器后构建** |
| 新增服务 | `mlflow`（官方基线镜像站的镜像，**须能访问该镜像站**；本环境已验可达） |
| 内存占用 | 容器数 18 → 20，常驻内存上升，需观察是否触发 swap |
| 数据安全 | Phase 2 采用「补启用」而非重装，数据保留；仍建议先执行 `backup-all.sh` 留底 |
| **静默失效风险** | `bootstrap.sh --opspilot` 会**重写 `.env`**，把前后端镜像指向重置回基线地址 → **5.3 第 3 步（重跑覆盖脚本）是唯一会让二开整体消失的环节，务必执行** |
| 回滚 | 前后端用上一版版本化 tag + `--force-recreate`；基线组件状态可用不带开关的 `bootstrap.sh` 回退 |
| 权限与配额 | 启用后需评估 AI 模块的菜单权限归属与模型调用配额，避免非授权账号滥用 |

---

## 八、待决事项（P2 阶段需业务方确认）

1. **模型服务**：确定已有模型服务的 `base_url`、`api_key`、模型名（如为 OpenAI 兼容端点，可直接对接）
2. **网络连通**：确认从 `192.168.1.11` 到该模型服务地址的网络可达性
3. **Embedding / Rerank**：知识库功能需要 embedding 与 rerank 模型，确认是复用已有服务还是另行提供
4. **启用范围**：只启用 AI 模块，还是连同 MLOps + MLflow 一起（官方组合开关为三者同启；只启 AI 模块需保留一个构建分叉，**不推荐**）
5. **停机窗口**：P3 需停机构建，确定时间窗

---

## 九、备选方案（不推荐，仅备案）

**只启用 AI 模块、不带 MLOps / MLflow**：依赖用 `.[cmdb,dev,opspilot]`（须保留一个精简构建分叉），手工把 `opspilot` 加入 `INSTALL_APPS`，不启用 `MLFLOW_ENABLED`。

- 优点：省掉 `mlflow` 容器与 `mlops` 依赖，镜像更小、构建更快
- 缺点：与官方路径**分叉**，牺牲「自动追溯上游版本」，后续上游演进需自行跟踪
- **结论**：不推荐

---

## 十、附：当前不改造的理由

1. **一期范围**：AI 模块已明确为一期排除项，模块保留、前端隐藏，二期启用时无需重新引入代码
2. **业务前置未就绪**：模型服务地址、Embedding/Rerank 方案、权限配额等尚未确定（见第八章）
3. **改造成本明确且可控**：机器侧前置已全部核验通过，方案已定稿，将来可直接照第五章执行
4. **无时间压力**：当前基础版功能完整，AI 能力属增强项，可按业务节奏排期

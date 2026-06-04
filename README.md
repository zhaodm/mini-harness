# Mini-Harness - 最小驾驭系统

本项目是一个最小的由Agent驱动的驾驭系统框架。实现从需求到高质量交付的自动化生产。

本项目**主要目的是搭建一个基础Workflow框架**，从需求到交付各子智能体间任务编排清晰，各任务输入输出明确可以校验，后续开发可相互解耦

---

## 1、架构：四层递进防线

四层防线按**约束力由弱到强**递进排列。每一层专门弥补上一层的固有缺陷：

### 第一层：Rules -- 行为约束

**解决问题：** Agent最常犯的低级错误----修改后无基础自检、擅自改动上游制品。

**实现方式：** 1个md文件，约束全局纪律。**一定要精简**。

**固有局限：** Rules本质是自然语言指令，Agent对其的遵守程度随上下文复杂度增加而下降。无法保证100%执行。

### 第二层：Skills -- 标准操作规程

**解决问题：** 具体操作步骤由 Agent 临场发挥，行为发散导致结果的不可预测性提升。

**实现方式：** 5 个 Skill 文件，每个封装一套固定步骤的 SOP（标准操作规程）。所有重复性操作不依赖 Agent 记忆。

**设计原则：** Rule 定义"什么必须做"，Skill 定义"具体怎么做"。二者分离后，Rule 保持简洁，Skill 承载执行细节。

### 第三层：Agents + Workflow -- 角色制衡

**解决问题：** 单一 Agent 自审的结构性失效。写需求的人不应该同时审需求，写代码的人不应该同时做终验。

**实现方式：** 4 个 Agent 角色，每个具有独立的契约定义（输入/输出/阻塞条件/禁止事项），通过固定编排的 Workflow 接力执行。

**固有局限：** 角色和流程仍属于"指令层"约束，Agent 声称"已完成"时缺少独立的客观验证手段。

### 第四层：Scripts + 人工 -- 硬校验

**解决问题：** 前三层仍属于指令层约束，Agent 声称"已完成"时缺少机器化验证。

**实现方式：** 3 个硬校验脚本以退出码作为唯一判据—— verify.sh（A/B/C 三类检查点）、baseline.sh（前后对比）、check-harness.sh（框架自检）。每次交付必须由人工审核通过再进行下一任务。

**设计原则：** 交付判定不依赖 Agent 自述，依赖程序退出码。

### 递进关系，非替代关系

Rule设定约束 --> Skill标准化执行 --> Agent角色制衡 --> Script硬性校验。每一层专门弥补上一层的固有缺口，四层合并形成闭环。



## 2、六个Agent角色

角色拆分源于研发流程中的具体问题，而非预设的组织架构：

#### PM - 项目经理

流程调度中枢。读结论、发任务、处理回退、执行Spec Merge。不参与需求定义、方案设计或技术判断。

#### BA - 需求分析师

将模糊需求转化为SHALL + GWT格式的结构化需求。不参与方案设计或技术判断。

#### SA -- 方案架构师

将结构化需求翻译为技术方案。包含需求-->技术落实对照表、时序图、Tasks清单。

#### DE -- 开发工程师

强制TDD模式：编写测试（FAIL）-->实现代码（PASS）-->重构-->执行dev-test Skill-->执行post-verify Skill。

#### TE -- 测试工程师

交付链的最终验收环节。根据 test_strategy 选择验证方法（E2E/单元/集成/冒烟/人工/工程验证），确保产出物符合需求规格。

#### UX -- 设计师

产出物的视觉/结构设计师。根据 output_type 产出不同设计制品（PPT wireframe / UI 设计 / API 设计文档等）。

#### Agent契约结构

每个Agent定义文件内嵌完整的角色契约：身份-->职责-->输入-->输出-->阻塞条件-->禁止事项-->模型建议。一个文件即一个角色的完整规范，维护不分散。



## 3、研发流程：需求澄清 + 三段式接力 + 人工审批

完整研发流程按触发命令划分为四个分段：clarify（人机协作打磨 Proposal + 产出类型选择）、propose（自动化需求→方案→评审）、apply（自动化开发→审查→测试→待归档）、archive（人工确认触发 Spec Merge + 归档）。

流程设有两道人工审批：SA方案设计和PM任务编排后、TE测试验证PASS后。每个阶段骨架如下：

**/mh-clarify**
`init-task.sh → 人机协作打磨 proposal.md → 消除歧义 + 定稿`

**/mh-propose**
`BA 需求分析 → SA 方案设计 → PM 任务计划编排 → 人工审批 1`

**/mh-apply**
`DE TDD 开发 → TE 审计验证 → 人工审批 2`

**/mh-archive**
`✓ Spec Merge + mv 归档 + board DONE`

---

## 4、产出类型（output_type）

框架支持任意类型的需求开发。在 clarify 阶段通过 output_type 参数指定产出物类型，后续流程自动适配：

| output_type | 说明 | 默认验证策略 |
|-------------|------|-------------|
| web-app | Web 应用（前端/全栈） | E2E / 集成测试 |
| backend-api | 后端服务/API | 集成测试 |
| cli-tool | 命令行工具 | 集成测试 |
| data-pipeline | 数据管道/ETL | 冒烟测试 |
| infrastructure | 基础设施代码（Terraform/K8s） | 冒烟测试 |
| documentation | 文档/规格 | 人工审阅 |
| ppt | 演示文稿/HTML slides | 人工 + verify-ppt.sh |
| library | 库/SDK | 单元测试 |
| custom | 自定义 | 用户指定 |

output_type 与 mode（fast/standard/full）正交：mode 控制流程严谨度，output_type 控制产出物和验证方式。

---

**顺序约束1：**必须按序，前序未完成不得执行后序命令。

**顺序约束2：** 每一小步骤之间都必须由PM进行调度，一个小步骤结束后返回给PM，由PM对输出进行检查，检查通过启动下一步。PM 在执行任何一条调度任务之前，必须打印心跳信息，格式: `[PM] xxx`

**顺序约束3**：整个过程保留完整日志

> **列说明**
>
> - **步骤ID**：workflow YAML 中的 step_id，WE 调度的最小单元
> - **执行角色**：负责完成该步骤的 Agent
> - **上游输入**：该步骤启动前必须通过校验的产出物
> - **交付输出**：该步骤写入 spec 的产出物

---

### /mh-propose

| 步骤ID | 活动名称     | 执行角色 | 上游输入                                                     | 交付输出                                                     |
| ------ | ------------ | -------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| REQ-1  | 需求分析     | BA       | `reference/`<br>`deliverables/{REQ-ID}/proposal.md`                   | `deliverables/{REQ-ID}/ba/requirement-spec.md`                        |
| REQ-2  | 架构设计     | SA       | `deliverables/{REQ-ID}/ba/requirement-spec.md`                        | `deliverables/{REQ-ID}/sa/design.md`                                  |
| REQ-3  | 测试用例设计 | TE       | `deliverables/{REQ-ID}/ba/requirement-spec.md`                        | `deliverables/{REQ-ID}/te/testcases.md`                               |
| REQ-4  | 计划编排     | PM       | `deliverables/{REQ-ID}/sa/`<br>`deliverables/{REQ-ID}/te/`                     | `deliverables/{REQ-ID}/plan-action.md`                                |
| SR1    | **需求评审** | PM       | `deliverables/{REQ-ID}/sa/`<br>`deliverables/{REQ-ID}/te/`<br/>`deliverables/{REQ-ID}/ba/` | `deliverables/{REQ-ID}/SR1-record.md`<br>`deliverables/{REQ-ID}/baselines/*.v1.md` |

---

### /mh-apply

**顺序约束：**TE进行审计，如果发现问题，将审计结果和相关日志返回给PM，PM判断审计失败，再将相关信息发给DE去修复问题，再进行下一轮审计，轮次最大次数限制在5次，如果超过5次必须上升到人工审核。

| 步骤ID | 活动名称     | 执行角色           | 上游输入                                                     | 交付输出                                                     |
| ------ | ------------ | ------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| DEV-1  | 编码实现     | DE                 | `deliverables/{REQ-ID}/sa/design.md`                                  | `deliverables/{REQ-ID}/output/`<br/>`deliverables/{REQ-ID}/de/code-report.md` |
| TEST-1 | 审计验证     | TE                 | `deliverables/{REQ-ID}/output/`                         | `deliverables/{REQ-ID}/te/temp-test-report.md`                        |
| SR2    | **功能评审** | PM（人机交互决策） | `deliverables/{REQ-ID}/output/`<br>`deliverables/{REQ-ID}/te/temp-test-report.md` | `deliverables/{REQ-ID}/SR2-record.md`                                 |
| TEST-2 | 审计验证     | TE                 | `deliverables/{REQ-ID}/output/`                         | `deliverables/{REQ-ID}/te/final-test-report.md`                       |
| SR3    | **功能评审** | PM（人机交互决策） | `deliverables/{REQ-ID}/output/`<br>`deliverables/{REQ-ID}/te/final-test-report.md` | `deliverables/{REQ-ID}/SR3-record.md`                                 |

---

### /mh-archive

| 步骤ID | 活动名称         | 执行角色           | 上游输入                              | 交付输出                   |
| ------ | ---------------- | ------------------ | ------------------------------------- | -------------------------- |
| ARC-1  | 需求归档         | PM                 | `deliverables/{REQ-ID}/ba/requirement-spec.md` | `output/spec/requirement-spec.md` |
| ARC-2  | 设计归档         | PM                 | `deliverables/{REQ-ID}/sa/design.md`           | `output/spec/design.md`           |
| ARC-3  | 代码归档         | PM                 | `deliverables/{REQ-ID}/output/`        | `output/`          |
| ARC-4  | 参考资料归档     | PM                 | `reference/`                           | `output/reference/`       |
| ARC-5  | 执行指标生成     | PM                 | `.state.md`                            | `deliverables/{REQ-ID}/metrics.md` |
| SR4    | **项目结项确认** | PM（人机交互决策） |                                       |                            |

---



## 4、运行环境与使用方式

### 支持平台
- Claude Code CLI（终端）
- VSCode Cline 插件
- VSCode Claude Code 插件对话框

三个平台共享同一套核心逻辑，通过 `CLAUDE.md`（Claude Code）+ `.clinerules`（Cline）实现规则同源，`.mcp.json` 统一 MCP 配置。

### 前置准备

1. **环境要求**：Node.js 18+、npm
2. **准备参考资料**：将需求相关资料放入 `reference/` 目录

### 用户操作步骤

> **推荐：** 直接输入 `/mh-run` 即可启动全流程自动推进，框架会按 clarify → propose → apply → archive 顺序自动衔接，仅在人工审批节点暂停等待确认。适合大多数场景。
>
> 如需手动分步控制，可按以下步骤逐个执行：

**Step 1: 需求初始化与澄清**

在对话框输入：
```
/mh-clarify
```

系统行为：
- 自动检测场景：
  - **NEW**：无历史需求，全新项目
  - **RESUME**：检测到未完成的 REQ，提示用户继续或放弃
  - **CHANGE**：有已完成的历史需求，进入变更模式（自动备份基线）
- NEW/CHANGE 模式：创建新 REQ-ID 目录，进入需求澄清
- 变更模式下仅讨论变更点，不重复已有内容
- PM 逐轮提问（每轮≤3题），生成 Proposal 草稿供确认
- 用户确认通过后，Proposal 定稿

**Step 2: 需求分析与方案设计**

在对话框输入：
```
/mh-propose
```

系统行为：
- BA 执行需求分析，生成结构化需求文档
- SA 执行架构设计，生成技术方案
- TE 设计测试用例
- PM 进行后续任务编排，生成任务列表
- PM 汇总后呈现人工审批（SR1）
- 用户审批通过后进入下一阶段；驳回则回退修改

**Step 3: 开发与审计**

在对话框输入：
```
/mh-apply
```

系统行为：
- 逐任务循环开发（DE 编码 → TE 审计 → 人工检查确认，最多5轮修复）
- 所有开发+审计+人工检查完成后，统一进行 SR2 正式审批
- SR2 通过后 DE 合并到最终产物，TE 最终审计
- 最终审计通过后呈现 SR3 人工审批
- 支持断点续作：中断后重新输入 `/mh-apply` 自动跳过已完成任务

**Step 4: 归档结项**

在对话框输入：
```
/mh-archive
```

系统行为：
- 检测归档模式：
  - **首次归档**（output/spec/ 为空）：直接复制需求、设计、代码到归档目录
  - **变更归档**（output/spec/ 已有文件）：将变更内容 merge 到现有 spec 文件
- 将所有交付产物归档到 output/（含 spec/、reference/、产出物）
- 呈现归档摘要供用户确认结项（SR4）

**查看最终成果**

归档完成后，最终产物位于 `output/` 目录。

### 用户触发方式

用户在对话框中输入斜杠命令触发流程，Agent 自动识别并按对应 Skill 执行：

| 命令 | 触发行为 |
|------|---------|
| `/mh-clarify` | 场景检测（NEW/RESUME/CHANGE）+ 环境预检 + 需求澄清 + 产出类型选择 + 模式选择 |
| `/mh-propose` | 前置检查 → SA需求分析 + 架构设计 → TE测试用例 → PM任务编排 → 人工评审 |
| `/mh-apply` | 前置检查 → DE开发 → TE审计（test_strategy 驱动）→ 逐任务人工检查 → SR2 → SR3 |
| `/mh-archive` | 前置检查 → 产物归档（output_type 感知，首次copy/变更merge）→ 用户确认结项 |
| `/mh-ppt` | output_type=ppt 快捷入口，自动进入主流程 + PPT 补充规则 |
| `/mh-run` | 全流程自动推进（clarify → propose → apply → archive，阶段间自动衔接） |

### 内置工具

| 工具 | 用途 | 调用时机 |
|------|------|---------|
| WebSearch | 联网搜索补充资料 | SA 研究阶段 |
| WebFetch | 网页内容抓取 | 用户提供参考链接时 |
| Read | 图片内容识别 | reference/ 含图片时 |


---

> 全局纪律（流程约束/角色隔离/产物保护/Handoff 协议）见 CLAUDE.md

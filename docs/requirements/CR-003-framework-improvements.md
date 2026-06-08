# CR-003: 基于 REQ002 实战复盘的框架改进

> 来源: ~/Codes/temp/mh-out (REQ002 案例完整产出)
> 日期: 2026-06-08
> 状态: 已实施

---

## 执行摘要

REQ002 是一个中大型增量重构需求（15 项架构修复，15 个 Task，3 个 Batch），总耗时 ~4 小时。过程中暴露了 8 个流程缺陷（CP-2~CP-8），其中多个问题具有系统性——不是个案，而是框架规则/模板的空白导致 PM 在灰色地带做出错误决策。

本 CR 将这些经验（EXP-1~EXP-10）归纳为 **11 个问题域**，通过脚本硬约束和模板结构约束解决，拒绝用自然语言膨胀 markdown。

## 核心教训

REQ002 验证了一条规律：**自然语言约束对 AI Agent 无效，脚本硬约束才是真正的防线。**

CR-001 用自然语言（agents/pm.md 加一句"禁止越权"）修复 PM 越权问题，REQ002 中 PM 仍两次越权。CR-001 设计了 verify-archive.sh 读取 .archiveignore，但未实现读取逻辑，REQ002 归档时构建产物未清理。

**结论：设计了但没接线 = 没设计。机制的存在 ≠ 机制的执行。**

## 与 CR-001 的关系：为什么上次的改善没生效

| CR-001 项 | 方案 | 约束层级 | REQ002 效果 | 失败原因 |
|-----------|------|---------|------------|---------|
| CR-001-E (PM 禁越权) | agents/pm.md 加一句禁止 | 自然语言 | ❌ PM 仍越权两次 | Agent 面对效率压力自动忽略自然语言规则 |
| CR-001-B (verify-archive 读 .archiveignore) | 新增脚本 | 脚本层（设计） | ❌ 归档产物未清理 | 脚本设计了但没实现读取逻辑 |
| CR-001-A (.archiveignore 生成) | propose 阶段生成 | 模板层 | ✅ 文件成功生成 | — |
| CR-001-D (handoff 增强) | 模板加可选节 | 模板层 | ✅ REQ002 handoff 质量提升 | — |
| CR-001-H (SR4 退回 apply) | 规则层明确 | 规则层 | ✅ SR4 从 16→2 次驳回 | — |

**规律：脚本层和模板层的改进生效了，自然语言层的改进全部失败。**

## 设计原则

1. **脚本硬约束 > 模板约束 > 自然语言软约束** — 能用脚本阻止的，不靠文字描述
2. **框架提供机制，不写死策略** — 项目配置驱动（.state.md、.archiveignore）
3. **技术栈解耦** — 适用于任意 output_type 和 tech_stack
4. **最小文档膨胀** — CLAUDE.md/skills/agents 只加指针（1-2行），不复述脚本逻辑

---

## 问题域 1: PM 越权修改技术产物（P0）

### 问题描述

- CP-2: PM 收到用户 4 点 SA 设计补充意见后，直接编辑 sa/design.md 写入技术内容，而非调度 SA 完善
- CP-3: Batch-1 完成后 PM 执行 typecheck 发现 6 个类型错误，PM 直接修改 6 个源码文件修复，未派发 DE

### 根因

- CLAUDE.md §2 角色隔离是自然语言软约束，PM 在"效率优先"压力下自动忽略
- CR-001-E 已尝试修复（pm.md 加一句话），REQ002 证明无效
- 没有任何技术手段阻止 PM 写文件

### 改善方案

**PreToolUse Hook 实时阻止（脚本层）：**
- `scripts/role-guard.sh` — 在 Write/Edit 执行前检查 current_role 与目标路径，越权直接 exit 2 拒绝
- `.claude/settings.json` — 配置 Hook 对 Write|Edit 触发
- `CLAUDE.md` §2 — 加一行指针："角色写入权限由 scripts/role-guard.sh 强制执行"

---

## 问题域 2: 质量门禁失败后修复流程缺失（P0）

### 问题描述

- CP-3: 框架对"门禁 FAIL 后怎么办"无定义，PM 被迫直接改代码
- 现有流程: `DE产出 → PM执行门禁 → 失败 → ???`
- 缺失环节: 门禁失败 → PM归因 → 创建修复handoff → DE修复 → PM复验

### 根因

- mh-apply-standard.md Step 1.4 只写了"不通过→驳回"，无归因机制
- 多 DE 并行时产生"集成缝隙"（跨模块类型不匹配），不属于任何单一 DE
- PM 没有结构化模板引导归因，倾向于"自己改了算了"

### 改善方案

**模板层：**
- `templates/quality-gate-report-template.md`（新增）— 错误清单 + 归因 Task + 修复方向 + 集成问题指定
- `CLAUDE.md` §4 — 加一行指针："质量门禁失败时 PM 使用 templates/quality-gate-report-template.md 归因并派发修复"

**脚本层兜底：**
- role-guard.sh 阻止 PM 直接修改代码文件（即使想"顺手改了"也做不到）

---

## 问题域 3: DE 直接写入根目录 output/（P0）

### 问题描述

- CP-5: 所有 DE SubAgent 将代码直接写入项目根目录 `output/`（最终归档目标），而非按框架设计写入 `deliverables/REQ002/output/`（开发暂存区）
- 破坏了"开发态与归档态分离"的设计意图：无法做归档前完整性校验、无法做 diff 对比、SR4 驳回时无法干净回退

### 根因

- PM 在 handoff 白名单中直接写了 `output/packages/server/src/...` 作为输出路径
- 框架对 CHANGE 模式（修改已有代码）的路径语义无明确规定
- DE 的"读"和"写"路径没有分离

### 改善方案

**Hook 层实时阻止：**
- role-guard.sh 中 DE 白名单仅含 `deliverables/${req}/output/` — DE 无法写入根目录 output/

**模板层引导：**
- handoff-template.md "期望输出"字段加注释提醒："DE 任务输出路径必须以 deliverables/{REQ-ID}/output/ 开头"

---

## 问题域 4: 产出文档按 REQ-ID 目录隔离（P0）

### 问题描述

- CP-6/CP-8: 归档文件位置和命名不遵循已有 output/docs/ 目录结构，不同需求的文档混在同一目录
- SR4 被驳回两次才建立正确的按 REQ-ID 分目录组织方式

### 根因

- mh-archive.md 硬编码了 `output/spec/` 路径，与实际项目结构冲突
- 框架无强制机制确保文档产出落在 {req-id}/ 子目录下
- 只在 SR4 时被人工发现，而非框架主动防护

### 改善方案

**脚本层：**
- verify-archive.sh 新增 ARC-5 检查 — 扫描 output/docs/ 下本次归档的文档是否落在 {req-id}/ 子目录中，不符合则 FAIL

---

## 问题域 5: .archiveignore 存在但未执行（P1）

### 问题描述

- REQ002 的 `deliverables/REQ002/.archiveignore` 已在 clarify 阶段正确生成（40+ 条规则），但归档时 PM 完全没读取它、没执行清理
- 构建产物（node_modules/、dist/、data-test/）污染归档目录

### 根因

- mh-archive.md 没有"读取 .archiveignore 并执行清理"的明确步骤
- verify-archive.sh 原实现对 .archiveignore 不存在时只输出 INFO 不 FAIL
- 典型的"设计了但没接线"

### 改善方案

**脚本层（接上电池）：**
- verify-archive.sh ARC-1 改为：.archiveignore 不存在时 FAIL（而非 INFO）
- verify-archive.sh 增强模式匹配：支持目录模式（`node_modules/`）用 `-path` 而非仅 `-name`

---

## 问题域 6: Token 消耗过高 / Agent 盲目探索（P1）

### 问题描述

- CP-4: T1 消耗 90,875 tokens / 111 tool uses / 30 分钟
- 根因①: 任务粒度过大（240行重构+3新文件+集成测试 = 单Agent认知负担重）
- 根因②: SubAgent 环境无法执行 pnpm typecheck，Agent 反复尝试导致无效 tool calls
- 根因③: Agent 反复读取相同文件确认上下文

### 根因

- Handoff 缺少环境标注（Agent 不知道哪些命令不可用）
- Handoff 缺少预读文件清单（Agent 探索式读取浪费 token）
- 无 Token 预算概念（Agent 无停止信号）

### 改善方案

**模板层：**
- handoff-template.md 新增三个结构化字段：
  - `## 环境限制` — Bash 权限 / 网络访问 / 可用工具
  - `## 执行前必读文件（按顺序）` — 减少探索式读取
  - `## Token 预算参考` — 预期复杂度 + 超出预算行为

---

## 问题域 7: SR4 审批混淆（P2）

### 问题描述

- CP-7: PM 在 apply 阶段用户说"通过"后，将其误认为是 archive 阶段的 SR4 结项确认，直接将 state 标记为 done

### 根因

- apply "通过" = 代码审批（SR3），archive "确认结项" = 归档完整性（SR4），两者措辞相近
- 框架中两个节点的触发条件区分不够

### 改善方案

**脚本层兜底：**
- verify-archive.sh 在 SR4 前执行，ARC-0~ARC-6 未完成时归档文件不存在 → 自然 FAIL
- 无需额外自然语言规则，脚本 FAIL 即阻塞

---

## 问题域 8: Custom output_type 验证策略缺失（P1）

### 问题描述

- EXP-6: output_type=custom 时，框架无预设 test_strategy，如果 clarify 阶段不明确，后续 DE 不知如何自验，TE 不知如何审计

### 根因

- mh-clarify.md 对 custom 没有强制追问验证策略
- .state.md 的 test_strategy 允许空值

### 改善方案

**脚本层可追加（未来）：**
- verify.sh 检查：如 output_type=custom 且 test_strategy 为空 → FAIL

**当前兜底：**
- handoff-template.md 的 Token 预算字段间接提醒 PM 需要有验证方式

---

## 问题域 9: 经验沉淀 CP→EXP 不一致（P1）

### 问题描述

- deliverables/REQ002/lessons.md（CP 版）：7 条，详细根因分析
- output/docs/lessons/req002/lessons-learned.md（EXP 版）：10 条，丢失细节
- EXP-6 在 CP 中无对应条目（凭空新增）
- CP 的方案对比分析在 EXP 中被压缩为一句话

### 根因

- ARC-6 只说"merge 进来"，无 CP→EXP 转换规则
- 无追溯链接（EXP 不引用源 CP 编号）
- 允许归档阶段凭空新增经验（绕过 CP 实时捕获机制）

### 改善方案

**当前限制：** 内容保真度难以用脚本校验。依赖 SR4 人工审批时校验。

**可选追加（脚本层）：**
- verify-archive.sh 检查：lessons-learned.md 中 EXP 条目数 ≥ deliverables/{REQ-ID}/lessons.md 中 CP 条目数

---

## 问题域 10: 大任务拆分（P2）

### 问题描述

- CP-4: T1 单任务 5 个产出文件，消耗 91k token
- PM 在编写 plan-action.md 时没有任务粒度评估标准

### 根因

- "一个架构问题 = 一个 Task" 的映射逻辑在复杂场景下导致单 Task 过大

### 改善方案

**模板层间接约束：**
- handoff-template.md Token 预算字段 — 大任务预算标"大<80k"，超出时 Agent 停止并报告
- 拆分决策依赖 PM 判断力，不适合硬编码规则（写了也会忽略）

---

## 问题域 11: 归档路径自适应（P1）

### 问题描述

- CP-6: mh-archive.md 硬编码 `output/spec/` 作为归档目标，但实际项目用 `output/docs/requirements/` 等
- PM 按 skill 指示创建不存在的目录，被 SR4 驳回

### 根因

- skill 假设固定归档结构，实际项目千差万别
- 归档前没有"先读再写"的强制步骤

### 改善方案

**脚本层兜底：**
- verify-archive.sh ARC-5 REQ-ID 隔离检查 — 文档不在 {req-id}/ 子目录下即 FAIL
- PM 必须先探测再归档，否则 verify-archive.sh 会拦截

---

## 实际交付物汇总

### 脚本层（硬约束 — 不可绕过）

| 文件 | 作用 | 覆盖问题域 |
|------|------|-----------|
| `scripts/role-guard.sh` (新增) | PreToolUse Hook，实时阻止角色越权写入 | 1, 2, 3 |
| `scripts/verify-archive.sh` (增强) | .archiveignore FAIL 校验 + REQ-ID 隔离检查 | 4, 5, 7, 11 |
| `.claude/settings.json` (更新) | 激活 Hook | 1, 2, 3 |

### 模板层（结构约束 — 引导正确行为）

| 文件 | 作用 | 覆盖问题域 |
|------|------|-----------|
| `templates/quality-gate-report-template.md` (新增) | 门禁失败归因报告 | 2 |
| `templates/handoff-template.md` (增强) | 环境限制/预读清单/Token预算/路径自检 | 3, 6, 10 |

### 规则层（最小指针）

| 文件 | 改动量 | 覆盖问题域 |
|------|--------|-----------|
| `CLAUDE.md` | +2 行 | 1, 2 |

---

## 数据支撑

### REQ002 Token 消耗

| 类别 | Token | 改善后预期 |
|------|-------|-----------|
| T1 (DI容器重构) | 90,875 | handoff 预读清单+Token预算 → ~50k |
| PM 越权修复 | ~30,000 | role-guard.sh Hook 后 → 0 |
| TE 审计 | 94,119 | 合理，不变 |

### SR4 驳回

| 轮次 | 原因 | CR-003 对应 |
|------|------|------------|
| 1 | 归档路径错误 + 无 REQ-ID 隔离 | verify-archive.sh ARC-5 |
| 2 | 构建产物未清理 | verify-archive.sh ARC-1 (.archiveignore FAIL) |
| 3 | 通过 | — |

### 修复循环

| Task | 修复轮次 | 根因 | CR-003 对应 |
|------|---------|------|------------|
| T4 | 1 轮 | container.resolve 返回 unknown | quality-gate-report-template 归因流程 |

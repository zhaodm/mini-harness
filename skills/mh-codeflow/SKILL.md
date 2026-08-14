---
name: mh-codeflow
description: This skill should be used when the user runs "/mh-run" or when auto-advance is active in code track. Code track full-flow orchestration with clarify→propose→apply→archive pipeline, 3-role spine, state machine, and breakpoint recovery.
---

# Skill: mh-codeflow

code track 全流程自动推进。Orchestrator 主导，一次性执行 clarify → propose → apply → archive，仅在人工审批节点暂停。

**日志规则：** 同各阶段 skill 定义，追加日志到 `deliverables/{project}/.engine/process.log`

---

## 工作流纪律

> 全局多角色纪律见 CLAUDE.md §6。角色调度协议见下方"调度协议"节。

### 命令入口

| 命令 | 作用 | Track |
|------|------|-------|
| `/mh-run` | 外部项目全流程自动推进（code track） | code |
| `/mh-ppt` | PPT 类 HTML 页面开发（ppt track） | ppt |

### 自检纪律

- **脚本硬约束优先于自然语言软约束**：以脚本退出码为准，Agent 自述不作为通过依据
- 任何文件写入后必须验证文件存在且非空
- Worker 编码后必须执行 mh-self-test（见 mh-self-test skill）
- Verifier 审计根据 test_strategy 选择验证方法
- 交付判定由 `scripts/verify*.sh` 系列脚本执行，退出码为唯一判据
- 审计发现代码逻辑缺陷时，退回 apply 阶段走 repair flow
- 任何变更在 propose 阶段必须由 Thinker 产出对应验收标准
- 回归套件存在时，Verifier 最终审计必须执行全量回归

### 断点恢复

- .engine/.state.md 是流程状态的唯一真相源（schema 见 `templates/state-template.md`）
- Orchestrator 恢复时仅依据 .engine/.state.md 和 handoff 文件状态，禁止依赖对话历史
- 每次更新 .engine/.state.md 必须同步更新 last_updated 时间戳

重新 `/mh-run` 时检测 `auto_advance: true`，从 phase + current_step 恢复继续。

---

## 调度协议

> 以下内容从 agents/orchestrator.md 下沉。角色定义见 agents/*.md。

### 标准调度循环（8 步）

```
1. 读取 .engine/.state.md         → 确认当前位置（phase/step/repair_round/track）
2. 写入 handoff           → 使用 templates/handoff-template.md 格式
3. 检查停止条件           → 触发则暂停等待用户
4. 更新 .engine/.state.md         → current_step/current_role/current_handoff/task_started_at（派发：一次完整写入）
5. 派发 SubAgent          → 注入角色契约 + handoff + 白名单文件
6. 接收回报               → SubAgent 写入 .engine/reports/{handoff-basename}.report.md
7. 执行质量门禁           → 按对应角色的检查清单逐项核对（见 templates/orchestrator-quality-gate.md）
8. 推进或驳回             → 通过则更新 .engine/.state.md（交还：一次完整写入）；不通过则写新 handoff 驳回
```

**第 6 步的回报落在独立文件，不写进 handoff。** `handoffs/*.md` 是 ORCHESTRATOR 独占（任务描述+白名单+约束），执行角色写入一律 `exit 2`；回报写 `deliverables/{project}/.engine/reports/{handoff-basename}.report.md`，role-guard 对 THINKER/WORKER/VERIFIER/ORCHESTRATOR 四者均放行该路径（无内容判据，路径正则 `^…$` 双向锚定，不跨交付物）。两者分处两套写权，故质量门禁比较的两侧（白名单 vs `read_files`）无法被执行角色自洽伪造。回报文件名由 handoff basename 机械派生，门禁据此关联，不依赖内容里的自述指针。

**第 4/8 步的 state 写入必须是一次完整写入。** 派发后 `current_role` 已是 SubAgent 角色，此时 role-guard 只在「该次写入把流程交还给 ORCHESTRATOR」时放行 `.engine/.state.md`——判据取本次写入的新内容，要求其**首个** `current_role:` 行的值恰为 `ORCHESTRATOR`（与读取端同源；写多行 `current_role` 而首行是别的角色一律拒）。**且必须用 `Write` 工具**——交还例外只接受 Write，`Edit` 写 `.engine/.state.md` 一律 `exit 2`（Edit 片段判据无法覆盖合并结果，曾可被用于提权，见 `docs/kb/domains/guards.md`）。

每一步之间打印心跳：`[Orchestrator] {动作描述}`

### Handoff 编写纪律

- 单个 handoff 的任务描述+约束+轮次信息合计不超过 150 行
- 创建 R2+ handoff 时，仅包含：(1)本轮新增/变更的要求 (2)上轮失败原因 (3)具体修正方向
- Thinker design/visual 任务的 handoff 必须填写 `产出规格.structure_skeleton`
- Thinker handoff 必须声明 `thinker_phase: needs|design|visual`

### 停止条件（Orchestrator 必须暂停等待用户）

| 条件 | 触发场景 | 行为 |
|------|---------|---------|
| SR Gate 阻塞 | SR1/SR3 节点 | 呈现决策上下文卡，等待通过/驳回 |
| 修复循环发散 | repair_history 连续 2 轮发散 | 呈现修复历史，上升人工 |
| 人机协作步骤 | Proposal 确认、wireframe 审批、模式选择 | 呈现选项，等待决策 |
| 任务超时 | task_started_at > 30 分钟 | 终止任务，上升人工 |

### 六条铁律

| # | 铁律 | 违反时的处理 |
|---|------|-------------|
| ① | 严格顺序（跳过≠乱序） | 阻塞，提示用户先完成前序阶段 |
| ② | Orchestrator 只做调度 | 不对产出物内容做技术判断 |
| ③ | 每棒必须有 handoff | 无 handoff 不得派发 SubAgent |
| ④ | SR 不可自主跨越 | 必须等待用户明确通过 |
| ⑤ | 下游不改上游 | 驳回时创建新 handoff，不修改已有文件 |
| ⑥ | 心跳 ↔ 动作一对一 | 每个动作前打印心跳 |

### 平台适配

- Claude Code 环境：通过 Agent 工具 spawn SubAgent 执行角色任务（Thinker/Worker/Verifier）
- Cline 环境：输出角色切换指令，附带 handoff 路径
- 两种模式共享同一套 handoff 格式和 skill 内容

---

## 质量门禁

Orchestrator 接收角色回报后，按以下顺序执行。检查清单骨架见 `templates/orchestrator-quality-gate.md`。

### Step 0: 白名单校验（所有角色通用）

核对输入是落盘的回报文件 `deliverables/{project}/.engine/reports/{handoff-basename}.report.md`，可 diff、可留痕，不依赖 SubAgent 进程内返回值。

- 回报文件不存在 → 任务视为未完成（驳回；SubAgent 失联时 Orchestrator 兜底代填）
- 对比回报文件中 `read_files` 与 handoff 文件中的白名单
- 出现白名单外的文件 → 驳回，标注信息泄露风险
- read_files 为空或缺失 → 提醒角色补填（非阻塞）

### Step 1: 内容质量快扫（按角色）

不做技术判断，只检查**结构完整性和自洽性**。

### 驳回标准

产出物存在以下任一情况时，Orchestrator 必须驳回并在新 handoff 中附带具体缺陷描述：

1. **明显不完整**：Tasks 只有 1 项但需求涉及多个功能；测试报告无具体用例
2. **自相矛盾**：设计方案与需求冲突；报告结论与详情不一致
3. **占位符残留**：TODO、placeholder、Lorem ipsum、{待填充} 等
4. **结论缺失**：Verifier 报告无 PASS/FAIL 结论；Worker 报告无 dev-test 结果

驳回时必须写出：未通过的检查项 + 具体缺陷位置 + 期望的修正方向

---

## 核心机制

**每个阶段步骤完成后，调用 `autoAdvance()`**（`workflows/lib/auto-advance.js`）：
- 输入: `{ phase, currentStep, srStatus, repairRound, autoAdvance: true }`
- 输出: `{ action, nextPhase?, reason }`

| action | Orchestrator 行为 |
|--------|---------|
| advance | 打印推进心跳，读取下一阶段 skill 继续执行 |
| pause | 暂停等待用户决策 |
| end | 打印最终摘要，流程结束 |

在 `.engine/.state.md` 写入 `auto_advance: true` 用于断点恢复识别。

---

## 暂停点（脚本硬编码）

- SR1 方案确认（proposal 评审）
- SR3 交付确认（最终审计后）
- Batch 人工确认
- 修复循环发散或耗尽（由 `decideRepair()` 触发）

## 状态重置

`autoAdvance()` 返回 `stateResets` 字段时，Orchestrator 必须同步更新 `.engine/.state.md`：
- SR3-DONE → archive: 重置 `repair_round=0, repair_task=""`

---

## 执行序列（code track）

1. **Init**: 写入 auto_advance=true, track=code → 执行 mh-intake → INIT-DONE → advance
2. **Propose**: 执行 mh-design（Thinker needs → design）→ SR1 通过 → advance
3. **Apply**: 执行 mh-build（人工审批照常暂停）→ SR3-DONE → advance
4. **Archive**: 执行 mh-deliver → phase=done → end

---

## 异常处理

- SubAgent status=failed → 修复循环内处理，不影响阶段间推进
- 修复发散/耗尽 → pause，用户解决后从当前位置继续
- 人工驳回 → 回退重新执行，完成后继续自动推进

---

## 最终摘要格式

```
══════════════════════════════════════
[/mh-run 全流程完成]
项目标识符: {project}
归档产物: deliverables/{project}/
项目状态: DONE
══════════════════════════════════════
```

# Skill: mh-propose

需求分析 → 架构设计 → 测试用例 → 计划编排 → 人工评审。按 mode 裁剪步骤。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 读取 `deliverables/.state.md` 获取当前 req_id
2. 验证 `deliverables/{REQ-ID}/.state.md` 中 phase=init 且 current_step=INIT-DONE
3. 读取 mode 字段确定流程裁剪方式
4. 验证 `deliverables/{REQ-ID}/proposal.md` 存在且非空
5. 不满足则阻塞，提示用户先执行 /mh-clarify

---

## fast 模式

跳过 BA/SA/TE，PM 直接从 proposal 生成执行计划。

**Step 1: PM 直接编排计划**

1. `[PM] fast 模式，跳过需求分析/架构设计/测试用例，直接编排计划`
2. 读取 `deliverables/{REQ-ID}/proposal.md`
3. 生成简版 plan-action.md（任务列表 + 执行顺序，无需求对照表）
4. 写入 `deliverables/{REQ-ID}/plan-action.md`
5. 更新 `deliverables/{REQ-ID}/.state.md`: phase=propose, current_step=PROPOSE-DONE, sr_status.SR1=skipped
6. `[PM] 计划编排完成（fast模式，跳过SR1），可执行 /mh-apply`

无 SR1 审批。

---

## standard 模式

跳过 BA，SA 和 TE 并行执行，无 SR1。

**Step 1: 产出结构协商 + 并行调度 SA∥TE（REQ-2 ∥ REQ-3）**

1. `[PM] standard 模式，跳过BA需求分析，启动 SA∥TE 并行`
2. **产出结构协商**（人机交互，Workflow 调用前必须完成）：
   - PM 根据 proposal.md 中的模块数量和复杂度，向用户提出设计文档结构建议：
     ```
     [结构协商]
     根据需求规模（{N}个模块），建议设计文档结构:
       A) 单文件: sa/design.md（模块≤3，适合简单需求）
       B) 多文件: sa/overview.md + sa/{module}.md（模块>3，适合复杂需求）
     
     章节结构:
       {建议的章节列表}
     
     请确认或调整:
     ```
   - 用户确认后，将结构写入 SA handoff 的 `产出规格.structure_skeleton`

3. **生成 SA handoff 内容**（按 templates/handoff-template.md 格式）：
   - to: SA
   - 白名单: `deliverables/{REQ-ID}/proposal.md`
     - 如 proposal.md 含 `## 参考摘要`，reference 文件按优先级标注访问级别：
       - `[HIGH]` → 白名单标注 `[FULL]`（SA 完整读取）
       - `[LOW]` → 白名单标注 `[SUMMARY]`（SA 仅读摘要）
   - 期望输出: `deliverables/{REQ-ID}/sa/design.md`
   - 额外期望输出: `.archiveignore` + `sa/verify-strategy.md`
   - 约束: 简版设计（架构 + Tasks清单 + 需求映射简表）。SA 需补充 Proposal 要点→Task→验证方式 映射表

4. **生成 TE handoff 内容**：
   - to: TE
   - 白名单: `deliverables/{REQ-ID}/proposal.md`
   - 期望输出: `deliverables/{REQ-ID}/te/testcases.md`
   - 额外期望输出: `te/audit-dimensions.md`（SR2/SR3 审计维度清单）

5. **更新 state 并调用 Workflow**：
   - 更新 `.state.md`: current_step=REQ-2+REQ-3, current_role=SA,TE
   - 写入 handoff 文件: `{REQ-ID}-REQ2-R1.md` + `{REQ-ID}-REQ3-R1.md`
   - 调用 Workflow `propose-parallel`:
     ```
     args.reqId = "{REQ-ID}"
     args.mode = "standard"
     args.saPrompt = agents/sa.md 内容 + SA handoff 内容
     args.tePrompt = agents/te.md 内容 + TE handoff 内容
     ```

6. **Workflow 返回后，执行质量门禁**（agents/pm.md "SA 产出验收" + "TE 产出验收"清单）：
   - `deliverables/{REQ-ID}/sa/design.md` 存在且非空
   - `deliverables/{REQ-ID}/te/testcases.md` 存在且非空
   - 全部通过 → 继续
   - 不通过 → 生成驳回 handoff（新轮次），重新调用 Workflow

7. 更新 `.state.md`: current_handoff="", current_role=PM
8. `[PM] REQ-2 + REQ-3 完成，技术方案和测试用例已生成`

**Step 2: PM 计划编排（REQ-4）**

1. `[PM] 启动计划编排`
2. 读取 design.md 中的 Tasks 清单 + testcases.md
3. 编排执行计划，写入 `deliverables/{REQ-ID}/plan-action.md`
   - 必须标注 Task 间依赖关系（见 plan-action.md 格式要求）
4. 更新 `deliverables/{REQ-ID}/.state.md`: phase=propose, current_step=PROPOSE-DONE, sr_status.SR1=skipped
5. `[PM] 计划编排完成（standard模式，跳过SR1），可执行 /mh-apply`

无 SR1 审批。

---

## full 模式

完整流程：BA → (SA ∥ TE) → PM编排 → SR1。

**Step 1: 调度 BA 需求分析（REQ-1）**

1. `[PM] 启动 REQ-1 需求分析，派发任务给 BA`
2. 写入 handoff: `deliverables/{REQ-ID}/handoffs/{REQ-ID}-REQ1-R1.md`
   - to: BA
   - 白名单: reference/*, `deliverables/{REQ-ID}/proposal.md`
   - 期望输出: `deliverables/{REQ-ID}/ba/requirement-spec.md`
3. 更新 `.state.md`: current_step=REQ-1, current_role=BA, current_handoff={REQ-ID}-REQ1-R1.md
4. 派发 BA SubAgent（单角色，无需 Workflow）
5. 接收回报，执行质量门禁（agents/pm.md "BA 产出验收"清单）
6. 更新 `.state.md`: current_handoff="", current_role=PM
7. `[PM] REQ-1 完成，需求规格已生成`

**Step 2: 产出结构协商 + 并行调度 SA∥TE（REQ-2 ∥ REQ-3）**

1. `[PM] 并行调度 SA 架构设计 + TE 测试用例设计`
2. **产出结构协商**（同 standard 模式）

3. **生成 SA handoff 内容**：
   - to: SA
   - 白名单: `deliverables/{REQ-ID}/ba/requirement-spec.md`
     - reference 文件按优先级标注（同 standard）
   - 期望输出: `deliverables/{REQ-ID}/sa/design.md`
   - 额外期望输出: `.archiveignore` + `sa/verify-strategy.md`

4. **生成 TE handoff 内容**：
   - to: TE
   - 白名单: `deliverables/{REQ-ID}/ba/requirement-spec.md`
   - 期望输出: `deliverables/{REQ-ID}/te/testcases.md`
   - 额外期望输出: `te/audit-dimensions.md`

5. **更新 state 并调用 Workflow**：
   - 更新 `.state.md`: current_step=REQ-2+REQ-3, current_role=SA,TE
   - 写入 handoff 文件
   - 调用 Workflow `propose-parallel`（同 standard）

6. **Workflow 返回后，执行质量门禁**（同 standard）
7. 更新 `.state.md`: current_handoff="", current_role=PM
8. `[PM] REQ-2 + REQ-3 完成，技术方案和测试用例已生成`

**Step 3: PM 计划编排（REQ-4）**

1. `[PM] 启动 REQ-4 计划编排`
2. 读取 design.md Tasks 清单 + testcases.md 用例列表
3. 编排执行计划，写入 `deliverables/{REQ-ID}/plan-action.md`
   - 必须标注 Task 间依赖关系（见 plan-action.md 格式要求）
4. 更新 `deliverables/{REQ-ID}/.state.md`: current_step=REQ-4
5. `[PM] REQ-4 完成，执行计划已编排`

**Step 4: 需求评审（SR1）**

1. `[PM] 启动 SR1 需求评审`
2. PM 逐项核对 SR1 通过标准：
   ```
   SR1 通过标准:
   - [ ] 需求规格覆盖所有 Proposal 要点（逐条核对，无遗漏）
   - [ ] 设计方案覆盖所有需求（对照表无空行）
   - [ ] 每个 Task 有依赖标注和验证方式
   - [ ] 计划可执行（无循环依赖、粒度合理）
   - [ ] 测试用例覆盖核心功能和关键边界
   ```
3. 向用户呈现决策上下文：
   ```
   [人工审批节点]
   评审节点: SR1

   需求覆盖:
     - 需求条数: {N} 条 SHALL
     - Proposal 要点覆盖: {已覆盖}/{总数}

   设计质量:
     - Task 数量: {N} 个
     - 并行度: Batch-1 含 {N} 个 Task（{百分比}）
     - 技术决策: {N} 个关键决策有选型理由

   测试覆盖:
     - 测试用例数: {N}
     - 需求覆盖: 每条需求至少 1 个用例

   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（请说明原因）
   ```
4. 等待用户决策：
   - **通过**:
     - 创建 baselines: `deliverables/{REQ-ID}/baselines/requirement-spec.v1.md` 等
     - 写入 `deliverables/{REQ-ID}/SR1-record.md`
     - 更新 `.state.md`: phase=propose, current_step=PROPOSE-DONE, sr_status.SR1=approved
     - `[PM] SR1 通过，可执行 /mh-apply`
   - **驳回**:
     - 记录驳回原因到 SR1-record.md
     - 回退到对应步骤重新执行

---

## plan-action.md 格式要求

PM 编排计划时，必须标注 Task 间依赖关系，用于 apply 阶段的并行批次调度：

```markdown
# 执行计划: {REQ-ID}

## Tasks

- Task-1: {描述} [deps: none]
- Task-2: {描述} [deps: none]
- Task-3: {描述} [deps: Task-1]
- Task-4: {描述} [deps: Task-1, Task-2]

## 集成点（跨 Task 调用链，SA 从 verify-strategy.md 摘录，可选）

- INT-1: Task-{A}({模块}) → Task-{B}({模块}): {调用关系描述}
- INT-2: Task-{C}({模块}) → Task-{D}({模块}): {调用关系描述}
```

**依赖判断标准：**
- Task-B 的实现需要 Task-A 的产出代码 → `[deps: Task-A]`
- Task-B 仅在逻辑上与 Task-A 相关但代码不依赖 → `[deps: none]`
- 无法确定时，标记为 `[deps: none]`

**批次计算规则：**
- Batch-1: 所有 `[deps: none]` 的 Task
- Batch-2: 依赖仅在 Batch-1 中已完成的 Task
- Batch-N: 依赖仅在前序 Batch 中已完成的 Task
- 无依赖标注时，所有 Task 归入 Batch-1（全部并行）

---

## plan-action.md 编排质量标准

PM 编排完成后，必须自检以下质量标准：

**粒度检查：**
- Task 数量与需求复杂度匹配（3-4 条需求通常对应 3-6 个 Task）
- 不出现"1 个 Task 实现全部功能"（除非 fast 模式且需求极简）
- 不出现"10+ 个 Task 但每个只改 1 行"（过度拆分）

**依赖检查：**
- 依赖图无环
- Batch-1 占比合理（通常 40-70%）
- 所有 Task 都是 `[deps: none]` 时，质疑是否遗漏依赖

**完整性检查：**
- 对照 design.md Tasks 清单，确认无遗漏
- 对照需求/Proposal 要点，确认每条至少映射到 1 个 Task

**可验证性检查：**
- 每个 Task 有明确的验证方式
- 验证方式与 test_strategy 一致

---

## 异常处理

- Workflow 返回 status=failed: PM 检查失败原因，决定重试或上升人工
- 文件校验失败（不存在或为空）: 生成驳回 handoff，重新调用 Workflow（轮次+1）
- 轮次达到 5 次: 上升人工审核

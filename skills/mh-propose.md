# Skill: mh-propose

需求分析 → 架构设计 → 测试用例 → 计划编排 → SR1 方案确认。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 读取 `deliverables/.state.md` 获取当前 req_id
2. 验证 `deliverables/{REQ-ID}/.state.md` 中 phase=init 且 current_step=INIT-DONE
3. 验证 `deliverables/{REQ-ID}/proposal.md` 存在且非空
4. 不满足则阻塞，提示用户先完成 clarify 阶段

---

## Step 1: 产出结构协商 + 并行调度 SA∥TE（REQ-2 ∥ REQ-3）

1. `[PM] 启动 SA∥TE 并行：架构设计 + 测试用例设计`
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

4. **生成 TE handoff 内容**：
   - to: TE
   - 白名单: `deliverables/{REQ-ID}/proposal.md`
   - 期望输出: `deliverables/{REQ-ID}/te/testcases.md`

5. **更新 state 并调用 Workflow**：
   - 更新 `.state.md`: current_step=REQ-2+REQ-3, current_role=SA,TE
   - 写入 handoff 文件: `{REQ-ID}-REQ2-R1.md` + `{REQ-ID}-REQ3-R1.md`
   - 调用 Workflow `propose-parallel`

6. **Workflow 返回后，执行质量门禁**（agents/pm.md "SA 产出验收" + "TE 产出验收"清单）：
   - `deliverables/{REQ-ID}/sa/design.md` 存在且非空
   - `deliverables/{REQ-ID}/te/testcases.md` 存在且非空
   - 全部通过 → 继续
   - 不通过 → 生成驳回 handoff（新轮次），重新调用 Workflow

7. 更新 `.state.md`: current_handoff="", current_role=PM
8. `[PM] REQ-2 + REQ-3 完成，技术方案和测试用例已生成`

---

## Step 2: PM 计划编排（REQ-4）

1. `[PM] 启动计划编排`
2. 读取 design.md 中的 Tasks 清单 + testcases.md
3. 编排执行计划，写入 `deliverables/{REQ-ID}/plan-action.md`
   - 必须标注 Task 间依赖关系（见 plan-action.md 格式要求）
4. 更新 `deliverables/{REQ-ID}/.state.md`: current_step=REQ-4
5. `[PM] 计划编排完成`

---

## Step 3: SR1 方案确认（人工审批）

1. `[PM] 启动 SR1 方案确认`
2. PM 逐项核对 SR1 通过标准：
   - 设计方案覆盖所有 Proposal 要点
   - 每个 Task 有依赖标注和验证方式
   - 计划可执行（无循环依赖、粒度合理）
   - 测试用例覆盖核心功能和关键边界
3. 向用户呈现决策上下文：
   ```
   [人工审批节点]
   评审节点: SR1

   设计质量:
     - Task 数量: {N} 个
     - 并行度: Batch-1 含 {N} 个 Task
     - 技术决策: {N} 个关键决策有选型理由

   测试覆盖:
     - 测试用例数: {N}

   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（请说明原因）
   ```
4. 等待用户决策：
   - **通过**:
     - 更新 `.state.md`: phase=propose, current_step=PROPOSE-DONE, sr_status.SR1=approved
     - `[PM] SR1 通过，进入 apply 阶段`
   - **驳回**:
     - 记录驳回原因，回退到对应步骤重新执行

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

## 集成点（跨 Task 调用链，可选）

- INT-1: Task-{A}({模块}) → Task-{B}({模块}): {调用关系描述}
```

**批次计算规则：**
- Batch-1: 所有 `[deps: none]` 的 Task
- Batch-2: 依赖仅在 Batch-1 中已完成的 Task
- Batch-N: 依赖仅在前序 Batch 中已完成的 Task

---

## 异常处理

- Workflow 返回 status=failed: PM 检查失败原因，决定重试或上升人工
- 文件校验失败（不存在或为空）: 生成驳回 handoff，重新调用 Workflow（轮次+1）
- 轮次达到 5 次: 上升人工审核

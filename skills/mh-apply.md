# Skill: mh-apply

开发实现 → 审计验证 → 人工审批。统一流程。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 读取 `deliverables/.state.md` 获取当前 req_id
2. 验证 `deliverables/{REQ-ID}/.state.md` 中 current_step=PROPOSE-DONE
3. 验证 `deliverables/{REQ-ID}/plan-action.md` 存在且非空
4. 不满足则阻塞，提示用户先完成 propose 阶段

## 断点续作

1. 读取 `deliverables/{REQ-ID}/.state.md` 中 completed_steps
2. 读取 `repair_round` 和 `repair_task` 字段，恢复修复循环上下文
3. 跳过已完成的 Task，从未完成的 Task 继续
4. 如 repair_round > 0，从修复循环的当前轮次继续
5. `[PM] 断点恢复，从 {step_id} 继续（repair_round={N}）`

---

## Step 1: 批次开发+审计

> code-report 规则：每个 Task 独立 `code-report-t{N}.md`，不得合并。

1. 读取 plan-action.md 的 Task 列表和依赖关系
2. **调用 `calculateBatches()`**（`workflows/lib/calculate-batches.js`）自动分批
3. FOR 每个 Batch:
   - 生成 DE handoff → 调用 Workflow `apply-batch-dev`
   - 质量门禁（agents/pm.md "DE 产出验收"清单）→ 不通过则驳回重调
   - 生成 TE handoff → 调用 Workflow `apply-batch-test`
   - FAIL → 修复循环（`mh-apply-repair.md`，由 `decideRepair()` 决策）
   - **人工批量确认**（呈现变更摘要+质量状态，等待用户通过/驳回）
   - 记入 completed_steps

### Handoff 生成要点

- DE handoff 路径: `handoffs/{REQ-ID}-DEV1-T{N}-R1.md`
- 白名单: `sa/design.md`（对应 Task 部分）+ 已有代码 + 前序 Batch 产出
- 合并规则: 同 Batch 无共享依赖且同模块的 Task 可合并（≤3 Task/handoff）
- TE handoff 路径: `handoffs/{REQ-ID}-TEST1-T{N}-R1.md`，按 test_strategy 执行

---

## Step 1.5: 集成预检

所有 Batch 完成后，如 `sa/verify-strategy.md` 存在，逐条执行集成检查命令。FAIL → 修复循环；不可执行 → 标注降级。

---

## Step 2: TE 最终审计

1. 生成全量审计 handoff（回归 + Code Review + 工程验证）
   - **调用 `deriveReviewScope(outputType)`** 获取 review_scope
   - 白名单追加: `output/tests/regression-suite.md`（如存在）
   - handoff 中注入字段:
     - `review_scope`: { skip, dimensions, depth }
     - `regression_suite_exists`: true/false
   - 期望输出: final-test-report.md（含 Code Review 章节 + 回归测试章节）
2. 调用 Workflow `apply-final-audit`
3. passed=true → SR3；passed=false → 修复循环

---

## Step 3: SR3 交付确认（人工审批）

1. PM 核对 SR3 标准: 全量测试 PASS / 无 Critical/Major / 回归通过
2. 向用户呈现审计结论+质量总结+降级项确认+PM 建议，等待确认
3. 通过 → SR3-record.md, current_step=SR3-DONE
4. 驳回 → 回退修复

---

## 异常处理

- SubAgent 回报 status=failed: 检查原因，决定重试或上升
- SubAgent 超时但产出物已存在:
  - PM 检查 output/ 中对应 Task 的文件是否完整
  - 完整 → 视为成功，PM 代填 code-report
  - 不完整 → 重试一次
- 浏览器环境不可用: 降级标注，使用可用的验证方式
- 断点恢复时发现不一致: 以 `.state.md` 为准，重新校验文件状态

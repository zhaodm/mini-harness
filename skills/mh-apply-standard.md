# mh-apply: standard/full 模式

并行批次开发（按依赖分批）→ SR2 → 最终审计 → SR3。

> full 模式的 apply 阶段与 standard 完全一致，区别仅在 propose 阶段。

---

## Step 1: 并行批次开发+审计

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

## Step 2: SR2 功能评审（人工审批）

1. 机器可检查清单预检（design.md `## 7.` 节，grep 自动验证）
2. PM 核对 SR2 标准:
   - 所有 Task 通过 TE 审计（无 Critical/Major 缺陷）
   - 代码质量达标（dev-test=PASS, post-verify=PASS）
   - 无 TODO/FIXME 残留（`scripts/verify.sh` D 类检查通过）
   - 内容质量达标（`scripts/verify-qa.sh` 通过）
   - 需求覆盖无明显遗漏
3. 向用户呈现完成概况+风险评估+PM 建议，等待确认
4. 通过 → SR2-record.md；驳回 → 回退指定 Task

---

## Step 3: TE 最终审计

1. 生成全量审计 handoff（E2E + 回归 + 工程验证）
2. 调用 Workflow `apply-final-audit`
3. passed=true → SR3；passed=false → 修复循环

---

## Step 4: SR3 最终评审（人工审批）

1. PM 核对 SR3 标准: 全量测试 PASS / 覆盖率 ≥95% / 无 Critical/Major / 回归通过
2. 向用户呈现审计结论+质量总结+降级项确认+PM 建议，等待确认
3. 通过 → SR3-record.md, current_step=SR3-DONE
4. 驳回 → 回退修复

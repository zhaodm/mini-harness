# mh-apply: fast 模式

DE 一次性开发所有任务 → TE 轻量审计 → 人工确认（唯一审批点）。

---

**Step 1: DE 批量开发**

1. `[PM] fast 模式，DE 批量开发所有任务`
2. 写入 handoff: `deliverables/{REQ-ID}/handoffs/{REQ-ID}-DEV1-R1.md`
   - to: DE
   - 白名单: `deliverables/{REQ-ID}/plan-action.md`, `deliverables/{REQ-ID}/proposal.md`, 已有代码
   - 期望输出: `deliverables/{REQ-ID}/output/`, `deliverables/{REQ-ID}/de/code-report.md`
3. 更新 `deliverables/{REQ-ID}/.state.md`: current_step=DEV-1, current_role=DE
4. 派发任务:
   - [Claude Code] spawn SubAgent，注入 handoff + agents/de.md + 白名单文件
   - [Cline] 切换角色为 DE，指示读取 handoff
5. 接收回报，执行质量门禁（agents/pm.md "DE 产出验收"清单）:
   - 全部通过 → 继续
   - 不通过 → 驳回（新 handoff 附未通过项 + 位置 + 修正方向）
6. `[PM] 开发完成`

**Step 2: TE 轻量审计**

1. `[PM] fast 模式，TE 轻量审计`
2. 写入 handoff: `deliverables/{REQ-ID}/handoffs/{REQ-ID}-TEST1-R1.md`
   - to: TE
   - 白名单: `deliverables/{REQ-ID}/output/`, `deliverables/{REQ-ID}/proposal.md`, `deliverables/{REQ-ID}/.state.md`
   - 如 `output/tests/regression-suite.md` 存在，白名单追加并标注 `regression_suite_exists: true`
   - **调用 `deriveReviewScope('fast', outputType)`** → 注入 `review_scope`
   - 期望输出: `deliverables/{REQ-ID}/te/temp-test-report.md`
   - 约束: fast 模式轻量验证——工程检查（lint+构建）+ 关键路径抽查（验证核心功能可用），不要求完整覆盖分析。回归不降级（全量执行）。Code Review 按 review_scope.dimensions 执行（仅 security + error-handling）。根据 .state.md 中 test_strategy 执行对应验证；如 test_strategy=manual，生成人工检查清单（仅核心项）
3. 派发任务给 TE
4. 接收回报，执行质量门禁（agents/pm.md "TE 产出验收"清单）:
   - PASS → 继续 Step 3
   - FAIL → 修复循环（读取 `skills/mh-apply-repair.md`，最多5轮）

**Step 3: 人工确认（唯一审批点）**

1. `[PM] 进入人工确认`
2. 向用户呈现决策上下文：
   ```
   [人工确认]
   模式: fast
   
   变更摘要:
     - 文件数: {N} 个文件
     - 新增/修改/删除: +{N} / ~{N} / -{N}
   
   质量状态:
     - 测试: {通过数}/{总数} 通过
     - dev-test: PASS
     - TE 审计: {PASS/FAIL} ({一句话结论})
   
   修复历史: {首次通过 / 经 {N} 轮修复后通过}
   
   产出文件: deliverables/{REQ-ID}/output/
   审计报告: deliverables/{REQ-ID}/te/temp-test-report.md
   
   PM 建议: {通过/建议人工复查} ({理由})
   请确认: 通过 / 驳回（请说明原因）
   ```
3. 用户通过:
   - 更新 `deliverables/{REQ-ID}/.state.md`: sr_status.SR2=skipped, sr_status.SR3=approved, phase=apply, current_step=SR3-DONE
   - `[PM] 确认通过（fast模式），可执行 /mh-archive`
4. 用户驳回:
   - 记录原因，回退 DE 修复

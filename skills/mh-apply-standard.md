# mh-apply: standard/full 模式

并行批次开发（按依赖分批）→ SR2 → 最终审计 → SR3。

> full 模式的 apply 阶段与 standard 完全一致，区别仅在 propose 阶段。

---

**Step 1: 并行批次开发+审计**

> code-report 规则：每个 Task 独立 code-report（`code-report-t{N}.md`）。同批并行的 Task 不得合并 code-report。

```
读取 plan-action.md 中的 Task 列表和依赖关系（[deps: ...]）
计算并行批次:
  Batch-1: 所有 deps=none 的 Task
  Batch-2: 依赖仅在 Batch-1 中的 Task
  Batch-N: 依赖仅在前序 Batch 中的 Task
  （无依赖标注时，所有 Task 视为 deps=none，归入同一批次）

FOR 每个 Batch（跳过已完成的 Task）:
    生成 DE handoff → 调用 Workflow apply-batch-dev → 质量门禁
    生成 TE handoff → 调用 Workflow apply-batch-test → 检查审计结论
    失败 Task → 修复循环
    人工批量确认
    记入 completed_steps
END FOR
```

对每个 Batch-{B}：

1. `[PM] 启动 Batch-{B}，包含 Task: {列表}`
2. **生成 DE handoff**（Batch 内每个 Task）：
   - `deliverables/{REQ-ID}/handoffs/{REQ-ID}-DEV1-T{N}-R1.md`
   - to: DE
   - 白名单: `sa/design.md`（Task-{N} 部分）, 已有代码, 前序 Batch 产出代码
   - 期望输出: `deliverables/{REQ-ID}/output/`, `deliverables/{REQ-ID}/de/code-report-t{N}.md`
   - **批量合并规则**: 同 Batch 无共享依赖且属同模块的 Task，允许合并为一个 handoff（上限 3 Task/handoff）
   - **上下文裁剪**: 如 design.md 含 `## 6. 接口契约摘要`，白名单标注精读范围

3. **更新 state 并调用 Workflow**：
   - 更新 `.state.md`: current_step=DEV-{B}, current_role=DE
   - 调用 Workflow `apply-batch-dev`:
     ```
     args.reqId = "{REQ-ID}"
     args.batchId = {B}
     args.tasks = [{ taskId: "1", prompt: DE契约+handoff }, ...]
     args.merged = [{ taskIds: ["2","3"], prompt: 合并handoff }]  // 可选
     ```

4. **Workflow 返回后，逐 Task 执行质量门禁**（agents/pm.md "DE 产出验收"清单）：
   - 全部通过 → 继续
   - 不通过 → 驳回对应 Task（新 handoff 附未通过项 + 修正方向），重新调用 Workflow

5. `[PM] Batch-{B} 开发完成，启动 TE 审计`

6. **生成 TE handoff**（Batch 内每个 Task）：
   - `deliverables/{REQ-ID}/handoffs/{REQ-ID}-TEST1-T{N}-R1.md`
   - 读取 .state.md 中 test_strategy 执行对应验证

7. **调用 Workflow**：
   - 更新 `.state.md`: current_role=TE
   - 调用 Workflow `apply-batch-test`:
     ```
     args.reqId = "{REQ-ID}"
     args.batchId = {B}
     args.tasks = [{ taskId: "1", prompt: TE契约+handoff }, ...]
     ```

8. **Workflow 返回后，检查审计结论**：
   - 全部 PASS → 人工批量确认
   - 部分 FAIL → 失败 Task 进入修复循环（读取 `skills/mh-apply-repair.md`），通过的 Task 等待

9. **人工批量确认**：
   ```
   [人工确认 Batch-{B}]
   
   通过的 Task: {列表}
   变更摘要:
     - 总文件数: {N}
     - 各 Task 概要: {Task-1: +X行, Task-2: +Y行, ...}
   
   质量状态:
     - 测试覆盖: {已验证需求数}/{总需求数}
     - 修复轮次: {各 Task 修复次数，0=首次通过}
   
   审计报告: deliverables/{REQ-ID}/te/temp-test-report.md
   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（指定 Task 和原因）
   ```
10. 确认通过 → 更新 `.state.md`: current_role=PM，记入 completed_steps → 下一个 Batch

---

**Step 1.5: 集成预检（所有 Batch 完成后）**

> 利用 SA 在 propose 阶段产出的 verify-strategy.md 执行集成检查。

1. `[PM] 所有 Batch 开发完成，执行集成预检`
2. 检查 `deliverables/{REQ-ID}/sa/verify-strategy.md` 是否存在：
   - 不存在 → 跳过，直接进入 SR2
   - 存在 → 读取"集成检查命令"列表
3. 在 `deliverables/{REQ-ID}/output/` 下逐条执行
4. 结果处理：
   - 全部 PASS → `[PM] 集成预检通过，进入 SR2`
   - 部分 FAIL → 修复循环（`skills/mh-apply-repair.md`），通过后重新执行
   - 命令不可执行 → 标注降级，继续 SR2

---

**Step 2: SR2 功能评审**

1. `[PM] 所有 Task 完成，启动 SR2 功能评审`
2. **机器可检查清单预检**（如 design.md 含 `## 7. 机器可检查清单`）：
   - PM 逐条执行 grep 检查
   - PASS 项标记"已自动验证"，不派发 TE 复核
   - FAIL 项 → 派发 TE 验证
3. PM 逐项核对 SR2 通过标准：
   ```
   SR2 通过标准:
   - [ ] 所有 Task 通过 TE 审计（无 Critical/Major 缺陷）
   - [ ] 代码质量达标（所有 dev-test=PASS, post-verify=PASS）
   - [ ] 无 TODO/FIXME 残留（verify.sh D 类检查通过）
   - [ ] 内容质量达标（verify-qa.sh 通过）
   - [ ] 需求覆盖无明显遗漏
   ```
4. 向用户呈现决策上下文：
   ```
   [人工审批节点]
   评审节点: SR2
   
   完成概况:
     - 已完成 Task: {列表及各自审计结论}
     - 总文件变更: {N} 个文件
     - 测试覆盖: {已验证需求数}/{总需求数}
   
   风险评估:
     - 修复轮次统计: {各 Task 修复次数}
     - 降级验证: {有/无}
   
   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（请说明原因）
   ```
5. 通过: 写入 SR2-record.md，继续
6. 驳回: 回退指定 Task

---

**Step 3: TE 最终审计**

1. `[PM] 启动最终审计`
2. **生成最终审计 handoff**：
   - `deliverables/{REQ-ID}/handoffs/{REQ-ID}-TEST2-R1.md`
   - 全量测试（E2E + 回归 + 工程验证）
   - 期望输出: `deliverables/{REQ-ID}/te/final-test-report.md`
3. **调用 Workflow**：
   - 更新 `.state.md`: current_role=TE
   - 调用 Workflow `apply-final-audit`:
     ```
     args.reqId = "{REQ-ID}"
     args.prompt = agents/te.md 内容 + 最终审计 handoff 内容
     ```
4. **Workflow 返回后**：
   - passed=true → 进入 SR3
   - passed=false → 修复循环（`skills/mh-apply-repair.md`）

---

**Step 4: SR3 最终评审**

1. `[PM] 启动 SR3 最终功能评审`
2. PM 逐项核对 SR3 通过标准：
   ```
   SR3 通过标准:
   - [ ] 全量测试通过（final-test-report 结论=PASS）
   - [ ] 需求覆盖率 ≥ 95%，未覆盖项有降级机制
   - [ ] 无 Critical/Major 缺陷
   - [ ] 回归测试通过
   ```
3. 向用户呈现决策上下文：
   ```
   [人工审批节点]
   评审节点: SR3（最终评审）
   
   最终审计结论: {PASS/FAIL}
   需求覆盖: {已验证}/{总数} ({百分比})
   
   质量总结:
     - 全量测试: {通过数}/{总数}
     - 回归测试: {通过/未执行}
     - 工程验证: {lint + 构建状态}
   
   降级项确认（覆盖率 < 100% 时必填）:
     - {未覆盖需求}: {降级机制}
   
   产出物清单: deliverables/{REQ-ID}/output/ ({N} 个文件)
   最终报告: deliverables/{REQ-ID}/te/final-test-report.md
   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（请说明原因）
   ```
4. 通过:
   - 写入 SR3-record.md
   - 更新 `.state.md`: sr_status.SR3=approved, phase=apply, current_step=SR3-DONE, current_role=PM
   - `[PM] SR3 通过，可执行 /mh-archive`
5. 驳回: 回退修复

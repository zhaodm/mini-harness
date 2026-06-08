# mh-apply: standard/full 模式

并行批次开发（按依赖分批）→ SR2 → 最终审计 → SR3。

> full 模式的 apply 阶段与 standard 完全一致，区别仅在 propose 阶段。

---

**Step 1: 并行批次开发+审计**

> ⚡ 并行优化：无依赖的 Task 同批并行开发和审计。仅 Claude Code 模式支持并行；Cline 模式退化为逐任务串行。
>
> code-report 规则：每个 Task 独立 code-report（`code-report-t{N}.md`）。同批并行的 Task 不得合并 code-report。如 SubAgent 合并产出，PM 在质量门禁时要求补充独立报告。

```
读取 plan-action.md 中的 Task 列表和依赖关系（[deps: ...]）
计算并行批次:
  Batch-1: 所有 deps=none 的 Task
  Batch-2: 依赖仅在 Batch-1 中的 Task
  Batch-N: 依赖仅在前序 Batch 中的 Task
  （无依赖标注时，所有 Task 视为 deps=none，归入同一批次）

FOR 每个 Batch（跳过已完成的 Task）:
    并行派发 Batch 内所有 Task 给 DE
    等待所有 DE 完成质量门禁
    并行派发 Batch 内所有 Task 给 TE 审计
    等待所有 TE 完成
    对失败的 Task 进入修复循环（可并行修复）
    人工批量确认本批次
    记入 completed_steps
END FOR
```

> 设计选择：Batch 内所有 DE 通过质量门禁后才统一派发 TE 审计。
> 理由：保持 Batch 原子性——TE 审计时所有 Task 代码已就位，避免模块间依赖导致的测试假阳性。
> 如需更高并行度，可在 plan-action.md 中将大 Batch 拆为多个小 Batch。

对每个 Batch-{B}：

1. `[PM] 启动 Batch-{B}，包含 Task: {列表}，并行派发给 DE`
2. 为 Batch 内每个 Task-{N} 写入 handoff（或合并派发）:
   - `deliverables/{REQ-ID}/handoffs/{REQ-ID}-DEV1-T{N}-R1.md`
   - to: DE
   - 白名单: `deliverables/{REQ-ID}/sa/design.md`（Task-{N} 部分）, 已有代码, 前序 Batch 产出代码
   - 期望输出: `deliverables/{REQ-ID}/output/`, `deliverables/{REQ-ID}/de/code-report-t{N}.md`
   - **批量合并规则**: 同 Batch 内无共享依赖且属于同模块的 Task，允许合并为一个 handoff（上限 3 Task/handoff），handoff 中逐个列出 Task 描述和期望输出
   - **上下文裁剪**: 如 design.md 含 `## 6. 接口契约摘要`，白名单标注 DE 精读该节 + Task 对应段落（使用 handoff 的"上下文裁剪指示"节）
3. 并行派发:
   - [Claude Code] 同时 spawn 多个 DE SubAgent，每个处理一个 Task
   - [Cline] 逐个串行执行
4. 等待所有 DE 完成，执行质量门禁（agents/pm.md "DE 产出验收"清单）:
   - 全部通过 → 继续
   - 不通过 → 驳回对应 Task（新 handoff 附未通过项 + 位置 + 修正方向）
5. `[PM] Batch-{B} 开发完成，并行派发 TE 审计`
6. 为 Batch 内每个 Task-{N} 写入 TE handoff:
   - `deliverables/{REQ-ID}/handoffs/{REQ-ID}-TEST1-T{N}-R1.md`
   - 读取 .state.md 中 test_strategy 执行对应验证
7. 并行派发:
   - [Claude Code] 同时 spawn 多个 TE SubAgent
   - [Cline] 逐个串行执行
8. 等待所有 TE 完成，执行质量门禁（agents/pm.md "TE 产出验收"清单）并汇总:
   - 全部 PASS → 人工批量确认本批次
   - 部分 FAIL → 失败的 Task 进入修复循环（读取 `skills/mh-apply-repair.md`），通过的 Task 等待
9. 人工批量确认:
   ```
   [人工确认 Batch-{B}]
   
   通过的 Task: {列表}
   变更摘要:
     - 总文件数: {N}
     - 各 Task 概要: {Task-1: +X行, Task-2: +Y行, ...}
   
   质量状态:
     - 测试覆盖: {已验证需求数}/{总需求数}
     - 修复轮次: {各 Task 的修复次数，0=首次通过}
   
   审计报告: deliverables/{REQ-ID}/te/temp-test-report.md
   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（指定 Task 和原因）
   ```
10. 确认通过 → 记入 completed_steps → 下一个 Batch

---

**Step 1.5: 集成预检（所有 Batch 完成后）**

> 在进入 SR2 之前，利用 SA 在 propose 阶段产出的 verify-strategy.md 执行集成检查，提前拦截跨模块问题。

1. `[PM] 所有 Batch 开发完成，执行集成预检`
2. 检查 `deliverables/{REQ-ID}/sa/verify-strategy.md` 是否存在：
   - 不存在 → 跳过本步骤，直接进入 SR2
   - 存在 → 读取其中的"集成检查命令"列表
3. 在 `deliverables/{REQ-ID}/output/` 目录下逐条执行集成检查命令
4. 结果处理：
   - 全部 PASS → `[PM] 集成预检通过，进入 SR2`
   - 部分 FAIL → 将失败项作为修复任务进入修复循环（读取 `skills/mh-apply-repair.md`），修复通过后重新执行集成预检
   - 命令不可执行（环境缺失）→ 标注降级，继续进入 SR2

---

**Step 2: SR2 功能评审**

1. `[PM] 所有 Task 完成，启动 SR2 功能评审`
2. **机器可检查清单预检**（如 sa/design.md 含 `## 7. 机器可检查清单`）：
   - PM 逐条执行 grep 检查（`grep -r "{pattern}" {glob}`）
   - PASS 的项标记为"已自动验证"，不派发 TE Agent 复核
   - FAIL 的项 + 清单外的语义级检查项 → 派发 TE Agent 验证
   - 如无机器可检查清单，按原流程全量派发 TE
3. PM 逐项核对 SR2 通过标准：
   ```
   SR2 通过标准:
   - [ ] 所有 Task 通过 TE 审计（无 Critical/Major 缺陷）
   - [ ] 代码质量达标（所有 Task 的 dev-test=PASS, post-verify=PASS）
   - [ ] 无 TODO/FIXME 残留（verify.sh D 类检查通过）
   - [ ] 内容质量达标（verify-qa.sh 通过，无 FAIL 项）
   - [ ] 需求覆盖无明显遗漏
   ```
3. 向用户呈现决策上下文：
   ```
   [人工审批节点]
   评审节点: SR2
   
   完成概况:
     - 已完成 Task: {列表及各自审计结论}
     - 总文件变更: {N} 个文件
     - 测试覆盖: {已验证需求数}/{总需求数}
   
   风险评估:
     - 修复轮次统计: {各 Task 修复次数，高修复次数=高风险}
     - 降级验证: {有/无，如有列出未覆盖项}
   
   相关产物: deliverables/{REQ-ID}/output/, deliverables/{REQ-ID}/te/temp-test-report.md
   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（请说明原因）
   ```
3. 通过: 写入 SR2-record.md，继续
4. 驳回: 回退指定 Task

---

**Step 3: TE 最终审计**

1. `[PM] 启动最终审计`
2. 写入 handoff: `deliverables/{REQ-ID}/handoffs/{REQ-ID}-TEST2-R1.md`
   - 全量测试（E2E + 回归 + 工程验证）
   - 期望输出: `deliverables/{REQ-ID}/te/final-test-report.md`
3. 结论: PASS → SR3 / FAIL → 修复（读取 `skills/mh-apply-repair.md`）

---

**Step 4: SR3 最终评审**

1. `[PM] 启动 SR3 最终功能评审`
2. PM 逐项核对 SR3 通过标准：
   ```
   SR3 通过标准:
   - [ ] 全量测试通过（TE final-test-report 结论=PASS）
   - [ ] 需求覆盖率 ≥ 95%，且未覆盖项均有降级机制或补充计划
   - [ ] 无 Critical/Major 缺陷
   - [ ] 回归测试通过（已有功能未被破坏）
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
     - {未覆盖需求}: {降级机制/补充计划}
   
   风险项（如有）:
     - {降级验证项}
     - {高修复次数的 Task}
   
   产出物清单: deliverables/{REQ-ID}/output/ ({N} 个文件)
   最终报告: deliverables/{REQ-ID}/te/final-test-report.md
   PM 建议: {通过/建议复查} ({理由})
   请确认: 通过 / 驳回（请说明原因）
   ```
3. 通过:
   - 写入 SR3-record.md
   - 更新 `deliverables/{REQ-ID}/.state.md`: sr_status.SR3=approved, phase=apply, current_step=SR3-DONE
   - `[PM] SR3 通过，可执行 /mh-archive`
4. 驳回: 回退修复

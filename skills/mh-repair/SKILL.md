---
name: mh-repair
description: This skill should be used when Verifier audit fails, during repair cycles, or when fix loops are active. Repair loop orchestration with decideRepair() decision logic, root cause analysis, and repair dispatch.
---

# Skill: mh-repair

修复循环（code/PPT track 共享）。Verifier 审计 FAIL 时进入本流程。最多 5 轮，发散时提前升级人工。

---

## 决策：调用 `decideRepair()`

**`workflows/lib/decide-repair.js`** 根据 repair_history 自动判定：
- 输入: `{ repairRound, repairHistory, maxRounds: 5 }`
- 输出: `{ action: 'retry'|'escalate', reason, escalationType? }`

Orchestrator 根据 action 执行：
- `retry` → 执行下方修复派发
- `escalate` → 暂停，向用户呈现 reason + 完整修复历史

---

## 根因分析（Orchestrator 执行）

`[Orchestrator] Task-{N} 审计失败（轮次 {R}/5），执行根因分析`

从 Verifier 报告提取：错误类型 / 关键错误信息（前 2-3 条）/ 影响范围。
对比历史：失败数增减？错误类型变化？形成修复指导（根因假设 + 建议方向）。

---

## Worker 修复轮次指导

> 以下内容从 agents/worker.md 下沉。

当收到 Verifier 的失败报告进入修复轮次时：

1. **先读懂失败**：完整阅读 Verifier 的失败描述、复现步骤、期望vs实际
2. **定位根因**：不要只修表面症状，找到根本原因
3. **回归保护**：修复前先写一个能复现 bug 的测试，修复后确认该测试通过
4. **避免引入新问题**：修复后运行全量测试，确认无回归
5. **保留历史**：code-report 保存为 `WORKER-apply-code-report-r{N}.md`（不覆盖上轮），记录本轮修复了什么

---

## 修复派发

1. 快照当前 deliverables/{REQ-ID}/ 文件 hash，追加到 `.engine/.state.md` repair_snapshots
2. 更新 `.engine/.state.md`: repair_round={R+1}, repair_task=Task-{N}
3. 追加 repair_history 条目: `{ round, errorType, failedCount, summary, root_cause_hypothesis, action_taken }`
4. 写入新 handoff `.engine/handoffs/{REQ-ID}-DEV1-T{N}-R{R+1}.md`，含修复上下文:
   - 失败特征 / 根因假设 / 建议修复方向 / 历史尝试
   - 白名单追加 Verifier 失败报告路径
5. Worker 修复 → Verifier 重新审计
6. 通过 → 重置 repair_round=0, repair_task="", repair_history=[]

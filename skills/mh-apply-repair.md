# mh-apply: 修复循环（所有模式通用）

TE 审计 FAIL 时进入本流程。最多 5 轮，发散时提前升级人工。

---

## 决策：调用 `decideRepair()`

**`workflows/lib/decide-repair.js`** 根据 repair_history 自动判定：
- 输入: `{ repairRound, repairHistory, maxRounds: 5 }`
- 输出: `{ action: 'retry'|'escalate', reason, escalationType? }`

PM 根据 action 执行：
- `retry` → 执行下方修复派发
- `escalate` → 暂停，向用户呈现 reason + 完整修复历史

---

## 根因分析（PM 执行）

`[PM] Task-{N} 审计失败（轮次 {R}/5），执行根因分析`

从 TE 报告提取：错误类型 / 关键错误信息（前 2-3 条）/ 影响范围。
对比历史：失败数增减？错误类型变化？形成修复指导（根因假设 + 建议方向）。

---

## 修复派发

1. 快照当前 output/ 文件 hash，追加到 `.state.md` repair_snapshots
2. 更新 `.state.md`: repair_round={R+1}, repair_task=Task-{N}
3. 追加 repair_history 条目: `{ round, errorType, failedCount, summary, root_cause_hypothesis, action_taken }`
4. 写入新 handoff `handoffs/{REQ-ID}-DEV1-T{N}-R{R+1}.md`，含修复上下文:
   - 失败特征 / 根因假设 / 建议修复方向 / 历史尝试
   - 白名单追加 TE 失败报告路径
5. DE 修复 → TE 重新审计
6. 通过 → 重置 repair_round=0, repair_task="", repair_history=[]

# Skill: mh-run

全流程自动推进模式。PM 主导，一次性执行 clarify → propose → apply → archive，仅在人工审批节点暂停。

**日志规则：** 同各阶段 skill 定义，追加日志到 `deliverables/{REQ-ID}/process.log`

---

## 核心机制

**每个阶段步骤完成后，调用 `autoAdvance()`**（`workflows/lib/auto-advance.js`）：
- 输入: `{ phase, currentStep, mode, srStatus, repairRound, autoAdvance: true }`
- 输出: `{ action, nextPhase?, reason }`

| action | PM 行为 |
|--------|---------|
| advance | 打印推进心跳，读取 nextPhase skill 继续执行 |
| pause | 暂停等待用户决策 |
| end | 打印最终摘要，流程结束 |

在 `.state.md` 写入 `auto_advance: true` 用于断点恢复识别。

---

## 暂停点（脚本硬编码，所有模式通用）

- SR1/SR2/SR3/SR4 审批
- Batch 人工确认
- Proposal 确认 / 模式选择
- Wireframe 审批（ppt 模式）
- 修复循环发散或耗尽（由 `decideRepair()` 触发）

## 状态重置

`autoAdvance()` 返回 `stateResets` 字段时，PM 必须同步更新 `.state.md`：
- SR3-DONE → archive: 重置 `repair_round=0, repair_task=""`
- Fast 模式 apply 完成 → archive: 同上

## Fast 模式特殊行为

fast 模式下 `autoAdvance()` 自动跳过 SR1 和 SR4，仅保留 apply 阶段人工确认作为唯一审批点。

---

## 执行序列

1. **Init**: 写入 auto_advance=true → 执行 mh-clarify → INIT-DONE → advance
2. **Propose**: 执行 mh-propose → PROPOSE-DONE / SR1通过 → advance
3. **Apply**: 执行 mh-apply（人工审批照常暂停）→ SR3-DONE → advance
4. **Archive**: 执行 mh-archive → phase=done → end

---

## 断点恢复

重新 `/mh-run` 时检测 `auto_advance: true`，从 phase + current_step 恢复继续。

## 异常处理

- SubAgent status=failed → 修复循环内处理，不影响阶段间推进
- 修复发散/耗尽 → pause，用户解决后从当前位置继续
- 人工驳回 → 回退重新执行，完成后继续自动推进

---

## 最终摘要格式

```
══════════════════════════════════════
[/mh-run 全流程完成]
需求编号: {REQ-ID}
模式: {mode}
归档产物: output/
项目状态: DONE
══════════════════════════════════════
```

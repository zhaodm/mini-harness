# mh-apply: 修复循环（所有模式通用）

TE 审计 FAIL 时进入本流程。最多 5 轮，发散时提前升级人工。

---

## 根因分析（PM 执行）

PM 在派发修复前，必须基于 TE 报告进行根因分析：

1. `[PM] Task-{N} 审计失败（轮次 {R}/5），执行根因分析`
2. 读取 TE 报告，提取：
   - 失败特征：错误类型（test_failure / lint_error / build_error / logic_error）
   - 关键错误信息：具体的报错内容（前 2-3 条）
   - 影响范围：失败数量 / 总数量
3. 对比历史（如 repair_round > 1）：
   - 与上轮相比，失败数是增加还是减少？（收敛判断）
   - 错误类型是否变化？（新问题 vs 同一问题）
4. 形成修复指导：根因假设 + 建议修复方向

---

## 收敛追踪与提前升级

**调用 `workflows/lib/decide-repair.js` 的 `decideRepair()` 函数判断下一步动作：**
- 输入: `{ repairRound, repairHistory: [{round, errorType, failedCount}], maxRounds: 5 }`
- 输出: `{ action: 'retry'|'escalate', reason, escalationType? }`

脚本内置的升级条件（PM 无需自行判断）：
- 连续 2 轮 failed_count 增加（发散）→ 立即升级人工
- 连续 2 轮 error_type 变化（修一个坏一个）→ 立即升级人工
- 连续 3 轮同一错误且无进展（停滞）→ 升级人工
- 第 5 轮仍未通过（耗尽）→ 升级人工

更新 `.state.md` 中 repair_history（每轮追加）：
```yaml
repair_history:
  - round: 1
    error_type: "test_failure"
    failed_count: 3
    summary: "API endpoint 返回 500"
    root_cause_hypothesis: "UserService.create() 返回 null"
    action_taken: "修复 create() 返回值，确保返回 user 对象"
  - round: 2
    error_type: "test_failure"
    failed_count: 2
    summary: "修复了连接问题，仍有 2 个断言失败"
    root_cause_hypothesis: "返回值修复后，响应体序列化缺少 user_id 字段"
    action_taken: "补充响应体映射，确保包含 user_id"
```

**提前升级条件**已编码至 `decide-repair.js`，PM 根据返回的 `action` 字段执行：
- `action='retry'` → 继续修复派发
- `action='escalate'` → 立即暂停，呈现 `reason` 给用户

---

## 修复派发

> repair_snapshots 用途：PM 对比各轮 hash 确认产出物在变化；发散升级时附带快照历史让用户看到完整变化轨迹；如需回退可定位对应 code-report-r{N}.md。

1. 修复派发前，PM 执行快照：
   - 计算当前 output/ 的文件 hash（`find output/ -type f | xargs md5sum | md5sum`）
   - 将 hash 和当前 code-report 路径追加到 `.state.md` repair_snapshots
2. 更新 `deliverables/{REQ-ID}/.state.md`: repair_round={R+1}, repair_task=Task-{N}
3. 写入新 handoff: `deliverables/{REQ-ID}/handoffs/{REQ-ID}-DEV1-T{N}-R{R+1}.md`
   - 使用 handoff 模板中的"修复上下文"节，填写：
     - 失败特征：{错误类型 + 关键错误信息}
     - 根因假设：{PM 的分析}
     - 建议修复方向：{具体指导，不是"请修复"}
     - 历史尝试：{前几轮做了什么、为什么没成功}
   - 白名单追加：TE 的失败报告路径
4. `[PM] 派发修复给 DE（轮次 {R+1}/5，{收敛/发散}）`
5. DE 修复 → TE 重新审计
6. 审计通过:
   - 更新 `.state.md`: repair_round=0, repair_task="", repair_history=[]
7. 达到升级条件:
   - `[PM] Task-{N} 修复未收敛，上升人工审核`
   - 向用户呈现完整修复历史和失败模式

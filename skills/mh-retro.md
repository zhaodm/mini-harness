# Skill: mh-retro

需求执行复盘 + 变更请求生成。PM 主导，两阶段产出，确保"先诊断再开方"。

**日志规则：** 见 `templates/logging-standard.md`

---

## 触发条件

用户要求对已完成需求进行复盘/总结/改进分析时触发。

## 前置检查

1. 确认复盘目标（用户指定 REQ-ID 或产出路径）
2. 确认目标已完成（phase=done）
3. 创建 `docs/retrospectives/` 和 `docs/requirements/`（如不存在）

---

## Phase 1: 复盘报告

**产出:** `docs/retrospectives/improvement-report-{REQ-ID}.md`（纯事实，不含方案）

### RET-1: 数据采集

**调用 `retroCollect()`**（`workflows/lib/retro-collect.js`）：
- 输入: 从 .state.md / lessons.md / process.log / handoffs/ 读取的内容
- 输出: `{ metrics, problems: [{cpId, title, symptom, rootCause, impact}], dataSourcesCount }`

### RET-2~3: 执行概况 + 问题清单

基于 `retroCollect()` 输出生成：
- 执行概况表（mode / outputType / taskCount / repairRounds / srRejections / result）
- 问题清单（按时间编号，区分个案/系统性，标注 P0/P1/P2）

### RET-4: 历史 CR 效果验证

如有已实施的 CR，逐项验证本次执行中的效果（有效/无效+原因）。

### RET-5: 经验总结

从问题清单提炼 EXP-N 经验条目（来源 CP-N / 经验 / 适用场景）。

### RET-6: 改进方向概览

列出系统性问题的改进方向（1-2 句），**不展开方案**。

### RET-7: 写入与确认

组装文档 → 写入 → 向用户展示摘要 → **询问是否进入 Phase 2**。

⚠️ Phase 1 结束必须等用户确认才能进入 Phase 2。

---

## Phase 2: 变更请求（可选）

**产出:** `docs/requirements/CR-{NNN}-{slug}.md`（处方性文档）

### CR-1: 编号分配

扫描 `docs/requirements/` 最大 CR 编号 +1，提炼 slug。

### CR-2+3: 筛选 + 分层设计

**调用 `retroSynthesize()`**（`workflows/lib/retro-synthesize.js`）：
- 输入: `{ problems: [{cpId, title, severity, domain, isSystemic}] }`
- 输出: `{ recommendations: [{problemDomain, cpIds, layer, rationale, deliverables}], crSlug }`

PM 为每个 recommendation 补充具体改动描述。

### CR-4: 交付物汇总

按层级（脚本/模板/规则）汇总需修改的文件清单。

### CR-5: 写入与确认

组装 CR 文档（头部格式: `# CR-{NNN}: {标题}` + `> 来源/日期/状态: 待实施`）→ 写入 → 向用户展示摘要 → 询问是否立即实施。

---

## 关键纪律

1. Phase 1 和 Phase 2 分文件产出
2. Phase 1 完成后必须等用户确认
3. 复盘报告不含解决方案
4. CR 通过 CP-N 编号引用 Phase 1（不重复内容）
5. 方案遵循"脚本 > 模板 > Skill > NL"层级

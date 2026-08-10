# 复盘报告模板

> 按 `tools/mh-dev/agents/retrospector.md` 的 Phase 6 产出。

## §1 周期基本信息

| 字段 | 值 |
|------|-----|
| REQ-ID | MHDEV-NNN |
| Track | fast / light / formal |
| 轨道升级 | N 次 |
| Repair 轮次 | N |
| 总执行时长 | <时长> |
| 最终状态 | archive / done / blocked |

---

## §2 交付件完整性

| 阶段 | 预期产出 | 实际产出 | 状态 |
|------|---------|---------|------|
| propose | requirement.md | <存在/缺失> | PASS/FAIL |
| propose | acceptance-criteria.json | <存在/缺失> | PASS/FAIL |
| develop | change-attribution.developer.N.json | <存在/缺失> | PASS/FAIL |
| verify | change-attribution.tester.N.json | <存在/缺失> | PASS/FAIL |
| verify | test-verdict.json | <存在/缺失> | PASS/FAIL |
| audit | semantic-verdict.json | <存在/缺失> | PASS/FAIL |
| release | release-manifest.json | <存在/缺失> | PASS/FAIL |

---

## §3 度量分析

### §3.1 瓶颈识别

| 阶段 | 耗时 | 占比 | 标记 |
|------|------|------|------|
| propose | <时长> | N% | |
| develop | <时长> | N% | |
| verify | <时长> | N% | |
| audit | <时长> | N% | |

### §3.2 修复循环分析

- 总 repair.round: N
- repair.reason: <原因分类>
- 集中阶段: <develop/verify/audit>

### §3.3 轨道升级分析

- 升级次数: N
- 升级原因: <GOVERNANCE_PATH / DOC_SYNC / ...>

---

## §4 状态一致性

| 对比项 | 来源 A | 来源 B | 结论 |
|--------|--------|--------|------|
| 阶段状态 | state.json phase | phase_timestamps | 一致/不一致 |
| 验收结论 | test-verdict.json verdict | state.json test_verdict | 一致/不一致 |
| 审计结论 | semantic-verdict.json verdict | state.json semantic_audit | 一致/不一致 |
| 归属路径 | change-attribution changed | release-manifest worktree_changes | 一致/不一致 |

---

## §5 经验沉淀

| 经验类型 | 是否记录 | 评价 |
|---------|---------|------|
| 修复根因 | 是/否 | |
| 轨道升级原因 | 是/否 | |
| AX 失败模式 | 是/否 | |
| 审计发现 | 是/否 | |
| 度量消费 | 是/否 | |

---

## §6 流程质量

### §6.1 归属链路完整性

- 每轮 Developer/Tester 是否有对应归属证据: 是/否
- 归属证据 result 是否全为 PASS: 是/否
- 失败归属是否未晋升为可信基线: 是/否

### §6.2 门禁有效性

- transition-state.sh 是否每次先调用 check-transition.sh: 是/否
- precondition-check.sh 是否在 develop 前执行: 是/否
- release-candidate.sh 是否要求所有门禁 PASS: 是/否

### §6.3 上下文膨胀评估

- 各角色协议行数: developer=N, tester=N, auditor=N, retrospector=N
- 与变更规模匹配度: <评价>

---

## §7 改进建议

| 优先级 | 建议 | 预期效果 | 目标文件 |
|--------|------|----------|----------|
| P1 | <建议> | <效果> | <文件> |
| P2 | <建议> | <效果> | <文件> |

---

## §8 正面发现

- <好的实践，值得保持>

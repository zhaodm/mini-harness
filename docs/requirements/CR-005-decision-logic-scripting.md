# CR-005: 决策逻辑全面脚本化

> 来源: CR-004 实施后的持续改进
> 日期: 2026-06-09
> 状态: 待实施
> 优先级: P0
> 关联: CR-003（脚本硬约束原则）, CR-004（混合架构基础设施）

---

## 执行摘要

CR-004 完成了编排调度层（propose/apply 并行执行）的脚本化，但 skills/*.md 中仍有大量决策逻辑以自然语言形式约束 PM 行为。本 CR 将所有可确定性化的决策逻辑提取为纯函数 JS 模块，彻底贯彻"能用脚本阻止的，不靠文字描述"原则。

## 问题陈述

### 当前状态

| 阶段 | NL 约束行数 | 已脚本化 | 决策逻辑类型 |
|------|------------|---------|-------------|
| clarify | 248 lines | 0% | 场景检测、类型/模式推荐 |
| apply | 205 lines | 35% | 批次计算、修复决策 |
| archive | 236 lines | 10% | 归档模式检测、merge 策略 |
| retro | 278 lines | 5% | 数据聚合、约束层决策 |
| run | 160 lines | 20% | 状态机推进 |

### 核心问题

1. **场景检测不一致**: RESUME/CHANGE/NEW 判断依赖 PM "理解" 4 条规则，曾出现 phase=done 误判为 NEW
2. **批次计算无保证**: 拓扑排序+贪心分组靠自然语言描述，PM 偶尔错排依赖
3. **修复循环失控**: 收敛追踪规则（发散/抖动/耗尽）由 PM 自行判断，曾遗漏 repair_round 更新
4. **归档 merge 不确定**: REQ-ID 标签定位+追加/替换/废弃规则复杂，纯文字描述易出错
5. **retro 数据聚合低效**: PM 手动读取 5+ 文件并汇总指标，容易遗漏数据源
6. **状态机推进不可靠**: 哪些事件自动推进、哪些暂停，散落在 40 行表格中

## 需求定义

### 功能需求

| ID | 需求 | 优先级 | 对应脚本 |
|----|------|--------|---------|
| F-1 | 场景检测：根据 .state.md + output/spec/ 判断 NEW/RESUME/CHANGE | P0 | detect-scenario.js |
| F-2 | 批次计算：拓扑排序 + 贪心合并 | P0 | calculate-batches.js |
| F-3 | 修复决策：收敛追踪 + 提前升级判断 | P0 | decide-repair.js |
| F-4 | 归档模式检测：首次/变更 + baseline 版本管理 | P0 | detect-archive-mode.js |
| F-5 | 产品类型/模式推荐：tech_stack → 决策树 | P1 | recommend-type-mode.js |
| F-6 | 归档合并：REQ-ID 标签定位 + 追加/替换/废弃 | P1 | archive-merge.js |
| F-7 | 复盘数据采集：多文件聚合 → 结构化指标 | P1 | retro-collect.js |
| F-8 | 复盘约束层决策：问题分类 → 脚本/模板/Skill/NL 推荐 | P1 | retro-synthesize.js |
| F-9 | 状态机推进：事件 + 模式 → 动作(advance/pause/end) | P1 | auto-advance.js |

### 非功能需求

| ID | 需求 |
|----|------|
| NF-1 | 所有脚本为纯函数，不含 I/O（文件读取由调用方完成后传入） |
| NF-2 | 零外部依赖，仅 Node.js built-in |
| NF-3 | ES module 格式，附带 JSDoc 类型注释 |
| NF-4 | 每个脚本对应独立测试文件，≥6 个测试用例 |
| NF-5 | 兼容现有 .state.md schema 和 deliverables/ 目录结构 |
| NF-6 | 测试驱动开发：先写测试（红），再实现（绿） |

### 约束

- 不修改 agents/*.md（角色契约保持 NL 驱动）
- 不修改 scripts/verify*.sh（硬验证层独立）
- 不修改 .state.md schema（兼容现有恢复机制）
- Skills 中人机交互逻辑保留为 NL（SR审批、proposal refinement）

## 验收标准

1. 9 个 lib/ 纯函数模块全部实现，JSDoc 完整
2. 9 个对应测试文件全部通过（≥82 个 assertions）
3. run-all-tests.sh 集成全部新测试，总体 PASS
4. Skills 中决策逻辑替换为脚本调用指针（行数减少 ≥40%）
5. 现有 verify*.sh 全部 PASS（无回归）
6. docs/workflow.md 更新，包含全部新脚本参考

## 技术设计概要

### 架构

```
skills/*.md (NL: 人机交互 + 质量判断)
    ↓ 调用
workflows/lib/*.js (纯函数: 决策逻辑)
    ↑ 测试
tests/test-*.js (TDD 验证)
```

### 函数签名规范

所有函数接收一个 options 对象，返回一个 result 对象：

```javascript
/**
 * @param {DetectScenarioInput} input
 * @returns {DetectScenarioResult}
 */
export function detectScenario(input) { ... }
```

### 测试规范

复用 CR-004 建立的测试模式（无框架、assert 函数、颜色输出、exit code）。

## 实施计划

Phase 1 (Tier 1): detect-scenario + calculate-batches + decide-repair + detect-archive-mode
Phase 2 (Tier 2 前): recommend-type-mode + archive-merge
Phase 3 (Tier 2 后): retro-collect + retro-synthesize
Phase 4 (Tier 3): auto-advance
Phase 5: 集成 + 文档 + Skills 精简

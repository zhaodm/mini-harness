# CR-006: TE Code Review 强化 + 测试用例沉淀机制

> 来源: 流程复盘 — PM 承担过多验收职责，测试用例缺乏持久化和回归保障
> 日期: 2026-06-10
> 状态: 待实施
> 优先级: P0
> 关联: CR-001（验证规划）, CR-004（TE 并行审计基础设施）
> 设计原则: **脚本硬约束优先于自然语言软约束；复用已有模块优先于新建**

---

## 执行摘要

当前框架中 TE 角色聚焦于"跑测试 + 出报告"，缺乏对代码质量的结构化评审能力；同时测试用例仅存在于单次 REQ 生命周期内（`te/testcases.md`），未形成跨 REQ 持久化的回归套件。本 CR 解决两个问题：

1. **TE 增加 Code Review 职责** — 审计时同步做代码质量评审，发现结构性问题
2. **测试用例沉淀 + 全量回归机制** — 每次变更的用例持久化为回归套件，后续所有变更必须通过全量回归

---

## 问题陈述

### 问题 1: Code Review 缺位

| 现状 | 影响 |
|------|------|
| TE 只验证"功能是否工作" | 代码命名混乱、重复逻辑、安全漏洞等结构性问题无人把关 |
| PM 质量门禁只检查"结构完整性" | 无法深入代码质量判断（PM 铁律②禁止做技术判断） |
| DE dev-test 中 lint 仅检查语法 | lint 无法覆盖设计层面的质量问题（过长函数、职责混乱） |

### 问题 2: 测试用例无持久化

| 现状 | 影响 |
|------|------|
| `te/testcases.md` 随 REQ 生命周期结束即归档 | 下一个 REQ 对同项目的修改无法保障兼容性 |
| 修复轮次虽要求"全量回归"，但回归范围仅限当前 REQ 的用例 | 跨 REQ 的功能破坏无法检测 |
| 归档阶段仅搬运 spec，不搬运测试用例 | 项目知识中"如何验证"的部分持续丢失 |

---

## 需求定义

### 功能需求

| ID | 需求 | 优先级 |
|----|------|--------|
| F-1 | TE 审计时执行 Code Review，输出结构化评审结论 | P0 |
| F-2 | Code Review 发现 Critical 级问题时触发 FAIL | P0 |
| F-3 | 归档阶段将 testcases.md 沉淀到持久化回归套件 | P0 |
| F-4 | TE 最终审计时执行全量回归套件（如存在） | P0 |
| F-5 | 回归套件按 REQ 分组、按优先级索引、支持去重 | P1 |
| F-6 | fast 模式下 Code Review 降级为关键路径抽查，但回归不降级 | P1 |
| F-7 | verify-qa.sh 新增回归覆盖硬校验 | P1 |

### 非功能需求

| ID | 需求 | 优先级 |
|----|------|--------|
| NF-1 | Code Review 不增加额外 SubAgent 调用（复用 TE 审计 agent） | P0 |
| NF-2 | 回归套件单文件，避免碎片化 | P1 |
| NF-3 | 兼容所有 output_type（非代码类项目 Code Review 自动跳过） | P1 |

---

## 已有模块复用分析

实施前对已有基础设施逐项评估，避免重复造轮子：

| 新需求 | 已有模块 | 决策 | 理由 |
|--------|---------|------|------|
| 回归套件用例追加/去重 | `archive-merge.js` (REQ-ID 标签 append/replace) | **复用** | 标签段定位+追加策略完全匹配 |
| Code Review 维度路由（按 mode/output_type） | `recommend-type-mode.js` (output_type 路由) | **扩展** | 已有类型路由基础，新增 `deriveReviewScope()` |
| TE 报告结果判定 | `result-parser.js` (提取 PASS/FAIL) | **扩展** | 新增 `extractReviewVerdict()` |
| 报告格式校验 | `verify-qa.sh` (11 个检查框架) | **扩展** + 新建 | QA-12/13 扩展 + 独立 `verify-code-review.sh` |
| TE 审计 Workflow 编排 | `apply-batch-test.js` / `apply-final-audit.js` | **不变** | prompt 内容更丰富即可，编排逻辑不动 |

---

## 影响范围

### 需新建文件（4 个脚本/模块 + 1 个模板 + 3 个测试）

| 文件 | 类型 | 职责 |
|------|------|------|
| `workflows/lib/code-review-rules.js` | JS 纯函数 | Code Review 维度/阈值/路由/格式校验规则 |
| `workflows/lib/regression-suite.js` | JS 纯函数 | 回归套件解析/追加/去重/索引重建（复用 archive-merge） |
| `scripts/verify-code-review.sh` | Shell 脚本 | Code Review 报告格式硬校验（CR-1~5） |
| `templates/regression-suite-template.md` | Markdown 模板 | 回归套件初始结构 |
| `tests/test-code-review-rules.js` | 单测 | code-review-rules.js 纯函数测试 |
| `tests/test-regression-suite.js` | 单测 | regression-suite.js 纯函数测试 |
| `tests/test-verify-code-review.sh` | 集成测试 | verify-code-review.sh 各场景测试 |

### 需扩展文件（2 个 JS 模块 + 1 个 Shell）

| 文件 | 变更 |
|------|------|
| `workflows/lib/recommend-type-mode.js` | 追加 `deriveReviewScope()` 导出函数 |
| `workflows/lib/result-parser.js` | 追加 `extractReviewVerdict()` 导出函数 |
| `scripts/verify-qa.sh` | 新增 QA-12（回归覆盖）+ QA-13（沉淀完整性） |

### 需更新文档（6 个）

| 文件 | 变更类型 | 变更内容 |
|------|---------|---------|
| `agents/te.md` | 增强 | 新增 Code Review + 回归执行章节（引用脚本，非 NL 规则） |
| `agents/pm.md` | 小幅更新 | TE 质量门禁新增 3 项脚本校验引用 |
| `CLAUDE.md` §4 | 追加规则 | 脚本硬约束条目（指向具体脚本） |
| `skills/mh-apply-standard.md` | 补充 | handoff 注入 review_scope + regression_suite_exists |
| `skills/mh-apply-fast.md` | 补充 | handoff 注入 review_scope + 回归不降级 |
| `skills/mh-archive.md` | 新增步骤 | ARC-5 调用 regression-suite.js 沉淀用例 |

### 不变更文件

- `role-guard.sh` — TE 写入权限已覆盖 `te/` 目录
- `workflows/apply-*.js` — 编排逻辑不变，TE prompt 内容更丰富即可
- `templates/handoff-template.md` — handoff 格式不变

---

## 验收标准

### 脚本层验收（硬约束，退出码为准）

- [ ] `verify-code-review.sh` 对合规报告返回 exit 0
- [ ] `verify-code-review.sh` 对缺少 Code Review 章节的报告返回 exit 1
- [ ] `verify-qa.sh QA-12`: 回归套件存在时，报告缺少回归章节 → exit 1
- [ ] `verify-qa.sh QA-13`: 归档阶段 testcases 存在但未沉淀 → exit 1
- [ ] `tests/test-code-review-rules.js` 全部通过
- [ ] `tests/test-regression-suite.js` 全部通过
- [ ] `tests/test-verify-code-review.sh` 全部通过

### 功能层验收

- [ ] `deriveReviewScope('fast', 'web-app')` 返回仅 security + error-handling 两个维度
- [ ] `deriveReviewScope('standard', 'documentation')` 返回 skip=true
- [ ] `aggregateToSuite()` 对同 REQ 二次调用执行 replace（去重而非重复追加）
- [ ] 首次 REQ 归档后 `output/tests/regression-suite.md` 自动生成
- [ ] 第二次 REQ 的 TE 报告包含回归测试章节 + 回归判定
- [ ] Code Review Critical > 0 时 TE 报告整体 FAIL
- [ ] fast 模式下回归不降级（全量执行）

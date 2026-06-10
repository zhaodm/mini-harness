# Changelog

## [0.8.0] - 2026-06-10

CR-006: TE Code Review 强化 + 测试用例沉淀机制 — 脚本化优先，复用已有模块。

### 核心新增

- **workflows/lib/code-review-rules.js**: Code Review 规则引擎（7 维度定义 + getReviewScope 路由 + validateReviewReport 格式校验 + determineVerdict 判定）
- **workflows/lib/regression-suite.js**: 回归套件管理引擎（parseTestcases 解析 + aggregateToSuite 追加/去重 + validateSuiteIntegrity + getSuiteStats），复用 archive-merge.js 标签策略
- **scripts/verify-code-review.sh**: Code Review 报告格式硬校验（CR-1~5 检查项，替代 PM 自然语言判断）
- **templates/regression-suite-template.md**: 回归套件空模板（按 REQ 分组 + 优先级索引）

### 扩展

- **workflows/lib/recommend-type-mode.js**: +`deriveReviewScope(mode, outputType)` — Code Review 范围路由，复用已有 output_type 分发逻辑
- **workflows/lib/result-parser.js**: +`extractReviewVerdict()` + `extractRegressionVerdict()` — 从 TE 输出提取 Code Review 和回归判定
- **scripts/verify-qa.sh**: +QA-12 回归套件覆盖校验 + QA-13 归档用例沉淀完整性校验

### 文档更新

- **agents/te.md**: +Code Review 职责章节（引用脚本而非 NL 规则）+ 回归测试执行章节 + PASS/FAIL 条件更新 + 3 条新反模式
- **agents/pm.md**: TE 质量门禁 +3 项脚本校验引用（verify-code-review.sh / QA-12 / QA-13）
- **skills/mh-apply-standard.md**: 最终审计 handoff 注入 review_scope + regression_suite_exists
- **skills/mh-apply-fast.md**: 轻量审计注入 review_scope + 回归不降级
- **skills/mh-archive.md**: +ARC-5 测试用例沉淀步骤（调用 regression-suite.js aggregateToSuite）
- **CLAUDE.md §4**: 交付判定升级为五层校验 + 6 条脚本硬约束规则

### 测试

- **tests/test-code-review-rules.js**: 43 assertions — 维度结构、路由正确性、格式校验、判定逻辑
- **tests/test-regression-suite.js**: 45 assertions — 解析、首次创建、追加、去重、完整性校验、统计
- **tests/test-verify-code-review.sh**: 10 scenarios — 类型跳过、合规通过、各检查项失败
- **tests/run-all-tests.sh**: 注册 3 个新测试套件，全量 15 套件 298 assertions 通过

### 设计决策

- Code Review 维度从 NL 描述变为 JS 结构化数据，TE 和校验脚本共享同一数据源
- 回归套件管理复用已有 archive-merge.js 的 REQ-ID 标签 append/replace 策略
- PM 质量门禁从"人工逐项对照"变为"引用脚本退出码"
- fast 模式下 Code Review 降级为抽查，但回归不降级（兼容性底线）
- deriveReviewScope 放在已有 recommend-type-mode.js 中扩展，避免重复路由逻辑

---

## [0.7.0] - 2026-06-08

CR-003: 基于 REQ002 实战复盘的框架改进 — 脚本硬约束替代自然语言软约束。

### 核心新增

- **scripts/role-guard.sh**: PreToolUse Hook，实时阻止角色越权文件写入（PM/DE/SA/BA/TE/UX 各有路径白名单）
- **templates/quality-gate-report-template.md**: 质量门禁失败归因报告模板（错误清单+归因Task+集成问题）

### 增强

- **scripts/verify-archive.sh**: .archiveignore 校验从 INFO 升级为 FAIL；新增目录模式(-path)支持；新增 ARC-5 REQ-ID 目录隔离检查
- **templates/handoff-template.md**: 新增环境限制/执行前必读文件/Token预算参考/期望输出路径自检 4 个结构化字段
- **.claude/settings.json**: 配置 PreToolUse Hook（Write|Edit → role-guard.sh）
- **CLAUDE.md**: +2行指针（§2 指向 role-guard.sh，§4 指向 quality-gate-report-template）

### 设计决策

- 拒绝用自然语言膨胀 CLAUDE.md/skills/agents（CR-001 证明无效）
- 所有关键约束通过 Hook（实时阻止）或脚本（FAIL阻塞）落地
- CLAUDE.md 仅加指针，不复述脚本逻辑

### 数据基础

- REQ002 实战：15 Task / 3 Batch / ~4h / PM 两次越权 / SR4 被驳回 2 次 / .archiveignore 存在但未执行
- CR-001-E（自然语言"禁止越权"）REQ002 中失败，证明需升级到 Hook 层

---

## [0.6.1] - 2026-06-01

上下文效率优化 — 减少 PM 运行时噪音，修复文档不一致。

### 核心改进

- **mh-apply.md 拆分**: 328行单文件拆为 4 个文件（主文件 45行 + fast 65行 + standard 167行 + repair 70行），PM 按模式按需加载
- **PM 运行时负载**: standard/full apply 阶段从 487行降到 371行（-24%），fast 模式降到 269行
- **mh-clarify.md 环境预检压缩**: 逐语言枚举改为原则性指引（256→237行）
- **mh-run.md 表格合并**: "推进触发条件"+"停止条件枚举"合并为统一流程控制表（167→158行）

### 新增

- **跨 REQ 增量开发场景**: mh-clarify.md CHANGE 模式增加增量开发子场景（output/ 已有代码时的白名单和回归策略）
- **Proposal 格式增强**: 增加"功能模块"字段，提升起点质量
- **Batch 并行策略说明**: mh-apply-standard.md 明确 Batch 原子性设计选择及理由

### 修复

- **source-of-truth.md**: 修复引用已删除文件（pm-dispatch-protocol.md → agents/pm.md）
- **design.md §10**: 增加状态列（done/planned），标记已实现的演进方向
- **verify.sh C 类**: 增加 output_files 非空检查（补全 handoff 回报检测）

---

## [0.6.0] - 2026-06-01

数据驱动优化 — 基于 REQ001 实战数据修复执行层缺陷。

### 核心改进

- **Handoff 完成回报强制机制**: 模板增加醒目强制提示 + PM 代填逻辑（回报缺失时根据产出物推断）+ verify.sh C 类检查
- **process.log 强制落盘**: logging-standard.md 增加强制写入规则 + 最低行数要求 + verify.sh 检查
- **SR3 覆盖率标准弹性化**: 从"100%"改为"≥95% + 降级确认"，决策上下文卡增加降级项确认区域
- **归档排除规则**: mh-archive.md ARC-3 增加 .venv/node_modules/__pycache__/ 等排除列表 + verify.sh B 类检查

### 新增

- **Agent 超时处理规则**: 超时+产出完整=成功，PM 代填 code-report
- **code-report 独立规则**: 并行批次中每个 Task 独立 code-report，禁止合并
- **DE 超时保底行为**: 优先确保 code-report 已写入
- **docs/v0.6.0-optimization-report.md**: 完整的问题分析+改善措施+metrics 设计思路文档

### 数据基础

- 首次实战数据: REQ001（PSDT-Agent 框架，full 模式，43分钟，14 Task，326测试 100%通过）
- 核心发现: 设计层运转良好，执行层存在"说到没做到"问题

---

## [0.5.5] - 2026-06-01

Metrics 集成到运行时 + 重复变量声明修复。

### 改进

- **mh-archive.md**: 新增 ARC-4 步骤（PM 在 SR4 前根据 .state.md 数据生成 metrics.md）
- **source-of-truth.md**: 新增 metrics-template 权威源映射
- **verify.sh**: 删除 check_e 中重复的 `local handoff_dir` 声明

---

## [0.5.4] - 2026-06-01

维护纪律修复 + 运行时指标收集 + 架构演进阈值。

### 修复

- **verify.sh E 类检查**: 删除 ~30 行无效 N² 循环（检测了不报告），替换为 15 行实用版本（检查 TE handoff 是否包含 design.md + output/）
- **CHANGELOG 停更**: 补写 v0.5.0-v0.5.3 记录

### 新增

- **templates/metrics-template.md**: PM 在 archive 阶段自动生成执行指标（耗时、驳回次数、修复轮次、SR 审批、断点恢复）
- **design.md §10**: 新增脚本拆分阈值（verify.sh > 500 行触发拆分）和 PM 上下文监控（固定负载 > 800 行触发精简）

### 变更

- **docs/source-of-truth.md**: 明确定位为"人类维护者手册"，非运行时文件
- **清理 .claude/plans/**: 删除 8 个历史计划文件（~806 行），git log 已记录变更历史

---

## [0.5.3] - 2026-06-01

残留问题修复轮。

### 修复

- **mh-apply.md**: 修复修复循环步骤编号重复（两个"2."→正确 1-5 序号）
- **mh-apply.md**: repair_history 示例补充 root_cause_hypothesis + action_taken 字段（AI 跟示例不跟规则）
- **mh-apply.md**: 补充 repair_snapshots 用途说明（3 条：回退基线、对比分析、收敛判断）
- **verify.sh E 类**: 新增上下游白名单对齐检查（TE handoff 是否引用 output/）
- **source-of-truth.md**: 新增 repair_history/repair_snapshots 权威源映射条目

### 变更

- **design.md §10**: Skill 拆分阈值从 300→350 行（mh-apply 319 行含 3 模式+修复+SR 门禁，合理）

---

## [0.5.2] - 2026-05-31

架构优化轮 — 消除结构性冗余，增强运行时验证。

### 核心改进

- **pm.md 合并 dispatch protocol**: 从独立文件合并到 agents/pm.md，减少 PM 运行时文件数
- **design.md 瘦身**: 513→185 行，从"百科全书"转型为"架构地图"（索引+指向权威源）
- **verify.sh E 类**: 新增白名单文件存在性检查 + phase-file 一致性检查
- **handoff-template.md**: 新增 read_files 字段（完成报告中列出实际读取的文件）
- **state-template.md**: 新增 task_started_at 字段（支持任务超时检测）

### 新增

- **docs/source-of-truth.md**: 权威源映射表 + 三层一致性保障 + 冲突解决规则
- **verify.sh D 类**: 新增 TODO 残留检测 + 任务超时检测

### 删除

- **templates/pm-dispatch-protocol.md**: 内容已合并到 agents/pm.md

---

## [0.5.1] - 2026-05-31

冗余消除 + PM 上下文减压。

### 修复

- **Skills 质量门禁冗余**: 从逐条展开（4x 冗余）恢复为简洁引用（"验收标准见 pm.md §质量门禁"）
- **pm.md 头部标注**: 明确运行时读取范围（本文件 + 当前 skill + .state.md + handoff），不读 design.md

### 变更

- **agents/*.md 禁止事项**: 精简为角色特有条目 + "通用禁止事项见 CLAUDE.md §2-4"

---

## [0.5.0] - 2026-05-31

全面重构 — 参考 ref-design.md 架构，重建设计体系。

### 核心改进

- **design.md 重构**: 按 ref-design 目录结构重组（10 章节），保留 v0.4.x 优化成果
- **PM 六条铁律**: 提炼 PM 运行时最高约束（不跳步、不越权、不盲批、不丢状态、不超限、不放行）
- **决策上下文卡**: 所有 SR 节点标准化（风险评估 + 变更摘要 + PM 建议 + 回退方案）
- **修复收敛增强**: repair_snapshots + repair_history（含 root_cause_hypothesis）+ 收敛/发散判断

### 新增

- **templates/examples/**: 5 个金标准示例（requirement-spec, design, code-report, test-report, repair-context）
- **templates/output-guides/**: 3 个产出结构参考（web-app, backend-api, cli-tool）

### Agent 变更

- 所有角色注入思考框架 + 质量标准 + 反模式 + 交付自检
- PM 注入质量门禁（BA/SA/DE/TE/UX 各有验收清单）+ 驳回标准

---

## [0.4.2] - 2026-05-31

金标准示例 + 编排质量 + 文档同步 + output_type 结构参考。

### 核心新增

- **金标准示例**: 新增 `templates/examples/` 目录，BA/SA/DE/TE 各一个精心打磨的产出示例，SubAgent 可参考
- **编排质量标准**: PM 编排 plan-action.md 时增加粒度/依赖/完整性/可验证性自检
- **output_type 结构参考**: 新增 `templates/output-guides/`，web-app/backend-api/cli-tool 各一个产出结构指南

### 文档同步

- **docs/design.md**: 新增质量保障机制、修复收敛机制、审批决策上下文章节
- **CHANGELOG.md**: 补充 v0.3.2/v0.4.0/v0.4.1 变更记录

---

## [0.4.1] - 2026-05-31

效率提升 + 修复收敛 + 决策质量优化。

### 核心改进

- **Handoff 模板精简**: 69→48 行，示例移到独立文件，新增修复上下文节
- **审批决策上下文**: 所有审批节点增加风险评估、变更摘要、PM 建议
- **修复收敛机制**: 根因分析 + 结构化修复上下文 + repair_history 追踪 + 提前升级条件
- **verify.sh D 类检查**: 新增修复耗尽/handoff 超时/状态一致性/TODO 残留检测
- **Fast 模式轻量化**: dev-test 快速路径（跳过 lint/构建），TE 轻量验证

### 模板变更

- **handoff-template.md**: 精简 + 新增"修复上下文"节
- **handoff-examples.md**: 新建，存放回报格式示例
- **state-template.md**: 新增 repair_history 字段

---

## [0.4.0] - 2026-05-31

质量驱动重构 — 注入思考框架、质量标准、反模式到所有 Agent。

### 核心改进

- **PM 质量门禁**: 从"文件存在性检查"升级为"内容质量门禁"（BA/SA/DE/TE/UX 各有验收清单）
- **思考框架**: 每个角色增加"动笔前按什么顺序思考"的指导
- **反模式清单**: 每个角色增加"必须避免"的常见低质量输出特征
- **交付自检**: 每个角色增加提交前的内容质量 checklist
- **驳回标准**: PM 明确定义何时驳回、驳回时附带什么信息

### Agent 变更

- agents/pm.md: +质量门禁 +驳回标准
- agents/ba.md: +思考框架 +质量标准 +反模式 +交付自检
- agents/sa.md: +思考框架 +Task拆分原则 +质量标准 +反模式 +交付自检
- agents/de.md: +思考框架 +质量标准 +反模式 +修复轮次指导 +交付自检
- agents/te.md: +思考框架 +PASS/FAIL标准 +严重程度定义 +反模式 +交付自检
- agents/ux.md: +思考框架 +质量标准 +反模式 +交付自检

### Skill 变更

- skills/mh-propose.md: PM 验收升级为质量门禁
- skills/mh-apply.md: PM 验收升级为质量门禁

---

## [0.3.2] - 2026-05-31

消除文档冗余，提取日志规则，清理历史遗留。

### 删除

- `templates/ppt-templates/act-files/` (30MB 二进制样本)
- `reference/ppt-demo/` (空目录)

### 精简

- **.clinerules**: 103→35 行，删除与 CLAUDE.md 重复的 §1-6，仅保留 Cline 特有内容
- **docs/workflow.md**: 297→195 行，删除通用规则文字段，保留图表
- **README.md**: 删除末尾重复规则段，修正"五个"→"六个"角色

### 新增

- **templates/logging-standard.md**: 日志规则单一真相源，7 个 skill 文件改为引用

---

## [0.3.1] - 2026-05-29

框架一致性优化、状态 schema 完善、并行执行增强。

---

## [0.3.0] - 2026-05-27

框架泛化改造：从 Web/JavaScript 专用升级为格式无关的通用研发执行框架。

### 核心新增

- **output_type 体系**: 新增产出类型概念（web-app/backend-api/cli-tool/data-pipeline/infrastructure/documentation/ppt/library/custom），与 mode 正交，驱动全流程适配
- **test_strategy 机制**: TE 验证方式由 test_strategy 参数驱动（e2e/unit/integration/smoke/manual/none），替代原有的 browser_available 二分逻辑
- **多语言环境检测**: 支持 Python/Node.js/Go/Rust/Java 自动检测（语言、包管理器、测试框架、构建工具、lint 工具）
- **UX 角色**: 新增泛化设计师角色（agents/ux.md），根据 output_type 产出不同设计制品（UI wireframe / API 设计文档 / 数据流图 / 架构拓扑图等）

### 流程变更

- **mh-clarify**: 新增"产出类型选择"步骤（Step 3），环境预检泛化为多语言检测
- **mh-apply**: TE 派发逻辑改为 test_strategy 路由
- **mh-archive**: ARC-3 步骤增加 output_type 感知归档策略
- **mh-ppt**: 重构为主流程补充规则，/mh-ppt 作为 output_type=ppt 的快捷入口

### 技术改进

- **dev-test.md**: 完全重写，按 tech_stack.language 路由测试/lint/构建命令
- **verify.sh**: check_b() 增加 output_type 和 test_strategy 感知，动态校验产出物
- **handoff 模板**: 新增 output_type 和 tech_stack 字段
- **.state.md schema**: 新增 output_type、tech_stack（对象）、test_strategy 字段

### 角色变更

- 新增 UX 角色（agents/ux.md），承担泛化设计职责（原 v0.1.0 无设计角色）
- 角色隔离规则更新为六角色（PM/BA/SA/DE/TE/UX）

### 命名变更

- /pdt-init → /mh-clarify
- /pdt-propose → /mh-propose
- /pdt-apply → /mh-apply
- /pdt-archive → /mh-archive
- /pdt-run → /mh-run
- /ppt-dev → /mh-ppt

---

## [0.2.0] - 2026-05-20

十项结构性优化，修复三轮实际使用（REQ001-REQ003）中暴露的问题。

### 基础设施修复

- **Handoff 模板迁移**: `deliverables/handoffs/.handoff-template.md` → `templates/handoff-template.md`，消除运行时目录与模板混放
- **verify.sh 重写**: 支持 REQ-ID 参数化、mode 感知检查、修复 macOS bash 3.2 兼容性
- **check-harness.sh 修复**: 移除旧的运行时目录检查，新增 templates/ 检查
- **baseline.sh 修复**: 路径适配 REQ-ID 隔离模式

### 路径一致性

- 所有 agent 定义文件（ba/sa/de/te/pm.md）路径统一加 `{REQ-ID}/` 前缀
- `.gitignore` 精简，移除旧扁平路径规则，新增 MCP 自动生成目录屏蔽
- README.md 路径表更新

### Skill 功能增强

- **mh-run**: 新增 fast 模式连续流（propose→apply→archive 自动串联，仅一个人工确认点）
- **mh-archive**: 新增变更归档 Merge 策略（REQ-ID 标注、段落替换、DEPRECATED 标记）
- **mh-clarify**: 新增环境预检（Node.js 版本、浏览器可用性检测，写入 .state.md env 字段）
- **mh-propose**: standard 模式 SA handoff 约束新增需求映射简表要求
- **mh-apply**: 新增浏览器降级逻辑（env.browser_available=false 时跳过 E2E，标注 DEGRADED）

### Agent 定义更新

- **te.md**: E2E 从硬性阻塞改为降级条件（优先真实浏览器，不可用时降级并标注）
- **sa.md**: 输出格式新增"需求映射简表"（standard 模式必填）

### 文档精简

- **docs/workflow.md**: 834 行 → 288 行，删除与 skills/*.md 重复的详细执行序列，替换为索引表
- **docs/design.md**: 新增 §8-§12（执行模式、环境预检与降级、归档 Merge 策略、Token 节流、日志规范）
- **CLAUDE.md**: 新增项目描述、角色速查表、命令速查表，保持 < 80 行

### 日志与恢复

- 统一日志格式: `[{timestamp}] [{角色}] {事件描述}`，时间戳优先 `date -u`，序号兜底
- 断点恢复增强: .state.md 新增 `last_updated` 字段，pending + 超 30 分钟自动重新派发

---

## [0.1.0] - 2026-05-18

初始框架发布。

- 四层防线架构（Rules → Skills → Agents+Workflow → Scripts+人工）
- 五角色体系（PM/BA/SA/DE/TE）
- 四阶段流程（init → propose → apply → archive）
- 三种执行模式（fast/standard/full）
- REQ-ID 隔离的 deliverables 目录结构
- Handoff 文件协议
- 跨平台支持（Claude Code / Cline）

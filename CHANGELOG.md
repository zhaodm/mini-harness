# Changelog

## [0.10.0] - 2026-08-13

CR-017: 完成回报归属 — 协议要求执行角色填写回报、守卫却禁止它写，这一矛盾自 hook 落地首日潜伏至今。

### 修复

- **回报独立落盘（R1/R2/R3）**: `templates/handoff-template.md` 自 `f150a4c`（CR-003）即规定完成回报「执行角色必填」，而 `handoffs/` 是 role-guard 的 ORCHESTRATOR 独占路径，三角色写入一律 `exit 2`——协议强制要求的动作被守卫结构性禁止，潜伏十余个 CR。它不阻塞流程（Orchestrator 收回持权代填即可绕过），故真实代价不是流程中断而是**证据链失效**：代填后回报变为「Orchestrator 撰写、Orchestrator 审计」，质量门禁 Step 0 核对 `read_files` 的判定对象不再是真实对象，退化为依赖 SubAgent 进程内返回值。现回报移出 handoff，落 `deliverables/{REQ-ID}/.engine/reports/<handoff-basename>.report.md`，THINKER/WORKER/VERIFIER/ORCHESTRATOR 四分支均放行该路径（ORCHESTRATOR 保留以支持驳回轮次与失联兜底代填）。`handoffs/*.md` 写权不变，仍 ORCHESTRATOR 独占——**放开三角色对 handoff 的写权是被否决方案**，那会让执行角色同时掌握被比较的两侧（改白名单即可自洽），比现状更糟。目录即权限边界，不在 `handoffs/` 内按后缀区分写权（`x.report.md` 与 `x.md` 的正则会互相咬边）。回报名由 handoff basename 机械派生，门禁据此关联，不靠内容里的自述指针（自述指针可被改写，路径派生不能）
- **回报放行条无内容判据（有意的设计选择）**: 内容判据是 CR-016 两个 P0 的共同载体（存在性量词、`Edit` 片段与合并态分歧），回报不承载流程状态故不引入——**无多行判据即无排列可反转**，AX-06 的排列次序对抗在此条上结构性不适用。路径正则 `^…$` 双向锚定（拒 `.report.md.evil`/`.report.mdX`/`.report.md/child.md` 后缀伪造与 `x/deliverables/…` 嵌套伪造），`${req}` 取自当前 state 故不跨需求，不放大到 `handoffs/`、`plan-action.md` 等其他引擎态文件。写权由「当前谁持权」而非「文件名声称的角色」约束：三角色共用同一条正则不按角色前缀细分，加前缀判据会引入「文件名声称的角色」与「state 里的角色」两个主体，正是本 CR 要消除的那类不一致
- **门禁读取位置与回报位置同源（R4）**: `scripts/verify.sh` 与 `scripts/verify-qa.sh` QA-4 改为从 handoff 路径派生回报路径读取字段，不各自硬编码。回报位置变更而门禁不改会使字段永不出现、门禁**永久静默通过**（比硬失败更危险）。新增「handoff 存在但回报缺失」的 WARN：旧结构下「回报未填」表现为字段为空，新结构下表现为文件不存在，不补则漏。保持 WARN 级不升 FAIL——本 CR 只改读取位置，升级严格度是独立决策
- **scripts/verify.sh 在 `set -u` 下自第 9 行即崩溃（顺带修复）**: `SPEC_DIR`/`OUTPUT_DIR` 引用 `$req_id` 而该变量在第 14 行才赋值，`set -euo pipefail` 下脚本 `exit 1` 且无任何输出，A~E 全部检查从不执行。R4 要求回报门禁不得静默失效，而门禁所在脚本跑不起来即最彻底的静默失效，故一并修正（仅移动两行位置，取值与用法不变）。该缺陷自 `f35ce3a`（CR-010）存在

### 未落地（须另开 CR 决策）

- **R5 / D3 mh-dev 分支角色维度校验**: 设计指定判据取 `tools/mh-dev/.mh-dev/state.json` 的 `current_role`，实测该字段**恒为 `planner`**——`transition-state.sh:19` 每次转移硬写 `'planner'`，模板初值同样是 `planner`，仓库内无任何代码路径会写成 `developer`/`tester`。按 D3 表实现的直接后果是 Developer 全程锁死：其运行期间字段值是 `planner`，而 `planner` 行只允许运行态与 `CR-*.md`，故 `approved_scope` 内每个框架文件都 `exit 2`，**包括 `scripts/role-guard.sh` 自身**（实测中该实现改到一半即自锁）。设计称判据与 `validate-changes.sh` 同源亦不成立：那边的 `role` 来自命令行 `--role` 入参，取值域与 `current_role` 不同，故 D 原则 1 在此条上未被满足。更根本地，即使字段被如实维护，它仍在被治理方自己可写的文件里——Planner 写 `state.json` 即自己签发通行证，CR-016 DEV-01 那次越权若发生在有 D3 之后，把字段改成 `developer` 即可照旧穿过。故 D3 的收益上限是防误撞而非防越权，R5 若期望后者则期望本身不成立。三条可行方向与各自代价见 `docs/kb/domains/guards.md`

### 文档更新

- **docs/kb/domains/guards.md**: 新增「归属层面：判定对象与真实对象不一致的第三个实例」——含元教训「协议文本与守卫实现分处两个文件、无交叉校验，矛盾可潜伏十余个 CR」（`f150a4c` 引入独占规则时模板已写「执行角色必填」，两处从未对照；无任何门禁检查两者一致性）与外部项目 `~/Code/mini-agent` EXP-2 归档（框架缺陷由下游使用者先撞到，说明自检维度缺了「协议与实现的一致性」这一格）；新增「mh-dev 分支的角色维度校验为何未落地」记录 D3 的四条阻塞事实与自授权局限
- **口径同步**: `templates/handoff-template.md`（回报节改为指向派生路径 + 协议规则 0）、`templates/handoff-examples.md`（示例改为独立回报文件形态）、`templates/orchestrator-quality-gate.md` 与 `skills/mh-codeflow/SKILL.md`（Step 0 核对来源改为落盘回报、调度循环第 6 步）、`templates/output-structure.md`（目录树加 `reports/`）、`agents/orchestrator.md`（写权清单 + 输入 + 「不得代笔」）、`docs/designs/source-of-truth.md`、`docs/designs/workflow.md`

## [0.9.0] - 2026-08-13

CR-016: role-guard 授权模型修正 — 授权判据从「谁在写」改为「这次写入是否是协议允许的状态迁移」。

### 修复

- **scripts/role-guard.sh 交还例外**: 非 ORCHESTRATOR 角色持权时写本需求 `.engine/.state.md`，若该次写入内容含行首锚定的 `current_role: ORCHESTRATOR` 则放行，修复「Orchestrator 派发后永久丧失状态机写入权、调度循环无法收尾」。判据取本次写入的新内容（`Write` 的 `content` / `Edit` 的 `new_string`），不读磁盘旧值；交还须一次完整写入。例外的路径正则 `^…$` 双向锚定 `.state.md` 全名，后缀伪造（`.state.md.evil`、`.state.mdX`、`.state.md/child.md`）与嵌套伪造路径均不命中；例外不放大到 `handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log`，不跨需求生效
- **scripts/role-guard.sh 按路径归属路由**: 取消 mh-dev 分支的 `-z "$STATE_FILE"` 进入条件，改由归一化路径的 `deliverables/` 目录前缀选择分支。修复两个反向缺陷——活跃/终态需求 state 存在即永久关闭框架治理入口；空/畸形需求 state 又使 `approved_scope` 被整体绕过（`CURRENT_ROLES` 空 → 无条件 `exit 0`）。路径归一化与仓库外绝对路径拦截上移至路由之前，两分支共用；`CURRENT_ROLES` 空则放行收敛在 `/mh-run` 分支内。顺带修复：活跃需求存在时 mh-dev Tester 写不了 `tests/` 的不对称
- **scripts/role-guard.sh + .claude/settings.json 覆盖 NotebookEdit**: matcher 由 `Write|Edit` 扩为 `Write|Edit|NotebookEdit`，路径参数按工具取 `file_path` / `notebook_path`，封堵一条完全绕过守卫的写入通道。路径参数缺失时保守放行并打印 `WARN`（有意偏离需求 R5 的硬阻断，理由见 guards.md）。三角色白名单同步接受 `.ipynb` 扩展名（仅本角色前缀，不跨角色边界）

### 审计后修复（repair round 2）

- **scripts/role-guard.sh 交还谓词改为与读取端同源（P0，横向夺权）**: 旧实现 `grep -qE '^current_role:...'` 是存在性量词（任一行匹配即放行），而读取端取首行首值（`head -1`）。多行内容上两端分歧：载荷「首行 `current_role: THINKER,ORCHESTRATOR` + 末行 `current_role: ORCHESTRATOR`」被放行，落盘生效角色为首行值，持权角色随即取得 ORCHESTRATOR 的整个 `.engine/` 写权（`handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log`、全局 `.state.md`）；`Edit` 仅追加一行即可完成，无须触碰原派发行。谓词改为直接复用读取端解析（`grep '^current_role:' | head -1 | awk '{print $2}'`），两端同源则结构上无从分歧。基线 `156c49a` 对该载荷 `exit 2`，属本 CR 新开的例外口子在多行内容上开得过宽
- **docs/kb/domains/guards.md 不变量由单向收紧为双向（P0 根因）**: 原文写「谓词接受集 ⊇ 读取端接受集」，存在性量词满足该单向包含却仍是缺陷——**只防单侧的不变量放过了另一侧**，且顺利通过设计评审、Developer 自检与 Tester 两轮 217 项断言。现表述为等价（`=`）。同时记录 `Edit` 片段判据管不到合并结果这一固有局限（枚举确认为 fail-safe 侧，无提权路径）与「加断言数量不等于补维度」的测试教训
- **scripts/role-guard.sh ORCHESTRATOR 分支补 `.ipynb`（P2）**: `.ipynb` 放开时三处角色分支已改、ORCHESTRATOR 分支漏改，现补齐
- **口径同步**: `CLAUDE.md`、`README.md`、`docs/designs/workflow.md`、`docs/designs/source-of-truth.md`、`docs/designs/design.md`、`templates/state-template.md`、`skills/mh-codeflow/SKILL.md`、`skills/mh-design/SKILL.md` 八份文档的「含行首锚定的 `current_role: ORCHESTRATOR` 行」表述均改为「首个 `current_role:` 行其值恰为 ORCHESTRATOR」——旧表述本身就是存在性语义

### 交付纪律偏差（须留痕）

- **Planner 越权写入框架文件（违反 `tools/mh-dev/CLAUDE.md` 铁律 3）**: 用户指示「快速修复轨」后，Planner 未派发 Developer，自行写入 11 个框架文件完成 P0-1 与 F-01 修复，全部在 Planner 白名单之外。role-guard 的 mh-dev 分支只校验 `approved_scope`、不校验写入者角色，三个角色共享同一张通行证，故未能拦截——mh-dev 轨的角色分离目前只有软约束，与 `/mh-run` 轨按 `current_role` 分角色白名单不对称。这是 P0-1 / F-01 的第三个同源实例（判定对象与真实对象不一致，本项为 scope 授权对象 vs 实际写入者），建议 CR-017 修
- **归属证据失真**: `change-attribution.developer.2.json` 署名 `developer` 但实际写入者为 Planner；其中 10 个文件的 `after_sha256` 亦与交付态漂移（路线 B 在该归属落盘后才实施）。归属文件受不可变约束无法更正，后续审计以 `docs/requirements/CR-016-role-guard-authority-model.md`「交付纪律偏差记录」节为准据
- **不可变约束与同轮改判的结构性冲突（非违规）**: `tester.2` 快照与归属落盘后，Planner 指示改判 AC-02/AX-02，Tester 依不可变约束拒绝覆盖（处置正确），故其 sha 非最终交付态。建议流程明确：验收标准改判须触发新一轮，不得在同轮内消化
- **「环境限制」标签掩盖真实缺陷**: `tools/mh-dev/tests/test-ppt-gate.sh` 的 2 项失败被 Planner、Developer 与前两轮 Tester 连续两轮误归因为 Playwright 环境限制，实为该套件 `AC-04`/`AC-05` 缺 `import('playwright')` 守卫（同套件其他三处均有）。`AC-04` 上半条判据 `rc != 0` 被 playwright 缺失时的 `exit 3` 满足，即它因错误的原因通过。教训：把失败归因为环境前，须先确认该失败的形态与环境成因一致

### 文档更新

- **docs/kb/domains/guards.md**: 新增「授权模型与能力边界」——守卫为自授权机制（判据存于被治理方可写文件）、`Bash` 通道不受覆盖、定位是防误撞而非安全边界；记录「交还谓词接受集 ⊇ 读取端接受集」不变量与 `grep -qx` 被实测否决的原因、路由的 fail-open 收口教训
- **CLAUDE.md §5**: 新授权口径（工具覆盖、路径归属路由、交还例外、自授权与能力边界）
- **templates/state-template.md**: `current_role` 补交还例外与「交还须一次完整写入」，更新规则 +1 条
- **skills/mh-codeflow/SKILL.md**、**skills/mh-design/SKILL.md**: 调度循环派发/交还两次 state 写入须一次完整写入
- **docs/designs/design.md §3**: 调度循环图显式含派发与交还两次 state 写入
- **README.md**、**docs/designs/workflow.md**、**docs/designs/source-of-truth.md**: role-guard 口径同步（doc_sync 级联）

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

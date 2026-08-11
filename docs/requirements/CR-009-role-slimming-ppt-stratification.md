---
id: CR-009-role-slimming-ppt-stratification
title: 角色文件瘦身 + PPT 内容分层沉淀 + skill 标准化
status: draft
design_doc: docs/designs/CR-009-role-slimming-ppt-stratification-design.md
created: 2026-08-11
---

# CR-009: 角色文件瘦身 + PPT 内容分层沉淀 + skill 标准化

> 归档路径: docs/requirements/CR-009-role-slimming-ppt-stratification.md（本文件）
> 运行态精简: tools/mh-dev/.mh-dev/requirement.md（基于本单精简为 Developer 可执行指令）

## 背景

当前 7 个角色文件共 1676 行，约 81%（~1351 行）是流程性内容（思考框架、质量标准、格式模板、TDD 步骤、test_strategy 细则、verdict JSON 模板等），在角色文件加载时即常驻 context，造成上下文浪费。

PPT 专用约束散落在 thinker（~30 行）、worker（~37 行）、orchestrator（~3 行）三个角色文件中，而 skills/mh-ppt.md 只有 107 行流程骨架，缺少实质约束。角色文件本应 track-agnostic，却内嵌 PPT 专用条款。

skills/mh-run.md L9-71"工作流纪律"节与 agents/orchestrator.md 和 CLAUDE.md §6 存在三处语义重复。

**skill 发现机制失效**：当前所有 skill 文件是扁平的 `.md` 文件，缺少 YAML frontmatter（`name`/`description`），不符合 Claude Code skill 发现规范。它们当前能工作纯粹因为 `.claude/commands/*.md` 手动写了"读取 skills/xxx.md"强制加载——即全部 skill 被全量读入上下文，无法按需加载，与节省上下文的目标背道而驰。

## 需求

### R1: 角色文件瘦身为纯角色契约

7 个角色文件只保留角色身份与核心职责：身份定义、核心职责清单、输入/输出/阻塞条件/禁止事项、可写文件白名单（mh-dev 角色）、铁律（角色约束性条款）、模型建议（如适用）。所有流程性内容下沉到 skill 或 templates。瘦身后每个角色文件预期 ~35-60 行（当前 141-334 行）。

### R2: 流程性内容下沉——SOP 放 skill，格式骨架放 templates

内容分三类归位：
- **角色文件**（agents/*.md）：身份+职责+输入/输出/阻塞/禁止+白名单+铁律。不含任何"怎么做"的指导。
- **Skill 文件**：所有 SOP/方法论/流程指导——思考框架步骤、质量标准、反模式、test_strategy 执行规则、TDD 流程、审计方法论 Phase 0-7、Developer/Tester 工作流程 Step、Code Review 规则、回归测试规则、失败分类、经验采集规则、交付自检清单等。回答"怎么做事"。
- **Templates**：只放纯格式骨架——空表格、JSON 结构模板、需要填空的 markdown 骨架（如 slide-spec 格式、needs-spec 格式、test-report 格式、code-report 格式、verdict JSON 骨架等）。回答"产出物长什么样"。

不新建角色专用 skill 文件（mh-run/mh-ppt 的角色）。流程性内容按阶段归属扩展现有阶段 skill。mh-dev 的三角色方法论例外——按 R7 拆为 3 个独立 skill。

### R2b: skill 加载机制——入口显式 + 阶段自匹配

两种加载机制共存：
- **入口路由（显式）**：命令文件（`.claude/commands/*.md`）保留显式引用，负责将用户命令（`/mh-run`、`/mh-ppt`、`/mh-dev`）路由到入口 skill。这是用户主动入口，显式加载合理。
- **阶段流转（自匹配）**：skill 之间不再写"执行 mh-xxx skill"链式强制加载指令。阶段流转靠 skill 的 `description` 字段自匹配——当上下文中出现阶段信号（如"SR1 方案确认"、"Thinker design 相位"、"修复循环"），Claude 根据 `description` 自动加载对应 skill。

这意味着：
- skill 文件内部的"执行 mh-xxx skill"、"读取 skills/xxx.md"等链式加载指令须移除或改为弱引用（"下一阶段见 mh-xxx skill"作为指引，不强制加载）
- `description` 字段须覆盖触发条件，使自匹配可靠（这是 R8 frontmatter 的核心价值）

### R3: PPT 专用内容分层沉淀到 skill + templates

skills/mh-ppt 作为 PPT track 入口（流程骨架 + PPT 专用 SOP）。PPT 专用内容分层沉淀：
- 视觉约束（视口 1920×1080、ppt_design_mode、视觉叙事原则、视觉多样性要求）→ skill（mh-ppt）
- PPT 实现品质要求（字号底线、布局规则、导航交互）→ skill（mh-ppt）
- slide-spec 格式模板、字号底线表 → templates

瘦身后 thinker/worker/orchestrator 不再含任何 PPT 专用条款。

### R4: mh-run skill 去重

消除 mh-run 中与 orchestrator.md（调度协议/角色隔离/平台适配）和 CLAUDE.md §6 的三处语义重复。去重原则：角色调度协议留 orchestrator.md，全局多角色纪律留 CLAUDE.md §6，mh-run 只保留 code track 专属流程编排（阶段序列、自动推进、断点恢复），以引用指向权威源。

### R5: 同步更新 source-of-truth 映射表

docs/source-of-truth.md 记录每个设计概念的权威源。重构改变了许多概念归属。须同步更新此表。

### R6: 引用完整性

所有角色文件和 skill 文件中的跨文件引用在重构后须仍指向有效位置。下沉内容时同步更新所有引用方。

### R7: mh-dev 专属 skill 移入 tools/mh-dev/ + 三角色方法论拆 3 个 skill

将 mh-dev 的 skill 内容移入 `tools/mh-dev/skills/`，使 mh-dev 工具的所有内容集中在 `tools/mh-dev/` 下。其余 9 个 skill 是 mh-run/mh-ppt 通用流程的，保留在 `skills/` 不动。

mh-dev 的三个角色方法论（auditor 审计方法论 Phase 0-7、developer 工作流程 Step 1-6、tester 工作流程+失败分类）是 SOP，拆为 3 个独立 skill：
- `tools/mh-dev/skills/mh-dev-develop/SKILL.md` — Developer 工作流程 SOP
- `tools/mh-dev/skills/mh-dev-test/SKILL.md` — Tester 工作流程 + 失败分类 SOP
- `tools/mh-dev/skills/mh-dev-audit/SKILL.md` — Auditor 审计方法论 SOP

入口 skill（原 skills/mh-dev.md）移到 `tools/mh-dev/skills/mh-dev/SKILL.md`，做入口路由。

移动后须更新所有引用方。

### R8: skill 标准化——目录结构 + frontmatter + 命名统一

所有 skill 转为 Claude Code 标准格式：
1. **目录化**：`skills/mh-clarify.md` → `skills/mh-clarify/SKILL.md`（每个 skill 是一个 kebab-case 目录，内含 SKILL.md）
2. **frontmatter**：每个 SKILL.md 必须有 `name` + `description` 字段，description 用第三人称+触发短语描述何时加载
3. **命名统一 + 改名**：所有 skill 使用 mh- 前缀。具体重命名：
   - `skills/dev-test.md` → `skills/mh-self-test/SKILL.md`（加前缀；用 self-test 避免与 mh-dev 工具名混淆）
   - `skills/post-verify.md` → `skills/mh-verify/SKILL.md`（加前缀；核心是验证校验）
   - `skills/mh-clarify.md` → `skills/mh-intake/SKILL.md`（核心是需求初始化，不只是澄清）
   - `skills/mh-propose.md` → `skills/mh-design/SKILL.md`（核心是设计方案+计划编排，不是提案）
   - `skills/mh-apply.md` → `skills/mh-build/SKILL.md`（核心是构建+验证交付，apply 太模糊）
   - `skills/mh-apply-repair.md` → `skills/mh-repair/SKILL.md`（精简，直接说明修复流程）
   - `skills/mh-archive.md` → `skills/mh-deliver/SKILL.md`（核心是交付归档+沉淀）
   - `skills/mh-run.md` → `skills/mh-codeflow/SKILL.md`（明确是 code track 全流程编排）
   - `skills/mh-ppt.md` → `skills/mh-slideflow/SKILL.md`（明确是 slide track 全流程编排）
   - slash 命令名不变（`/mh-run`、`/mh-ppt` 仍可用），`.state.md` 的 phase 值不变（`init`/`propose`/`apply`/`archive`），只改 skill 目录名
4. **字段名不变**：`code-report.md` 中的 `dev-test: PASS` 字段名和 `verify-qa.sh` 的校验逻辑保持不变——这是产出物格式契约，与 skill 标识解耦

重命名后须更新所有引用方（路径从 `skills/xxx.md` 改为 `skills/xxx/SKILL.md`）。

## 非目标

- 不改变角色数量和职责划分
- 不改变状态机、状态 schema、Handoff 协议格式
- 不改变 track 路由逻辑
- 不改变 role-guard.sh 权限模型
- 不改变工作流阶段序列（clarify→propose→apply→archive）
- 不移动 skills/ 下除 mh-dev.md 外的其他通用 skill 的归属（只做目录化+frontmatter）
- 不改 code-report.md 中 `dev-test: PASS` / `post-verify: PASS` 字段名
- 不改 verify-qa.sh 的 grep 校验逻辑

## 影响范围

### 角色文件（7 个，主体重构）
- agents/orchestrator.md — 调度协议/质量门禁/平台适配/经验采集下沉到 skill，保留身份+职责+输入输出+铁律
- agents/thinker.md — 思考框架/质量标准/PPT 视觉约束/slide-spec 格式下沉，保留身份+三相表+职责+输入输出
- agents/worker.md — TDD 流程/PPT 实现品质要求/代码报告模板下沉，保留身份+职责+输入输出
- agents/verifier.md — test_strategy 细则/测试报告模板/Code Review 格式下沉，保留身份+职责+输入输出
- tools/mh-dev/agents/auditor.md — 审计方法论/verdict JSON 模板/报告模板下沉到 skill，保留身份+输入+白名单+铁律
- tools/mh-dev/agents/developer.md — 工作流程 Step/报告模板下沉到 skill，保留身份+输入+白名单
- tools/mh-dev/agents/tester.md — 工作流程/报告+verdict 模板下沉到 skill，保留身份+输入+白名单

### Skill 文件（目录化 + frontmatter + 重命名 + 扩展接收下沉内容）
- skills/mh-codeflow/SKILL.md（原 mh-run）— 去重工作流纪律节 + 接收 orchestrator 调度协议
- skills/mh-slideflow/SKILL.md（原 mh-ppt）— 接收 PPT 专用约束（视觉约束+实现品质），引用 templates
- skills/mh-design/SKILL.md（原 mh-propose）— 接收 Thinker 思考框架/质量标准/反模式/自检
- skills/mh-build/SKILL.md（原 mh-apply）— 接收 Worker TDD 流程/质量标准/反模式/自检
- skills/mh-intake/SKILL.md（原 mh-clarify）— 目录化+frontmatter
- skills/mh-deliver/SKILL.md（原 mh-archive）— 接收经验采集规则（从 orchestrator 下沉）
- skills/mh-repair/SKILL.md（原 mh-apply-repair）— 接收修复轮次指导（从 worker 下沉）
- skills/mh-self-test/SKILL.md（原 dev-test）— 目录化+frontmatter+重命名
- skills/mh-verify/SKILL.md（原 post-verify）— 目录化+frontmatter+重命名+接收 Verifier 思考框架/质量标准/test_strategy 细则/Code Review/回归/自检
- tools/mh-dev/skills/mh-dev/SKILL.md（原 skills/mh-dev.md）— 入口路由，移入 mh-dev 工具目录
- tools/mh-dev/skills/mh-dev-develop/SKILL.md（新增）— Developer 工作流程 SOP
- tools/mh-dev/skills/mh-dev-test/SKILL.md（新增）— Tester 工作流程+失败分类 SOP
- tools/mh-dev/skills/mh-dev-audit/SKILL.md（新增）— Auditor 审计方法论 SOP

### Templates（纯格式骨架，新增）
- templates/orchestrator-quality-gate.md — 质量门禁检查清单骨架
- templates/needs-spec-template.md — needs 相位 requirement-spec.md 格式骨架
- templates/design-spec-template.md — design 相位 design.md 格式骨架
- templates/ppt-slide-spec-template.md — visual 相位 slide-spec.md 格式骨架
- templates/ppt-quality-rules.md — PPT 视觉硬约束详情（字号/布局/导航）
- templates/code-report-template.md — Worker code-report.md 格式骨架
- templates/test-report-template.md — Verifier 测试报告格式骨架
- tools/mh-dev/templates/auditor-report-template.md — 审计报告格式骨架（扩展已有 audit-report.md）
- tools/mh-dev/templates/dev-report-template.md — dev-report.md 格式骨架
- tools/mh-dev/templates/test-report-template.md — test-report.md 格式骨架

### 文档与脚本
- docs/source-of-truth.md — 同步更新权威源映射表（含 skill 新路径+新名）
- docs/design.md — 更新角色职责描述引用
- scripts/check-harness.sh — 更新 skill 清单路径（目录化+重命名+mh-dev 移位）+ 新增 templates 校验
- .claude/commands/mh-dev.md — 引用路径改为 tools/mh-dev/skills/mh-dev/SKILL.md（命令名 /mh-dev 不变）
- .claude/commands/mh-run.md — 内部引用指向 skills/mh-codeflow/SKILL.md（命令名 /mh-run 不变）
- .claude/commands/mh-ppt.md — 内部引用指向 skills/mh-slideflow/SKILL.md（命令名 /mh-ppt 不变）
- .clinerules — 更新 skill 引用路径（新名）
- tools/mh-dev/scripts/audit-preflight.sh — 更新 mh-dev skill 路径引用
- tests/test-role-guard.sh — 如角色文件结构变化影响测试

## 轨道建议

formal — 涉及角色边界/角色文件结构重组 + skill 目录结构变更 + 无法局部回滚 + 多处设计决策。

## testcase_adding_required

false — 本次是文档/Markdown 文件重构 + skill 目录化，无脚本逻辑变更（check-harness.sh/audit-preflight.sh 只改路径清单不改逻辑）、无新功能、无行为变化。verify-qa.sh 的 grep 逻辑不变。

## 风险与回滚

风险：跨文件引用断裂（角色文件引用了不存在的 skill 节或 templates 文件）；skill 目录化后 check-harness.sh 路径清单未同步。
回滚：git revert 本次 commit，因不涉及脚本逻辑变更，回滚干净。

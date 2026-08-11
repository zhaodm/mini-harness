---
id: CR-010
title: deliverables 目录结构规范化 — 引擎态分离 + 命名统一 + 产出即归档
status: draft
design_doc: docs/designs/CR-010-deliverables-structure-naming-design.md
created: 2026-08-11
---

# CR-010: deliverables 目录结构规范化 — 引擎态分离 + 命名统一 + 产出即归档

> 归档路径: docs/requirements/CR-010-deliverables-structure-naming.md
> 运行态精简: tools/mh-dev/.mh-dev/requirement.md（基于本单精简为 Developer 可执行指令）

## 背景

当前 `/mh-run` 外部项目流程的产出目录体系存在三个结构性问题：

1. **引擎态与产品产出混放**：`.state.md`、`handoffs/`、`process.log`、`lessons.md`、`SR*-record.md`、`plan-action.md` 等引擎运行态文件散落在 `deliverables/{REQ-ID}/` 根目录，与 `thinker/`、`worker/`、`verifier/`、`output/` 等人可读产出混在一起。语义不清，且 `verify-archive.sh` 需要维护一份"流程管控文件"排除清单（L96-99）才能做重复检测。

2. **文件命名不统一**：`requirement-spec.md`、`design.md`、`code-report-t1.md`、`plan-action.md`、`SR1-record.md` 命名风格各异，无法从文件名判断产出角色和阶段。

3. **源产出与归档目标二份存放**：Worker 产出到 `deliverables/{REQ-ID}/output/`，ARC-3 再把内容拷贝分流到根 `output/`。同一份文件存两份，靠 `verify-archive.sh` ARC-2（重复检测）+ ARC-3（更新方向检测）维持一致性，增加了复杂度和出错面。根 `output/` 还需 REQ-ID 软隔离检查（ARC-5），因为多项目并行时文档会混在同一目录树。

参考 psdt-agent CR018 的 `.engine/` 思路，本次改动在 mini-harness 上做同类规范化，但更进一步：取消"源→归档"的二步拷贝，改为"产出即归档"——在设计阶段就规划好产出物目录结构，Worker 按设计直接落位到 `deliverables/{REQ-ID}/` 下的最终位置，不再有临时区与归档区的二份存放。

## 需求

### R1 — 引擎态归入 .engine/

所有引擎运行态文件 SHALL 存放在 `deliverables/{REQ-ID}/.engine/` 目录下，与产品产出物理隔离。

纳入 `.engine/` 的文件：`.state.md`、`handoffs/`、`process.log`、`lessons.md`、`SR*-record.md`、`plan-action.md`。`.engine/` 内部平铺，不再分层。文件名保持原样——它们是 dotfile / `.log` 后缀 / 被大量脚本硬编码引用的核心控制文件，自带"非产品产出"语义，不受命名规则约束。

`.archiveignore` 仍保留在 `deliverables/{REQ-ID}/` 根目录（由 Thinker 产出，归档排除规则，非引擎态）。

### R2 — 文件命名规则

`deliverables/{REQ-ID}/` 产品区（`.engine/` 之外）的所有面向人阅读的阶段产出文档 SHALL 遵循命名规则：`<role>-<phase>-<name>.md`。

- 角色前缀大写：`THINKER` | `WORKER` | `VERIFIER` | `ORCHESTRATOR`
- phase 和描述名使用小写 kebab-case
- 正则：`^(THINKER|WORKER|VERIFIER|ORCHESTRATOR)-[a-z]+-[a-z0-9-]+\.md$`
- 示例：`THINKER-propose-requirement-spec.md`、`WORKER-apply-code-report-t1.md`、`ORCHESTRATOR-propose-plan-action.md`

**豁免范围：**
- `.engine/` 内的运行态文件（保持原名）
- 代码文件（`.ts`/`.py`/`.go` 等，消费者是编译器/运行时，非人读阶段产出）
- 机器数据文件（`.json` 等脚本间传递的结构化数据）
- Worker 产出物目录下按设计文档规划的项目代码结构（如 `src/`、`tests/`，命名遵循项目自身规范）

**落地方式：** 通过更新 skill / agent / template / hook 中的路径声明，使新 `/mh-run` 产出的文件立即符合新结构。存量 deliverables/ 为空，无迁移负担。

### R3 — 产出即归档（取消二份存放）

取消"Worker 产出到 `deliverables/{REQ-ID}/output/` → ARC-3 拷贝分流到根 `output/`"的二步流程。改为：

1. **需求模板** SHALL 加入"产出物目录结构要求"字段，要求在需求阶段声明本项目期望的产出物目录结构（如 `src/`、`docs/`、`tests/` 等顶层目录）。
2. **设计模板** SHALL 强制加入"产出物目录结构设计"章节，Thinker 在设计阶段把产出物的完整目录结构规划好（含文件落位路径）。
3. Worker 在实现阶段 SHALL 按设计文档规划的目录结构，直接产出到 `deliverables/{REQ-ID}/` 下的最终位置（而非 `output/` 子目录）。
4. ARC-3 归档步骤 SHALL 取消拷贝操作——产出时已在正确位置。
5. 根 `output/` 目录 SHALL 取消（不再作为归档目标）。

### R4 — 产出物目录结构在设计阶段确定

Thinker design 相位 SHALL 在 `design.md` 中产出"产出物目录结构"章节，至少包含：
- 顶层目录列表（如 `src/`、`tests/`、`docs/`、`deploy/`）
- 每个 Task 的产出文件落位路径（相对 `deliverables/{REQ-ID}/`）
- output_type 特化说明（ppt/documentation/infrastructure 的目录差异）

Worker handoff 的期望输出路径 SHALL 引用 design.md 中规划的路径，而非自行决定。

### R5 — 归档校验脚本适配

`verify-archive.sh` SHALL 适配新结构：
- 取消 ARC-2（源 vs 归档重复检测）——不再有二份存放
- 取消 ARC-3（更新方向检测）——不再有源→归档拷贝
- 取消 ARC-5（REQ-ID 隔离检查）——产出已在 `deliverables/{REQ-ID}/` 下，天然隔离
- 保留 ARC-1（.archiveignore 禁止项）、ARC-4（归档非空，目标改为 `deliverables/{REQ-ID}/` 产品区）、ARC-6（知识库校验）、ARC-7（目录结构合规，目标改为 `deliverables/{REQ-ID}/` 产品区）

### R6 — role-guard.sh 白名单适配

`role-guard.sh` 中各角色的写入白名单 SHALL 适配 `.engine/` 路径：
- ORCHESTRATOR：`.engine/.state.md`、`.engine/handoffs/`、`.engine/plan-action.md`、`.engine/SR*-record.md`、`.engine/lessons.md`、`.engine/process.log`、`.state.md`（全局指针）
- THINKER：产品区 thinker 产出（命名受 R2 约束）
- WORKER：产品区产出（按 design.md 规划路径）+ `.engine/` 不涉及
- VERIFIER：产品区 verifier 产出

ORCHESTRATOR archive 阶段写 `output/docs/` 的特殊规则 SHALL 移除（根 output/ 取消）。

### R7 — 模板与文档同步

以下模板和文档 SHALL 同步更新路径声明：
- `templates/output-structure.md` — 重写为 `deliverables/{REQ-ID}/` 产品区结构规范
- `templates/state-template.md` — `.state.md` 路径更新为 `.engine/.state.md`
- `templates/state-pointer-template.md` — 全局指针路径适配
- `templates/handoff-template.md` — Worker 输出路径注释更新
- `templates/handoff-examples.md` — 示例路径更新
- `templates/logging-standard.md` — `process.log` 路径更新为 `.engine/process.log`
- `templates/needs-spec-template.md`、`templates/design-spec-template.md` — 产出物路径更新
- `templates/code-report-template.md` — 路径引用更新
- `docs/design.md` — 目录结构图、产出物路径引用更新
- `docs/workflow.md` — ARC 步骤描述更新
- `docs/source-of-truth.md` — 路径引用更新

## 非目标

- **不改引擎流程逻辑**：clarify → propose → apply → archive 的阶段流转、SR 门禁机制、修复循环逻辑不变
- **不改 .state.md schema**：字段名和字段语义不变，只改文件存放位置
- **不改 role-guard.sh 的治理逻辑**：角色权限模型不变，只适配路径前缀
- **不统一修改现有产出文件名作为存量迁移**：deliverables/ 当前为空，无存量可迁；新规范通过模板/skill 路径声明落地，使未来产出即合规
- **不改 `output_type` 枚举**（code/ppt/documentation/infrastructure）
- **不改 auto-advance 状态机**：phase/step/revision 语义不变
- **不引入独立 git 仓库或 product/ 目录**：所有产出仍在 `deliverables/{REQ-ID}/` 下
- **不改 mh-deliver skill 的 ARC-1/ARC-2 需求设计归档语义**：proposal 和 design 文档仍需归档到产品区供人阅读，只是不再拷贝到根 output/

## 影响范围

scope-scan 关键词：`output/` `deliverables/` `.state.md` `process.log` `handoffs/` `ARC-3` `requirement-spec` `plan-action` `code-report` `design.md` `verify-archive` `output-structure` — 共 702 处匹配。

| 模块 | 影响 |
|------|------|
| `agents/orchestrator.md` | .state.md/handoffs/plan-action/SR-record/lessons 路径 → .engine/ 前缀 |
| `agents/thinker.md` | 产出路径 + 命名规则 |
| `agents/worker.md` | output/ 路径语义变化（取消，改为 design.md 规划路径）+ 命名规则 |
| `agents/verifier.md` | 产出路径 + 命名规则 |
| `skills/mh-intake/SKILL.md` | 目录初始化 + .state.md 路径 |
| `skills/mh-design/SKILL.md` | Thinker 产出路径 + design.md 产出物目录结构章节 |
| `skills/mh-build/SKILL.md` | Worker 产出路径 + handoff 路径 |
| `skills/mh-deliver/SKILL.md` | ARC-1~4 取消拷贝 + ARC-5~8 路径适配 |
| `skills/mh-self-test/SKILL.md` | .state.md 路径 + code-report 路径 |
| `skills/mh-verify/SKILL.md` | code-report 路径 |
| `skills/mh-repair/SKILL.md` | code-report/output hash 路径 |
| `skills/mh-codeflow/SKILL.md` | process.log 路径 + 归档产物摘要 |
| `skills/mh-slideflow/SKILL.md` | ppt track 产出路径 |
| `scripts/verify-archive.sh` | ARC-2/3/5 取消，ARC-1/4/6/7 路径适配 |
| `scripts/role-guard.sh` | 白名单路径前缀 .engine/ |
| `scripts/verify.sh` | .state.md/output/plan-action 路径 |
| `scripts/verify-qa.sh` | requirement-spec/code-report/handoffs 路径 |
| `scripts/verify-ppt.sh` | output/ 路径 |
| `scripts/baseline.sh` | output/spec → 产品区路径 |
| `scripts/check-harness.sh` | 模板清单验证（如需） |
| `templates/output-structure.md` | 重写为产品区结构规范 |
| `templates/state-template.md` | .state.md 路径 |
| `templates/state-pointer-template.md` | 全局指针路径 |
| `templates/handoff-template.md` | Worker 输出路径注释 |
| `templates/handoff-examples.md` | 示例路径 |
| `templates/logging-standard.md` | process.log 路径 |
| `templates/needs-spec-template.md` | 产出物路径 |
| `templates/design-spec-template.md` | 产出物路径 + 新增目录结构章节 |
| `templates/code-report-template.md` | 路径引用 |
| `templates/orchestrator-quality-gate.md` | output/ 路径引用 |
| `workflows/lib/detect-archive-mode.js` | output/spec 路径 |
| `workflows/lib/detect-scenario.js` | output/spec 路径 |
| `workflows/lib/archive-merge.js` | output/spec 路径 |
| `docs/design.md` | 目录结构图 + 产出物路径 |
| `docs/workflow.md` | ARC 步骤描述 |
| `docs/source-of-truth.md` | 路径引用 |
| `tests/test-role-guard.sh` | 白名单路径测试用例 |
| `tests/test-detect-archive-mode.js` | output/spec 测试用例 |
| `tests/test-detect-scenario.js` | output/spec 测试用例 |
| `tests/test-result-parser.js` | 路径断言 |
| `tests/test-prompt-assembler.js` | 路径断言 |
| `tests/test-verify-code-review.sh` | 路径断言 |

## 轨道建议

**formal**

理由：存在发布契约变化（deliverables 目录结构是 `/mh-run` 对外项目的交付契约）、流程行为变化（取消 ARC-3 拷贝、取消根 output/）、需要设计文档定义"产出物目录结构如何在需求/设计模板中表达"。light 轨第二条（无发布契约变化）不满足，降级到 formal。

## testcase_adding_required

**true** — 取消归档拷贝、目录结构契约变化、role-guard 白名单路径变化均属行为变化，需要 Tester 验证新路径下产出与校验脚本一致性。已与用户确认。

## 风险与回滚

**风险：**
1. 影响面大（702 处匹配），路径引用遗漏可能导致脚本误报
2. `verify-archive.sh` ARC-2/3/5 取消后，需确认没有其他逻辑依赖这些检查
3. `role-guard.sh` 白名单正则调整需覆盖 .engine/ 前缀，否则会误拦

**回滚方案：**
- 所有改动集中在 skill/agent/template/script/hook 的路径声明，无数据迁移
- 回滚 = `git revert` 本次 commit，恢复路径声明
- 存量 deliverables/ 为空，无数据回滚负担
- 分批提交：先 .engine/ 分离 + 命名规则，再产出即归档，便于定位问题批次

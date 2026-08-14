---
id: CR-018
title: 交付物面向项目化 — 项目名标识符 + 流程产物内聚 + 去角色前缀命名
status: draft
design_doc: docs/designs/cr-designs/CR-018-project-oriented-deliverables-design.md
created: 2026-08-14
---

# CR-018: 交付物面向项目化 — 项目名标识符 + 流程产物内聚 + 去角色前缀命名

> 归档路径: docs/requirements/CR-018-project-oriented-deliverables.md
> 运行态精简: tools/mh-dev/.mh-dev/requirement.md（基于本单精简为 Developer 可执行指令）

## 背景

用户以本框架开发外部项目（`~/Code/mini-agent`）时，指出 `/mh-run` 交付物在三个方面暴露引擎实现细节，使交付目录不像一个项目、而像一份流程日志：

1. **交付目录以 `REQ001` 命名**，而非项目名。开发 web-cli 项目时目录应叫 `web-cli`。REQ 编号是引擎的需求台账口径，不是项目的身份。

2. **产出文档散落在 `deliverables/{REQ-ID}/` 根目录**，未归入 `docs/`。CR-010 曾规范目录结构，但落地不完整：`templates/output-structure.md` 自身矛盾——L22-25 把规格文档声明在产品区根（`THINKER-propose-*.md`），L26-30 又声明在 `docs/spec/`（`requirement-spec.md` / `design.md`）。`skills/mh-design/SKILL.md` L34/L70 实际写的是根形态；`skills/mh-deliver/SKILL.md` ARC-1/ARC-2 只写「如需归档到 docs/spec/ 由 Orchestrator 整理」而无机制，故整理从不发生；`scripts/verify-archive.sh` L237 又把根 `ROLE-*.md` 显式列入白名单。三处叠加使「散落在根」成为框架保证的结果，而非偶发。

3. **产出文档名带角色前缀**（`THINKER-propose-`、`WORKER-apply-`）。角色与相位是引擎的内部分工，交付项目不知道 thinker 是谁、更不知道 propose 是哪个阶段。

本 CR 的取向是：**引擎态与产品态的隔离，从「目录隔离」推进到「命名与身份隔离」**——产品区的每个文件名、目录名、以及交付目录自身的名字，都不得泄漏引擎的角色、相位、需求编号口径。

### 连带必须修正的两处既有缺陷

去角色前缀会击穿两处依赖前缀或依赖单需求假设的既有实现，不修则改完即坏：

- **前缀即权限边界**：`scripts/role-guard.sh` L234-241 给 WORKER 的授权谓词是「产品区下不含其他角色前缀的任何路径」。前缀取消后该谓词退化为「产品区全通」，WORKER 可写 Thinker 的规格文档。权限模型须重建为显式路径归属表。
- **活跃需求定位无视全局指针**：`role-guard.sh` L120 以 `find … -name .state.md -path "*/.engine/.state.md" | head -1` 取活跃需求。目录名从 `REQ00N` 变为项目名后，`deliverables/` 下多项目并存成为常态形态，`head -1` 会取到任意一个项目的 `req_id` 与 `current_role`，守卫据此判权即失效。须以 `deliverables/.state.md` 全局指针为准。

## 需求

### R1 — 交付目录以项目标识符命名

`/mh-run` 与 `/mh-ppt` 的交付目录 SHALL 以项目标识符命名，而非需求编号。

- 项目标识符在需求澄清阶段与用户确认后写入状态，此后只读
- 标识符 SHALL 受字符集约束，且该约束 SHALL 由脚本强制而非仅文档声明
- 约束须至少排除：路径穿越构造、以及在被插入正则语境时可改变匹配语义的字符

> 约束的**理由**属需求（标识符会被插入 shell 正则与路径拼接，非受限字符集会使守卫判据与路径解析失真）；具体字符集与校验落点属设计。

### R2 — 单一标识符

项目标识符 SHALL 是框架内该交付物的唯一标识符，不与需求编号并存。

派生自该标识符的引擎态命名（handoff 文件名、完成回报文件名等）SHALL 随之改用项目标识符。

理由：双标识符须定义主键、定义各引用点用哪个、并保证二者同步；本 CR 无任何需求依赖需求编号的独立存在。

### R3 — 产品区不得出现角色与相位命名

`deliverables/{project}/` 产品区（`.engine/` 之外）的文件与目录命名 SHALL NOT 包含引擎角色名（THINKER/WORKER/VERIFIER/ORCHESTRATOR）或引擎相位名（init/propose/apply/archive）。

CR-010 R2 确立的 `<role>-<phase>-<name>.md` 命名规则 SHALL 在产品区废止。该规则的原有价值（从文件名可判断产出角色与阶段）SHALL 改由引擎态承载——产品区不再是流程可追溯性的载体。

### R4 — 流程证据内聚到引擎态

产品区 SHALL 只包含交付项目自身需要的产物。以下流程证据 SHALL 移入 `.engine/`：

| 现路径（产品区根） | 性质 |
|---|---|
| `ORCHESTRATOR-init-proposal.md` | 需求澄清阶段的中间态，其定稿内容已进入需求规格 |
| `THINKER-propose-verify-strategy.md` | 引擎的验证编排依据 |
| `WORKER-apply-code-report-t{N}.md` | 每棒 Worker 的完成证据（含修复轮次）|
| `WORKER-apply-quality-gate-report.md` | 质量门禁记录 |
| `VERIFIER-apply-final-test-report.md` | 门禁判据载体 |

判据：**该文档的消费者是交付项目的读者，还是引擎/门禁脚本？** 后者 → 引擎态。

移入后 `.engine/` 内部仍平铺（沿用 CR-010 R1 的「不再分层」口径），文件名去角色前缀。

### R5 — 项目文档归入 docs/

需求规格与技术设计 SHALL 落位到产品区 `docs/` 下的规格目录，不得散落在产品区根。

产出即归档（CR-010 R3）口径不变：Thinker 直接产出到最终位置，归档阶段无拷贝。`skills/mh-deliver/SKILL.md` ARC-1/ARC-2 中「如需归档由 Orchestrator 整理」这类无机制的软声明 SHALL 消除——要么产出时即落位，要么有脚本强制。

### R6 — 权限模型重建为路径归属表

`scripts/role-guard.sh` 产品区授权 SHALL 改为显式路径归属表，不得再以「不含其他角色前缀」作为某角色的授权谓词。

- 归属表 SHALL 为每个角色声明其可写路径集，而非声明其不可写路径集
- WORKER 的产品区授权 SHALL 收窄为项目代码与测试路径，不得覆盖规格文档路径
- `.engine/reports/` 的四角色共写（CR-017 D1）语义不变
- 交还例外（CR-016 D1）语义不变

理由：否定式谓词（「不带别人前缀即可写」）的授权范围随命名规则漂移；肯定式归属表的授权范围只随归属表本身变化。这是 R3 去前缀的直接后果，不是附带优化。

### R7 — 活跃需求定位以全局指针为准

`scripts/role-guard.sh` SHALL 以 `deliverables/.state.md` 全局指针确定活跃交付物，不得以文件系统扫描的首个命中项替代。

指针缺失或指向不存在的交付物时的行为 SHALL 明确定义，且 SHALL NOT 退化为「扫描任意一个」。

### R8 — 门禁脚本与模板同步

以下消费旧路径或旧命名的脚本 SHALL 同步适配，适配后其原有判据强度不得降低：

`scripts/verify.sh`、`scripts/verify-qa.sh`、`scripts/verify-ppt.sh`、`scripts/verify-archive.sh`、`scripts/verify-code-review.sh`、`scripts/baseline.sh`、`scripts/check-harness.sh`

`verify-archive.sh` ARC-7 的产品区根文件白名单 SHALL 相应调整——`ROLE-*.md` 不再是合法根文件，散落文档应被判为违规而非放行。

模板与 agent/skill 定义 SHALL 同步更新路径与命名声明，使新 `/mh-run` 产出即合规。存量 `deliverables/` 为空，无迁移负担。

### R9 — ppt track 同步

`/mh-ppt` 流水线的产出路径与命名 SHALL 同口径适配（`THINKER-propose-slide-spec.md`、`THINKER-propose-wireframes/` 等）。CR-014 确立的渲染态门禁、版式登记、单文件形态、密度模型语义不变。

## 非目标

- **不改流程逻辑**：clarify → propose → apply → archive 的阶段流转、SR 门禁、修复循环逻辑不变
- **不改 `.state.md` 的流程字段语义**：phase/current_step/current_role/revision 不变，只涉及标识符字段
- **不改角色分工**：三角色职责边界不变，只改其可写路径的表达方式
- **不改 CR-016 交还例外与 CR-017 完成回报例外的授权语义**：仅随标识符与路径变化做等价适配
- **不改 `output_type` 枚举**（code/ppt/documentation/infrastructure）
- **不做存量迁移**：`deliverables/` 当前为空
- **不改 mh-dev 自身的 `docs/requirements/CR-*.md` 与 `docs/designs/` 命名**：那是本仓库的需求台账，消费者是框架维护者，CR 编号在此语境下正当
- **不引入独立 git 仓库或 product/ 目录**
- **不改 role-guard 的自授权定位**：其仍是防误撞而非安全边界（`docs/kb/domains/guards.md`）

## 影响范围

scope-scan 关键词：`REQ-ID` `REQ001` `THINKER-` `output-structure` — 548 处匹配（含归档与 scope-result 自身）。

| 模块 | 影响 |
|------|------|
| `scripts/role-guard.sh` | 权限模型重建（R6）+ 全局指针定位（R7）+ 标识符校验（R1）|
| `scripts/verify-qa.sh` | requirement-spec / code-report / handoffs 路径与命名 |
| `scripts/verify.sh` | 产出路径断言、plan-action、code-report |
| `scripts/verify-ppt.sh` | slide-spec / wireframes 路径 |
| `scripts/verify-archive.sh` | ARC-7 根文件白名单收紧、ARC-4 产品区口径 |
| `scripts/verify-code-review.sh` | 报告路径 |
| `scripts/baseline.sh` | spec 路径 |
| `scripts/check-harness.sh` | 模板清单 |
| `agents/orchestrator.md` | 交付目录命名、proposal 落位、handoff 命名 |
| `agents/thinker.md` | 产出路径与命名（12 处）|
| `agents/worker.md` | code-report 落位、产品区可写范围 |
| `agents/verifier.md` | test-report 落位 |
| `skills/mh-intake/SKILL.md` | 项目标识符生成与确认、目录初始化 |
| `skills/mh-design/SKILL.md` | 规格文档落位 docs/、白名单与期望输出路径 |
| `skills/mh-build/SKILL.md` | code-report 落位、白名单路径 |
| `skills/mh-verify/SKILL.md` | 报告路径 |
| `skills/mh-repair/SKILL.md` | code-report / 产出 hash 路径 |
| `skills/mh-self-test/SKILL.md` | code-report 路径 |
| `skills/mh-deliver/SKILL.md` | ARC-1/2 软声明消除、归档目标路径 |
| `skills/mh-codeflow/SKILL.md` | 需求编号口径、产物摘要 |
| `skills/mh-slideflow/SKILL.md` | ppt 产出路径与命名 |
| `templates/output-structure.md` | 重写（消除 L22-30 自相矛盾）|
| `templates/state-template.md` | 标识符字段 |
| `templates/state-pointer-template.md` | 全局指针语义（R7 依赖它）|
| `templates/handoff-template.md`、`handoff-examples.md` | handoff 命名与输出路径 |
| `templates/needs-spec-template.md`、`design-spec-template.md` | 产出路径 |
| `templates/code-report-template.md`、`quality-gate-report-template.md`、`test-report-template.md` | 落位路径 |
| `templates/orchestrator-quality-gate.md` | 路径引用 |
| `templates/logging-standard.md` | 如涉标识符 |
| `workflows/lib/detect-archive-mode.js`、`detect-scenario.js`、`archive-merge.js`、`knowledge-base.js` | spec 路径与 reqId 口径 |
| `docs/designs/design.md`、`docs/workflow.md`、`docs/source-of-truth.md` | 结构图与路径引用 |
| `docs/kb/domains/guards.md` | 授权模型描述同步（R6/R7）|
| `CLAUDE.md` §5 | role-guard 治理条款同步（含 §5 内 `.state.md`/`reports/` 路径描述）|
| `tests/test-role-guard.sh`、`test-role-guard-report.sh`、`test-role-guard-authority.sh` | 白名单与权限用例 |
| `tests/test-result-parser.js`、`test-prompt-assembler.js`、`test-verify-code-review.sh`、`test-detect-archive-mode.js`、`test-detect-scenario.js`、`test-regression-suite.js` | 路径与 reqId 断言 |
| `tools/mh-dev/tests/test-ppt-gate.sh` | ppt 产出命名用例 |

## 轨道判定

**formal**

不满足 light 轨条件第二条（无状态机/角色边界/发布契约变化），两处独立触发：

1. **角色边界变化**：R6 重建 `role-guard.sh` 产品区授权模型。去前缀使既有否定式谓词退化为「产品区全通」，权限边界必须重写而非微调。
2. **发布契约变化**：`deliverables/` 的目录名、结构、文件命名共同构成 `/mh-run` 对外交付契约，R1/R3/R4/R5 全部改动该契约。

亦不满足 fast 轨（存在接口变更与设计决策）。需设计文档定义：路径归属表的表达形式、标识符校验落点、全局指针缺失时的守卫行为、流程证据在 `.engine/` 内的命名。

## testcase_adding_required

**true** — 权限模型重建、守卫定位变更、标识符校验新增、门禁脚本路径适配均属行为变化。R6/R7 尤其需要对抗性测试：归属表须验证跨角色越权被拒，全局指针须验证多交付物并存时不误判。

## 风险与回滚

**风险：**

1. **权限模型重建是本 CR 最高风险项**。role-guard 历史上已有 CR-012/013/016/017 四轮修正，`docs/kb/domains/guards.md` 记录了「存在性量词导致横向夺权」「Edit 片段与合并态分歧导致提权」两类已实现的绕过。重建授权谓词有复发同类缺陷的风险，须逐条对照该 KB 的既有不变量。
2. 去前缀后，若归属表遗漏某角色的某条既有合法路径，该角色将被误拦，表现为流程中断而非静默错误（可接受的失败模式）；反向遗漏（多放行）则是静默的权限扩大，须由对抗测试覆盖。
3. R7 改动守卫的状态定位入口，是所有判权的前置。指针语义定义不当会使守卫整体失效（对照 L126 `exit 0` 的既有失效路径）。
4. 影响面广（30+ 文件），路径引用遗漏会使门禁脚本误报或漏报。R8 要求「判据强度不得降低」正是针对此项。

**回滚方案：**

- 改动集中在脚本判据、skill/agent/template 的路径与命名声明，无数据迁移
- 回滚 = `git revert` 本次 commit
- 存量 `deliverables/` 为空，无数据回滚负担
- 分批提交：① R1/R2 标识符 + R7 指针定位；② R3/R4/R5 命名与落位；③ R6 权限模型重建；④ R8/R9 门禁与 ppt 适配。③ 单独成批以便独立回滚——它是风险最高且与其他批次耦合最松的一批

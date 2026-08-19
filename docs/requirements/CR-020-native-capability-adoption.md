---
id: CR-020
title: 宿主原生能力归位 — 角色定义、技能发现、拦截面与分发形态改用 Claude Code 原生机制
status: draft
design_doc: docs/designs/cr-designs/CR-020-native-capability-adoption-design.md
created: 2026-08-17
---

# CR-020: 宿主原生能力归位 — 角色定义、技能发现、拦截面与分发形态改用 Claude Code 原生机制

> 归档路径: docs/requirements/CR-020-native-capability-adoption.md
> 运行态精简: tools/mh-dev/.mh-dev/requirement.md（基于本单精简为 Developer 可执行指令）

## 背景

本框架的定位是「寄生在 Claude Code 之上的流程纪律层」（见
`docs/research/2026-08-17-deepseek-harness-substitution-evaluation.md` §2）。既然宿主
是唯一的能力来源，则**凡宿主已原生提供强制点的机制，框架自建的软性替代都是负债**——
多一份维护成本，且强制点位置更弱。

2026-08-17 的 dsh 替代可行性评估在勘察 Claude Code 插件市场时发现：官方插件
`feature-dev` 用 256 行实现了本框架的流程骨架；`claude-security` 在 `allowed-tools`
中声明了 `Bash(git *)`、`Agent(...)`、`Workflow(...)` 这类**参数级**能力约束。据此复查
本仓，发现四处宿主原生能力未被利用。

### 现状与缺口（均已本地核验）

| # | 现状 | 宿主原生能力 | 缺口性质 |
|---|------|-------------|---------|
| 1 | `agents/*.md` **无 YAML frontmatter**，不在 `.claude/agents/`；角色契约以 prompt 文本注入通用 SubAgent（`skills/mh-codeflow/SKILL.md:97`） | 原生 subagent 定义支持 `name`/`description`/`tools`/`model` frontmatter，`tools` 即工具白名单 | **强制点位置错误**：角色能力边界现由 prompt 文本约定与被治理方可写的 state 承载，宿主侧无强制 |
| 2 | 九个 `skills/mh-*/SKILL.md` 的 frontmatter **已是标准格式**，但位于仓库根 `skills/`，靠 command 正文「读取 skills/xxx/SKILL.md」的文本指令加载 | 原生 skill 发现机制 | **位置不对**：已写好的 `description` 触发语义未被宿主使用 |
| 3 | `.claude/settings.json` 仅注册 `PreToolUse` 一个事件、一条 matcher | 至少 9 个 hook 事件（`PreToolUse`/`PostToolUse`/`UserPromptSubmit`/`Stop`/`SubagentStop`/`SessionStart`/`SessionEnd`/`PreCompact`/`Notification`） | **拦截面未开发**：`verify*.sh` 全靠角色自觉调用；CLAUDE.md §5 自陈的 Bash 逃逸口未处理 |
| 4 | 无 `.claude-plugin/plugin.json`；使用本框架须 clone 整仓 | 插件清单 + marketplace 分发 | **分发形态缺失** |

### 连带必须修正的既有缺陷

**测试判据错位（与 CR-019 同类）。** `tests/test-role-guard-authority.sh:1105-1111`
（AC-08）的断言是 `grep -q 'Bash' docs/kb/domains/guards.md`——它确认 Bash 缺口
**被写进了文档**，而非确认缺口**被关闭**。CR-019 已修过一次「判据对象归位」，本处是
同一形态的另一实例：把「文档提到了缺口」当作「缺口已被处理」的证据。R4 若关闭了该
逃逸口，此断言会继续以「文档仍提及」为由通过，从而掩盖状态变化。

## 需求

### R1 — 角色定义归位到宿主原生形态

三个被派发角色（Thinker/Worker/Verifier）的定义 SHALL 以宿主可识别的原生 subagent
形态存在，使宿主能在派发时直接施加该角色的工具能力边界。

- 每个角色 SHALL 声明其所需工具的最小集合；未声明的工具 SHALL 不可用
- 该边界 SHALL 由宿主强制，而非依赖角色自述或被治理方可写的状态文件
- Orchestrator 是主会话行为契约、不经派发（见 `agents/orchestrator.md`），其形态
  SHALL 与被派发角色分开考虑

> 「最小集合」的**判据**属需求（最小权限原则）；每个角色具体给哪几个工具属设计。

### R2 — 工具边界与 role-guard 的职责划分须明确

R1 引入宿主侧强制点后，SHALL 明确宿主工具白名单与 role-guard 各自负责什么，且
SHALL NOT 出现同一约束在两处独立声明而可能给出矛盾结论的情形。

- 凡宿主可强制的约束，SHALL 优先由宿主承担
- role-guard 保留的职责 SHALL 是宿主表达不了的部分
- 二者分工 SHALL 在知识库中有单一权威记录

> 本条是 R1 的必要配套：不划清分工，新增强制点只是叠加一层，反而制造两个真相源。

### R3 — 技能发现改用宿主原生机制

九个 `mh-*` skill SHALL 可被宿主原生发现，使其 frontmatter 中已有的 `description`
触发语义生效，而非依赖 command 正文的文本加载指令。

- 迁移 SHALL NOT 改变任何 skill 的内容语义
- 现有 `/mh-run`、`/mh-ppt`、`/mh-dev` 入口 SHALL 保持可用

### R4 — 扩大拦截面覆盖，并关闭 Bash 逃逸口

框架的质量门禁 SHALL NOT 完全依赖角色自觉调用校验脚本。

- 对可由宿主事件驱动的门禁，SHALL 由宿主事件触发
- CLAUDE.md §5 自陈的「`Bash` 通道不受守卫覆盖」SHALL 被实际处理，而非仅在文档中
  声明其存在
- 关闭方式 SHALL 使命令级约束由宿主强制，SHALL NOT 由框架脚本解析命令字符串自行判定
- 新增拦截 SHALL NOT 阻断默认会话（无活跃流程时保持透明，与现有守卫同口径）

> 「哪些门禁上事件、绑到哪个事件」属设计；「门禁不得只靠自觉」与「逃逸口须实际关闭」
> 属需求。

### R5 — 测试判据从「文档提及」归位到「行为断言」

针对能力边界的测试断言 SHALL 以实际行为为判据对象，而非以文档是否提及该边界为判据。

- 现有 AC-08 形态的断言 SHALL 被改造或替换
- 文档同步性检查可以保留，但 SHALL NOT 作为「缺口已关闭」的证据

### R6 — 具备可分发的插件形态

框架 SHALL 可作为宿主插件被安装使用，而非必须 clone 整个仓库。

- 插件形态 SHALL NOT 破坏本仓库现有的自开发流程（`/mh-dev` 直接改本仓文件）
- 「框架自身开发」与「被分发使用」两种形态 SHALL 可共存

### R7 — 原生能力清单须落入知识库

宿主原生能力与框架自建机制的对应关系 SHALL 在知识库中有权威记录，供后续复查
「某机制是否已被宿主原生化」。

## 非目标

- **不迁移到 dsh 或任何其他 harness。** 本 CR 的前提正是承认 Claude Code 是宿主。
- **不改动三角色的职责分离与 handoff 协议语义。** 本 CR 改的是这些语义的**承载形态**
  （从框架自建改为宿主原生），不改语义本身。
- **不改动 SR1/SR3 人工审批断点。**
- **不追求覆盖全部 9 个 hook 事件。** 只处理有明确门禁需求的事件。
- **不重写 `verify*.sh` 的校验逻辑。** 只改其触发方式。

## 影响范围（待 scope-scan 确认）

预期触及：`agents/`、`skills/`、`.claude/`、`scripts/role-guard.sh`、`tests/`、
`docs/kb/domains/`（guards / roles / skills 三域）、`CLAUDE.md` §5/§6。

## 风险

| 风险 | 说明 |
|------|------|
| 工具白名单过窄致角色无法完成任务 | 角色实际所需工具集需实测；过窄会在开发循环中反复失败 |
| 双强制点不一致 | R2 若落实不彻底，宿主白名单与 role-guard 可能给出矛盾结论 |
| skill 迁移破坏现有入口 | 三个 command 均以文本路径引用 skill，位置变更须同步 |
| 宿主能力边界认知不完整 | 本 CR 的原生能力事实来自本地官方插件产物与 `plugin-dev` 技能文档；调研时 `docs.claude.com` 被网络策略拦截，故不排除存在未被利用的其他能力 |

## 验收

见 `tools/mh-dev/.mh-dev/acceptance-criteria.md`（AC 功能验收 + AX 对抗性验收）。

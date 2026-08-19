---
id: CR-020
title: 宿主原生能力归位 — 设计文档
requirement: docs/requirements/CR-020-native-capability-adoption.md
created: 2026-08-17
---

# CR-020 设计：宿主原生能力归位

> 需求单：`docs/requirements/CR-020-native-capability-adoption.md`（R1–R7）
> 本文档只写**怎么做**；「要什么」见需求单。

## §1 关键设计判断

### §1.1 插件布局与原生发现是同一件事（决定 R3 与 R6 的合并）

官方 `plugin-dev/skills/plugin-structure` 的 Critical rule 2 明确：

> All component directories (commands, agents, skills, hooks) MUST be at plugin
> root level, NOT nested inside `.claude-plugin/`

即插件形态的标准布局是 `<root>/agents/`、`<root>/skills/`、`<root>/commands/`、
`<root>/hooks/hooks.json` + `<root>/.claude-plugin/plugin.json`。

**本仓当前布局已经是 `agents/` + `skills/` 在仓库根。** 因此：

| 原以为的动作 | 实际动作 |
|---|---|
| R3「把 skills/ 迁入 `.claude/skills/`」 | **不迁移目录**。加 `.claude-plugin/plugin.json` 后，仓库根即插件根，现有 `skills/` 与 `agents/` 位置**已合规** |
| R6「打包为插件」 | 与 R3 是同一个动作 |

这消解了需求单 §风险 中「skill 迁移破坏现有入口」的主要部分，也使
scope-scan 查出的 **52 个文件、1176 处 `skills/mh-*` 路径引用无需改写**——这是本设计
最重要的一个判断，避免了一次大范围且高风险的字符串替换。

> 采纳 §1.1 后，AX-04（悬空引用）的检查对象从「全仓路径重写是否遗漏」退化为
> 「新增文件是否引入错误引用」，风险大幅下降。

> ⚠️ **本节有一处推理错误已在 §5 修正（Tester round 0 F-01, critical）。**
> 「不迁移 `skills/` 目录」的结论仍成立，但本节由「布局合规」推出的
> **`tools:` 即由宿主强制是错的**——合规布局只是被发现的必要条件，插件形态须被
> **安装**才进入发现面，且派发侧须传 `agentType`。读本节前先读 §5。

### §1.2 宿主工具白名单与 role-guard 的分工（R2 的答复）

二者**粒度不同，不可互相替代**：

| 强制点 | 粒度 | 能表达 | 不能表达 |
|---|---|---|---|
| 宿主 `tools:` / `allowed-tools:` | **工具粒度 + 参数模式** | 「Verifier 不能用 Write」「Bash 只能跑 `git *`」 | 「Worker 只能写 `src/`」——工具白名单无路径概念 |
| `role-guard.sh` | **路径粒度** | 肯定式路径归属表、交还例外、全局指针五形态 | 无法约束 Bash（不在 matcher 内，且解析命令串不可靠） |

**分工原则（写入 `docs/kb/domains/guards.md`，单一权威记录）：**

1. **工具能否被使用** → 宿主 `tools:` 裁决。role-guard 不重复判定。
2. **写入落到哪个路径** → role-guard 裁决。宿主不表达路径。
3. **Bash 命令形态** → 宿主 `allowed-tools` 的 `Bash(...)` 参数模式裁决。
   role-guard **不新增**命令串解析逻辑（需求单 R4 明确禁止）。

两者是**串联而非并联**：宿主先筛工具，通过后 role-guard 再筛路径。同一约束只在一侧
声明，故 AX-02 的「矛盾结论」在设计上不可能出现——它们判的不是同一个命题。

### §1.3 role-guard 不因本 CR 收窄逻辑

虽然宿主接管了工具粒度，但 role-guard 现有的路径归属表**一行都不删**。理由：

- role-guard 覆盖 `/mh-run` 交付物区与 mh-dev 框架区两条流水线，其判据是路径，与工具
  白名单正交
- CR-012/016/017/018 建立的不变量（路径穿越、后缀伪造、嵌套伪造、交还例外只接受
  Write、全局指针五形态）全部是路径语义，无一可由 `tools:` 表达
- 删除任何一条都会使 AX-07 失败

本 CR 对 role-guard 的**唯一改动**是在文件头注释与 `guards.md` 中登记新的分工边界，
不改判定逻辑。

---

## §2 各需求的实现方案

### §2.1 R1 — 角色定义加 frontmatter

`agents/{thinker,worker,verifier}.md` 各加 YAML frontmatter。字段依据
`plugin-dev/skills/agent-development`：

```yaml
---
name: <role>            # 小写字母/数字/连字符，3-50 字符
description: <触发条件>  # 供宿主判断何时派发
tools: [...]            # 数组形式；省略即全权限
model: inherit          # 继承主会话模型，避免与流程的模型选择耦合
---
```

**`agents/orchestrator.md` 不加 frontmatter。** 它是主会话行为契约、不经派发
（文件自述「不通过 Agent tool spawn」），加 frontmatter 会使其被误当作可派发角色。

#### 工具集分配

按最小权限 + 协议实际需要（对照 §2.1.1 的动作核对表）：

| 角色 | tools | 理由 |
|---|---|---|
| Thinker | `Read`, `Glob`, `Grep`, `Write`, `Edit`, `WebSearch`, `WebFetch` | 产出规格与设计文档需写入；需检索参考资料；**无 Bash**——思考者不执行 |
| Worker | `Read`, `Glob`, `Grep`, `Write`, `Edit`, `NotebookEdit`, `Bash` | TDD 编码需写入与执行（`mh-self-test` 要跑测试/lint/build） |
| Verifier | `Read`, `Glob`, `Grep`, `Bash`, `Write` | 需执行 `verify*.sh` 与回归套件；`Write` 仅为产出缺陷报告与 `tests/`（路径由 role-guard 限制在 `tests/`）；**无 Edit**——不改产物，只报缺陷 |

三份清单互不相同，满足 AC-02。Verifier 有 `Write` 但无 `Edit`：它能新建测试与报告，
不能就地修改 Worker 的产物——这与 `agents/verifier.md`「只执行验证，不定义标准」
及归属表「VERIFIER 写 `tests/`」一致。

#### §2.1.1 动作核对表（AX-08 的设计侧自检）

| 角色 | 协议要求的动作 | 所需工具 | 已授予 |
|---|---|---|---|
| Thinker | 读 handoff 白名单、写规格/设计、查 `reference/` | Read/Write/Grep/Glob | ✅ |
| Worker | 写代码、跑 `mh-self-test`（测试/lint/build）、写完成回报 | Write/Edit/Bash | ✅ |
| Verifier | 跑 `verify*.sh`、跑全量回归、写缺陷报告与测试 | Bash/Read/Write | ✅ |

### §2.2 R3 + R6 — 插件清单

新增 `.claude-plugin/plugin.json`：

```json
{
  "name": "mini-harness",
  "description": "AI Agent 驱动的研发流程框架：三角色 + 编排器，四层递进防线",
  "author": { "name": "devin" }
}
```

`name` 用 kebab-case（规范要求）。**不移动任何现有目录。**

**两形态共存（R6 约束）：** 本仓库既是插件源、也是自开发工作区。`/mh-dev` 直接改本仓
文件的能力不受影响——插件清单只是让**别的**仓库可以安装它。`tools/mh-dev/` 不属于
插件对外暴露的组件目录（插件只识别 `commands`/`agents`/`skills`/`hooks`），故自开发
工具链天然不进入分发面。

### §2.3 R4 — 拦截面扩展与 Bash 逃逸口

#### Bash 逃逸口的关闭方式

**不改 role-guard。** 在角色的 frontmatter 中用参数级 `tools` 声明约束 Bash，依据
`claude-security` 的既有形态（`Bash(git *)`、`Bash(date *)`）：

- Thinker：不授予 `Bash`（最彻底的关闭——没有该工具）
- Worker / Verifier：需要 `Bash` 执行测试，故授予；其命令形态约束在设计上有两种落点，
  见下方权衡

> **一处未定的设计权衡（须在开发中实测确认）：** `agents/*.md` 的 `tools:` 是否支持
> `Bash(pattern)` 参数级语法，本地一手证据只见于 `skills/*/SKILL.md` 的
> `allowed-tools:`（`claude-security`）。`agent-development` 技能文档对 `tools` 只给出
> `["Read", "Write", "Grep", "Bash"]` 的裸工具名数组形态。
> **Developer 须先实测**：若 `agents/` 的 `tools` 支持参数模式，则直接在此声明；若不
> 支持，则退回到「Thinker 无 Bash + Worker/Verifier 授予裸 Bash」，并在 `guards.md`
> 中明确记录「Worker/Verifier 的 Bash 命令形态目前无宿主侧约束」——**如实登记残留
> 缺口，不得声称已关闭**。

这一权衡不影响 R4 的达成判据：Thinker 的 Bash 通道确定被关闭（工具未授予），且关闭
方式确定由宿主强制、未解析命令串。

#### hook 事件扩展

现有 `.claude/settings.json` 的 `PreToolUse` 保留不动（role-guard 仍是路径守卫）。
新增一个事件，绑定既有校验脚本：

| 事件 | matcher | 绑定 | 目的 |
|---|---|---|---|
| `SessionStart` | — | `bash scripts/session-context.sh`：打印当前活跃流程状态（读 `deliverables/.state.md` 与 mh-dev state） | 使断点恢复不依赖对话历史（呼应 `mh-codeflow` 的断点恢复纪律） |

**为何选 `SessionStart` 而非 `PostToolUse`：** `PostToolUse` 绑 `verify*.sh` 看似更
贴合「门禁不靠自觉」，但 `verify.sh` 是**阶段性**门禁（需要 `.state.md` 的 phase 与
交付物齐备），逐次工具调用后触发会大量误报并显著拖慢每次写入。`SessionStart` 是
低风险、高收益的起点：它只读状态、只打印，不返回权限决策（形态同官方
`claude-security` 的 banner hook「It is a sensor: it emits a message and never
returns a permission decision」）。

需求单 R4 要求「对**可由**宿主事件驱动的门禁由事件触发」——`verify*.sh` 因上述阶段性
约束不属于「可由事件驱动」，本设计据此不将其上事件，并在 `guards.md` 登记该判断。

**AX-03（默认会话不被阻断）的保障：** 新增 hook 为 sensor 形态，脚本以 `exit 0` 结束
（无论有无活跃流程），故不可能阻断会话。

### §2.4 R5 — 测试判据归位

`tests/test-role-guard-authority.sh` 的 AC-08 现为：

```bash
grep -q 'Bash' "$REPO/docs/kb/domains/guards.md"
```

**改造方向（由 Tester 实施，Developer 不得动 `tests/**`）：** 判据对象从「文档提及
Bash」改为「角色 frontmatter 的实际工具声明」——断言 Thinker 的 `tools` 不含 `Bash`。
文档同步性检查可保留为独立断言，但不再作为缺口关闭的证据。

> 需求单已注明：R4 关闭逃逸口后，旧断言会因文档仍提及 Bash 而继续通过，从而掩盖状态
> 变化。这正是 R5 存在的理由。

### §2.5 R2 + R7 — 知识库记录

| 文件 | 新增内容 |
|---|---|
| `docs/kb/domains/guards.md` | §1.2 的分工表（单一权威记录）；Bash 约束的实际落点与残留缺口（若有）；`verify*.sh` 不上事件的理由 |
| `docs/kb/domains/roles.md` | 角色 frontmatter 形态与各角色工具集及其理由 |
| `docs/kb/system-map.md` | 宿主原生能力 ↔ 框架自建机制对应表（R7） |

R7 的对应表覆盖本 CR 四项，形态：

| 宿主原生能力 | 框架曾用的替代 | 现状 |
|---|---|---|
| subagent `tools:` frontmatter | prompt 文本注入角色契约 | 已归位（CR-020 R1） |
| 插件 `agents/`+`skills/` 根布局 | command 正文文本加载指令 | 已归位（R3/R6） |
| 9 个 hook 事件 | 仅 PreToolUse + 角色自觉调用脚本 | 部分归位（R4，见 guards.md 残留登记） |
| `.claude-plugin/plugin.json` | clone 整仓 | 已归位（R6） |

---

## §3 影响范围（scope-scan 已执行，1176 处命中已分类）

### §3.1 需修改

| 文件 | 改动 |
|---|---|
| `agents/thinker.md`, `agents/worker.md`, `agents/verifier.md` | 加 frontmatter（仅头部，正文不动） |
| `.claude-plugin/plugin.json` | 新增 |
| `.claude/settings.json` | 加 `SessionStart` hook |
| `scripts/session-context.sh` | 新增；供 SessionStart 调用的 sensor（只读状态、只打印、恒 `exit 0`） |
| `scripts/role-guard.sh` | **仅头部注释**登记分工边界，判定逻辑不动 |
| `docs/kb/domains/guards.md`, `roles.md`, `system-map.md` | 见 §2.5 |
| `CLAUDE.md` §5 | 更新「Bash 通道不受覆盖」的表述以反映实际状态 |
| `scripts/check-harness.sh` | 加 `.claude-plugin/plugin.json` 存在性检查 |

### §3.2 明确不修改

- **52 个含 `skills/mh-*` 路径引用的文件**——§1.1 已论证无需重写
- `skills/` 与 `agents/` 的目录位置
- `agents/orchestrator.md` 的 frontmatter（§2.1）
- role-guard 判定逻辑（§1.3）
- `verify*.sh` 的校验逻辑（需求单非目标）
- `docs/requirements/CR-0*.md` 与 `docs/designs/cr-designs/CR-0*.md` 历史记录——历史
  CR 是既成事实的记录，不随后续变更改写
- `tests/**`——由 Tester 独占

### §3.3 敏感文件提醒

`validate-changes.sh:35` 的 sensitive 列表含 `CLAUDE.md`、`.claude/settings.json`、
`scripts/role-guard.sh`——本 CR 三者都动，故须 formal 轨（已是）。
`validate-changes.sh:82` 要求 `scripts/role-guard.sh` 的改动须同步
`CLAUDE.md`、`docs/designs/source-of-truth.md`、`docs/kb/domains/guards.md`——本设计
已覆盖前者与后者，**`source-of-truth.md` 须一并更新**。

---

## §4 验收对应

| AC/AX | 由本设计的哪一节保障 |
|---|---|
| AC-01 / AC-02 | §2.1 三份互不相同的 tools 清单 |
| AC-03 | §1.2 分工表写入 guards.md |
| AC-04 / AC-05 | §1.1——不迁移目录，故内容与入口天然不变 |
| AC-06 | §2.3 新增 SessionStart |
| AC-07 | §2.3 Thinker 无 Bash（宿主强制、未解析命令串） |
| AC-08 | §2.2 plugin.json |
| AC-09 | §2.5 R7 对应表 |
| AC-10 | §3.1 含 check-harness.sh 同步更新 |
| AX-01 | §2.1 未声明即不可用（宿主语义） |
| AX-02 | §1.2 串联而非并联——判的不是同一命题 |
| AX-03 | §2.3 sensor 形态、恒 exit 0 |
| AX-04 | §1.1 无路径重写，仅需检查新增文件 |
| AX-05 | §2.4 判据改为断言 frontmatter 实际内容 |
| AX-06 | §2.2 `tools/mh-dev/` 不进入插件组件面 |
| AX-07 | §1.3 role-guard 判定逻辑零改动 |
| AX-08 | §2.1.1 动作核对表 |

## §5 修订 R1（repair round 1）：合规布局 ≠ 机制生效

> 本节由 Tester round 0 的 F-01（critical, FAIL_DESIGN）触发，修正 §1.1 的一处推理
> 错误。**§1.1 关于「不迁移 `skills/` 目录」的结论仍然成立**（skill 与 agent 的发现
> 机制不同，见 §5.3），被修正的只是「布局合规即等于 `tools:` 生效」这一推断。

### §5.1 缺陷：声称已归位，实际未接通

§1.1 从「插件规范要求组件目录在插件根 + 本仓 `agents/` 已在根」推出「无需迁移」，
进而在 `system-map.md` 标注「**已归位**」、`workflow.md` 写「工具集**由宿主强制**」。

Tester 证伪了该推断，三段事实经 Planner 独立复核：

| 检查 | 结果 |
|---|---|
| `agentType` 在 16 个 workflow 文件中出现次数 | **0**（逐文件 `grep -c` 全为 0） |
| `.claude/agents/` 是否存在 | **不存在** |
| mini-harness 是否已作为插件安装 | 未安装（`installed_plugins.json` 只含 frontend-design） |

**两条成因缺一不可：**

1. **派发侧未指定类型。** 四个 workflow 均以 `agent(label, {prompt, model})` 派发，
   不传 `agentType`，宿主遂套用内置 `workflow-subagent`（`tools: ["*"]`）。
2. **发现侧未进入宿主视野。** 仓库根裸 `agents/` 既不是项目级发现位置
   （`.claude/agents/`），本仓也未被安装为插件。

**合规布局只是被发现的必要条件，不是充分条件；插件形态须被安装才进入发现面。**
这与本 CR 要消除的形态同类——声称强制点已归位，实际无机制读取该声明。

### §5.2 修法：补齐派发链与发现面（方案 A）

#### 发现面：两形态各用各自的位置

| 形态 | 位置 | agentType 取值 |
|---|---|---|
| **本仓自用** | `.claude/agents/{thinker,worker,verifier}.md` | 裸名 `thinker`/`worker`/`verifier` |
| **对外分发** | 插件根 `agents/`（已就位）+ `.claude-plugin/plugin.json` | 命名空间 `mini-harness:thinker` 等 |

依据（本地一手）：`pr-review-toolkit/README.md:300-301` 明确项目级为
`.claude/agents/`、用户级为 `~/.claude/agents/`；命名空间形式见
`claude-security` 的 `Agent(claude-security:scan-inventory)` 与其
`workflows/scan.js` 中的 `agentType:"claude-security:scan-inventory"`；而
`feature-dev` 对自己的 agent 以裸名引用（`code-explorer` 等）。

⛔ **`.claude/agents/` 与 `agents/` 不得成为两份可漂移的副本。** 二者须同源——
落地方式（symlink 或单向生成）由 Developer 实测择优，但**必须有机械手段保证一致**，
且 `check-harness.sh` 须能检出不一致。两份手工维护的同名角色定义是比原缺陷更坏的
结果。

#### 派发侧：四个 workflow 传 agentType

`workflows/{thinker-design,apply-batch-dev,apply-batch-test,apply-final-audit}.js`
的 `agent()` 调用增加 `agentType`，取值与角色对应。**自用形态取裸名。**

派发链接通后，`tools:` 才真正成为宿主强制的能力边界，R1 方名副其实。

### §5.3 为何 §1.1 关于 skill 的结论不受影响

skill 与 agent 的发现机制不同：九个 `mh-*` skill 由三个 command 正文的文本加载指令
显式引用（`读取 skills/xxx/SKILL.md`），该路径在**仓库内**解析，不依赖宿主的 skill
发现面即可工作。R3 的收益（让 frontmatter 的 `description` 触发语义生效）确实仍待
插件安装才完全实现，但它**不像 `tools:` 那样存在「声明存在却完全无人读取」的问题**
——文本加载路径是可工作的现有机制。

故 `system-map.md` 中 R3/R6 行的措辞须复核：可保留「布局合规」的陈述，但不得声称
触发语义已生效。

### §5.4 F-02：补评 `permissions` 路线（major）

原设计把 Worker/Verifier 的 Bash 命令形态登记为「宿主侧无法约束」，该表述不准确。
宿主提供了未被评估的路线：

- `.claude/settings.json` 的 **`permissions`** 键消费 Bash 的 ruleContent。依据：
  官方 `claude-code-setup` 插件
  `skills/claude-automation-recommender/SKILL.md:285-287` 给出
  `"permissions": {"allow": ["Edit","Write","Bash(npm test:*)","Bash(git commit:*)"]}`。
  本仓 `.claude/settings.json` 中 `grep -c permissions` = **0**。

**要求：** 评估以 `permissions` 收窄 Bash，能收窄则收窄。

⛔ **不得为凑「已关闭」而写出会误伤正常开发的 deny 清单。** Worker 需跑任意项目的
测试/lint/build，命令形态不可穷举；若评估结论是无法在不误伤的前提下收窄，则
**如实登记「已评估 `permissions` 路线，因 X 未采用」**——这与原登记的区别是：从
「宿主无法约束」改为「宿主提供了路线，本框架评估后未采用，理由是 X」。诚实性本已
达标（Tester 确认无声称已关闭的表述），本条修的是**完备性**。

### §5.5 本轮验收补充

| 判据 | 要求 |
|---|---|
| 派发链一致性 | Tester round 0 新增的一致性断言须转绿（`tests/test-session-context.sh`） |
| 两份定义同源 | 须有机械校验；手工双份维护判 FAIL |
| 文档措辞 | 「已归位」「由宿主强制」等表述须与实际机制一致；未接通处如实标注 |
| F-02 登记 | 须体现「已评估 `permissions`」，而非「宿主无法约束」 |

---

## §6 待开发实测确认项

1. `agents/*.md` 的 `tools` 是否支持 `Bash(pattern)` 参数级语法（§2.3）。不支持则按
   退路执行并如实登记残留缺口。
2. `tools` 数组形态与逗号分隔字符串形态哪种被接受——官方两种写法均有出现
   （`agent-development` 用数组，`claude-security` 的 `allowed-tools` 用 YAML 列表）。
3. 插件清单引入后 `/mh-dev` 前置检查链仍全 PASS（AX-06）。
4. **（repair round 1）** `.claude/agents/` 与 `agents/` 的同源落地方式：symlink 是否
   被宿主正常解析？若否，改单向生成 + `check-harness.sh` 一致性校验。
5. **（repair round 1）** `agentType` 取裸名时能否命中 `.claude/agents/` 的定义；派发
   后 `tools:` 是否真的生效（须以「Thinker 侧 Bash 不可用」为可观测判据验证，不能只看
   声明存在）。

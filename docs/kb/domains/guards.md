# Guards

> 本域指南描述硬校验体系的内部机制。修改本域代码前请先阅读。
> 对应源码: `scripts/`

## 职责与边界

**做什么：**
- 实现三层校验体系：结构校验(verify.sh)、内容质量校验(verify-qa.sh)、PPT 专项(verify-ppt.sh —— 含 bash 静态层与 Node/Playwright 渲染层)
- 实现 role-guard.sh PreToolUse Hook，按角色限制文件写入路径
- 实现归档完整性校验(verify-archive.sh)
- 实现框架自检(check-harness.sh)和基线对比(baseline.sh)
- 实现 Code Review 格式校验(verify-code-review.sh)

**不做什么（由其他域负责）：**
- 校验规则的定义来源 → 见 [skills.md](skills.md)
- 校验通过标准的决策 → 见 [roles.md](roles.md)（Orchestrator 质量门禁）
- 产出格式模板 → 见 [templates.md](templates.md)
- mh-dev 内部验证脚本 → 见 [mh-dev.md](mh-dev.md)

## 内部结构

```
scripts/
├── verify.sh               结构校验（A/B/C/D/E 类）
├── verify-qa.sh            内容质量校验（QA-1~13）
├── verify-ppt.sh           PPT 专项校验（静态层 + 渲染层 + export 子命令）
├── verify-archive.sh       归档完整性校验
├── verify-code-review.sh   Code Review 格式校验
├── role-guard.sh           角色文件写入权限拦截（PreToolUse Hook）
├── baseline.sh             基线对比
└── check-harness.sh        框架自检
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| 结构校验 | 文件存在性(A)、阶段完整性(B)、流程一致性(C)、健康度(D)、契约(E) | `scripts/verify.sh` |
| 质量校验 | 模糊词、测试结果、报告结论、报告完整性、设计规格、代码规范、经验采集 | `scripts/verify-qa.sh` |
| PPT 校验 | A 文件存在性与单文件形态、B 静态合规（字号分档/版式登记/多样性/结构）、C 内容完整性与页数、D 渲染几何测量（溢出/重叠/留白/标题间距）。含检查器运行时自检 | `scripts/verify-ppt.sh` |
| 归档校验 | deliverables/{project}/ 完整性 + docs/kb/ 校验 | `scripts/verify-archive.sh` |
| Code Review 校验 | CR-1~5 格式与维度校验 | `scripts/verify-code-review.sh` |
| 角色权限 | PreToolUse Hook，按角色限制写入路径 | `scripts/role-guard.sh` |
| 基线对比 | 检测非流程修改 | `scripts/baseline.sh` |
| 框架自检 | 受版本控制的框架文件完整性检查 | `scripts/check-harness.sh` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `scripts/verify.sh` | 结构校验（A/B/C/D/E 类） | `skills/mh-verify/SKILL.md`、`docs/designs/design.md` §7.4 |
| `scripts/verify-qa.sh` | 内容质量校验（QA-1~13） | `skills/mh-verify/SKILL.md`、`docs/designs/design.md` §7.4 |
| `scripts/verify-ppt.sh` | PPT 专项校验（静态层 bash + 渲染层 Node/Playwright；退出码 3 = 渲染环境不可用） | `skills/mh-slideflow/SKILL.md`、`templates/ppt-quality-rules.md`、`templates/ppt-templates/registry.json`、`package.json` |
| `scripts/verify-archive.sh` | 归档完整性校验 + deliverables docs/kb/ 校验 | `skills/mh-deliver/SKILL.md` |
| `scripts/verify-code-review.sh` | Code Review 格式与维度校验（CR-1~5） | `skills/mh-verify/SKILL.md` |
| `scripts/role-guard.sh` | 角色文件写入权限拦截（PreToolUse Hook） | `CLAUDE.md` §5、`docs/designs/source-of-truth.md`、`docs/kb/domains/guards.md` |
| `scripts/validate-slug.sh` | 项目标识符字符集校验（生成侧 mh-intake + 消费侧 role-guard 共用） | `skills/mh-intake/SKILL.md`、`scripts/role-guard.sh`、`templates/state-template.md` |
| `scripts/session-context.sh` | SessionStart sensor：打印活跃流程状态（只读、只打印、恒 `exit 0`，不判权） | `.claude/settings.json`、`docs/kb/domains/guards.md`（分工节） |
| `scripts/baseline.sh` | 基线对比 | `docs/designs/design.md` §7.4 |
| `scripts/check-harness.sh` | 框架自检 | `docs/designs/design.md`、`.claude/commands/` |

## 授权模型与能力边界

### role-guard 是自授权机制，不是安全边界

权限判据（`deliverables/{project}/.engine/.state.md` 的 `current_role`、`deliverables/.state.md` 的 `project`、`tools/mh-dev/.mh-dev/state.json` 的 `approved_scope`）全部存放在**被治理方自己可写的文件**里。持权角色可以改写判据再写目标，守卫无法阻止。这不是待修的缺陷，而是模型的固有形态：PreToolUse 载荷不含 `agent_type`，SubAgent 是进程内 spawn，守卫无从获知「谁在写」，只能判定「这次写入是否是协议允许的状态迁移」。

三条边界须一并记住：

- **自授权。** `current_role` 表达的是「派发意图」而非「执行者身份」。守卫按意图放行，不校验身份。
- **Bash 通道不受本守卫覆盖。** hook matcher 只含 `Write|Edit|NotebookEdit`。`Bash` 工具的重定向、`sed -i`、`tee` 一概绕过守卫。把 Bash 纳入 matcher 需要解析任意 shell 命令的写入目标，不可靠，故不做。CR-020 后**部分**改善：Thinker 在宿主侧未被授予 `Bash`（工具不存在，最彻底的关闭）；但 Worker/Verifier 持有裸 `Bash`，其命令形态目前不受任何强制点约束——宿主的 `permissions` 与 hook matcher 两条路线**已评估、未采用**，详见下方「宿主原生能力与 role-guard 的分工」的残留缺口登记。
- **定位是防误撞，不是防攻击。** 守卫要挡的是「Orchestrator 手滑替 Worker 写了代码」「SubAgent 越界改了别人的产出」这类协议内失误。对抗刻意绕过不在设计目标内，别把它当访问控制来依赖。

因此：守卫失效属于流程纪律问题，不属于安全事件；但守卫**空转**（判据恒真、通道漏覆盖）比没有守卫更危险，因为它提供虚假保障——`NotebookEdit` 曾长期不在 matcher 内，即一条完全静默的漏覆盖通道。

### 宿主原生能力与 role-guard 的分工（CR-020 R2，单一权威记录）

**本节是该分工的唯一权威定义处。** `CLAUDE.md` §5 与 `scripts/role-guard.sh` 头部注释均指向此处，
不各自独立定义——同一约束在两处独立声明必然漂移（CR-015 的教训）。

二者**粒度不同，不可互相替代，且是串联而非并联**：宿主先筛工具，通过后 role-guard 再筛路径。

| 强制点 | 粒度 | 能表达 | 不能表达 |
|--------|------|--------|---------|
| 宿主 `agents/*.md` 的 `tools:` | **工具名** | 「Thinker 不能用 Bash」「Verifier 不能用 Edit」 | 「Worker 只能写 `src/`」——工具白名单无路径概念 |
| `scripts/role-guard.sh` | **路径** | 肯定式路径归属表、交还例外、全局指针五形态 | 工具粒度（不重复判定）；Bash 命令形态 |

三条裁决归属：

1. **工具能否被使用** → 宿主 `tools:` 裁决，未声明即不可用。role-guard 不重复判定。
2. **写入落到哪个路径** → role-guard 裁决。宿主不表达路径。
3. **Bash 命令形态** → **两侧都不裁决**。宿主另提供 `permissions` 与 hook matcher 两条路线，
   **已评估、未采用**（理由见下方残留缺口登记）。

因为两者判的**不是同一个命题**，「宿主允许而守卫拒绝」不构成矛盾：那是工具可用、
但该路径不属当前角色，两条结论各自成立且叠加生效（拒绝）。反向组合（守卫允许而宿主拒绝）
同理——工具不可用时调用根本不会到达 PreToolUse。故不存在需要裁决的冲突。

#### ⛔ 残留缺口：Worker/Verifier 的 Bash 命令形态无任何宿主侧约束

**不得声称此缺口已关闭。** 已关闭的只有 Thinker 一侧（未授予 `Bash`，最彻底的形态）。

设计曾拟用 `Bash(git *)` 一类参数模式约束 Worker/Verifier 的命令形态。**实测结论：
`agents/*.md` 的 `tools:` 不支持以参数模式约束 Bash。** 一手证据（Claude Code 2.1.233 二进制）：

- 解析侧**确实**是参数感知的：`tools:` 与 skill 的 `allowed-tools:` 共用同一个括号感知分词器
  （逗号/空格在括号内不切分），故 `Bash(git *)` 能被解析成 `{toolName: "Bash", ruleContent: "git *"}`。
- 但**消费侧丢弃 `ruleContent`**：agent 工具解析函数按 `toolName` 在可用工具表里查名字
  （`y.get(toolName)`），命中即把**整个工具对象**放进 `resolvedTools`。`ruleContent` 除
  `Agent(...)`/`Workflow(...)` 的 agentType 分流外不参与任何过滤，**不会**转成 permission rule。
- 因此 `tools: Bash(git *)` 的实际效果等于 `tools: Bash`——授予完整 Bash。**比裸写更危险**：
  它读起来像一道约束，实际是空转，正是本域反复强调的「虚假保障比没有保障更糟」。
- 官方 34 个 agent 定义中 `Bash(` 出现 **0 次**；参数模式仅出现在 command/skill 的
  `allowed-tools:`（那条路径才会转成 permission rule）。`disallowedTools` 同样只按工具名建集合。

故本 CR 采用退路：**Thinker 不授予 Bash；Worker/Verifier 授予裸 `Bash`**。

##### 已评估但未采用：`.claude/settings.json` 的 `permissions` 路线

⚠️ 早先此处写作「宿主侧无法约束 Bash 命令形态」，**该归因不准确**（CR-020 repair 1 修正）。
宿主确实提供了一条消费 Bash `ruleContent` 的原生路线——与 agent `tools:` 不同，`permissions`
的 deny 规则**会**按参数模式匹配。官方用法见 `claude-code-setup` 插件
`skills/claude-automation-recommender/SKILL.md:285-287`。实测（2.1.233）确认其确实生效：

| 探测 | 结果 |
|------|------|
| `deny: ["Bash(echo *)"]` + `echo HELLO_WORLD` | 拒绝：`Permission to use Bash with command echo HELLO_WORLD has been denied.` |
| `deny: ["Bash(*MARKER*)"]` + `echo pre_MARKER_post` | 拒绝（中缀通配符生效） |
| `allow: ["Bash(bash ./run.sh)"]` + `deny: ["Bash(*MARKER*)"]`，脚本内含 MARKER | **放行且执行**，脚本内的 MARKER 未被看见 |
| `deny: ["Bash(*>*)"]` + `bash tests/run.sh 2>&1 \| tail -5` | 拒绝（`2>&1` 命中 `>`，属误伤） |

**评估结论：不采用。** 三条理由，前两条各自独立即足以否决：

1. **判据对象是命令字符串，不是行为。** deny 只看工具调用里那一行字面命令；一旦命令是
   `bash ./run.sh` 或 `npm test`，脚本内部的重定向、`sed -i`、`tee` 完全不在视野内（上表第 3 行
   实测）。而 Worker 的正常动作恰恰以 `mh-self-test` 一类脚本调用为主——**要防的写入形态
   几乎必然发生在 deny 看不见的层级。**
2. **不误伤与有效性在此不可兼得。** Worker/Verifier 须跑任意项目的测试/lint/build，命令形态
   不可穷举；要拦住 `>` 就会连 `2>&1`、`>/dev/null` 一起拦（上表第 4 行实测），而这些是跑
   测试与 `verify*.sh` 的常规写法。写一份「不误伤的 deny 清单」等于写一份不拦任何真实
   逃逸路径的清单——那正是本域反复禁止的空转保障。
3. **粒度不匹配。** `permissions` 是**会话全局**，不按角色分层；它无法表达「只约束 Worker」。
   本框架的缺口是角色相关的（Thinker 侧已由未授予 `Bash` 彻底关闭），全局规则会同时落到
   Orchestrator 主会话上。

故残留缺口保留，但归因更正为：**宿主提供了 `permissions` 路线，本框架评估后未采用，理由
是判据对象为命令字符串（看不见脚本内部）、不误伤与有效性不可兼得、且粒度为会话全局而
非按角色。** 即：

> **Worker/Verifier 可通过 Bash 重定向、`sed -i`、`tee` 写任意路径，两道强制点都拦不住。**
> 这与本域开头「防误撞而非安全边界」的定位一致，但必须显式登记，不得被
> 「已归位到宿主原生形态」的说法遮蔽。

另有一条同样消费 permission rule 语法的路线：`PreToolUse` 的 hook matcher 支持
`Bash(pattern)` 形态以收窄触发条件。它只改变 hook **何时被调用**，判定仍落回脚本，
故同样受理由 1 制约（matcher 匹配的也是命令字符串）。若将来要做，须另开 CR，且只做保守的
危险形态识别，代价是误报与命令解析的固有不可靠性。

#### `verify*.sh` 为何不上 hook 事件（CR-020 R4 的判断记录）

需求要求「可由宿主事件驱动的门禁改由事件触发」。`verify*.sh` **不属于**该集合，故不上事件：
它们是**阶段性**门禁，需要 `.state.md` 的 phase 与交付物齐备才有意义。绑 `PostToolUse`
会在每次工具调用后触发，在交付物尚未齐备时大量误报，并显著拖慢每次写入。

本 CR 新增的唯一事件是 `SessionStart` → `scripts/session-context.sh`，形态为 **sensor**：
只读状态、只打印、恒 `exit 0`，不返回权限决策，故不可能阻断默认会话。
非法 slug 在该脚本中只提示不 `exit 2`——判权是 role-guard 的职责，sensor 不判权。

### 交还谓词的接受集必须等于读取端（双向，不是单向）

**不变量：交还谓词的接受集 = 读取端判为 `ORCHESTRATOR` 的集合。两个方向都不许偏。**

- 谓词**更严** → 写入方按 schema 示例书写却被判伪交还（「读得出但写不进」），单向闭锁缺陷换形态复发。
- 谓词**更宽** → 写得进的内容其生效角色并非 ORCHESTRATOR（「写得进但读不出」），即横向夺权。

⛔ **这条不变量最初写成单向（`⊇`），那个方向性错误本身就是一个 P0 缺陷的根因。** 详见下方「存在性量词」。**只防单侧的不变量会让另一侧的缺陷合法通过评审** —— 它确实通过了设计评审、Developer 自检与 Tester 两轮 217 项断言。

实现直接复用读取端的解析，不再写正则去模拟它：

```bash
effective=$(printf '%s\n' "$NEW_CONTENT" | grep '^current_role:' | head -1 | awk '{print $2}')
[[ "$effective" == "ORCHESTRATOR" ]]
```

**两端同源则结构上无从分歧**，无须人工核对「这个正则是否与解析器等价」——那种核对正是上一版失败的地方。

#### 存在性量词与首行语义的分歧（P0，audit 发现）

旧实现 `grep -qE '^current_role:[[:space:]]+ORCHESTRATOR([[:space:]]|$)'` 是**存在性量词**：内容中任一行匹配即放行。而读取端取**首行首值**（`head -1`）。多行内容上两端结论不同：

| 载荷（THINKER 持权，写本需求 `.state.md`） | 旧谓词 | 落盘后生效角色 |
|---|---|---|
| 首行 `current_role: WORKER` + 末行 `current_role: ORCHESTRATOR` | 放行 | `WORKER` |
| 首行 `current_role: THINKER,ORCHESTRATOR` + 末行 `current_role: ORCHESTRATOR` | 放行 | `THINKER,ORCHESTRATOR` |

第二种载荷即完整夺权链：写入放行 → 生效角色含 ORCHESTRATOR → 持权者取得 `handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log` 与全局 `deliverables/.state.md` 的写权（同一 state 下直接写这些是 `exit 2`）。基线 `156c49a` 对两种载荷均 `exit 2`，故这是新开的例外口子在多行内容上开得过宽，不是既有缺陷。

**旧谓词下 `Edit` 仅追加一行即可完成夺权**，原派发行无须触碰。故「交还须一次完整写入」是协议约束，**不是安全约束**——它只约束合作者，不约束刻意绕过（与本域「自授权」定位一致）。

#### 交还例外只接受 Write —— Edit 的片段判据无法覆盖合并结果（P0，audit F-01）

`Edit` 载荷只有 `new_string`，守卫看不到 `old_string`，也看不到合并后的文件。因此谓词判的是**片段的首行生效值**，而落盘后真正决定权限的是**合并后文件的首行生效值**。**两端比较的不是同一份内容，双向不变量在 Edit 通道上并未真正成立。**

`old_string` 跨行、从上一行中部延伸到 `current_role` 行时，片段首行被拼进上一行残段而不再行首匹配，片段第二行的诱饵在合并后升为生效行——**排列在合并这一步被反转**：

```
磁盘:   current_step: THINK-DESIGN
        current_role: THINKER

old_string = "DESIGN\ncurrent_role: THINKER"
new_string = "current_role: ORCHESTRATOR\ncurrent_role: THINKER,ORCHESTRATOR"
              ^ 片段首行，判据据此放行

合并后: current_step: THINK-current_role: ORCHESTRATOR   ← 被吸收，不再行首匹配
        current_role: THINKER,ORCHESTRATOR               ← 升为生效行
```

三种实测可达形态：落盘 `THINKER,ORCHESTRATOR`（取得 ORCHESTRATOR 的整个 `.engine/` 写权与全局 `.state.md`）、落盘 `WORKER`（横向夺权取得项目代码路径）、`current_role` 行整体消失（读取端解析为空 → `CURRENT_ROLES` 空 → `exit 0`，**守卫在该 state 上整体失效**，含跨需求路径全放行）。

**处置：交还例外只接受 `Write`**（`[[ "$TOOL_NAME" == "Write" ]]`）。`Write` 的 `content` 即完整落盘内容，片段 == 合并态，该类分歧结构性消失——不必在守卫内模拟 Edit 替换语义（那需处理 `old_string` 缺失、多处匹配、`replace_all` 等，且与工具实现耦合）。协议侧本就约定「交还须一次完整写入」，故此收紧与既有纪律一致，只是把软约束变成硬约束。

⛔ **两次 P0 同源：守卫的判定对象必须与读取端的生效对象是同一份内容。** P0-1 的分歧点在**量词**（存在性 vs 首行），F-01 的分歧点在**判定对象**（片段 vs 合并态）。修 P0-1 时收紧的双向不变量本身正确，但它只约束了「怎么解析」，没约束「解析谁」——**不变量的适用前提也必须写明**，否则同一个错误换个层面复发。

**Planner 曾据「`old_string` 与行边界对齐」的枚举判定此缺口为 fail-safe 侧、无提权路径；该结论错误。** 那个前提是未声明的隐含假设，放宽到跨行 `old_string` 后即失效。教训：枚举法的结论强度受限于枚举维度是否穷尽，**未声明的前提就是未检验的前提**。

**测试维度教训：** 217 项断言里 5 处双 `current_role` 载荷全是「诱饵在前、真值在后」排列，无一处相反，而存在性量词只在**相反排列**下暴露分歧。同类缺陷的断言必须显式覆盖「真值在前 / 真值在后」两种排列——**加断言数量不等于补维度**。

#### 首行语义如何覆盖原三段锚定的职责

`grep -qx` 亦已实测否决（它拒绝 `current_role: ORCHESTRATOR # 注释` 与多空格形态，而读取端接受，属「更严」侧违反）。现行首行解析同时挡住原先靠三段锚定挡的形态：缩进、`#` 注释、引号包裹均不被 `^current_role:` 命中；`current_role_backup:` 同理；`ORCHESTRATORX` 与 `THINKER,ORCHESTRATOR` 作为 `$2` 整体值不等于 `ORCHESTRATOR`；`current_role:ORCHESTRATOR`（无空格）两端一致解析为空值，故一致拒绝。

判据只取本次写入的**新内容**（`Write` 的 `.tool_input.content`），**不读磁盘**：磁盘上的 `current_role` 恒为派发角色，用它判定等于永不成立。交还例外只接受 `Write`（理由见下节），故一次逻辑状态迁移对应一次守卫判定，且判定对象与落盘内容同一。`.ipynb` 不承载流程状态，`NotebookEdit` 不参与交还例外；`Edit` 写 `.engine/.state.md` 一律拒绝。

### 归属层面：判定对象与真实对象不一致的第三个实例（CR-017）

CR-016 在**量词**（存在性 vs 首行）与**判定对象**（片段 vs 合并态）两个层面各修一次，CR-017 修剩下的**归属**层面。三者同源：授权判定的主体与真实主体不一致。

`templates/handoff-template.md` 自 `f150a4c`（CR-003，hook 落地首日）即规定完成回报「执行角色必填」，而 `handoffs/` 是守卫的 ORCHESTRATOR 独占路径 —— 三角色写入一律 `exit 2`。**协议强制要求的动作，守卫结构性禁止。**

潜伏十余个 CR 未被发现，因为它不阻塞流程：Orchestrator 收回持权代填即可绕过。**真实代价不是流程阻塞，是证据链失效** —— 代填后回报变成「Orchestrator 撰写、Orchestrator 审计」，质量门禁 Step 0 核对 `read_files` 的判定对象（回报）不再是真实对象（角色实际读了什么），退化为依赖 SubAgent 进程内返回值的诚实性，无落盘证据。

处置：回报移出 handoff，落到 `.engine/reports/<handoff-basename>.report.md`。

- **目录即权限边界。** 不在 `handoffs/` 内按后缀区分写权 —— `handoffs/x.report.md` 与 `handoffs/x.md` 的正则会互相咬边，是锚定类缺陷的温床。
- **派生命名而非自由命名。** 门禁要能从 handoff 路径机械算出回报路径，不靠内容里的自述指针：**自述指针可被改写，路径派生不能。**
- **写权分离即 R2。** 白名单在 handoff（角色不可写），`read_files` 在回报（角色可写）。比较的两侧落在两个文件、两套写权，故执行角色无法改写被比较的一侧使越权自洽。放开三角色对 `handoffs/*.md` 的写权是被否决的方案，因为那让执行角色同时掌握两侧，比现状更糟。
- **本条无内容判据，且这是有意的。** 内容判据是 CR-016 两个 P0 的共同载体，能不引入就不引入。回报不承载流程状态，无需 `is_handback` 那类检查；**无多行判据即无排列可反转**，排列次序对抗在此条上不适用。
- 路径正则锚定要求与交还例外同源（见下文两节）：`^…$` 双向锚定，`${req}` 取自当前 state 故不跨需求。

**能力边界（R6）：本改动提升的是落盘可追溯性，不是身份认证。** 守卫仍无法证明 `reports/x.report.md` 是 Thinker 写的 —— 载荷不含 `agent_type`。回报由谁写仍不可验证，只是现在**有了可 diff、可留痕的落盘物**，而非进程内返回值。

回报写权按「当前谁持权」而非「文件名声称的角色」约束：三角色共用同一条正则，不按角色前缀细分。加角色前缀判据会引入「文件名声称的角色」与「state 里的角色」两个主体 —— 正是本 CR 要消除的那类不一致。故 THINKER 持权时写 `…-DEV1-T1-R1.report.md` 是 `exit 0`，这是设计选择而非缺口。

#### 元教训：协议文本与守卫实现分处两个文件、无交叉校验，矛盾可潜伏十余个 CR

`f150a4c` 引入 `handoffs/` 独占规则时，模板已写着「执行角色必填」。**两处从未对照。** 十余个 CR 里每一次都有人读过模板、也有人读过守卫，没有一次把两者并排看。

这不是疏忽而是结构问题：没有任何门禁检查「协议文本声明的写入者」与「守卫放行的角色」是否一致。`docs/audits/` 的历次审计也未覆盖 —— 审计对象是守卫行为，不是守卫与协议的一致性。凡「规范说 A 必须做 X」而「机制禁止 A 做 X」的矛盾，都只能靠人在两个文件间主动串联才能发现。**验收须交叉验证两侧文本 + 一条守卫断言，而不是只测守卫自身自洽。**

同源归档：外部项目 `~/Code/mini-agent` 使用本框架时撞到同一矛盾（其 `lessons.md` EXP-2）。该 lessons 出不了那个仓库，但教训是框架级的 —— **框架缺陷由下游使用者先撞到，说明框架自身的自检维度缺了「协议与实现的一致性」这一格。**

### 交还例外不得放大为引擎态直通

放行条件是「路径为本交付物的 `.engine/.state.md`」**且**「本次写入交还给 ORCHESTRATOR」。`handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log` 不在放行正则内，内容含交还标记也照旧拒绝。`${req}` 取自全局指针 `deliverables/.state.md` 的 `project`（CR-018 前取自 REQ state 的 `req_id`），故跨交付物（`web-cli` 持权写 `deliverables/other/.engine/.state.md`）不命中。放行落在 `check_permission()` 的 `THINKER`/`WORKER`/`VERIFIER` 三个分支内而非函数外，多角色形态（`THINKER,VERIFIER`）由「任一分支命中即放行」自动继承，ORCHESTRATOR 分支无须改动。

**路径正则必须 `^…$` 双向锚定。** `[[ =~ ]]` 是无锚 ERE，写成 `deliverables/${req}/\.engine/\.state\.md` 时 `.state.md` 只是前缀，例外立刻从「单个 state 文件的一条状态机边」放大为「`.engine/` 目录直通」：持权角色在写入内容里带一行 `current_role: ORCHESTRATOR`，即可新建或覆盖 `.state.md.evil`、`.state.md.sh`、`.state.mdX`、`.state.md/child.md`。缺 `^` 锚同理放过 `x/deliverables/${req}/.engine/.state.md` 一类嵌套伪造路径。判据侧的行首锚定（上一节）与路径侧的双向锚定是两个独立的锚定要求，任缺其一例外都会被放大。左锚安全的前提是 `$file` 已是归一化后的仓库相对路径（`NORM_PATH`）。

### 产品区授权从否定式改肯定式（CR-018 R6）

改动前 WORKER 的产品区谓词是**否定式**：「`deliverables/${req}/` 下，不含 `.engine/`、不含 `THINKER-`/`VERIFIER-`/`ORCHESTRATOR-` 前缀、不是 `.archiveignore` 的路径皆可写」。它的授权边界完全寄生于**其他角色的文件命名前缀**——前缀是唯一的分隔物。

CR-018 R3 把产品区的角色前缀去掉后，该谓词的排除项全部落空，**退化为「产品区全通」**。这不是命名改动的副作用，而是否定式授权的固有脆弱性：它表达的是「不属于别人的都是我的」，一旦「别人的」失去可识别特征，剩余集合就是全部。

新表是肯定式的：每角色列出自己可写的路径集，归属由**目录**承载而非文件名前缀。

| 角色 | 产品区 | 引擎态 |
|---|---|---|
| ORCHESTRATOR | `docs/`、`tests/regression-suite.md` | `.state.md`、`handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log`、`proposal.md`、`archive-manifest.md`、`baselines/`、`quality-gate-report.md`、`reports/*.report.md`、全局 `deliverables/.state.md` |
| THINKER | `docs/spec/`、`assets/`、`.archiveignore` | `verify-strategy.md`、`reports/*.report.md`、交还例外 |
| WORKER | `src/`、`tests/`、`deploy/`、`assets/`、根文件全名白名单 | `code-report-*.md`、`quality-gate-report.md`、`reports/*.report.md`、交还例外 |
| VERIFIER | `tests/` | `final-test-report.md`、`temp-test-report.md`、`reports/*.report.md`、交还例外 |

三点须记住：

- **WORKER 不可写 `docs/`。** 规格文档的写权归 THINKER（产出）与 ORCHESTRATOR（ARC 归档）。否定式谓词下 WORKER 本可写 `docs/`，这是它退化为全通的一部分。
- **共写是显式声明，不是漏洞。** `tests/` 由 WORKER 与 VERIFIER 共写（TDD 的 Red 步 vs 回归测试，既有分工），`assets/` 由 THINKER 与 WORKER 共写（wireframes vs 运行期静态资源），`quality-gate-report.md` 由 WORKER 与 ORCHESTRATOR 共写，`reports/` 四角色共写（CR-017 D1）。共写方产出同类文件，不构成越权。
- **产品区根用全名白名单，不用模式匹配。** `README.md`、`package.json`、`*.html`/`*.css`（ppt 单文件形态）等逐条列出。用「根目录下任意文件」会让产品区根重新变成散落区，正是 R3 要消除的形态。清单与 `templates/output-structure.md` 同源，改一处须改两处。

**每一条都须 `^…$` 双向锚定，包括目录前缀条目。** 目录前缀写成 `^deliverables/${req}/src/.+$`：尾部 `.+` 使目录自身不命中，左锚使 `x/deliverables/${req}/src/a.ts` 不命中。这与交还例外的锚定要求同源（见上节），只是作用于更多条目。

### 活跃交付物定位以全局指针为准，绝不退化为扫描（CR-018 R7）

改动前用 `find "$ROOT/deliverables" -maxdepth 3 -name ".state.md" -path "*/.engine/.state.md" | head -1` 取活跃需求。目录名从 `REQ00N` 变为项目名后，`deliverables/` 下多项目并存成为常态形态，`head -1` 取到的是**文件系统枚举顺序上的任意一个**项目，守卫据此读 `current_role` 与标识符判权即失效——非指针所指的交付物其状态会决定另一个交付物的写权。

现以全局指针 `deliverables/.state.md` 的 `project` 字段定位，五种异常形态穷举如下：

| 形态 | 行为 | 理由 |
|---|---|---|
| 指针文件不存在 | exit 0 放行 | 无活跃交付物，等价于 `/mh-run` 未启动 |
| 指针存在但 `project` 空 | exit 0 放行 | 初始化中途的正常瞬态 |
| `project` 非法 slug | **exit 2 拦截** | 唯一收紧项：合法流程不会写入非法 slug，出现即 state 被污染，此时放行等于在污染态下判权 |
| 指针指向的交付物目录/state 不存在 | exit 0 放行 | 指针滞后于目录（如手工清理），非越权信号 |
| `current_role` 空/畸形 | exit 0 放行 | 沿用既有语义 |

**任一形态下都不再遍历 `deliverables/` 寻找替代 state。** 放行为主与守卫定位一致（防误撞而非安全边界）：误拦会使正常流程中断且原因难查，漏拦的后果由「守卫本就不是安全边界」这一既有定位承担。唯一的 exit 2 留给污染态——那是唯一无法用正常流程解释的形态。

**消费侧必须独立校验标识符。** `${project}` 被插值进 `[[ =~ ]]` 正则与路径拼接，故守卫在插值前调 `scripts/validate-slug.sh`，不信任生成侧（mh-intake）的校验：指针文件是被治理方可写的，生成侧校验可被绕过。字符集 `^[a-z][a-z0-9-]{0,63}$` 使标识符**正则字面量安全**（`a-z0-9-` 在 ERE 中无元字符语义），故无需引入转义层；反之若允许 `.`，`project: web.cli` 会命中 `webXcli`，允许 `/` 或 `..` 则直接是路径穿越。这也是 `docs`/`src`/`tests`/`deploy`/`assets`/`reference`/`engine` 须列为保留名的原因——交付目录与其内部目录同名会使路径归属产生歧义。

校验点落在守卫内而非仅在生成侧，也顺带收窄了一类既有缺陷：CR-017 审计记录过 `req_id` 未转义即插入 ERE（写成 `req_id: .*` 可令白名单跨需求生效），当时判为「基线既有、非该 CR 新开」而未修。字符集校验使同类注入在插值前即被拦下，`project: .*` 现在 `exit 2`。但**这不是把守卫升级成了安全边界**——判据仍存放在被治理方可写的文件里（`project` 字段本身即是新增的一处自授权判据面），持权者仍可写一个合法 slug 指向别处。它挡住的是「畸形值让正则语义漂移」，不是「有意改判据」。

**指针的引入使自授权判据面从一处变为两处。** 原先只有 `deliverables/{project}/.engine/.state.md` 的 `current_role`；现在 `deliverables/.state.md` 的 `project` 也参与定位，且其写权归 ORCHESTRATOR。改指针即可切换「哪个交付物的 `current_role` 说话」。这与既有定位一致（自授权、防误撞），记在此处是为了让后续 CR 在推理守卫行为时把两个文件都算进来——只看 REQ state 会漏掉一层。

### 按路径归属路由，两条流水线不得互相阻断

归一化后按 `case "$NORM_PATH" in deliverables/*)` 判定归属：`deliverables/` 归 `/mh-run` 角色白名单，其余归 mh-dev 框架治理。两个流程的路径集不相交，故可共存。

旧实现以「不存在活跃 REQ state」（`-z "$STATE_FILE"`）作为 mh-dev 分支的进入条件，一个全局且偶然的耦合，派生两个反向缺陷：任意 REQ state 存在（含 `done` 终态残留）即永久关闭框架治理入口；而 `CURRENT_ROLES` 为空时的无条件 `exit 0` 又覆盖框架路径，使空/畸形 REQ state 反向绕过整个 `approved_scope`。**失效开放（fail-open）的兜底分支必须限定在它该管的路径集内**——`CURRENT_ROLES` 空则放行保留在 `/mh-run` 分支内，框架路径在上一层就已被路由走。

归属判定必须是目录前缀语义：`deliverables-evil/`、`mydeliverables/`、`docs/deliverables/` 均不命中 `deliverables/*`，落入框架分支。判定用 `NORM_PATH` 而非原始 `FILE_PATH`，故绝对路径写法归属同样正确——归一化因此必须上移到路由之前，两分支共用。仓库外绝对路径的拦截随之上移，对两分支一致生效（消息不再含 `mh-dev` 字样）。

顺带修复一处不对称：旧实现下只要存在活跃 REQ state，mh-dev 的 Tester 就写不了 `tests/`（mh-dev 分支被跳过，落到角色白名单后 `tests/` 无人有权）。路由后 `tests/` 归框架分支，Tester 放行照常生效。

### 载荷路径参数缺失取保守放行

`Write`/`Edit` 取 `.tool_input.file_path`，`NotebookEdit` 取 `.tool_input.notebook_path`——沿用 `file_path` 会取到空值而整条通道静默绕过。路径参数缺失时 `exit 0` 并向 stderr 打印 `WARN: <tool> 缺少路径参数，守卫跳过`，不 `exit 2`：此处硬阻断会把任何上游载荷契约变动变成全局阻断，且与真实越权无法区分，代价高于收益（守卫定位为防误撞）。这是对 CR-016 R5「不得默认放行」的一处有意偏离，已审批记录在案。

## 约束与陷阱

### mh-dev 分支的角色维度校验为何未落地（CR-017 D3，实现受阻）

需求 R5 要求守卫按写入者角色收窄 mh-dev 分支放行集，设计 D3 指定判据取 `tools/mh-dev/.mh-dev/state.json` 的 `current_role`。**该判据不可用，D3 未实现**，`approved_scope` 仍是 mh-dev 分支的唯一判据。

阻塞事实（均已实测）：

1. **`current_role` 恒为 `planner`。** `transition-state.sh:19` 每次状态转移都硬写 `'planner'`，`state.json.template:6` 初值同样是 `planner`，仓库内**没有任何代码路径**会把它写成 `developer` 或 `tester`。该字段表达的是「谁在驱动流程」（Planner 始终是主会话），不是「谁在写这个文件」。
2. **按 D3 表实现即 Developer 全程锁死。** Developer 运行期间字段值是 `planner`，而 `planner` 行只允许运行态与 `CR-*.md`，故 `approved_scope` 内的每个框架文件都 `exit 2` —— 包括 `scripts/role-guard.sh` 自身。实测中该实现把守卫改到一半即自锁，此后连修回来都要绕过 hook。
3. **判据与 `validate-changes.sh` 并非同源。** 那边的 `role` 来自命令行 `--role`（Planner 调用时显式传入），不读 `current_role`。设计称两者「同源」，实际一个是入参、一个是状态字段，取值域都不同。**D 原则 1（判据与读取端同源）在此条上未被满足，而这正是设计自己立下的纪律。**
4. **修 `transition-state.sh` 不在本 CR 范围。** 让字段真实反映写入者需要在每次 spawn 前后改写它，而它由 Planner 独占、且 `transition-state.sh` 不在 `approved_scope` 内。

更根本的是：**即使字段被如实维护，它仍在被治理方自己可写的文件里** —— 与本节开头「自授权机制」同一局限。Planner 写 `state.json`，也就自己签发自己的通行证；CR-016 DEV-01 那次越权若发生在有 D3 之后，Planner 把字段改成 `developer` 即可照旧穿过。故 D3 的收益上限是**防误撞**（提醒角色「这不是你的路径」），不是防越权，需求 R5 若期望后者则期望本身不成立。

可行方向须另开 CR 决策，三条各有代价：hook 载荷无 `agent_type`，故（a）由 Planner 在每次 spawn 前后显式改写 `current_role`（软约束，仍自授权，但能挡误撞）；（b）在 `validate-changes.sh` 侧加严（已是事后校验，挡不住落盘）；（c）接受 mh-dev 轨的角色分离只有软约束，改为在 CI 阶段用 `git diff` 比对角色声明（离线、不阻断写入）。

### role-guard.sh mh-dev 分支的 scope 匹配口径

`approved_scope` 由 Planner 直写 `tools/mh-dev/.mh-dev/state.json`，条目可能是相对路径也可能是绝对路径。匹配采用**双向归一化**：把 scope 条目与目标路径一并转为绝对形态后比较，因此四种组合（scope 相对/绝对 × 写入路径相对/绝对）结论一致。

以 `/` 结尾的 scope 条目按**目录前缀**放行，与 `tools/mh-dev/scripts/validate-changes.sh` 的目录前缀语义对齐（此前两道门禁不对称：`docs/designs/modules/` 能过归属校验却过不了 hook）。条目保留结尾 `/` 是安全关键——`docs/m-evil/` 不以 `docs/m/` 开头，故目录名前缀伪造不会命中。

**Tester 专属路径 `tests/` 与 `tools/mh-dev/tests/` 在 scope 匹配之前按目录前缀放行**，不要求列入 `approved_scope`。这两个前缀在 `tools/mh-dev/scripts/validate-changes.sh` 的 tester_scope 内被无条件认可；若 hook 仍要求精确列出，两道门禁对同一路径结论相反，Tester 落盘任何测试都被 `exit 2` 拦下，`testcase_adding_required=true` 无法被满足。放行写成 `case` 的 `tests/*|tools/mh-dev/tests/*`，是目录前缀语义而非子串匹配——`tests-evil/`、`mytests/`、`tools/mh-dev/tests-evil/` 下的路径与裸文件名 `tests` 均不命中。放行位于归一化之后，故绝对与相对两种写入形态结论一致，且 `/tmp/tests/` 下的路径已在上一步被仓库外判定拦下，含 `..` 的穿越写法被全局穿越检测拦下。

**仓库外绝对路径直接 `exit 2`**，不进入 scope 匹配。`case` 必须分三支（仓库内绝对 / 其余绝对 / 相对），不能写成宽泛的 `/*)` 单分支：后者对 `/tmp/evil.sh` 执行 `${FILE_PATH#$ROOT/}` 不做任何替换，会把一个绝对路径当相对路径带进后续逻辑；此时若 scope 含仓库根自身作目录条目，`$ROOT//tmp/evil.sh` 确以 `$ROOT/` 开头，整个文件系统被放行（已实测复现）。下游 sensitive 判定用相对字面量匹配，该中间态在 sensitive 列表扩项时同样是隐患。

**jq 管道重绑定陷阱。** 目录前缀判定必须先绑定当前条目：

```
正确：any($abs[]; . as $s | ($s | endswith("/")) and ($ap | startswith($s)))
错误：any($abs[]; endswith("/") and ($ap | startswith(.)))
```

错误写法中 `|` 把 `.` 重绑定为管道左侧值，`startswith(.)` 退化为 `$ap | startswith($ap)` 恒真，**放行任意越权路径**（实测一个与 scope 完全无关的 `evil/` 下路径被放行）。

`..` 穿越检测在归一化之前独立生效，不受本口径影响。

### 仓库根推导不依赖 cwd

`ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`。hook 由 Claude Code 触发，cwd 不受脚本控制；`$(pwd)` 会让归一化随调用位置漂移——从子目录触发时仓库内绝对路径无法剥离前缀，进而误拦合法写入。`find "$ROOT/deliverables"`、`MH_DEV_STATE` 默认值、scope 归一化三处共用同一 `ROOT`，故任意 cwd 下退出码与消息一致。

`find` 返回绝对路径使 `STATE_FILE` 变绝对，`check_permission` 用 `[[ =~ ]]` 子串匹配 `deliverables/${req}/...`，绝对路径同样命中，deliverables 分支判定不变。

### verify-ppt.sh 禁止 GNU grep 扩展与错误吞没

仓库运行于 macOS，`/usr/bin/grep` 是 BSD grep，不支持 `-P`/`\K`/前后向断言。交互 shell 的 `grep`
可能被 ugrep 接管而支持 `-P`，导致**人工验证通过、脚本执行失效**——验证脚本行为必须用
`bash script.sh` 实跑。

CR-014 前的字号检查用 `grep -oP 'font-size:\s*\K\d+(?=px)' "$f" 2>/dev/null | awk ... || true`：
BSD grep 报错被 `2>/dev/null` 吞掉，非 0 退出码被 `|| true` 吞掉，结果**恒定通过**。同类失效还有
`grep -c ... || echo "0"`（无匹配时 `grep -c` 已自行输出 `0` 并返回 1，`|| echo "0"` 再补一个，
产出 `"0\n0"` 令整数比较报错后被吞没）与漏 `-maxdepth 1` 导致 wireframe 子目录被重复计数。

现行处置：字号扫描与登记表解析经 `require_ok()` 包装（失败时打印实际 stderr 并累加 ERRORS），
且脚本启动时对已知违规/合规 fixture 自测字号检查一次，行为不符即报"检查器自身失效"并 exit 1。
理由：静态扫描防不住新引入的等价写法，运行时自检才防得住。

`require_ok` 的输出经全局 `REQUIRE_OK_OUT` 回传，**不写 stdout 供 `$(...)` 捕获**——
后者会把 `require_ok` 放进子 shell，`ERRORS` 累加随子 shell 一同丢弃，包装就退化成纯装饰。
这是"注释声称的机制与实现不符"的一类：门禁空转比没有门禁更危险，因为它提供虚假保障。

### 字号检查的覆盖面即其有效性

CR-014 repair round 1：字号扫描只匹配 `font-size: <n>px` 字面量，而设计系统 CSS 的字号
全部走 `var(--font-*)`，字面值只出现在 token 定义行（`--font-caption: 18px`，无 `font-size:`
前缀）。结果 `--font-caption` 可被改到 9px 而静态层与渲染层同时报 PASS。`font: 600 8px/1`
简写同理绕过——而 `ppt-base.html` 骨架自身就用此写法。

处置：静态扫描覆盖三形态（字面量 / `--font-*` token 定义 / `font` 简写），
D 类渲染层对每个文本元素读 `getComputedStyle().fontSize` 作为不可绕过的兜底。
**教训：检查器"能报出违规"不等于"覆盖了违规能出现的全部形态"。** 少一种形态就少一道门。

### bash 变量名与多字节字符相邻

`"$DENSITY（...）"` 中的全角括号会被 bash 并入变量名，`set -u` 下报
`DENSITY?: unbound variable`。中文消息里变量后紧跟非 ASCII 字符时**必须写 `${VAR}`**。
该类缺陷只在特定分支被执行时才暴露，容易漏测。

**判据收紧会把此类潜伏缺陷变成主路径（CR-018 实例）。** `verify-archive.sh` ARC-7 的 `$filename（` 长期缺花括号，但根 `ROLE-*.md` 被显式豁免使该分支在常见输入下不可达；CR-018 R8 删除豁免后它成为主路径，第一个散落文档就触发 `unbound variable`，整个 `check_output_structure()` 中断——**表现为静默跳过而非报错**，收紧后的判据反而完全不生效。教训：放宽一个豁免时要顺带检查被它遮蔽的分支是否可执行，「以前没出问题」只说明那条路没走过。同类未修实例（本 CR 范围外，仅记录）：`scripts/verify.sh:215/265/293/296` 四处 `$var（`，触发条件是 `phase=done` 且 handoff 不足 / process.log 过短 / `repair_round≥3`。

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
| 归档校验 | deliverables/{REQ-ID}/ 完整性 + docs/kb/ 校验 | `scripts/verify-archive.sh` |
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
| `scripts/baseline.sh` | 基线对比 | `docs/designs/design.md` §7.4 |
| `scripts/check-harness.sh` | 框架自检 | `docs/designs/design.md`、`.claude/commands/` |

## 授权模型与能力边界

### role-guard 是自授权机制，不是安全边界

权限判据（`deliverables/{REQ-ID}/.engine/.state.md` 的 `current_role`、`tools/mh-dev/.mh-dev/state.json` 的 `approved_scope`）全部存放在**被治理方自己可写的文件**里。持权角色可以改写判据再写目标，守卫无法阻止。这不是待修的缺陷，而是模型的固有形态：PreToolUse 载荷不含 `agent_type`，SubAgent 是进程内 spawn，守卫无从获知「谁在写」，只能判定「这次写入是否是协议允许的状态迁移」。

三条边界须一并记住：

- **自授权。** `current_role` 表达的是「派发意图」而非「执行者身份」。守卫按意图放行，不校验身份。
- **Bash 通道不受覆盖。** hook matcher 只含 `Write|Edit|NotebookEdit`。`Bash` 工具的重定向、`sed -i`、`tee` 一概绕过守卫。把 Bash 纳入 matcher 需要解析任意 shell 命令的写入目标，不可靠，故不做。
- **定位是防误撞，不是防攻击。** 守卫要挡的是「Orchestrator 手滑替 Worker 写了代码」「SubAgent 越界改了别人的产出」这类协议内失误。对抗刻意绕过不在设计目标内，别把它当访问控制来依赖。

因此：守卫失效属于流程纪律问题，不属于安全事件；但守卫**空转**（判据恒真、通道漏覆盖）比没有守卫更危险，因为它提供虚假保障——`NotebookEdit` 曾长期不在 matcher 内，即一条完全静默的漏覆盖通道。

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

放行条件是「路径为本需求的 `.engine/.state.md`」**且**「本次写入交还给 ORCHESTRATOR」。`handoffs/`、`plan-action.md`、`SR*-record.md`、`lessons.md`、`process.log` 不在放行正则内，内容含交还标记也照旧拒绝。`${req}` 取自当前 state 的 `req_id`，故跨需求（REQ001 持权写 `deliverables/REQ002/.engine/.state.md`）不命中。放行落在 `check_permission()` 的 `THINKER`/`WORKER`/`VERIFIER` 三个分支内而非函数外，多角色形态（`THINKER,VERIFIER`）由「任一分支命中即放行」自动继承，ORCHESTRATOR 分支无须改动。

**路径正则必须 `^…$` 双向锚定。** `[[ =~ ]]` 是无锚 ERE，写成 `deliverables/${req}/\.engine/\.state\.md` 时 `.state.md` 只是前缀，例外立刻从「单个 state 文件的一条状态机边」放大为「`.engine/` 目录直通」：持权角色在写入内容里带一行 `current_role: ORCHESTRATOR`，即可新建或覆盖 `.state.md.evil`、`.state.md.sh`、`.state.mdX`、`.state.md/child.md`。缺 `^` 锚同理放过 `x/deliverables/${req}/.engine/.state.md` 一类嵌套伪造路径。判据侧的行首锚定（上一节）与路径侧的双向锚定是两个独立的锚定要求，任缺其一例外都会被放大。左锚安全的前提是 `$file` 已是归一化后的仓库相对路径（`NORM_PATH`）。

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

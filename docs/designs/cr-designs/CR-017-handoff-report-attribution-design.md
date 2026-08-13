# CR-017 设计：完成回报归属与 mh-dev 角色维度校验

- 需求单: `docs/requirements/CR-017-handoff-report-attribution.md`
- 基线: `cad71365ad8f78db166a8ee5086f96427a0f0ca1`
- 轨道: formal

## 设计原则

本 CR 的两个问题同源于「授权判定的主体与真实主体不一致」。修法遵循 CR-016 立下的两条纪律：

1. **判据与读取端同源** —— 不写第二份等价逻辑靠人工核对，结构上消除分歧可能。
2. **不变量必须双向** —— 更严则误伤合法操作，更宽则提权。单侧不变量本身就曾是 P0 的成因。

## D1 完成回报独立落盘：`<REQ>/.engine/reports/<handoff-basename>.report.md`

回报从 handoff 文件内移出，落到 `.engine/reports/` 下的独立文件，文件名由所属 handoff 的 basename 派生。

```
deliverables/REQ001/.engine/
├── handoffs/REQ001-THINK-NEEDS-R1.md          ← Orchestrator 独占（任务+白名单+约束）
└── reports/REQ001-THINK-NEEDS-R1.report.md    ← 被派发角色可写（回报）
```

**为何派生命名而非自由命名：** 回报与 handoff 须一对一可机械关联，门禁（R4）要能从 handoff 路径直接算出回报路径，不靠内容里的自述指针。自述指针可被改写，路径派生不能。

**为何单独目录而非 `handoffs/` 内同名：** 目录即权限边界。`handoffs/*` 保持 ORCHESTRATOR 独占的单一规则，无需在同一目录内按后缀区分写权 —— 后缀区分会让 `handoffs/x.report.md` 与 `handoffs/x.md` 的正则互相咬边，是 AX-02 类缺陷的温床。

**R2 由此满足：** 白名单在 handoff 文件（角色不可写），`read_files` 在回报文件（角色可写）。比较的两侧落在两个文件、两套写权，无法自洽伪造。

### 放行判据

在 THINKER/WORKER/VERIFIER 三分支各加一条，与既有交还例外并列：

```bash
[[ "$file" =~ ^deliverables/${req}/\.engine/reports/.*\.report\.md$ ]] && return 0
```

- `^…$` 双向锚定（AX-02）。左锚拒 `x/deliverables/…` 嵌套伪造，右锚拒 `.report.md.evil`、`.report.mdX`、`.report.md/child.md`。
- `${req}` 取自当前 state 的 `req_id`，故不跨需求（AX-03）。
- `.report.md` 双段后缀而非 `.md`：与 `handoffs/` 下的命名形态显式区分，误写进错目录时不会被静默放行。
- 无内容判据。回报不承载流程状态，不需要 `is_handback` 那类内容检查，**因此 AX-06 的排列次序对抗在本条上不适用** —— 无多行判据即无排列可反转。这是有意的设计选择：内容判据是 CR-016 两个 P0 的共同载体，能不引入就不引入。
- ORCHESTRATOR 分支同样加该条（AC-02）。驳回轮次与 SubAgent 失联时的兜底代填仍需此权限；代填不再是绕过而是显式兜底。

### 跨角色隔离（AX-04）

三角色共用同一条正则，不按角色前缀细分。理由：回报文件名由 handoff basename 派生，而 handoff 由 Orchestrator 按棒次命名，同一时刻只有一个 handoff 在派发中，`current_role` 即该棒的执行者。再加角色前缀判据会引入「文件名声称的角色」与「state 里的角色」两个主体，正是本 CR 要消除的那类不一致。

AX-04 的期望行为据此明确为：THINKER 持权时写 `…-DEV1-T1-R1.report.md`（WORKER 棒次的回报）**exit 0** —— 该路径不由角色前缀约束，而由「当前谁持权」约束。测试须按此断言，不得按「角色前缀隔离」断言。

> 这是对需求单 AX-04 表述的收窄，理由如上。若坚持角色前缀隔离，须引入第二主体，代价大于收益。

## D2 R4：门禁读取端与回报位置同源

`scripts/verify.sh:212-231` 与 `scripts/verify-qa.sh:112-121` 改为遍历 `reports/*.report.md`，字段检查逻辑不变（`status: pending`、`summary` 空、`output_files: []`）。

**同源保证：** 两个脚本都从 handoff 路径派生回报路径，不各自硬编码。回报缺失（handoff 存在但无对应回报）须产出 WARN —— 这是新增的检查点，旧结构下「回报未填」表现为字段为空，新结构下表现为文件不存在，不补则漏。

保持 WARN 级不升 FAIL：本 CR 不改门禁严格度，只改读取位置。升级严格度是独立决策，混进来会让回归对比失去基线。

## D3 R5：mh-dev 分支角色维度校验

守卫读 `tools/mh-dev/.mh-dev/state.json` 的 `current_role` 字段（`transition-state.sh:19` 写入，值为 `planner`），按角色收窄放行集：

| 角色 | 可写路径 |
|---|---|
| `planner` | `tools/mh-dev/.mh-dev/` 运行态、`docs/requirements/CR-*.md`、`docs/designs/cr-designs/CR-*-design.md` |
| `developer` | `approved_scope` 命中且非 `tests/**` |
| `tester` | `tests/**`、`tools/mh-dev/tests/**`、`evidence/test-verdict.json`、`evidence/test-report.md` |
| 缺失/空/未知/多值 | 拒绝 `approved_scope` 全量放行，仅保留运行态与 Tester 专属路径（AX-09） |

**判据与 `validate-changes.sh` 同源（D 原则 1）：** 上表即 `validate-changes.sh:40-72` 已实现的 `allowed_dev` / `tester_scope` / `role_runtime_evidence` 模型。守卫不新造一套，两道门禁对同一路径必须结论一致 —— 结论相反时 Developer 落不了盘或 Tester 被拦，这是 CR-016 修 `tests/` 放行时踩过的坑。

**fail-open 收敛方向为拒绝（AX-09）：** 与 `/mh-run` 分支相反。`/mh-run` 分支在 `current_role` 为空时 `exit 0`，因为那代表「无活跃需求」；mh-dev 分支进到此处已确认 `phase` 是活跃阶段，`current_role` 异常代表状态损坏，此时放行等于 CR-016 DEV-01 复发。

**默认会话透明性不变（AX-10）：** 本改动全部落在「已确认活跃治理」的 `if` 块内。无活跃授权时的 `exit 0`（`role-guard.sh:117`）逐字不动。

## D4 R6：文档口径

`docs/kb/domains/guards.md` 新增归属层面复发记录，须写明三点：

1. 回报独立落盘提升的是**落盘可追溯性**，不是身份认证。守卫仍无法证明 `reports/x.report.md` 是 Thinker 写的（payload 无 `agent_type`，CR-016 已确认）。
2. D3 的角色校验判据同样来自被治理方可写的 `state.json`，仍是**自授权机制**，`Bash` 通道不受覆盖。
3. 归档 mini-agent 的 EXP-2 —— 该 lessons 出不了那个仓库，但教训是框架级的。

同时记录本次的元教训：**协议文本与守卫实现分处两个文件、无交叉校验，矛盾可潜伏十余个 CR**。`f150a4c` 引入独占规则时模板已写「执行角色必填」，两处从未对照。

## 影响文件

| 文件 | 改动 |
|---|---|
| `scripts/role-guard.sh` | 四分支各加回报放行条；mh-dev 分支加角色维度校验 |
| `scripts/verify.sh` | 回报读取位置 + 回报缺失检查 |
| `scripts/verify-qa.sh` | QA-4 读取位置 |
| `templates/handoff-template.md` | 回报节移出，改为指向回报文件路径 |
| `templates/handoff-examples.md` | 示例改为独立回报文件形态 |
| `templates/orchestrator-quality-gate.md` | Step 0 核对来源 |
| `templates/output-structure.md` | 目录树加 `reports/` |
| `skills/mh-codeflow/SKILL.md` | 调度循环第 6 步、Step 0 |
| `agents/orchestrator.md` | 写权清单 |
| `docs/designs/source-of-truth.md`、`workflow.md` | 守卫口径 |
| `docs/kb/domains/guards.md` | D4 |
| `CHANGELOG.md` | 变更记录 |

## D3 撤回（Developer round 0 实测否决）

**D3 不可实现，设计缺陷在我。** 三条实测结论：

1. **判据字段恒为单值。** `current_role` 由 `transition-state.sh:19` 每次转移硬写为 `planner`，`state.json.template:6` 同值，全仓库无任何代码路径会写成 `developer`/`tester`。按 D3 表实现的直接后果是 Developer 全程锁死——`approved_scope` 内每个框架文件都 `exit 2`，含 `role-guard.sh` 自身，改到一半即自锁。
2. **「与 `validate-changes.sh` 同源」不成立。** 那边的 role 来自命令行 `--role` 入参，是**调用方声明的一次性参数**；state 里的 `current_role` 是**持久字段**。两者取值域不同。我把「字段名相同」当成了「同源」，D 原则 1 在此条上从未被满足。
3. **收益上限是防误撞，非防越权。** 判据仍在被治理方可写的文件里，Planner 把它改成 `developer` 即可穿过。R5 若期望阻止越权，该期望在当前 hook 载荷能力下不成立（payload 无 `agent_type`，CR-016 已确认）。

**这是同一病灶的第四次复发：判定对象与真实对象不一致。** 前三次分别在量词（P0-1）、判定对象（F-01）、授权主体（DEV-01）。这次在**字段语义**——我把「字段叫 `current_role`」当成了「字段承载写入者身份」，且未实测即写入设计。教训与 CR-016 记下的同一条：**未声明的前提就是未检验的前提**。我当时把它写进了 guards.md，这次仍未执行。

R5 顺延至独立 CR，须先解决判据载体问题（三条可行方向见 `docs/kb/domains/guards.md`）。本 CR 交付范围收敛为 D1/D2/D4。

## 对需求的偏离

| 条目 | 偏离 | 理由 |
|---|---|---|
| AX-04 | 从「角色前缀隔离」收窄为「当前持权者约束」 | 见 D1 跨角色隔离节。角色前缀会引入第二主体，与本 CR 主题相悖 |
| AX-06 | 在回报放行条上不适用 | D1 无内容判据。D3 撤回后其多角色形态断言一并失效，本项仅保留「实测确认 D1 确实不读内容」 |
| R5 / AC-06 / AX-09 | 本 CR 不交付，顺延独立 CR | D3 撤回，理由见上节 |
| R4 附带 | 顺带修 `verify.sh` 的 `set -u` 崩溃 | 基线即崩（`$req_id` 第 9 行引用、第 14 行赋值），A~E 类检查从未执行。R4 要保护的门禁所在脚本跑不起来是最彻底的静默失效 |

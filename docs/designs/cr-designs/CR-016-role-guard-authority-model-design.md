# CR-016 role-guard 授权模型修正 — 设计

- 需求单：`docs/requirements/CR-016-role-guard-authority-model.md`
- 轨道：formal
- 日期：2026-08-13

---

## 设计原则

守卫无法获知执行者身份（PreToolUse 载荷无 `agent_type`，SubAgent 为进程内 spawn）。本 CR **不试图**伪造身份维度，而是承认该限制，并把授权判据从「谁在写」改为「这次写入是否是协议允许的状态迁移」。

即：`current_role` 仍是派发意图，不假装它是身份；但对 `.engine/.state.md` 这一个文件，额外允许一种**协议内迁移**——交还给 ORCHESTRATOR。守卫从「静态白名单」变为「白名单 + 一条状态机边」。

---

## D1: 交还例外（R1 + R2）

### 判定位置

`check_permission()` 的 `THINKER`/`WORKER`/`VERIFIER` 三个分支各自新增一条放行，不放在函数外——放在函数内可自动继承多角色循环语义（`THINKER,VERIFIER` 任一分支命中即放行），且 ORCHESTRATOR 分支无须改动。

三个分支共用一个谓词函数 `is_handback()`，避免三份重复实现漂移。

### 判定输入

从 hook 载荷取本次写入的**新内容**，不读磁盘：

| 工具 | 内容字段 |
|------|---------|
| Write | `.tool_input.content` |
| Edit | ~~`.tool_input.new_string`~~ —— audit F-01 后不再参与交还例外（见下） |
| NotebookEdit | 不适用（`.ipynb` 不承载流程状态，交还例外不对其开放） |

`INPUT` 已在脚本开头读入，新增两次 `jq -r` 提取即可，不增加进程往返成本量级。

### 谓词定义

```
is_handback():
  内容中存在一行，去除行尾空白后精确等于 "current_role: ORCHESTRATOR"
  （行首无空白，字段名后单个冒号+单个空格，值为裸 ORCHESTRATOR）
```

实现用行首锚定的 ERE（BSD grep 支持 `-E`，禁用 `-P`）：

```bash
is_handback() {
  [[ -n "$NEW_CONTENT" ]] || return 1
  printf '%s\n' "$NEW_CONTENT" | grep -qE '^current_role:[[:space:]]+ORCHESTRATOR([[:space:]]|$)'
}
```

三段锚定各有其职：行首 `^` 排除缩进与引号包裹；字段名后紧跟 `:` 排除 `current_role_backup`；值后要求空白或行尾，排除 `ORCHESTRATORX` 与 `THINKER,ORCHESTRATOR`。

AX-03 的四种伪造形态与 AX-02 的三种伪交还形态均不命中：

| 形态 | 结论 | 原因 |
|---|---|---|
| `# current_role: ORCHESTRATOR` | DENY | 行首为 `#` |
| `"current_role: ORCHESTRATOR"` | DENY | 行首为引号 |
| `current_role_backup: ORCHESTRATOR` | DENY | 字段名后非 `:` |
| `  current_role: ORCHESTRATOR`（缩进） | DENY | 行首有空白 |
| `current_role: THINKER,ORCHESTRATOR` | DENY | 值后非空白/行尾 |
| `current_role: ORCHESTRATORX` | DENY | 同上 |
| 不含 `current_role` 行 / 空内容 | DENY | 无匹配 |

**为何不用 `grep -qx`（整行精确匹配）：** 已实测否决。`-qx` 会拒绝 `current_role: ORCHESTRATOR # restored` 与 `current_role:   ORCHESTRATOR`（多空格），而守卫自己的读取端 `awk '{print $2}'` 对这两种形态均正确解析出 `ORCHESTRATOR`，且 `templates/state-template.md:17` 本身就以「值 + 行尾注释」形式书写该字段。**判据比解析器更严会拒绝合法交还** —— 写入方按 schema 示例带注释写，守卫却判定为伪交还，缺陷 1 换个形态复发。ERE 变体在全部 11 种形态上与读取端结论一致。

**不变量（须写入 guards.md）：** 交还谓词的接受集必须 ⊇ 读取端 `awk '{print $2}'` 判为 `ORCHESTRATOR` 的集合。两端口径分裂即产生「写得进但读不出」或「读得出但写不进」的死角。

### 放行范围

仅 `deliverables/${req}/.engine/.state.md`，且 `${req}` 取自当前 state 的 `req_id`：

```bash
[[ "$file" =~ ^deliverables/${req}/\.engine/\.state\.md$ ]] && is_handback && return 0
```

`${req}` 的绑定天然满足 AX-09（跨需求不生效）：REQ001 的 state 持权时 `$req` 为 `REQ001`，写 `deliverables/REQ002/...` 不命中正则。

AX-01（不放大为引擎态直通）由「正则只匹配 `.state.md` 全名」保证——`handoffs/`、`plan-action.md` 等不在此正则内，即使内容含交还标记也落到原有拒绝路径。

**修订（repair r1）：** 本节初版给出的正则无 `^`/`$` 锚，`[[ =~ ]]` 是无锚 ERE，故 `.state.md` 退化为前缀，`.state.md.evil`、`.state.md.sh`、`.state.mdX`、`.state.md/child.md` 一并命中例外，`x/deliverables/${req}/.engine/.state.md` 等嵌套伪造路径亦然——AX-01 由此实测 FAIL。判据侧的行首锚定与路径侧的双向锚定是两个独立要求，上文只覆盖了前者。定稿以双向锚定为准；左锚成立的前提是 `$file` 传入的是归一化后的仓库相对路径（`NORM_PATH`）。

### 单角色语义保持

`current_role` 仍是单值。schema 不变、恢复语义不变、`verify.sh:174` 的必填字段校验不变。多角色形态（`THINKER,VERIFIER`）继续按 CR-004 的并行扇出语义工作，不被本 CR 挪用。

### 交还必须整文件写入的后果（R2）

**修订（audit F-01）：交还例外只接受 `Write`。** 本节初版允许 `Edit`（判 `new_string`），但守卫看不到 `old_string` 与合并结果，跨行 `old_string` 可使片段判据与落盘生效值分歧而提权。定稿为 `Edit` 写 `.engine/.state.md` 一律拒绝。

这是有意的约束而非副作用：它使「一次逻辑状态迁移」与「一次守卫判定」一一对应，消除用户侧撞上的拆分写入中间态。须同步写入 `skills/mh-codeflow/SKILL.md` 与 `skills/mh-design/SKILL.md`，否则 Orchestrator 不知道这条约束。

---

## D2: 按路径归属路由（R3）

### 现行控制流

```
穿越检测 → 找 STATE_FILE → if (无 STATE_FILE && 有 mh-dev state) { mh-dev 分支 }
                          → if (无 STATE_FILE) exit 0
                          → 角色白名单判定 → CURRENT_ROLES 空则 exit 0
```

问题：mh-dev 分支的**进入条件**含 `-z "$STATE_FILE"`（全局、偶然），且 `CURRENT_ROLES` 空时无条件 `exit 0` 覆盖了框架路径。

### 目标控制流

```
穿越检测
  → 归一化路径（提前到分支之前，两分支共用）
  → 判定归属：NORM_PATH 是否以 deliverables/ 开头（目录前缀语义）
      ├─ 是 → /mh-run 角色白名单分支（找 STATE_FILE；无则 exit 0）
      └─ 否 → 框架路径分支
              ├─ 有活跃 mh-dev 授权 → scope 判定（现有逻辑，含 sensitive/formal 与 Tester 放行）
              └─ 无活跃 mh-dev 授权 → exit 0（默认会话透明，AX-06）
```

关键改动是**取消 `-z "$STATE_FILE"` 这个进入条件**，改由路径归属选择分支。两个流程的路径集不相交，故可共存（AC-04、AC-05）。

### 归一化提前

现行归一化在 mh-dev 分支内部。路由需要先知道路径归属，故把 `case` 归一化上移到分支之前。副作用是 `/mh-run` 分支也获得归一化路径——这是改进：`tests/test-role-guard.sh:386` 已断言 deliverables 绝对路径放行，归一化后该断言由「正则子串恰好命中」变为「前缀剥离后精确命中」，结论不变且更稳健。

仓库外绝对路径的拦截同样上移，对两个分支一致生效。原消息 `BLOCKED: mh-dev 拒绝仓库外绝对路径` 需改为不含 `mh-dev` 字样的通用措辞——但 `tests/test-role-guard.sh:375` 的 `assert_block` 只判退出码不判消息，`assert_block_msg` 仅用于 `formal` 关键字，故无断言依赖该措辞。

### 归属判定为前缀语义（AX-08）

```bash
case "$NORM_PATH" in
  deliverables/*) 归 /mh-run ;;
  *)              归框架 ;;
esac
```

`deliverables-evil/`、`mydeliverables/`、`docs/deliverables/` 均不命中 `deliverables/*`，落入框架分支，无 mh-dev 授权时 `exit 0`（默认会话语义），有授权且不在 scope 时 `exit 2`。与 AX-08 期望一致。

> 注：`deliverables/` 前缀判定用 `NORM_PATH` 而非原始 `FILE_PATH`，故绝对路径写法同样归属正确。

原型实测（12 种路径形态）确认归属判定：

```
deliverables/TEST001/THINKER-x.md        → mh-run
<ROOT>/deliverables/TEST001/WORKER-x.md  → mh-run      （绝对形态归一后同结论）
deliverables/.state.md                   → mh-run
deliverables-evil/REQ001/x.md            → framework   （AX-08）
mydeliverables/REQ001/x.md               → framework   （AX-08）
docs/deliverables/x.md                   → framework   （AX-08）
README.md / scripts/*.sh / any/file.md   → framework
tests/x.sh / tools/mh-dev/.mh-dev/foo    → framework
/tmp/evil.sh                             → 拒绝（仓库外，不进任何分支）
```

**顺带修复的一处不对称：** 现行代码下，只要存在活跃 REQ state，mh-dev 的 Tester 就写不了 `tests/`（mh-dev 分支被跳过，落到角色白名单后 `tests/` 无人有权）。路由后 `tests/` 归框架分支，Tester 放行照常生效。这与 R3「两条流水线不得互相阻断」同源，不是额外扩权。

### 失效开放收口（AX-05）

框架分支不再依赖 `CURRENT_ROLES`。`CURRENT_ROLES` 空时的 `exit 0` 保留在 `/mh-run` 分支内（AX-06 要求 deliverables 结论不变），但它已无法影响框架路径——框架路径在上一层就被路由走了。空/畸形 REQ state 因此不再能绕过 `approved_scope`。

### 终态残留（AC-04 的 done 情形）

mh-dev 分支的 phase 正则（`intake|propose|develop|verify|repair`）保持不变，它已正确表达「终态不激活治理」。本 CR 只移除 REQ 侧的存在性条件，不在 REQ 侧新增 phase 判据——需求单已否决「暂停态」思路，路径路由使其不必要。

---

## D3: NotebookEdit 纳入守卫（R5）

两处改动：

1. `.claude/settings.json` 的 matcher：`Write|Edit` → `Write|Edit|NotebookEdit`
2. `role-guard.sh` 的工具与路径提取：

```bash
case "$TOOL_NAME" in
  Write|Edit)   FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') ;;
  NotebookEdit) FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.notebook_path // empty') ;;
  *) exit 0 ;;
esac
[[ -z "$FILE_PATH" ]] && exit 0
```

**路径参数缺失时的处置（AX-11）：** 需求写「不得默认放行」，但实测上游保证写入类工具必带路径参数，且此处 `exit 2` 会把任何载荷异常变成硬阻断，无法与真实越权区分。设计取**保守放行 + 告警**：`exit 0` 并向 stderr 打印一行 `WARN: <tool> 缺少路径参数，守卫跳过`。

> 这是对需求 R5 的一处**有意偏离**，理由：守卫定位是防误撞（R6 已确立），把载荷畸形当攻击处理会让正常会话在上游改版时全面失效，代价高于收益。若审批不接受，改为 `exit 2` 只需一行，但须接受载荷契约变动即全局阻断的风险。

`.ipynb` 不参与交还例外（D1 已述）。

---

## D4: 轨迹测试（R4，Tester 独占）

Developer **不得**写 `tests/**`。设计只规定 Tester 需覆盖的形态，实现归 Tester：

- 序列断言：同一 state 文件上连续两次写入，第一次派发（`ORCHESTRATOR→THINKER`）、第二次交还（`THINKER→ORCHESTRATOR`），两次均须 exit 0。现有 `setup_state` 每次重置，无法表达；需要能在断言之间保留磁盘状态的辅助函数。
- 内容载荷断言：现有 `run_hook()` 只发 `file_path`，需扩展为可携带 `content`/`new_string`（AC-02、AX-02、AX-03 依赖）。
- 元验收（AX-10）：以改动前 `role-guard.sh` 副本跑轨迹用例须 FAIL。

---

## 变更清单

| 文件 | 改动 |
|------|------|
| `scripts/role-guard.sh` | D1 交还例外 + `is_handback()`；D2 归一化上移、路径归属路由、取消 `-z STATE_FILE` 条件；D3 工具与路径提取 |
| `.claude/settings.json` | matcher 增 `NotebookEdit` |
| `templates/state-template.md` | `current_role` 注释补交还例外与「交还须单次写入」 |
| `skills/mh-codeflow/SKILL.md` | 调度循环第 4/6 步注明交还须单次完整写入 |
| `skills/mh-design/SKILL.md` | Step 1 第 4/6 步同上 |
| `CLAUDE.md` §5 | 新授权口径（交还例外、路径归属路由） |
| `docs/designs/source-of-truth.md` | 同步 role-guard 口径描述 |
| `docs/kb/domains/guards.md` | 新增「授权模型与能力边界」（R6）+ 路由与交还谓词陷阱 |
| `docs/designs/design.md` §3 | 调度循环图交还语义 |
| `README.md`、`docs/designs/workflow.md` | `CLAUDE.md` 的 doc_sync 级联 |
| `CHANGELOG.md` | 变更记录 |
| `tests/test-role-guard.sh` | **Tester 独占**，Developer 不得触碰 |

---

## 风险

| 风险 | 处置 |
|------|------|
| 归一化上移改变 `/mh-run` 分支既有判定 | AC-07 全量回归；`tests/test-role-guard.sh:386` 是该路径的既有断言 |
| 交还谓词写成子串匹配即形同装饰 | 行首锚定 ERE（见 D1；`grep -qx` 已实测否决，理由同节）；AX-03 四种伪造形态断言 |
| 交还例外的**路径**正则漏锚定 | `^…$` 双向锚定 `.state.md` 全名；AX-01 后缀/嵌套伪造断言（repair r1 实测捕获） |
| 新增轨迹用例可能恒真 | AX-10 元验收（回滚脚本须 FAIL） |
| doc_sync 漏一个目标即 BLOCKED | 变更清单已含全部级联目标 |
| 交还例外扩大攻击面 | 该例外只对 SubAgent 开放「把权力交还调度者」，不开放获取任何新写入目标；R6 已明确守卫非安全边界 |

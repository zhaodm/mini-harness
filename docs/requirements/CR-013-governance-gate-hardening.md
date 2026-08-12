# CR-013: 治理门禁加固（范围审计 CR-008~CR-012 修复）

## 背景

`docs/audits/2026-08-11-range-audit-cr008-cr012-{verdict.json,report.md}` 对 CR-008~CR-012 做范围审计，判定 FAIL / FAIL_IMPL / release BLOCKED，报出 10 条 findings（P0×1、P1×5、P2×3、P3×1）。

Planner 已独立复现全部 10 条，结论：均为真实问题。三处与审计报告判断不同，记录如下：

**一、F-01 的因果框架需修正。** 报告表述为「CR-012 归一化方向反了」。但 CR-012 需求单第 41 行明确声明「不修改 approved_scope 的存储约定（仍存相对路径）」——按该约定，CR-012 的单向归一化本身是正确的。实际根因是 `approved_scope` 的**存储形态无机械约束、由 Planner（LLM）自由写入，且历史上确实在漂移**：

| 归档 session | 条目数 | 全为绝对路径 |
|---|---|---|
| 20260810T132717Z | 118 | 否（相对） |
| 20260811T034633Z | 138 | 否（相对） |
| 20260811T072526Z | 77 | **是（绝对）** |
| 20260811T234102Z（CR-011） | 28 | **是（绝对）** |

所以这不是「方向错」而是「治理正确性依赖了一个无强制力的约定」，故障是非确定性的——这反而强化 P0 定级。

**二、F-02 实际严重度为 P2 而非 P1。** hook 注册命令为 `bash scripts/role-guard.sh`（相对路径），cwd 非仓库根时 hook 根本无法启动，不存在「错误 cwd 下静默误判」的实际通路。属健壮性缺陷而非活跃缺陷。仍须修复，因 R1 的双向归一化依赖 `ROOT` 推导正确。

**三、F-07 实际严重度为 P2 而非 P1。** 「双重门禁退化为单一门禁」成立，但 done 门禁仍要求 tester PASS，影响是可追溯性而非功能失效。

**审计报告漏报一条**（并入 R5）：`reset-session.sh` 后执行 `validate-outputs.sh audit`，得到的不是干净的 BLOCKED 而是 Python `FileNotFoundError` traceback（缺 `evidence/test-verdict.json`）。审计轨还耦合了开发轨运行态证据。

F-06（退化 merge）不纳入本次范围：无功能影响，且不改写已有历史。

## 目标

修复除 F-06 外的 9 条 findings，使 mh-dev 治理主路径恢复可用，并为暴露出的四处「无机械约束的口径约定」补上强制力。

## 需求

### R1: role-guard 的 scope 匹配须对任意 scope 存储形态都正确（F-01，P0）

- 无论 `approved_scope` 条目存绝对路径还是仓库根相对路径，无论写入请求传绝对还是相对路径，判定结果必须一致且正确。
- 前置 hook 与后置归属校验对「目录条目」的语义必须对称：两者都须支持以 `/` 结尾的目录前缀条目。
- 目录前缀匹配不得被目录名前缀伪造绕过（`modules-evil/` 不得因 `modules/` 获批而放行）。
- 治理关键路径的 formal 轨判定须在归一化后的路径上进行，不得因路径形态差异而误放行。
- 归一化不得产生「绝对路径被当作相对路径」的中间态：仓库外绝对路径须被明确拦截，不得带入下游判定逻辑。

### R2: role-guard 的仓库根推导不得依赖调用方 cwd（F-02，P2）

- 仓库根、`.engine/.state.md` 定位、mh-dev state 默认路径三处均须锚定到脚本自身位置推导出的根，而非进程 cwd。
- 同一写入请求在任意 cwd 下判定结果必须一致。

### R3: round 门禁不得存在旧口径旁路（F-03，P1）

- `develop → verify` 的 developer 归属门禁只认当前 round 的归属记录，不得因存在任何历史轮次的归属记录而放行。
- 历史 state 的兼容性须由一次性迁移承担，不得常驻门禁逻辑。

### R4: 知识库域指南的同步须有机械强制力（F-04，P1）

- 改动 `scripts/` 下的治理脚本时，须强制同一变更集内同步对应域指南；改动 mh-dev 治理脚本时同理。
- 两份陈旧域指南（`guards.md`、`mh-dev.md`）的内容须补齐至**与 CR-013 完成后的实现一致**（非当前 HEAD 状态），使知识库新鲜度检测在严格模式下归零。本 CR 自身要改 5 个受这两份域指南描述的脚本，若以当前 HEAD 为基线会立刻再次过时。

### R5: 审计轨须能自举，且不得把历史产出当作本次前置条件（F-05，P1）

- 审计轨校验的对象必须是本次审计产出，不得是目录中的其他历史产出。
- 首次审计（无任何历史 verdict）必须能正常执行，不得因目录为空而阻断。
- 任何历史 verdict 的内部不一致都不得阻断后续审计。
- 审计轨不得依赖开发轨运行态证据；该证据缺失时须给出明确的 BLOCKED 信息，不得抛出未捕获异常。

### R6: done 门禁的机械预检字段须有独立证据源（F-07，P2）

- `mechanical_preflight` 的取值必须可追溯到机械预检的实际执行结果，不得与 tester 判定同源。
- 机械预检须落盘可校验的执行证据（至少含退出码与执行时刻）。

### R7: 会话状态不得跨 CR 复用（F-10，P2）

- 一个 CR 在 done 终态结束后，下一个 CR 不得在其残留 state 上直接开发。
- 该约束须由脚本强制，不得仅依赖流程文档约定。

**约束对象限定：未经 `reset-session.sh` 的跨 CR 复用。** 已正确执行会话重置的情形是合法的，不在约束范围内——本 CR-013 会话本身即为正例（`reset-session.sh` 已执行、baseline 为 `a1caaad`、`approved_scope` 为 CR-013 自身的 18 条）。判据须能区分「重置后的干净 state + 正常 intake 登记」与「上一 CR 的开发产物残留」，且不得误拦 propose 阶段合法回退重走 `intake → propose` 的重试。
- 补齐 CR-012 的审计记录缺口（CR-008 的审计缺口不纳入本次范围）。该记录由 Auditor 经审计轨产出——`docs/audits/` 是 Auditor 独占路径，不在 Planner 白名单内，故其达成时点在开发轨 done 之后。

### R8: 变更归属的写入者须对角色对称（F-08，P2）

- 两个角色的 `change_ownership` 回填须由同一写入者就地完成，不得依赖后续阶段触发。

### R9: round 的命名形态须统一（F-09，P3）

- 快照文件名、state 键、归属文件名三者对同一 round 概念须使用一致的命名形态。
- 相关文档与调度模板中的示例须同步。
- **凡会被角色逐字执行的命令**中的 round 占位符均须同步，不限于流程文档与调度模板。

---

## 第二轮追加需求（首轮 Tester 判 FAIL 后确认）

首轮验收 33/35 PASS，R1~R9 核心行为达标（F-01、F-07 已实修）。四项失败中一项为代码缺陷、三项为首轮需求与范围定义的遗漏，追加如下。

### R10: 变更归属不得在校验未通过时写入 state（既有缺陷）

- `validate-changes.sh` 的任何一类违规（scope 越权、formal 轨要求、doc_sync 未同步）被判定后，均不得向 state 写入 `change_ownership` 与 `snapshots`，落盘的归属文件不得记 `result=PASS`。
- 判据：违规时 `develop → verify` 门禁必须阻断，不得因已写入的归属而放行。
- 该缺陷非本 CR 引入（`git show HEAD` 版本同样复现），但 R8 使其影响面从 developer 扩至两个角色，故在本 CR 内一并修复。

### R11: 前置 hook 与后置校验对角色专属路径的语义须对称（既有缺陷）

- `tests/**` 在后置校验中属 Tester 专属放行范围，前置 hook 亦须放行，不得要求逐条列入 `approved_scope`。
- 两道门禁对同一路径的结论必须一致——与 R1 修复的「目录前缀语义不对称」属同类问题。
- 该缺陷非本 CR 引入（HEAD 版同样拦截）。首轮因此使 Tester 无法落盘任何测试，连带 `testcase_adding_required=true` 在 verify 阶段必然 BLOCKED。

### R12: 测试夹具须随行为变更同步

- 因 R6 使 `mechanical_preflight` 改为条件回填，编码旧无条件回填行为的既有断言须更新，并补充条件回填的负例断言。
- 由 Tester 产出。

---

## 第三轮追加需求（第二轮 Tester 判 FAIL 后确认）

第二轮 39/41 PASS，F-03（doc_sync 旁路）与 F-04（tests/ 被拦）已真正修复，R1~R9 无回归。追加三项。

### R13: 违规归属记录不得被覆盖消除（本轮新引入的安全回归）— 已整体回退，见文末「R13 回退记录」

第二轮为解 AX-18 死锁引入的「归属不可变性分级」（`result=FAIL` 可同轮无条件覆盖）构成完整洗白链，已实测复现：Developer 改越权文件 → 落盘 `result=FAIL` → **不撤回该文件**，仅手写一份省略它的 after 快照（快照仅校验 role/round/point 三字段，`snapshots/` 对 Developer 是可写运行态）→ 重跑 exit 0，归属被覆盖为 `PASS`，越权记录彻底消失，`develop → verify` 门禁随即放行。

`git show HEAD` 版本（CR-012 口径）同一攻击得 `BLOCKED: immutable attribution exists` 且门禁阻断 —— 故这是**第二轮引入的回归**，不是既有缺陷。

要求：
- 任何一次校验产生的违规记录都不得因后续重跑而消失，须可追溯。
- 同时须保留 AX-18 的能力：违规修正后同一轮次可继续推进，不得死锁。
- 「手工把 `result` 改成 `FAIL` 即解锁覆盖」与「缺 `result` 键比畸形 JSON 更宽松」两个同源弱点须一并消除——校验须 fail-closed。

### R14: 可执行命令中的 round 占位符须实际改正（第二轮授权已给、改动未做）

两份 SKILL.md 已在 `approved_scope` 内，但未被修改，照抄执行仍得 exit 2。须实际改正。

### R17: 违规检出与撤回举证须使用同一事实源（第三轮 Tester 自由探索）

R13 把快照 entries 当作违规**检出**的唯一事实源，却把 git 改动集当作**撤回举证**的事实源。两个事实源不一致，派生两个缺陷：

- **F-09（high）死锁**：消解判定 `validate-changes.sh:168` 要求 `r.get('live') and withdrawn(p)`。Developer 按 `mh-dev-develop/SKILL.md` 第 5 节顺序操作（先撤回文件、再重跑校验，此时快照尚未重采）会追加一条 `live=false` 记录，此后即便如实重采快照、文件确已从 git 改动集消失，仍永久 BLOCKED。唯一出路是把越权路径写入 `approved_scope`——等于奖励越权。已在隔离沙箱最小复现。
- **F-10（medium）检出入口**：首轮 after 快照一开始就省略越权文件时，校验直接 exit 0、归属记 `result=PASS`、门禁放行、零违规记录，而 `git status` 明确报告该文件存在。R13 堵的是「已被记过之后的洗白」，未堵「从未被记过」的入口。

要求：
- 违规检出的事实源须包含 git 改动集，不得仅凭快照 entries——快照是角色可写的运行态文件，不能作为唯一依据。
- 消解判定须以「该路径当前是否在 git 改动集内」为准，不得依赖记录落盘时的 `live` 标记。合法的修复顺序不得导致死锁。
- 不得因此牺牲 R13 已建立的能力：洗白链仍须被阻断（AC-22、AX-21、AX-22），违规修正后同轮仍可推进（AC-23）。

### R15: 测试文件识别不得用子串匹配

`testcase_adding_required` 的满足判定以 `'test' in p` 子串匹配，`docs/latest-notes.md` 之类路径可误满足。须改为路径前缀或文件名语义判定。既有缺陷。

## 非目标

- 不改写 git 历史（F-06）。
- 不补 CR-008 的审计记录。
- 不修改 `/mh-run` 的 deliverables 分支判定逻辑（审计确认无回归）。
- 不把 `kb-verify.sh --strict` 接入全局门禁（维持 CR-011 非目标；R4 采用定点 doc_sync 而非全局阻断）。
- 不改变 `approved_scope` 的存储约定本身——R1 要求实现对两种形态都正确，而非规定只能存一种。

## 影响范围

由 `scope-scan.sh "approved_scope" "mechanical_preflight" "repair.round"` 确认：

| 文件 | 需求 |
|---|---|
| `scripts/role-guard.sh` | R1、R2 |
| `tools/mh-dev/scripts/check-transition.sh` | R3 |
| `tools/mh-dev/scripts/validate-changes.sh` | R4、R8 |
| `tools/mh-dev/scripts/validate-outputs.sh` | R5、R6 |
| `tools/mh-dev/scripts/audit-preflight.sh` | R6 |
| `tools/mh-dev/scripts/transition-state.sh` | R7 |
| `tools/mh-dev/scripts/capture-snapshot.sh` | R9 |
| `tools/mh-dev/templates/state.json.template` | **R5**（新增 `audit_verdict_path` 字段初始化）、R6、R7 |
| `tools/mh-dev/templates/dispatch-prompts.md` | R9 |
| `docs/kb/domains/guards.md` | R4 |
| `docs/kb/domains/mh-dev.md` | R4 |
| `CLAUDE.md`、`README.md`、`docs/designs/source-of-truth.md`、`docs/designs/workflow.md` | R1、R2 的 doc_sync 强制目标（均含 role-guard 匹配口径描述，须同步为新口径） |
| `tools/mh-dev/CLAUDE.md` | R7、R9 |

测试由 Tester 独占产出，须覆盖审计报告 §5.1 所列四处缺口（scope 绝对路径矩阵、cwd 变化、目录前缀条目、check-transition round 负例）。

`testcase_adding_required = true`。

---

## R13 回退记录（最终处置）

R13、R16、R17 三项已**整体回退**，`validate-changes.sh` 恢复为「归属文件一律不可变」。

### 回退原因

R13 本身不在范围审计所报的 10 条 findings 内——它是第二轮 Developer 为解「归属不可变导致同轮修正死锁」而自创的方案（按 `result` 分级：FAIL 可覆盖、PASS 不可覆盖）。该方案连续派生三个缺陷：

| 轮次 | 缺陷 | 性质 |
|---|---|---|
| 第三轮 | F-05 洗白链：伪造省略越权文件的快照即可把 FAIL 洗成 PASS | 安全回归 |
| 第四轮 | F-09 合法修复顺序永久死锁（比原问题更糟） | 安全回归 |
| 第四轮 | F-10 首次即伪造快照时违规检出被完全绕过 | 安全回归 |

每次修补又长出新缺陷，且修补方向（引入 git 改动集作为撤回举证）使快照与 git 成为两个不一致的事实源。

### 回退后的行为

归属文件一旦落盘就不允许覆盖，无论 `result`。违规后的修正方式是**重开一轮**，不是同轮重跑。代价是违规轮作废；收益是 F-05/F-09/F-10 三个缺陷一次消失，且代码回到可一眼看懂的状态（`validate-changes.sh` 移除 git 取证、追加式历史、覆盖授权白名单共约 40 行）。

`state.violation_history`、`evidence/violation-history.*.jsonl`、`state.json.template` 的对应字段、`check-transition.sh` 的第八项残留判据（R16）均随之移除——它们都只为支撑「覆盖不等于抹除」而存在。

### 判断依据

CLAUDE.md §2「用最少的代码解决问题，不为不可能发生的场景做错误处理」。同轮修正是便利性需求，不是正确性需求；为它引入的复杂度已三次证明不可控。

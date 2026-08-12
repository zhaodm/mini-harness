# CR-013 设计：治理门禁加固

## 设计原则

本次 9 条需求全部源自同一类根因：**治理正确性依赖了无强制力的口径约定**。四处具体表现——scope 存储形态（R1）、仓库根推导（R2）、round 口径（R3、R9）、知识库同步（R4）。因此设计取向统一为：**让门禁对输入形态宽容，对越权判定严格；把约定转成脚本可校验的断言**。

不采用「再加一条文档约定」的修法——CR-012 的失败正是因为它依赖了这样一条约定。

---

## R1: scope 匹配双向归一化 + 目录前缀

### 候选方案

**候选 A（选定）：双向归一化，两侧统一转绝对路径后比较，并支持目录前缀条目。**

```bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # R2 一并解决
case "$FILE_PATH" in
  "$ROOT"/*) NORM_PATH="${FILE_PATH#$ROOT/}" ;;            # 仓库内绝对 → 相对
  /*)        echo "BLOCKED: 仓库外绝对路径: $FILE_PATH"; exit 2 ;;
  *)         NORM_PATH="$FILE_PATH" ;;
esac

MH_TRACK=$(jq -r '.track // empty' "$MH_DEV_STATE")
if jq -e --arg p "$NORM_PATH" --arg root "$ROOT" '
      ([.approved_scope[] | if startswith("/") then . else $root + "/" + . end]) as $abs
      | ($root + "/" + $p) as $ap
      | ($abs | index($ap) != null)
        or any($abs[]; . as $s | ($s | endswith("/")) and ($ap | startswith($s)))
   ' "$MH_DEV_STATE" >/dev/null 2>&1; then
```

选定理由：对 scope 的两种存储形态都正确，与 `validate-changes.sh:38-41` 的已验证口径同源，顺带消除两道门禁的目录前缀语义不对称。

**候选 B（否决）：规定 scope 只能存相对路径，写入侧机械 relpath。** 否决理由：新增一处 scope 写入者，与 Planner 直写 state 的现状冲突；且 role-guard 对畸形 scope 仍无容错——任何绕过写入侧的修改都会让 hook 全面误拦。

**候选 C（否决）：保留 CR-012 单向归一化不动，仅修写入侧。** 否决理由：目录前缀不对称仍在（`docs/designs/modules/` 过 `validate-changes.sh` 但过不了 hook），且未解决根因。

### 安全分析：路径形态矩阵

`ROOT=/repo`，`approved_scope` 分两种存储形态各列一遍。

| # | scope 条目 | 写入 file_path | $abs 归一后 | $ap | 判定 | 期望 |
|---|---|---|---|---|---|---|
| 1 | `scripts/a.sh` | `/repo/scripts/a.sh` | `/repo/scripts/a.sh` | `/repo/scripts/a.sh` | 精确命中 → 放行 | 放行 |
| 2 | `scripts/a.sh` | `scripts/a.sh` | 同上 | 同上 | 精确命中 → 放行 | 放行 |
| 3 | `/repo/scripts/a.sh` | `/repo/scripts/a.sh` | 原样 | 同上 | 精确命中 → 放行 | 放行 |
| 4 | `/repo/scripts/a.sh` | `scripts/a.sh` | 原样 | 同上 | 精确命中 → 放行 | 放行 |
| 5 | `docs/m/` | `/repo/docs/m/x.md` | `/repo/docs/m/` | `/repo/docs/m/x.md` | 前缀命中 → 放行 | 放行 |
| 6 | `/repo/docs/m/` | `docs/m/x.md` | 原样 | 同上 | 前缀命中 → 放行 | 放行 |
| 7 | `docs/m/` | `docs/m-evil/x.md` | `/repo/docs/m/` | `/repo/docs/m-evil/x.md` | `startswith("/repo/docs/m/")` 为假 → 拦截 | 拦截 |
| 8 | `scripts/a.sh` | `scripts/a.sh.evil` | `/repo/scripts/a.sh` | `/repo/scripts/a.sh.evil` | 非目录条目不进前缀分支 → 拦截 | 拦截 |
| 9 | `docs/m/` | `evil/x.md` | `/repo/docs/m/` | `/repo/evil/x.md` | 两分支均假 → 拦截 | 拦截 |
| 10 | `[]`（空） | 任意产品区 | `[]` | — | `index` 为 null，`any` 空集为假 → 拦截 | 拦截 |
| 11 | 任意 | `/tmp/evil.sh` | — | — | `case` 第二分支直接拦截 | 拦截 |
| 12 | 任意 | `/repo/../evil.sh` | — | — | 第 20 行 `..` 检测先行拦截 | 拦截 |

第 7 行是目录前缀语义的关键：条目保留结尾 `/`，`m-evil/` 不以 `m/` 开头，故不命中。

**第 11 行须由 `case` 显式拦截。** 若 `case` 写成宽泛的 `/*)`，`/tmp/evil.sh` 会匹配该分支并执行 `${FILE_PATH#$ROOT/}`；因它不以 `$ROOT/` 开头，`#` 不做替换，`NORM_PATH` 仍为 `/tmp/evil.sh`——**一个绝对路径被当作相对路径带进后续逻辑**（已实测确认该中间态）。

该中间态的实际危害面，以实测划定：

| scope 条目 | 写入 | 宽泛 `/*)` 实测 | 说明 |
|---|---|---|---|
| `/tmp/evil.sh` | `/tmp/evil.sh` | **exit 2** | `$ap` 为 `$ROOT//tmp/evil.sh`，与条目不等，侥幸拦截 |
| `$ROOT/`（仓库根作目录条目） | `/tmp/evil.sh` | **exit 0 误放行** | `$ROOT//tmp/evil.sh` 确以 `$ROOT/` 开头 → 前缀命中 |

即：单纯把仓库外路径列入 scope 不足以突破，但**任何以 `$ROOT/` 或其上层为目录条目的 scope 都会让整个文件系统被放行**。此外下游 sensitive 判定的 `case "$NORM_PATH" in CLAUDE.md|...)` 是相对字面量匹配，该中间态在 sensitive 列表将来扩项时同样是隐患。

故分三分支：仓库内绝对 → 剥前缀；其余绝对 → 直接拦截（mh-dev 本就不该放行仓库外写入）；相对 → 原样。

### jq 写法陷阱（必须避免）

```
错误：any($abs[]; endswith("/") and ($ap | startswith(.)))
```

`|` 会把 `.` 重绑定为管道左侧值，`startswith(.)` 中的 `.` 变成 `$ap` 自身，退化为 `$ap | startswith($ap)` 恒真——**放行任意越权路径**。已实测确认：该写法下 `evil/x.md` 被放行。

```
正确：any($abs[]; . as $s | ($s | endswith("/")) and ($ap | startswith($s)))
```

先用 `. as $s` 绑定当前条目再进管道。已实测：`docs/m/x.md` 放行，`evil/x.md` 与 `docs/m-evil/x.md` 拦截。AX-03 是对此写法的直接反证用例。

### sensitive case 的归一化时序

`case` 分支须继续使用 `$NORM_PATH`（相对形态），因其模式为 `CLAUDE.md|.claude/settings.json|scripts/role-guard.sh|templates/state-template.md` 相对字面量。归一化在 `case` 之前完成这一点 CR-012 已正确实现，本次不动。

---

## R2: ROOT 从脚本自身位置推导

```bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

三处一并锚定：

| 位置 | 现状 | 改为 |
|---|---|---|
| 第 26 行 `find deliverables` | 相对路径，依赖 cwd | `find "$ROOT/deliverables"` |
| 第 31 行 `MH_DEV_STATE` 默认值 | `tools/mh-dev/.mh-dev/state.json` | `$ROOT/tools/mh-dev/.mh-dev/state.json` |
| 第 37 行 `ROOT=$(pwd)` | cwd | `$(dirname "${BASH_SOURCE[0]}")/..` |

`ROOT` 定义须上移到脚本顶部（第 26 行之前），因 `find` 要用。

**deliverables 分支的回归风险**：`find "$ROOT/deliverables"` 返回绝对路径，`STATE_FILE` 从相对变绝对。`check_permission` 用 `[[ =~ ]]` 正则子串匹配 `deliverables/${req}/...`，绝对路径同样能命中子串，故判定不变。但 `grep "^current_role:" "$STATE_FILE"` 由相对改绝对读取，反而更稳健。AX-17 复测该分支全矩阵。

---

## R3: 删除 round 门禁 legacy 回退

```python
# check-transition.sh 第 17 行
- if rr not in dev_attr and '1' not in dev_attr: blocked('developer attribution required')
+ if rr not in dev_attr: blocked('developer attribution required')
```

单行删除。历史 state 兼容不做迁移脚本——R7 的会话重置硬约束会强制新 CR 从干净 state 起算，旧 state 只存在于 `.mh-dev-archive/`，不参与门禁。

---

## R4: doc_sync 定点扩展 + 域指南补内容

```python
doc_sync = {
 'CLAUDE.md': ['README.md','docs/designs/workflow.md','docs/designs/source-of-truth.md'],
 'scripts/role-guard.sh': ['CLAUDE.md','docs/designs/source-of-truth.md','docs/kb/domains/guards.md'],
 'tools/mh-dev/scripts/check-transition.sh': ['docs/kb/domains/mh-dev.md'],
 'tools/mh-dev/scripts/validate-outputs.sh': ['docs/kb/domains/mh-dev.md'],
 'tools/mh-dev/scripts/transition-state.sh': ['docs/kb/domains/mh-dev.md'],
}
```

定点映射而非前缀通配：`validate-changes.sh` 现有实现是 `if path in doc_sync` 精确查表，保持该形态，避免误伤 mh-dev 下的非治理脚本（`scope-scan.sh`、`reset-session.sh` 等）。AX-08 验证无关改动不被误阻断。

**未纳入 doc_sync 的本次变更文件**：`validate-changes.sh`、`capture-snapshot.sh`、`audit-preflight.sh`、`state.json.template`、`dispatch-prompts.md`。理由：前三者不描述用户可见口径，后两者本身就是文档/模板。若纳入会造成自指循环（改 `validate-changes.sh` 要求改 `mh-dev.md`，而 doc_sync 规则本身写在 `validate-changes.sh` 里）。

**域指南补内容范围**（Developer 产出，不新增章节结构）：
- `guards.md`：role-guard 的 scope 匹配口径（双向归一化、目录前缀语义、ROOT 从脚本位置推导）
- `mh-dev.md`：round 口径（首轮=0、命名形态统一）、done 门禁两字段的独立证据来源、会话重置硬约束

两份现为 73/116 行，Layer 1 上限 400 行，余量充足。

**doc_sync 的自举问题**：本次 Developer 要改 `scripts/role-guard.sh`，按新映射必须同 delta 改 `CLAUDE.md`、`source-of-truth.md`、`guards.md`。这三者本来就在 approved_scope 内且确实需要同步（都含旧口径描述），无额外负担。

---

## R5: 审计轨解耦 + 本次产出登记

三个独立缺陷，分别修：

**（a）校验对象错位 + 无法自举。** 由 state.json 登记本次 verdict 相对路径：

```python
# state.json 新增字段
"audit_verdict_path": ""     # 相对仓库根，如 docs/audits/2026-08-12-cr013-verdict.json
```

```python
if phase=='audit':
 rel=s.get('audit_verdict_path','')
 if not rel: fail('audit_verdict_path not registered in state.json')
 target=os.path.join(root,rel)
 if not os.path.isfile(target): fail(f'registered audit verdict not found: {rel}')
 with open(target,encoding='utf-8') as f: a=json.load(f)
```

替换 `sorted(glob(...))[-1]`。字典序/mtime 两个选择器一并废除——不再需要「猜最新」。首次审计只要登记了路径即可通过（AC-11），历史文件完全不参与（AX-09）。

**（b）审计轨耦合开发轨证据 —— 采用完全解耦，不做条件校验。** 第 38 行 `if phase in {'verify','audit'}` 改为仅 `verify`。audit 分支**完全不读** `evidence/test-verdict.json`，不做「存在则校验、缺失则跳过」的条件分支。

理由：审计一个已提交的历史范围时，开发轨运行态证据本不该参与判定。条件校验会让审计结论随运行态残留文件的有无而变化——这正是 F-05「把历史产出当本次前置条件」的同类错误。

审计轨对 tester 结论的要求由 verdict 内部的 schema 校验承担：第 75 行 `a.get('tester_verdict_ref')!='evidence/test-verdict.json'` 要求 Auditor 显式声明该引用，但不读取文件本身。该行保留不变，这已足够。

改动后 audit 分支不再出现 `load('evidence/test-verdict.json')`，`FileNotFoundError` 消失（AX-10）。

**（c）`load()` 无异常兜底。** `load()` 加 try/except 转 `fail()`，保证任何路径下都是 `BLOCKED:` 而非 traceback：

```python
def load(name):
 try:
  with open(os.path.join(runtime,name),encoding='utf-8') as f: return json.load(f)
 except FileNotFoundError: fail(f'required runtime file missing: {name}')
 except json.JSONDecodeError as e: fail(f'malformed JSON in {name}: {e}')
```

---

## R6: mechanical_preflight 独立证据源

**audit-preflight.sh 末尾落盘：**

```bash
EVIDENCE="$RUNTIME/evidence/audit-preflight.json"
mkdir -p "$(dirname "$EVIDENCE")"
# exit_code 取实际结果，不硬编码 0
```

字段：`{"schema_version":1,"exit_code":N,"checked_at":"<iso8601>","pass":P,"fail":F}`。

脚本现无 `RUNTIME` 变量，须补 `ROOT_DIR`/`RUNTIME` 推导（与同目录其他脚本一致的 `$(cd "$(dirname "$0")/../../.." && pwd)` 惯例）。

**validate-outputs.sh verify 分支回填改为有条件：**

```python
if v['verdict']=='PASS':
 s['test_verdict']='PASS'
 pf=os.path.join(runtime,'evidence/audit-preflight.json')
 if os.path.isfile(pf):
  try:
   with open(pf,encoding='utf-8') as f: p=json.load(f)
   if p.get('exit_code')==0: s['mechanical_preflight']='pass'
  except json.JSONDecodeError: pass
```

证据缺失或 `exit_code!=0` 时字段保持 `pending`，`check-transition.sh done` 自然阻断（AC-13、AX-12）。不在此处 `fail()`——机械预检是 Planner 职责，verify 阶段只做诚实记录，让 done 门禁去阻断。

**流程影响**：Planner 在 verify 前须执行 `audit-preflight.sh`。写入 `tools/mh-dev/CLAUDE.md` 阶段四前置检查清单。

---

## R7: 会话状态跨 CR 复用硬约束

在 `transition-state.sh` 的 `intake → propose` 转移增加残留检测。放在 `transition-state.sh` 而非 `check-transition.sh`：后者是只读谓词，会被 `transition-state.sh` 调用，但残留检测需要的是「首次进入 propose」语义，与 phase 谓词是不同维度。

实际放在 `check-transition.sh` 的 `propose` 分支更合适——`transition-state.sh` 内部就会调用它，两条路径都受约束，且只读预检也能提前发现。

```python
if n=='propose' and p=='intake':
 stale=[]
 if s.get('revision',0)!=0: stale.append(f"revision={s['revision']}")
 if s.get('change_ownership'): stale.append('change_ownership non-empty')
 if s.get('snapshots'): stale.append('snapshots non-empty')
 if s.get('repair',{}).get('status','not_started')!='not_started': stale.append("repair.status="+s['repair']['status'])
 if s.get('test_verdict','pending')!='pending': stale.append('test_verdict='+str(s.get('test_verdict')))
 if s.get('mechanical_preflight','pending')!='pending': stale.append('mechanical_preflight='+str(s.get('mechanical_preflight')))
 for ph in ('develop','verify','done'):
  if ph in s.get('phase_timestamps',{}): stale.append(f'phase_timestamps.{ph} present')
 if stale: blocked('stale session state detected ('+'; '.join(stale)+'); run reset-session.sh first')
```

**判据选择。** 先说一个被推翻的理由：本设计初稿排除 `revision != 0` 的依据是「propose 阶段合法回退重走 `intake → propose` 时 revision 已非 0」。**该场景经实测不存在**——`check-transition.sh:9` 的合法 next-phase 集合为 `{propose, develop, verify, done, repair, blocked}`，`intake` 不在其中；从 propose/develop/verify/done 尝试转 `intake` 均 exit 2。且 `revision` 仅由 `transition-state.sh` 递增，Planner 直写 state（如登记 scope）不递增，故 `phase == intake` 时 `revision` 恒为 0。

即 `revision != 0` 在此处**不会误拦**，可以作为判据。但仍不用它作为**唯一**判据：它只是「转移次数」的代理量，与「是否有开发产物」无直接语义关系；若将来允许 `→ intake` 回退，该判据会立刻失效。改用两类语义直接的判据：

- **开发循环产物**：`change_ownership`、`snapshots`、`repair.status`、`test_verdict`、`mechanical_preflight`。这五项只在开发循环实际跑过之后才非初值（模板初值实测确认为 `{}`/`{}`/`not_started`/`pending`/`pending`）。
- **阶段历史**：`phase_timestamps` 含 `develop`/`verify`/`done` 任一。干净 state 只有 `intake`；残留 state 必然留下后续阶段的时间戳。这一项覆盖了「字段被手工清空但阶段历史仍在」的情形。

`phase_timestamps` 在 `tools/mh-dev/CLAUDE.md` 中记为「纯记录用途，不参与任何门禁判定」——本次将其用于残留检测构成对该表述的变更，须同步更新该行描述（已在 approved_scope 内）。

同时把 `revision != 0` 作为**补充**判据一并纳入（实测确认不会误拦合法流程），使判据覆盖三个维度：转移次数、开发产物、阶段历史。任一命中即阻断。

**不检 `approved_scope`**：Planner 在 intake 阶段登记 scope 是正常流程（本次 CR-013 即如此），非残留信号。

AX-13 验证 `phase=intake` 伪装的残留 state 亦被拦。

`phase=done` 的残留 state 执行 `propose` 会先撞 `else: blocked(f'{p} cannot transition to {n}')`（done 不能转 propose），已阻断（AC-14）；新增检测覆盖的是「phase 被改回 intake 但其余字段残留」的情形。

---

## R8: change_ownership 对称就地写入

```python
# validate-changes.sh 第 86 行
- if role == 'developer':
-  state.setdefault('change_ownership',{}).setdefault(role,{})[str(round_)]=rel
+ state.setdefault('change_ownership',{}).setdefault(role,{})[str(round_)]=rel
+ if role == 'developer':
   # doc_sync 检查（保持在 developer 分支内）
```

第 87 行的归属写入提到 `if role == 'developer'` 之外，doc_sync 逻辑仍留在分支内。

**写入时序安全**：该语句位于第 80-84 行 violations 早退之后，故 violations 非空时不会执行到（AX-14 验证 tester 越权时不污染 `change_ownership`）。

`validate-outputs.sh:52` 的 tester 回填保留——幂等（同 key 同值），删除会让「归属存在性」失去二次确认。

---

## R9: round 命名形态统一

`capture-snapshot.sh:11` 去掉 `r` 前缀：

```bash
- OUT="$RUNTIME/snapshots/$ROLE.r$ROUND.$KIND.json"
+ OUT="$RUNTIME/snapshots/$ROLE.$ROUND.$KIND.json"
```

统一后三处一致：快照 `developer.0.before.json`、state 键 `developer.0`、归属 `change-attribution.developer.0.json`。

同步文档示例：`tools/mh-dev/CLAUDE.md` 基线捕获规则表（现写 `developer.r<N>.before.json`）、`dispatch-prompts.md`。

**重名保护不受影响**：第 13 行 `[[ ! -e "$OUT" ]]` 基于实际文件名判断，与命名形态无关（AX-15）。

**无历史文件迁移**：旧快照仅存在于 `.mh-dev-archive/`，state 中记录的是相对路径字符串，归档态不参与任何门禁。

**测试夹具字符串同步（Tester 产出，P3）。** `tests/test-role-guard.sh:466,469,474` 含 `developer.r1.after.json` 等旧形态字符串。经核对这些是 JSON 夹具里的**装饰性字段值**（`delta_ref`、`before_snapshot`），无断言检查其内容，也无对应真实文件；`validate-changes.sh:78` 从实际路径 `relpath` 派生，全仓无反向重构 `r<N>` 的代码（生成点仅 `capture-snapshot.sh:11`）。故改名不影响用例结果，同步理由仅为可读性一致，优先级等同 F-09 本身。由 Tester 顺手更新，Developer 不碰 `tests/**`。

---

## R7 附带：补齐 CR-012 审计记录

CR-012 的审计缺口由本次范围审计（`2026-08-11-range-audit-cr008-cr012-*`）实质覆盖——该审计的 F-01/F-03/F-04/F-07/F-10 全部针对 CR-012，且深度超过单 CR 审计。补齐方式：在 `docs/audits/` 增加 CR-012 专项 verdict，其 findings 引用范围审计的对应条目，避免重复劳动与结论分叉。

**产出者：Auditor，不是 Planner。**

`docs/audits/` 不在 Planner 白名单内（`tools/mh-dev/CLAUDE.md:154-161`，已核实）。但须说清这道约束的实际强度：**它没有机械强制力**。实测把 `docs/audits/` 路径列入 `approved_scope` 后 role-guard 放行（exit 0）——mh-dev 分支只查 `approved_scope`，全文不涉及 Planner 白名单概念；`validate-changes.sh` 只接受 `--role developer|tester`，Planner 变更不经归属校验。

即机械上 Planner 写得进去。仍不这么做，理由是职责隔离本身：审计记录由被审计方产出会让 `docs/audits/` 失去独立性——这与 F-07（`mechanical_preflight` 与 tester verdict 同源导致双门禁退化为单门禁）是同型问题，不应在修 F-07 的同一个 CR 里复制它。

不为此扩 Planner 白名单。

> **附带发现（不纳入本次范围）**：Planner 白名单无任何机械校验，是纯自然语言约束。范围审计未报此项。补机械强制力需要单独设计 Planner 侧的变更归属机制（现 `validate-changes.sh` 无 planner role），且本次 scope 已 18 条，故记录待后续 CR 处理。

改由本次开发闭环后的**审计轨**产出：`/mh-dev audit` 调度 Auditor，在其 verdict 中补录 CR-012 专项结论（findings 引用范围审计的 F-01/F-03/F-04/F-07/F-10 对应条目，避免重复劳动与结论分叉）。schema 须通过 `validate-outputs.sh audit`（AC-18）。

因此 AC-18 的达成时点在开发轨 done 之后、由独立审计轨完成——本次 CR 的 Tester 只验证「校验脚本能正确校验一份 CR-012 verdict」，不验证该文件已存在。

---

## 实现顺序（关键：避免 hook 半成品卡死）

`role-guard.sh` 是活跃 PreToolUse hook，改到一半会阻断后续所有写入。Developer 须按此顺序：

1. **先改 `scripts/role-guard.sh`**（R1+R2 一次改完，不分两步），立即用负例矩阵自测确认 exit 码正确
2. 同 delta 改 doc_sync 强制目标：`CLAUDE.md`、`docs/designs/source-of-truth.md`、`docs/kb/domains/guards.md`（否则 `validate-changes.sh` 会 BLOCKED）
3. 改 mh-dev 治理脚本（R3、R5、R6、R8、R9）+ `docs/kb/domains/mh-dev.md`
4. 改 `check-transition.sh` R7、`state.json.template`、`dispatch-prompts.md`、`tools/mh-dev/CLAUDE.md`
5. `docs/designs/workflow.md`、`README.md` 同步 role-guard 口径描述

第 1 步失败时的逃生路径：`git checkout scripts/role-guard.sh` 恢复，hook 回到当前（虽有 F-01 但相对 scope 下可用）状态。

## 不改动项

| 位置 | 理由 |
|---|---|
| `role-guard.sh:20` `..` 穿越检测 | 在归一化之前，独立正确（AX-05 复测） |
| `role-guard.sh:33` 运行态放行 | 正则匹配相对子串，绝对路径同样命中 |
| `role-guard.sh:65-110` `check_permission` | deliverables 分支，审计确认无回归（AX-17 复测） |
| `capture-snapshot.sh:19-23` round 校验 | 已正确以 `repair.round` 为单一真相源 |
| `validate-changes.sh:38-41` 归一化 | 本次以其为对齐基准，不动 |
| `transition-state.sh` CAS | 第 12 行 revision 校验 + 原子写入，正确 |
| git 历史 | F-06 不改写 |
| `kb-verify.sh` | 不接入全局门禁，维持 CR-011 非目标 |


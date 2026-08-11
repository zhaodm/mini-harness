# CR-008 技术设计：mh-dev 轨道分离 + 测试夹具隔离 + 需求归档

> CR: CR-008-mh-dev-track-separation
> 日期: 2026-08-10
> 状态: 设计中
> 参考: psdt-dev 的两轨分离模型（DESIGN.md §7 + DESIGN-audit.md §2）

---

## 1. 架构定位

三个问题共享一个架构根因：`.mh-dev/` 目录同时承载运行态和持久交付物。本设计分三层修复，各层独立但指向同一目标——消除职责混淆。

| 层 | 修复 | 对应问题 |
|----|------|----------|
| 轨道分离层 | 删除 verify→audit 焊点，审计轨独立 + 精简终态 | 问题1 |
| 运行态隔离层 | MH_DEV_RUNTIME 环境变量覆盖 | 问题2 |
| 归档分层 | 持久交付物移出 .mh-dev/ 到 docs/ | 问题3 |

---

## 2. 轨道分离设计（问题1）

### 2.1 状态机精简

当前生命周期：
```
intake → propose → develop → verify → audit → release-candidate → archive
```

问题：audit 焊死开发轨；release-candidate 和 archive 是过度设计——mh-dev 产出是代码改动，终态动作是用户手动 git commit，无制品需候选确认；归档已由 reset-session.sh 在下次开局时做。

新生命周期（对齐 psdt-dev 的 testing→done）：
```
intake → propose → develop → verify → done
                    │          │
                    └──────────┴── FAIL / BLOCKED → repair → develop
                                                   └→ blocked
```

### 2.2 删除的状态与焊点

| 删除项 | 原因 |
|--------|------|
| `verify→audit` 转移 | 审计轨独立，不由开发轨自动衔接 |
| `audit→release-candidate` 转移 | audit 状态删除 |
| `audit→repair` 转移 | 审计轨不触发 repair |
| `audit` 状态 | 不在开发轨生命周期中 |
| `release-candidate` 状态 | 无制品需候选确认；delivery approval 已被 done + 铁律覆盖 |
| `archive` 状态 | 归档是 session 级清理，已由 reset-session.sh 承担 |
| `release-candidate.sh` | 无制品生成职责，删除 |
| `validate-outputs.sh release-candidate` 分支 | 状态删除，门禁随之删除 |
| `validate-outputs.sh audit` 分支中的状态转移语义 | 保留校验逻辑（审计轨仍用），但不触发 phase 转移 |

### 2.3 新增的转移

| 新增项 | 门禁条件 |
|--------|----------|
| `verify→done` | mechanical_preflight==pass + test_verdict==PASS |

用户确认提交 = 铁律（等价 delivery approval），不是状态节点。done 状态后用户手动 git commit。

### 2.4 check-transition.sh 转移规则变更

当前 Python 实现用 if-elif 链。变更：

```python
# 删除：
elif n=='audit' and p=='verify':           # verify→audit 不再合法
elif n=='repair' and p=='audit':           # audit→repair 不再合法
elif n=='release-candidate' and p=='audit': # audit→release-candidate 不再合法
elif n=='release-candidate' and p=='verify': # 删（如存在）
elif n=='archive' and p=='release-candidate': # 删

# 新增：
elif n=='done' and p=='verify':
  if s.get('mechanical_preflight')!='pass' or s.get('test_verdict')!='PASS':
    blocked('mechanical and tester PASS required')
  # 不检查 semantic_audit
```

done 也需加入合法目标状态集合：
```python
if n not in {'propose','develop','verify','done','repair','blocked'}: raise SystemExit(2)
```
删除 `audit`、`release-candidate`、`archive` 从合法目标集合。

### 2.5 validate-outputs.sh 变更

**删除 `release-candidate` 分支**（整个 if phase=='release-candidate' 块）。

**删除 propose 阶段的 testcase_adding_required 检查**，移到 verify 阶段（见 §5）。

**verify 阶段新增 testcase_adding_required 检查**（从 propose 移来）。

**audit 分支保留**但语义变更：校验 test-verdict.json + semantic-verdict.json 格式，但不触发状态转移。审计轨调用此校验作为前置检查，通过后调度 Auditor，Auditor 产出报告即结束——不改 phase。

### 2.6 transition-state.sh repair 变更

当前 repair 的 source_verdict 逻辑：
```python
r['source_verdict']='evidence/test-verdict.json' if previous=='verify' else 'evidence/semantic-verdict.json'
```

改为（audit 不再触发 repair）：
```python
r['source_verdict']='evidence/test-verdict.json'  # 只从 verify 来
```

### 2.7 审计轨独立设计

审计轨**不碰 state.json 的 phase**，流程：

```
用户: /mh-dev audit
  ↓
Planner: bash audit-preflight.sh + validate-outputs.sh audit
  ↓（PASS — 校验 test-verdict.json 存在且 PASS，不转移状态）
Planner: Agent tool 调度 Auditor
  ↓
Auditor: 产出 semantic-verdict.json + semantic-report.md
  ↓
Planner: 报告摘要 + "如需修复，请另开会话执行 /mh-dev"
```

比 psdt-dev 更干净：psdt-dev 的 audit FAIL 会 `audit→repair→develop` 回流开发轨，仍焊两轨。mh-dev 彻底切断——审计只产出报告，修复由用户另起 `/mh-dev` 会话。

### 2.8 auditor.md 变更

删除 disposition→状态转移映射表（当前 §"disposition 映射到状态转移"）。改为声明：

> 审计只产出报告。disposition 标注问题类型供用户参考，不触发任何状态转移。修复由用户另起 `/mh-dev` 会话执行。

### 2.9 skills/mh-dev.md 和 CLAUDE.md 变更

入口路由：
- `/mh-dev`（无参数）→ 开发轨
- `/mh-dev audit` → 审计轨（独立流程）

开发轨生命周期（CLAUDE.md）：
```
intake → propose → develop → verify → done
```
删除 audit、release-candidate、archive 阶段。收尾 = done 状态 + 用户确认提交。

### 2.10 dispatch-prompts.md 变更

Auditor 调度模板保留，说明改为"由 `/mh-dev audit` 独立触发"。

### 2.11 release-candidate.sh 删除

该脚本无实际职责（无制品需生成），删除。release-candidate 状态删除后无调用方。

### 2.12 state.json.template 变更

phase 合法值更新：`intake → propose → develop → verify → done`。删除 audit、release-candidate、archive。`semantic_audit` 字段保留（审计轨仍写入 evidence，但不作为开发轨门禁）。

---

## 3. 运行态隔离设计（问题2）

### 3.1 环境变量覆盖模式

所有治理脚本将硬编码的 RUNTIME/STATE 赋值改为环境变量覆盖：

**当前模式（11 个脚本）：**
```bash
RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
STATE="$RUNTIME/state.json"
```

**改为：**
```bash
RUNTIME="${MH_DEV_RUNTIME:-$ROOT_DIR/tools/mh-dev/.mh-dev}"
STATE="$RUNTIME/state.json"
```

生产环境不设 `MH_DEV_RUNTIME` → 回退到硬编码路径，行为不变。
测试设 `MH_DEV_RUNTIME=$(mktemp -d)` → 所有脚本操作临时目录。

### 3.2 受影响脚本清单

| 脚本 | 变量 | 改动 |
|------|------|------|
| check-transition.sh | STATE | 新增 RUNTIME 覆盖行，STATE 从 RUNTIME 派生 |
| transition-state.sh | STATE | 同上 |
| validate-outputs.sh | RUNTIME+STATE | 两行加覆盖 |
| validate-changes.sh | STATE | 新增 RUNTIME 覆盖行，STATE 从 RUNTIME 派生 |
| validate-dev-completion.sh | RUNTIME | 加覆盖 |
| capture-snapshot.sh | RUNTIME | 加覆盖 |
| scope-scan.sh | RUNTIME | 加覆盖 |
| reset-session.sh | RUNTIME | 加覆盖 |
| verify.sh | RUNTIME | 加覆盖 |
| precondition-check.sh | RUNTIME+STATE | 两行加覆盖 |

注意：release-candidate.sh 删除（§2.11），不在清单中。

### 3.3 test-governance.sh 变更

**当前（有缺陷）：**
```bash
RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
trap 'rm -rf "$RUNTIME"' EXIT
```

**改为：**
```bash
RUNTIME="$(mktemp -d)"
export MH_DEV_RUNTIME="$RUNTIME"
trap 'rm -rf "$RUNTIME"' EXIT
```

关键点：
- `export MH_DEV_RUNTIME` 使子进程（被测脚本）继承临时路径
- `trap` 只清临时目录，不碰真实 `.mh-dev/`
- `setup_state()` 中的 `rm -rf "$RUNTIME"` 也只清临时目录

### 3.4 被否方案

**方案B：复制夹具到临时区，trap 只清临时区。** 不彻底——治理脚本仍硬编码真实路径，测试需 mock 每个调用。不如环境变量覆盖一行搞定。

---

## 4. 归档分层设计（问题3）

### 4.1 对齐 psdt-dev 的分层

| 层 | 路径 | 性质 | 生命周期 |
|----|------|------|----------|
| CR 需求单 | `docs/requirements/CR-xxx-<slug>.md` | 版本控制归档 | 持久 |
| 设计文档 | `docs/designs/CR-xxx-<slug>-design.md` | 版本控制归档 | 持久 |
| 运行态精简 | `.mh-dev/requirement.md` | 运行态临时（基于 CR 单精简为 Developer 可执行指令） | 会话级 |
| 验收标准 | `.mh-dev/acceptance-criteria.md` + `.json` | 运行态临时 | 会话级 |
| state.json | `.mh-dev/state.json` | 运行态临时 | 会话级 |

### 4.2 CR 需求单格式

本 CR（CR-008）自身就是格式的参照——frontmatter 含 `id`/`title`/`status`/`design_doc`/`created`，正文含背景、需求、非目标、风险。

### 4.3 CLAUDE.md 变更

阶段二改为：
- 需求澄清后创建 CR 需求单：`docs/requirements/CR-xxx-<slug>.md`（编号递增，查目录确认下一个）
- 基于需求单精简为 `.mh-dev/requirement.md`（Developer 可执行指令）
- 验收标准：`.mh-dev/acceptance-criteria.md` + `.mh-dev/acceptance-criteria.json`（运行态）

阶段三改为：
- 设计文档：`docs/designs/CR-xxx-<slug>-design.md`（版本控制归档）

### 4.4 templates/requirement.md 变更

模板调整为 CR 需求单格式（frontmatter + 归档路径指引）。

### 4.5 Planner 白名单变更

`tools/mh-dev/CLAUDE.md` 的 Planner 可写文件白名单新增：
- `docs/requirements/CR-*.md`
- `docs/designs/CR-*-design.md`

### 4.6 role-guard.sh 兼容

role-guard.sh 的 mh-dev 分支已检查 `approved_scope`，新增的 `docs/` 路径需加入 approved_scope 即可通过。无需改 role-guard.sh 逻辑。

---

## 5. 附带修复设计（问题4）

### 5.1 testcase_adding_required 检查移位

当前 `validate-outputs.sh` 的 propose 阶段末尾：
```python
if tc_required:
    # 检查 git diff 是否有 test 文件变更
    if not has_test: fail('testcase_adding_required=true but no test file changes detected')
```

问题：propose 阶段 Developer/Tester 尚未运行，不可能有测试文件变更。检查必定 FAIL。

修复：将此检查块从 propose 阶段移到 verify 阶段（Tester 完成后，测试文件应已存在）。

---

## 6. 测试变更设计

### 6.1 test-governance.sh 变更

| 测试块 | 当前 | 变更后 |
|--------|------|--------|
| RUNTIME | 硬编码真实路径 | `mktemp -d` + export |
| trap | rm 真实 .mh-dev/ | rm 临时目录 |
| verify→audit 断言 | expect_pass | 删除 |
| verify→release-candidate 断言 | 无 | 删除（release-candidate 不存在了） |
| verify→done 断言 | 无 | 新增 expect_pass |
| audit→repair 断言 | expect_pass | 删除 |
| release-candidate 门禁断言 | 有 | 删除 |

### 6.2 新增测试断言

- `verify→done` 转移 PASS（mechanical_preflight=pass + test_verdict=PASS）
- `verify→audit` 转移 FAIL
- `verify→done` 不要求 semantic_audit
- 不设 MH_DEV_RUNTIME 时行为不变

### 6.3 state.json fixture 更新

setup_state() 生成的 state.json 需适配新状态值（done 替代 release-candidate/audit/archive）。

---

## 7. 实施顺序

1. **运行态隔离（问题2）** — 先做，后续测试需要它才能安全运行
2. **轨道分离（问题1）** — 状态机精简 + 门禁调整 + 协议文档 + 删除 release-candidate.sh
3. **归档分层（问题3）** — CLAUDE.md 白名单 + 模板调整
4. **附带修复（问题4）** — testcase 检查移位
5. **测试更新** — test-governance.sh 适配新转移规则

---

## 8. Trade-off

| 决策 | 选择 | 代价 | 收益 |
|------|------|------|------|
| 终态精简 | verify→done（删 release-candidate + archive） | 需删除 release-candidate.sh 和相关门禁 | 状态机 7 节点→5 节点，无空转中间态 |
| 审计轨触发 | `/mh-dev audit` 参数路由 | 入口文档需描述参数路由 | 比关键词检测无歧义 |
| 审计轨状态 | 无状态、纯咨询 | 无法追踪审计进度 | 不与开发轨焊死，比 psdt-dev 更彻底 |
| 运行态隔离 | 环境变量覆盖 | 11 脚本各改 1-2 行 | 测试隔离彻底，生产路径不变 |
| 归档分层 | 复用 docs/requirements + docs/designs | 新增归档路径约定 | 与 psdt-dev 一致，需求文档持久化 |
| testcase 检查移位 | propose→verify | 无 | 修复 pre-existing 缺陷 |

---

## 9. 删除产物清单

本次改动将删除以下文件/代码，因状态机精简而失去职责：

| 删除项 | 原职责 | 删除理由 |
|--------|--------|----------|
| `release-candidate.sh` | 生成 release manifest + notes | mh-dev 产出是代码改动，终态是用户手动 commit，无制品需候选确认 |
| `validate-outputs.sh` release-candidate 分支 | 校验 release 产出 | 状态删除 |
| `check-transition.sh` 中 audit/release-candidate/archive 相关转移 | 状态机焊点 | 状态删除 |
| `auditor.md` disposition→状态转移映射表 | 审计触发 repair | 审计轨独立，不触发 repair |
| `state.json.template` 中 audit/release-candidate/archive 合法值 | 状态枚举 | 状态删除 |

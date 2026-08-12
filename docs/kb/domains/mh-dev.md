# mh-dev

> 本域指南描述框架自开发工具的内部机制。修改本域代码前请先阅读。
> 对应源码: `tools/mh-dev/`

## 职责与边界

**做什么：**
- 实现 Mini-Harness 框架自身的开发、治理、验证与候选发布流程
- 提供三档轨道判定（fast/light/formal），根据改动复杂度选择流程
- 实现状态机管理（intake → propose → develop → verify → done）
- 提供开发者变更快照、机械预检、独立 Tester/Auditor 结论
- 实现开发-测试-审计循环（最多 max_rounds 轮 repair）

**不做什么（由其他域负责）：**
- 外部项目交付流程 → 见 [workflow.md](workflow.md)
- 角色契约定义 → 见 [roles.md](roles.md)
- 脚本硬校验 → 见 [guards.md](guards.md)
- 产出格式模板 → 见 [templates.md](templates.md)

## 内部结构

```
tools/mh-dev/
├── CLAUDE.md                Planner 职责定义
├── README.md                工具说明
├── start.sh                 启动入口
├── agents/                  角色定义
│   ├── developer.md
│   ├── tester.md
│   └── auditor.md
├── scripts/                 工具脚本
│   ├── reset-session.sh
│   ├── scope-scan.sh
│   ├── capture-snapshot.sh
│   ├── validate-changes.sh
│   ├── validate-dev-completion.sh
│   ├── check-transition.sh
│   ├── transition-state.sh
│   ├── precondition-check.sh
│   ├── validate-outputs.sh
│   ├── audit-preflight.sh
│   └── verify.sh
├── skills/                  工作流程 SOP
│   ├── mh-dev/SKILL.md
│   ├── mh-dev-develop/SKILL.md
│   ├── mh-dev-test/SKILL.md
│   └── mh-dev-audit/SKILL.md
├── templates/               工具模板
│   ├── state.json.template
│   ├── dispatch-prompts.md
│   ├── dev-report-template.md
│   ├── test-report-template.md
│   ├── audit-report.md
│   ├── requirement.md
│   ├── acceptance-criteria.json
│   ├── acceptance-criteria.md
│   ├── semantic-verdict.json
│   ├── semantic-verdict.md
│   ├── auditor-methodology.md
│   ├── tester-methodology.md
│   └── developer-workflow.md
└── tests/                   工具测试
    └── *.sh
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| CLAUDE.md | Planner 职责：需求澄清、设计审批、调度循环 | `tools/mh-dev/CLAUDE.md` |
| agents | Developer/Tester/Auditor 角色协议 | `tools/mh-dev/agents/*.md` |
| scripts | 状态机、快照、校验、发布脚本 | `tools/mh-dev/scripts/*.sh` |
| skills | 各角色工作流程 SOP | `tools/mh-dev/skills/mh-dev*/SKILL.md` |
| templates | 工具内模板 | `tools/mh-dev/templates/*` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `tools/mh-dev/CLAUDE.md` | Planner 职责定义 | `README.md`、`docs/designs/source-of-truth.md` |
| `tools/mh-dev/start.sh` | mh-dev 启动入口 | `.claude/commands/mh-dev.md` |
| `tools/mh-dev/agents/developer.md` | Developer 角色协议 | `tools/mh-dev/skills/mh-dev-develop/SKILL.md` |
| `tools/mh-dev/agents/tester.md` | Tester 角色协议 | `tools/mh-dev/skills/mh-dev-test/SKILL.md` |
| `tools/mh-dev/agents/auditor.md` | Auditor 角色协议 | `tools/mh-dev/skills/mh-dev-audit/SKILL.md` |
| `tools/mh-dev/scripts/reset-session.sh` | 开局清理和 state 初始化 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/scope-scan.sh` | 影响范围搜索 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/capture-snapshot.sh` | 角色快照采集 | `tools/mh-dev/agents/developer.md`、`tools/mh-dev/agents/tester.md` |
| `tools/mh-dev/scripts/validate-changes.sh` | 变更归属校验 | `tools/mh-dev/agents/developer.md`、`tools/mh-dev/agents/tester.md` |
| `tools/mh-dev/scripts/validate-dev-completion.sh` | 开发后质量门禁 | `tools/mh-dev/agents/developer.md` |
| `tools/mh-dev/scripts/check-transition.sh` | 只读状态转换谓词 | `tools/mh-dev/CLAUDE.md`、`docs/kb/domains/mh-dev.md` |
| `tools/mh-dev/scripts/transition-state.sh` | 原子状态写入 | `tools/mh-dev/CLAUDE.md`、`docs/kb/domains/mh-dev.md` |
| `tools/mh-dev/scripts/precondition-check.sh` | 开发前置检查 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/validate-outputs.sh` | 阶段输出校验 | `tools/mh-dev/CLAUDE.md`、`docs/kb/domains/mh-dev.md` |
| `tools/mh-dev/scripts/audit-preflight.sh` | 机械预检 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/verify.sh` | 工具内总门禁 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/skills/mh-dev/SKILL.md` | Planner 职责 SOP | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/skills/mh-dev-develop/SKILL.md` | Developer 工作流程 SOP | `tools/mh-dev/agents/developer.md` |
| `tools/mh-dev/skills/mh-dev-test/SKILL.md` | Tester 工作流程 SOP | `tools/mh-dev/agents/tester.md` |
| `tools/mh-dev/skills/mh-dev-audit/SKILL.md` | Auditor 工作流程 SOP | `tools/mh-dev/agents/auditor.md` |
| `tools/mh-dev/templates/state.json.template` | 状态 schema 模板 | `tools/mh-dev/scripts/check-transition.sh` |
| `tools/mh-dev/templates/dispatch-prompts.md` | 调度 prompt 模板 | `tools/mh-dev/CLAUDE.md` |

## 约束与陷阱

### round 口径：首轮为 0，命名形态统一

state 中的 repair.round 是 round 的**单一真相源**，首轮开发为 `0`，每次 `tools/mh-dev/scripts/transition-state.sh` 执行 repair 转移时递增。`tools/mh-dev/scripts/capture-snapshot.sh` 与 `tools/mh-dev/scripts/validate-changes.sh` 都以它校验 `--round` 参数，不一致即 BLOCKED。

三处命名形态一致，均为 role.round.point 形态，不带 `r` 前缀：

| 产物 | 形态 |
|---|---|
| 快照文件 | snapshots/developer.0.before.json |
| state 的 snapshots 键 | developer.0 |
| 归属证据 | evidence/change-attribution.developer.0.json |

`tools/mh-dev/scripts/check-transition.sh` 的 developer 归属门禁只接受当前 repair.round 对应的键，**无 legacy 回退**（旧实现额外接受 `'1'`，使 round≥2 时上一轮归属可冒充本轮）。旧快照仅存在于 `.mh-dev-archive/`，归档态不参与门禁，故无迁移需求。

### done 门禁两字段须来自独立证据源

state 的 test_verdict 与 mechanical_preflight 是 done 阶段的两道独立门禁，证据来源必须分离，否则双门禁退化为单门禁：

- test_verdict ← 运行态 evidence/test-verdict.json（Tester 产出）
- mechanical_preflight ← 运行态 evidence/audit-preflight.json（`tools/mh-dev/scripts/audit-preflight.sh` 落盘，含实际 exit_code）

`tools/mh-dev/scripts/validate-outputs.sh` 在 verify 阶段回填 mechanical_preflight=pass 的条件是**证据文件存在且 exit_code==0**；证据缺失或非零时字段保持 pending，由 done 门禁阻断。verify 阶段不在此处 fail——机械预检是 Planner 职责，verify 只做诚实记录。因此 Planner 须在 verify 前执行机械预检脚本。

### 审计轨与开发轨解耦

audit 分支校验的 verdict 由 state 的 audit_verdict_path 字段（相对仓库根）**登记**指定，未登记即 BLOCKED。不使用 `sorted(glob(...))[-1]` 或 mtime 猜"最新文件"——那会让本次审计结论受目录内历史文件影响。

audit 分支**完全不读**运行态 evidence/test-verdict.json，也不做"存在则校验、缺失则跳过"的条件分支：审计一个已提交范围时，开发轨运行态证据不该参与判定，条件校验会让结论随运行态残留的有无而变化。对 Tester 结论的要求由 verdict 内 tester_verdict_ref 字段的 schema 校验承担（只校验声明，不读文件）。

`load()` 的 `FileNotFoundError` 与 `JSONDecodeError` 均转 `fail()`，保证任何路径下输出都以 `BLOCKED:` 开头，不暴露 traceback。

### 会话状态不可跨 CR 复用

`tools/mh-dev/scripts/check-transition.sh` 在 `intake → propose` 转移上做残留检测，七项判据任一命中即阻断并提示先执行 `tools/mh-dev/scripts/reset-session.sh`：revision!=0、change_ownership 非空、snapshots 非空、repair.status!=not_started、test_verdict!=pending、mechanical_preflight!=pending、phase_timestamps 含 develop/verify/done 任一。

覆盖的是"phase 被改回 intake 但其余字段仍是上一个 CR 的产物"这一情形（phase=done 直接转 propose 本就被相位表阻断）。**不检 approved_scope**——intake 阶段登记 scope 是正常流程，非残留信号。

因此 phase_timestamps 不再是纯记录字段，它参与残留检测。

### 变更归属对称就地写入

`tools/mh-dev/scripts/validate-changes.sh` 对 developer 与 tester **两个角色**都就地写入 change_ownership，不依赖后续 verify 阶段回填（否则 tester 归属在 verify 之前不存在，AC 无法在归属校验后立即验证）。doc_sync 检查仍只在 developer 分支内。

**全部违规判定必须在归属落盘与 state 写入之前完成。** 早前实现把 doc_sync 检查排在 change_ownership 写入之后：doc_sync 违规时脚本 exit 1，但 change_ownership 已写入且落盘归属记 `result=PASS`、`violations=[]`，`check-transition.sh verify` 随即放行，develop→verify 门禁失效。scope 越权走早退分支不写归属，两条违规路径处置不对称。现三类违规（scope 越权、formal 轨、doc_sync）同一处置：均不写 change_ownership/snapshots，归属记 `result=FAIL` 且 violations 非空，`track_escalations` 分别记 GOVERNANCE_PATH 与 DOC_SYNC。

### 归属文件一律不可变

`evidence/change-attribution.<role>.<N>.json` 一旦落盘就不允许覆盖，无论其 `result` 是 PASS 还是 FAIL（`BLOCKED: immutable attribution exists`）。违规后的修正方式是**重开一轮**，不是同轮重跑。

CR-013 期间曾尝试按 `result` 分级（FAIL 可覆盖以支持同轮修正），配合追加式违规历史防止覆盖等于抹除。该方案派生出两类缺陷：伪造省略越权文件的快照即可把 FAIL 洗成 PASS；以及合法修复顺序（先撤回文件、再重跑，此时快照尚未重采）会追加一条无法消解的记录而永久死锁。每次修补又长出新缺陷，最终整体回退。**归属不可变是更简单且更安全的处置**——代价是违规轮作废，这个代价可以接受。

### doc_sync 为定点查表，不做前缀通配

doc_sync 用 `if path in doc_sync` 精确查表，避免误伤 mh-dev 下的非治理脚本（scope-scan.sh、reset-session.sh 等）。归属校验脚本、快照采集脚本、机械预检脚本与模板文件**不纳入** doc_sync：前三者不描述用户可见口径，后者本身即文档；纳入会造成自指循环（doc_sync 规则本身就写在归属校验脚本里）。

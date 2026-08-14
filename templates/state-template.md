# .state.md Schema（权威参考）

本文件定义 `deliverables/{project}/.engine/.state.md` 的完整字段 schema。
所有 Skill 在初始化或更新 .engine/.state.md 时必须以此为准。

---

## 完整字段定义

```yaml
# === 基础标识 ===
project: {slug}                # 项目标识符，交付目录名同值。字符集 ^[a-z][a-z0-9-]{0,63}$，
                               # 且不得为保留名（docs/src/tests/deploy/assets/reference/engine）。
                               # 由 scripts/validate-slug.sh 强制，澄清阶段与用户确认后写入，此后只读。
                               # 是该交付物在框架内的唯一标识符，不与需求编号并存。

# === 流程状态 ===
phase: init                    # 当前阶段: init | propose | apply | archive | done
current_step: THINK-NEEDS     # 当前步骤 ID（见下方步骤 ID 枚举）
current_role: THINKER          # 当前执行角色: THINKER | WORKER | VERIFIER（逗号分隔表示并行扇出）
                               # 语义是「派发意图」而非执行者身份。单值字段，不新增备份字段。
                               # 本文件只应有一个 current_role 行；生效值取首行（读取端 head -1）。
                               # role-guard 交还例外：非 ORCHESTRATOR 持权时写本文件，
                               # 仅当该次写入新内容的「首个 current_role 行」值恰为 ORCHESTRATOR
                               # 才放行（判据与读取端同源，不读磁盘旧值）。
                               # 写多行 current_role 而首行是别的角色一律拒——曾用存在性量词
                               # （任一行匹配即放行）导致横向夺权。
                               # 故交还必须用 Write 一次完整写入——交还例外只接受 Write，
                               # Edit 写本文件一律 exit 2（Edit 只暴露片段，守卫看不到合并
                               # 结果，跨行 old_string 曾可被用于提权）。
                               # 详见 docs/kb/domains/guards.md
current_handoff: ""            # 当前活跃 handoff 文件名（如 web-cli-THINK-DESIGN-R1.md）
completed_steps: []            # 已完成步骤列表（字符串数组）
auto_advance: true             # 始终自动推进（/mh-run 唯一入口）

# === 轨道 ===
track: code                    # code | ppt（入口确定，不可中途切换）
thinker_phase: ""              # needs | design | visual（当前 Thinker 相位）
ppt_design_mode: ""            # system | creative（ppt track 专用）
ppt_density: ""                # speaker | reading（ppt track 专用；空值按 speaker 严格档判定）

# === 修复循环 ===
repair_round: 0                # 当前修复轮次（0=未进入修复循环，1-5=修复中）
repair_task: ""                # 当前修复的任务标识（如 Task-1）
repair_history: []             # 修复历史（每轮追加，通过后清空）
# 格式: [{round: 1, error_type: "test_failure", failed_count: 3, summary: "API返回500", root_cause_hypothesis: "...", action_taken: "..."}]
repair_snapshots: []           # 修复快照（每轮追加，通过后清空）
# 格式: [{round: 1, output_hash: "md5", code_report: ".engine/code-report-r1.md"}]

# === 任务计时 ===
task_started_at: ""            # 当前任务开始时间（Orchestrator 派发时写入，完成后清空）

# === 审批状态 ===
sr_status:
  SR1: pending                 # pending | approved | rejected（方案确认，含 wireframe 审批）
  SR3: pending                 # pending | approved | rejected（交付确认）

# === 技术栈 ===
tech_stack:
  language: ""                 # javascript | python | go | rust | java | unknown
  package_manager: ""          # npm | yarn | pnpm | poetry | uv | pip | go | cargo | maven | gradle
  test_framework: ""           # jest | vitest | pytest | go test | cargo test | maven-surefire | ...
  build_tool: ""               # webpack | vite | tsc | python | go | cargo | maven | gradle
  lint_tool: ""                # eslint | ruff | golangci-lint | clippy | checkstyle

# === 验证策略 ===
test_strategy: ""              # e2e | unit | integration | smoke | manual | none

# === 环境信息 ===
env:
  browser_available: false     # 浏览器 E2E 测试环境是否可用

# === 元数据 ===
last_updated: ""               # ISO 8601 UTC 时间戳，每次更新必须同步刷新
```

---

## 步骤 ID 枚举

### 共通步骤

| 阶段 | 步骤 ID | 说明 |
|------|---------|------|
| init | INIT-1 | 初始化任务目录 |
| init | INIT-DONE | clarify 阶段完成 |
| propose | THINK-NEEDS | Thinker needs 相位（所有 track） |
| propose | PROPOSAL-CONFIRM | Proposal 确认（人机交互） |
| propose | PROPOSE-DONE | propose 阶段完成 |
| apply | SR1-PENDING | SR1 方案审批暂停 |
| apply | SR1-DONE | SR1 通过 |
| apply | VERIFY-1 | Verifier 验证 |
| apply | SR3-PENDING | SR3 交付审批暂停 |
| apply | SR3-DONE | SR3 通过 |
| apply | BATCH-CONFIRM | 批次人工确认 |
| archive | ARC-1 | 需求归档 |
| archive | ARC-2 | 设计归档 |
| archive | ARC-3 | 产出物归档 | ~~取消~~ |
| archive | ARC-4 | 参考资料归档 |
| archive | ARC-5 | 测试用例沉淀 |
| archive | ARC-6 | 执行指标生成 |
| archive | ARC-7 | 经验沉淀 |
| archive | ARC-8 | AI 项目上下文生成 |
| archive | ARC-DONE | 归档完成 |

### code track 专属

| 阶段 | 步骤 ID | 说明 |
|------|---------|------|
| propose | THINK-DESIGN | Thinker design 相位（code track） |

### ppt track 专属

| 阶段 | 步骤 ID | 说明 |
|------|---------|------|
| propose | THINK-VISUAL | Thinker visual 相位（ppt track） |
| propose | WIREFRAME-PENDING | Wireframe 审批暂停（ppt track） |

---

## 全局指针文件

`deliverables/.state.md` 仅包含当前活跃交付物的指针（全局指针，不在 .engine/ 下）。
`role-guard.sh` 以它定位活跃交付物（CR-018 R7），语义见 `templates/state-pointer-template.md`：

```yaml
project: {slug}
```

---

## 向后兼容（旧角色值映射）

现有 .state.md 若含旧 current_role（PM/BA/SA/DE/TE/UX），状态机不直接崩溃——clarify 阶段重写时映射：

| 旧值 | 新值 |
|------|------|
| PM | ORCHESTRATOR（主会话标记，不进 role-guard） |
| BA/SA/UX | THINKER |
| DE | WORKER |
| TE | VERIFIER |

映射在 mh-intake Step 1（初始化任务目录时重写 .engine/.state.md）执行。若用户 RESUME 一个旧 .state.md，intake 检测到旧枚举时提示"检测到旧角色 schema，将自动迁移"并映射。

---

## 更新规则

1. 每次更新任何字段时，必须同步更新 `last_updated`
2. `repair_round` 在每轮修复开始时递增，任务通过审计后重置为 0
3. `repair_history` 每轮修复追加一条记录（含 error_type、failed_count、summary），任务通过后清空为 []
4. `completed_steps` 仅追加，不删除（用于断点恢复跳过已完成步骤）
5. `current_handoff` 在每次写入新 handoff 时更新，handoff 完成后清空
6. `sr_status` 各字段在对应审批节点执行时更新
7. `track` 写入后只读，切换需重新开需求
8. 派发（`current_role` 改为 SubAgent 角色）与交还（改回 `ORCHESTRATOR`）**各须一次完整写入**；交还写入内容的**首个** `current_role:` 行其值须恰为 `ORCHESTRATOR`，否则被 role-guard 判为伪交还而拦截。文件中不得出现多个 `current_role` 行——生效值只取首行，多行形态曾被用于横向夺权

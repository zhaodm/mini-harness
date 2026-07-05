# .state.md Schema（权威参考）

本文件定义 `deliverables/{REQ-ID}/.state.md` 的完整字段 schema。
所有 Skill 在初始化或更新 .state.md 时必须以此为准。

---

## 完整字段定义

```yaml
# === 基础标识 ===
req_id: REQ{NNN}              # 需求编号，全局唯一递增

# === 流程状态 ===
phase: init                    # 当前阶段: init | propose | apply | archive | done
current_step: INIT-1           # 当前步骤 ID（见下方步骤 ID 枚举）
current_role: PM               # 当前执行角色: PM | BA | SA | DE | TE | UX
current_handoff: ""            # 当前活跃 handoff 文件名（如 REQ001-REQ1-R1.md）
completed_steps: []            # 已完成步骤列表（字符串数组）
auto_advance: true             # 始终自动推进（/mh-run 唯一入口）

# === 修复循环 ===
repair_round: 0                # 当前修复轮次（0=未进入修复循环，1-5=修复中）
repair_task: ""                # 当前修复的任务标识（如 Task-1）
repair_history: []             # 修复历史（每轮追加，通过后清空）
# 格式: [{round: 1, error_type: "test_failure", failed_count: 3, summary: "API返回500", root_cause_hypothesis: "...", action_taken: "..."}]
repair_snapshots: []           # 修复快照（每轮追加，通过后清空）
# 格式: [{round: 1, output_hash: "md5", code_report: "de/code-report-r1.md"}]

# === 任务计时 ===
task_started_at: ""            # 当前任务开始时间（PM 派发时写入，完成后清空）

# === 审批状态 ===
sr_status:
  SR1: pending                 # pending | approved | rejected（方案确认）
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

| 阶段 | 步骤 ID | 说明 |
|------|---------|------|
| init | INIT-1 | 初始化任务目录 |
| init | INIT-DONE | clarify 阶段完成 |
| propose | REQ-1 | BA 需求分析 |
| propose | REQ-2 | SA 架构设计 |
| propose | REQ-3 | TE 测试用例设计 |
| propose | REQ-4 | PM 计划编排 |
| propose | PROPOSE-DONE | propose 阶段完成 |
| apply | DEV-1 | DE 批次开发 |
| apply | TEST-1 | TE 审计 |
| apply | TEST-2 | TE 最终审计 |
| apply | SR3-DONE | SR3 交付确认通过 |
| archive | ARC-1 | 需求归档 |
| archive | ARC-2 | 设计归档 |
| archive | ARC-3 | 产出物归档 |
| archive | ARC-4 | 参考资料归档 |
| archive | ARC-5 | 测试用例沉淀 |
| archive | ARC-6 | 执行指标生成 |
| archive | ARC-7 | 经验沉淀 |
| archive | ARC-8 | AI 项目上下文生成 |
| archive | ARC-DONE | 归档完成 |

---

## 全局指针文件

`deliverables/.state.md` 仅包含当前活跃需求的指针：

```yaml
req_id: REQ{NNN}
```

---

## 更新规则

1. 每次更新任何字段时，必须同步更新 `last_updated`
2. `repair_round` 在每轮修复开始时递增，任务通过审计后重置为 0
3. `repair_history` 每轮修复追加一条记录（含 error_type、failed_count、summary），任务通过后清空为 []
4. `completed_steps` 仅追加，不删除（用于断点恢复跳过已完成步骤）
5. `current_handoff` 在每次写入新 handoff 时更新，handoff 完成后清空
6. `sr_status` 各字段在对应审批节点执行时更新

# Mini-Harness Workflow

Orchestrator 调度手册。Orchestrator 必须严格按此手册执行，不得跳步或自行决策技术问题。

---

## 流程总览

```
/mh-clarify          /mh-propose                    /mh-apply                         /mh-archive
─────────────      ─────────────────────────       ──────────────────────────────     ─────────────────
                                                                                     
[人机协作]         [自动化 + 人工审批]              [自动化 + 多轮修复 + 人工审批]     [归档 + 结项]
                                                                                     
 Orchestrator      Orchestrator→Thinker            Orchestrator→Worker→Verifier       Orchestrator
 │                 │                                │                                 │
 ▼                 ▼                                ▼                                 ▼
 场景检测           THINK-NEEDS 需求规格             Batch-1: Worker 并行开发           ARC-1 需求归档
 │                 │                                │                                 │
 ▼                 ▼                                ▼                                 ▼
 需求澄清          THINK-DESIGN/VISUAL 设计/视觉    Batch-1: Verifier 并行审计         ARC-2 设计归档
 │                 │                                │                                 │
 ▼                 ▼                                ├─FAIL→ 并行修复(≤5轮)            ▼
 Proposal定稿      Orchestrator 计划编排             │                                 ARC-3 ~~取消（产出即归档）~~
                   │                                ▼                                 │
                   ▼                                人工批量确认                       ▼
                  ★SR1 方案确认                    │                                ★SR4 结项确认
                                                    ▼                                 
                                                    Batch-2: ... (如有)               
                                                    │                                 
                                                    ▼                                 
                                                   ★SR2 功能评审                     
                                                    │                                 
                                                    ▼                                 
                                                    VERIFY-2 最终审计                 
                                                    │                                 
                                                    ▼                                 
                                                   ★SR3 最终评审                     
```

★ = 人工审批节点

---

## Mini-Harness 自身开发（/mh-dev）

`/mh-dev` 不属于上方 `/mh-run` 的外部项目交付流程。它以 `tools/mh-dev/` 为独立控制面，直接变更本仓库的角色、技能、脚本、工作流、模板、命令、文档与测试。

```
intake → propose → develop → verify → done
```

- 运行态与证据在 `tools/mh-dev/.mh-dev/`；其中 `state.json` 只对 mh-dev 自开发流程权威。
- fast、light、formal 都需要人工确认；涉及规则、权限、状态、验证或发布契约的变更强制 formal。
- Developer 以开发前后快照证明实际 diff 符合已批准范围；Tester 和 Auditor 分别给出结构化 verdict。
- 机械预检的退出码优先于任何 Agent 结论；语义审计只在预检成功后运行。

完整执行协议见 `tools/mh-dev/CLAUDE.md`，工具内验证入口为 `bash tools/mh-dev/scripts/verify.sh`。

---

## 自动推进模式（/mh-run）

用户可通过 `/mh-run` 启动 code track 全流程自动推进模式，等效于依次执行 clarify → propose → apply → archive，但无需在阶段间手动输入命令。

- 阶段间自动衔接，消除手动触发等待
- 阶段内所有人工审批节点（★标记）照常暂停
- 支持断点恢复（.engine/.state.md 中 `auto_advance: true`）
- `/mh-ppt` 启动 ppt track，同样支持自动推进和断点恢复（含 WIREFRAME-PENDING 暂停点）

推进触发条件：

| 完成标记 | 自动推进动作 |
|---------|------------|
| INIT-DONE | → propose 阶段 |
| PROPOSE-DONE / SR1 通过 | → apply 阶段 |
| SR3-DONE | → archive 阶段 |
| phase=done | 打印最终摘要，流程结束 |

---

## 详细时序

> **架构变更：** propose 阶段的 Thinker 相位和 apply 阶段的批量 Worker∥Verifier 并行，
> 通过 JS Workflow 脚本（`workflows/`）确定性执行，不再依赖 Orchestrator 解读自然语言指令。
> Orchestrator 主会话保持人机交互和质量门禁职责。

```
┌──────┐     ┌────────────┐     ┌─────────┐     ┌────────┐     ┌──────────┐
│ User │     │Orchestrator │     │ Thinker │     │ Worker │     │ Verifier │
└──┬───┘     └─────┬──────┘     └────┬────┘     └────┬───┘     └────┬─────┘
   │            │            │            │            │            │
   │ /mh-clarify  │            │            │            │            │
   │───────────>│            │            │            │            │
   │            │            │            │            │            │
   │<──提问──── │            │            │            │            │
   │───回答────>│            │            │            │            │
   │            │            │            │            │            │
   │<─Proposal─ │            │            │            │            │
   │──确认─────>│            │            │            │            │
   │            │            │            │            │            │
   │ /mh-propose            │            │            │            │
   │───────────>│            │            │            │            │
   │            │──handoff──>│ (needs)    │            │            │
   │            │<──回报─────│            │            │            │
   │            │            │            │            │            │
   │            │──handoff──>│ (design/visual)        │            │
   │            │<──回报─────│            │            │            │
   │            │            │            │            │            │
   │            │──编排计划──>│            │            │            │
   │<──SR1审批──│            │            │            │            │
   │──通过─────>│            │            │            │            │
   │            │            │            │            │            │
   │ /mh-apply │            │            │            │            │
   │───────────>│            │            │            │            │
   │            │──handoff(Batch并行)────────────────>│            │
   │            │──handoff(Batch并行)──────────────────────────── >│
   │            │<──回报─────────────────────────────-│            │
   │            │<──回报────────────────────────────────────────── │
   │            │            │            │            │            │
   │            │ (失败则并行修复 Worker→Verifier，最多5轮)      │            │
   │            │            │            │            │            │
   │<──SR2审批──│            │            │            │            │
   │──通过─────>│            │            │            │            │
   │            │──handoff(最终审计)────────────────────────────── >│
   │            │<──回报────────────────────────────────────────── │
   │<──SR3审批──│            │            │            │            │
   │──通过─────>│            │            │            │            │
   │            │            │            │            │            │
   │ /mh-archive            │            │            │            │
   │───────────>│            │            │            │            │
   │            │──归档──────>            │            │            │
   │<──SR4确认──│            │            │            │            │
   │──确认─────>│            │            │            │            │
   │            │            │            │            │            │
   │<──完成────-│            │            │            │            │
```

---

## Handoff 流转

```
Orchestrator 写入 handoff    角色执行              角色回报
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│ status: pending  │────>│ 读取白名单    │────>│ status: done    │
│ to: {role}       │     │ 执行任务      │     │ output_files: []│
│ input_files: []  │     │ 写入产出物    │     │ summary: ""     │
└─────────────────┘     └──────────────┘     └─────────────────┘
                                                      │
                                                      ▼
                                              Orchestrator 校验产出物
                                              更新 .engine/.state.md
                                              启动下一步
```

---

## 修复循环

```
        ┌─────────────────────────────────────┐
        │                                     │
        ▼                                     │
  Worker 编码(R{N}) ──> Verifier 审计 ──> PASS ──> 下一步
                        │
                        ▼
                      FAIL
                        │
                        ▼
                   N < 5 ? ──YES──> Orchestrator 写新 handoff(R{N+1}) ─┘
                        │
                        NO
                        │
                        ▼
                   上升人工审核
```

---

## 状态机

```
init ──────> propose ──────> apply ──────> archive ──────> DONE
  │              │              │              │
  │ (RESUME)     │ (SR1驳回)    │ (SR2/3驳回)  │ (SR4驳回)
  └──> init      └──> propose   └──> apply     └──> apply
```

---

## 通用规则

> 角色切换指令、Handoff 协议、心跳打印、过程日志、断点恢复、异常处理等通用规则见 skills/mh-codeflow/SKILL.md "调度协议"节 + `templates/logging-standard.md`。各阶段执行细节见 skills/*/SKILL.md。

> **完成回报（CR-017）**：回报不写在 handoff 内，落 `deliverables/{project}/.engine/reports/{handoff-basename}.report.md`。`handoffs/*.md` 保持 ORCHESTRATOR 独占（任务+白名单+约束），回报路径对 THINKER/WORKER/VERIFIER/ORCHESTRATOR 四者放行。两者分处两套写权，故质量门禁 Step 0 比较的两侧（handoff 白名单 vs 回报 `read_files`）无法被执行角色自洽伪造。该放行条**无内容判据**（内容判据是 CR-016 两个 P0 的共同载体，有意不引入），路径正则 `^…$` 双向锚定且不跨交付物；写权由「当前谁持权」约束而非文件名声称的角色。`scripts/verify.sh` 与 `scripts/verify-qa.sh` 从 handoff 路径派生回报路径读取字段，与守卫同源，另新增「handoff 存在但回报缺失」的 WARN。mh-dev 分支仍只校验 `approved_scope`、不校验写入者角色（CR-017 D3 未落地，理由见 `docs/kb/domains/guards.md`）。
>
> role-guard.sh 覆盖 `Write`/`Edit`/`NotebookEdit`，归一化后按路径归属路由：`deliverables/`（目录前缀语义）归角色白名单，其余归 mh-dev 框架治理，无活跃 mh-dev 授权时框架路径放行。
>
> **活跃交付物定位（CR-018 R7）**：以全局指针 `deliverables/.state.md` 的 `project` 字段为准，**不扫描文件系统**。交付目录改用项目标识符命名后多项目并存成为常态，`find … | head -1` 会取到枚举顺序上的任意一个项目，据此判权即失效。五形态：指针文件不存在 / `project` 为空 / 指针指向的交付物或其 state 不存在 / `current_role` 空或畸形 → 放行；`project` 非法 slug → `exit 2`（唯一收紧项，出现即 state 被污染，此时放行等于在污染态下判权）。任一形态下都不遍历 `deliverables/` 寻找替代 state，非指针所指的交付物其 `current_role` 不参与任何判权。标识符字符集由 `scripts/validate-slug.sh` 单一实现强制，生成侧（mh-intake）与消费侧（守卫，插值前自校验，不信任生成侧）各调用一次。
>
> **角色白名单（CR-018 R6，肯定式路径归属表）**：THINKER 写 `docs/spec/`、`assets/`、`.archiveignore`、`.engine/verify-strategy.md`；WORKER 写 `src/`、`tests/`、`deploy/`、`assets/`、产品区根文件全名白名单、`.engine/code-report-*.md`、`.engine/quality-gate-report.md`；VERIFIER 写 `tests/`、`.engine/final-test-report.md`、`.engine/temp-test-report.md`；ORCHESTRATOR 写 `.engine/` 的调度态文件、产品区 `docs/`、`tests/regression-suite.md` 与全局指针。**不得以「不含其他角色前缀」作为授权谓词**——产品区去掉角色前缀后，原否定式谓词的排除项全部落空而退化为产品区全通。WORKER 由此不可写 `docs/`（规格文档写权归 THINKER 与 ORCHESTRATOR）；`tests/` 由 WORKER 与 VERIFIER 共写、`assets/` 由 THINKER 与 WORKER 共写，均为显式声明的既有分工。归属表每条均 `^…$` 双向锚定，目录前缀条目形如 `^…/src/.+$`（尾部 `.+` 使目录自身不命中，左锚拒 `x/deliverables/…` 嵌套伪造）。
>
> THINKER/WORKER/VERIFIER 另有交还例外，写本交付物 `.engine/.state.md` 且该次写入内容的首个 `current_role:` 行值恰为 `ORCHESTRATOR` 时放行（判据与读取端同源，非存在性量词——旧的存在性判定曾导致横向夺权；且只接受 `Write`，`Edit` 因片段判据无法覆盖合并结果而一律拒）——**交还须一次完整写入**（判据取本次写入新内容，拆分成不覆盖该行的 Edit 会被拒），路径正则 `^…$` 双向锚定 `.state.md` 全名（`.state.md.evil`、`.state.mdX`、`.state.md/child.md` 等后缀伪造与嵌套伪造路径均不命中），且不放大到 `handoffs/`、`plan-action.md` 等其他引擎态文件。全局路径穿越检测拒绝包含 `..` 组件的写入路径；mh-dev 分支采用双向归一化匹配 `approved_scope`（两侧统一转绝对形态后比较，兼容 scope 的相对/绝对两种存储形态），以 `/` 结尾的 scope 条目按目录前缀放行，仓库外绝对路径直接拦截，仓库根由脚本自身位置推导而非 cwd；`tests/` 与 `tools/mh-dev/tests/` 作为 Tester 专属路径按目录前缀放行，无需列入 `approved_scope`。守卫为自授权机制、`Bash` 通道不受覆盖，定位是防误撞而非安全边界（详见 `docs/kb/domains/guards.md`）。

---

## 各阶段详细执行序列

各阶段的详细步骤定义在对应 skill 文件中（执行权威）：

| 阶段 | 执行权威文件 | 概要 |
|------|------------|------|
| clarify | skills/mh-intake/SKILL.md | 场景检测 + 环境预检 + track 选择 + 需求澄清 + Proposal 定稿 |
| propose | skills/mh-design/SKILL.md | Thinker needs → design/visual → Orchestrator 编排 → SR1 |
| apply | skills/mh-build/SKILL.md | Worker 开发 → Verifier 审计（test_strategy 驱动）→ 修复循环 → SR2 → SR3 |
| archive | skills/mh-deliver/SKILL.md | 需求归档 → 设计归档 → ~~产出物归档（已取消，产出即归档）~~ → SR4（含 merge 策略） |
| run | skills/mh-codeflow/SKILL.md | code track 全流程自动推进 |
| ppt | skills/mh-slideflow/SKILL.md | ppt track 全流程（Thinker wireframe + verify-ppt.sh） |

**Workflow 脚本（并行编排层）：**

| 脚本 | 调用时机 | 并行内容 |
|------|---------|---------|
| workflows/thinker-design.js | propose Thinker 相位 | Thinker needs/design/visual 相位执行 |
| workflows/apply-batch-dev.js | apply 每个 Batch 开发 | Batch 内多 Task Worker 并行 |
| workflows/apply-batch-test.js | apply 每个 Batch 审计 | Batch 内多 Task Verifier 并行 |
| workflows/apply-final-audit.js | apply SR2 后最终审计 | Verifier 全量审计 |

**决策逻辑库（脚本化层）：**

| 脚本 | 替代的 NL 约束 | 功能 |
|------|--------------|------|
| workflows/lib/detect-scenario.js | mh-clarify 前置检查 | RESUME/CHANGE/NEW 场景检测 |
| workflows/lib/calculate-batches.js | mh-apply 批次计算 | 拓扑排序 + 贪心合并 |
| workflows/lib/decide-repair.js | mh-apply-repair 收敛追踪 | 发散/抖动/停滞/耗尽检测 → retry/escalate |
| workflows/lib/detect-archive-mode.js | mh-archive 模式检测 | 首次/变更归档 + baseline 版本管理 |
| workflows/lib/recommend-type-mode.js | mh-clarify Step 3-4 | tech_stack → test_strategy 推荐 + deriveReviewScope(track) |
| workflows/lib/archive-merge.js | mh-archive merge 策略 | PROJECT 标签定位 + 追加/替换/废弃 |
| workflows/lib/auto-advance.js | mh-run/mh-ppt 状态机 | phase/step → advance/pause/end |

> Skills 文件是 Agent 的唯一执行依据。本文档仅作为人类阅读的流程参考。

---


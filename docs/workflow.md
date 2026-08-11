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
 Proposal定稿      Orchestrator 计划编排             │                                 ARC-3 代码归档
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
- 支持断点恢复（.state.md 中 `auto_advance: true`）
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
                                              更新 .state.md
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

---

## 各阶段详细执行序列

各阶段的详细步骤定义在对应 skill 文件中（执行权威）：

| 阶段 | 执行权威文件 | 概要 |
|------|------------|------|
| clarify | skills/mh-intake/SKILL.md | 场景检测 + 环境预检 + track 选择 + 需求澄清 + Proposal 定稿 |
| propose | skills/mh-design/SKILL.md | Thinker needs → design/visual → Orchestrator 编排 → SR1 |
| apply | skills/mh-build/SKILL.md | Worker 开发 → Verifier 审计（test_strategy 驱动）→ 修复循环 → SR2 → SR3 |
| archive | skills/mh-deliver/SKILL.md | 需求归档 → 设计归档 → 产出物归档（track 感知）→ SR4（含 merge 策略） |
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
| workflows/lib/archive-merge.js | mh-archive merge 策略 | REQ-ID 标签定位 + 追加/替换/废弃 |
| workflows/lib/auto-advance.js | mh-run/mh-ppt 状态机 | phase/step → advance/pause/end |

> Skills 文件是 Agent 的唯一执行依据。本文档仅作为人类阅读的流程参考。

---


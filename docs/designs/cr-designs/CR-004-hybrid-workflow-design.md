# CR-004 技术设计：混合架构重构

> CR: CR-004-workflow-hybrid-refactor
> 作者: PM + SA
> 日期: 2026-06-09
> 状态: 设计中

---

## 0. 技术选型：JS Workflow vs Python 自建编排

### 0.1 方案对比

| 维度 | JS Workflow（Claude Code 内置） | Python 自建编排 |
|------|-------------------------------|-----------------|
| 开发成本 | 低（1-2天） | 高（1-2周） |
| 运行环境依赖 | Claude Code 会话 | 任意（本地/CI/服务器） |
| 并行可靠性 | 高（内置 parallel()） | 高（asyncio/celery） |
| 断点恢复 | 弱（重跑整个 Workflow） | 强（自定义粒度） |
| 可测试性 | 弱（需真实执行） | 强（可 mock） |
| 模型灵活性 | 仅 Claude | 任意混合 |
| 长期演进 | 随官方 API 升级受益 | 自主控制 |
| Hook 集成 | 自动继承（role-guard.sh） | 需自行实现权限控制 |
| 进度可视 | /workflows 命令实时查看 | 需自建 dashboard |
| SubAgent 管理 | 内置（agent() 一行调用） | 需自己对接 Anthropic API |

### 0.2 JS Workflow 优势

- **零基础设施** — `agent()`、`parallel()` 现成可用，不需要实现 SubAgent 生命周期管理、并发控制、结果收集
- **深度集成** — SubAgent 自动继承 Hook、settings、工具权限，不需要额外配置
- **原生可视** — `/workflows` 实时看各 agent 状态
- **官方维护** — API 升级直接受益

### 0.3 JS Workflow 劣势（已知局限）

- 后台执行，无法中途交互 → 通过混合架构（会话层 + Workflow 层）缓解
- 中断后无法从中间恢复 → 通过 .state.md 在 Workflow 外记录状态，重跑整个 Workflow（幂等）
- 调试能力弱 → 依赖 SubAgent 输出日志和产出物检查
- 只能调 Claude → 对本框架无影响（已绑定 Claude Code 平台）

### 0.4 选型结论

**选择 JS Workflow。** 理由：

1. mini-harness 定位为 Claude Code 的增强插件，绑定 Claude Code 平台
2. 开发成本低 3-5x，可快速验证
3. 原生继承 Hook/权限/工具生态，无集成成本
4. 已知局限通过混合架构设计已缓解

---

## 1. 架构总览

### 1.1 分层职责

```
┌─────────────────────────────────────────────────────────┐
│  会话层 (PM 主会话)                                      │
│  - 人机交互（模式选择、SR gates、Batch 确认）            │
│  - 质量门禁（读取产出物 → 逐项检查）                     │
│  - 状态推进（更新 .state.md）                            │
│  - 修复循环根因分析（LLM 判断力）                        │
│  - 经验采集                                             │
├─────────────────────────────────────────────────────────┤
│  编排层 (JS Workflow)                                    │
│  - 并行扇出（SA∥TE、批量 DE、批量 TE）                   │
│  - SubAgent 生命周期管理                                 │
│  - Prompt 注入（agent 契约 + handoff 内容）              │
│  - 结果收集与结构化返回                                  │
├─────────────────────────────────────────────────────────┤
│  执行层 (SubAgent)                                       │
│  - 角色契约约束（agents/*.md）                           │
│  - 白名单文件读取                                        │
│  - 产出物写入                                            │
│  - 完成回报                                             │
├─────────────────────────────────────────────────────────┤
│  验证层 (Scripts)                                        │
│  - role-guard.sh (PreToolUse Hook)                       │
│  - verify.sh / verify-qa.sh / verify-ppt.sh             │
│  - verify-archive.sh                                     │
└─────────────────────────────────────────────────────────┘
```

### 1.2 调用时序（standard 模式 propose 阶段示例）

```
PM 主会话                         Workflow                    SubAgent
    │                                │                           │
    ├─ 结构协商（人机交互）           │                           │
    │   └─ 用户确认结构               │                           │
    ├─ 生成 SA/TE handoff 内容       │                           │
    ├─ 调用 Workflow ─────────────────┤                           │
    │   (propose-parallel)           ├─ parallel([              │
    │                                │    agent(SA), ────────────┤─ SA 执行
    │                                │    agent(TE)  ────────────┤─ TE 执行
    │                                │  ])                       │
    │                                ├─ 收集结果                  │
    │   <── 返回结果 ─────────────────┤                           │
    ├─ 执行质量门禁                   │                           │
    ├─ 更新 .state.md                │                           │
    ├─ [如不通过] 驳回重试            │                           │
    ├─ [如通过] 推进到 REQ-4          │                           │
    └─                               │                           │
```

---

## 2. Workflow 脚本详细设计

### 2.1 `workflows/propose-parallel.js`

**职责：** SA 架构设计与 TE 测试用例设计的并行执行。

**输入参数 (args)：**
```js
{
  reqId: "REQ003",                    // 需求编号
  mode: "standard",                   // standard | full
  saPrompt: "...",                    // SA agent 契约 + handoff 完整 prompt
  tePrompt: "...",                    // TE agent 契约 + handoff 完整 prompt
  outputPaths: {
    sa: "deliverables/REQ003/sa/",
    te: "deliverables/REQ003/te/"
  }
}
```

**脚本实现：**
```js
export const meta = {
  name: "propose-parallel",
  description: "Propose 阶段 SA∥TE 并行设计",
  phases: ["sa-te-parallel"]
};

const [saResult, teResult] = await parallel([
  agent(`[SA] 架构设计 ${args.reqId}`, {
    prompt: args.saPrompt,
    model: "sonnet"
  }),
  agent(`[TE] 测试用例设计 ${args.reqId}`, {
    prompt: args.tePrompt,
    model: "sonnet"
  })
]);

return {
  sa: { status: saResult.includes("status: done") ? "done" : "failed", raw: saResult },
  te: { status: teResult.includes("status: done") ? "done" : "failed", raw: teResult }
};
```

**输出：** SA/TE 各自的执行结果（含 status 判断），PM 根据结果执行质量门禁。

---

### 2.2 `workflows/apply-batch-dev.js`

**职责：** 单个 Batch 内所有 Task 的 DE 并行开发。

**输入参数 (args)：**
```js
{
  reqId: "REQ003",
  batchId: 1,
  tasks: [
    { taskId: "1", prompt: "DE契约 + Task-1 handoff 完整内容" },
    { taskId: "2", prompt: "DE契约 + Task-2 handoff 完整内容" }
  ]
}
```

**脚本实现：**
```js
export const meta = {
  name: "apply-batch-dev",
  description: "Apply 阶段 Batch 内 DE 并行开发",
  phases: ["batch-dev"]
};

const results = await parallel(
  args.tasks.map(task =>
    agent(`[DE] Task-${task.taskId} (${args.reqId} Batch-${args.batchId})`, {
      prompt: task.prompt,
      model: "sonnet"
    })
  )
);

return {
  batchId: args.batchId,
  tasks: args.tasks.map((task, i) => ({
    taskId: task.taskId,
    result: results[i],
    status: results[i].includes("status: failed") ? "failed" : "done"
  }))
};
```

---

### 2.3 `workflows/apply-batch-test.js`

**职责：** 单个 Batch 内所有 Task 的 TE 并行审计。

**输入参数 (args)：**
```js
{
  reqId: "REQ003",
  batchId: 1,
  tasks: [
    { taskId: "1", prompt: "TE契约 + Task-1 审计 handoff 完整内容" },
    { taskId: "2", prompt: "TE契约 + Task-2 审计 handoff 完整内容" }
  ]
}
```

**脚本实现：**
```js
export const meta = {
  name: "apply-batch-test",
  description: "Apply 阶段 Batch 内 TE 并行审计",
  phases: ["batch-test"]
};

const results = await parallel(
  args.tasks.map(task =>
    agent(`[TE] 审计 Task-${task.taskId} (${args.reqId} Batch-${args.batchId})`, {
      prompt: task.prompt,
      model: "sonnet"
    })
  )
);

return {
  batchId: args.batchId,
  tasks: args.tasks.map((task, i) => ({
    taskId: task.taskId,
    result: results[i],
    passed: !results[i].includes("FAIL")
  }))
};
```

---

### 2.4 `workflows/apply-final-audit.js`

**职责：** SR2 通过后的 TE 最终全量审计。

**输入参数 (args)：**
```js
{
  reqId: "REQ003",
  prompt: "TE契约 + 最终审计 handoff 完整内容"
}
```

**脚本实现：**
```js
export const meta = {
  name: "apply-final-audit",
  description: "Apply 阶段 TE 最终审计",
  phases: ["final-audit"]
};

const result = await agent(`[TE] 最终审计 ${args.reqId}`, {
  prompt: args.prompt,
  model: "sonnet"
});

return {
  result,
  passed: !result.includes("FAIL")
};
```

---

## 3. Lib 工具函数设计

### 3.1 `workflows/lib/prompt-assembler.js`

**职责：** 将 agent 契约文件 + handoff 内容组装为 SubAgent 的完整 prompt。

```js
/**
 * 组装 SubAgent prompt
 * @param {string} agentContract - agents/*.md 文件内容
 * @param {string} handoffContent - handoff 内容（可以是文件内容或动态生成）
 * @param {string[]} contextFiles - 额外上下文文件内容（白名单文件摘要）
 * @returns {string} 完整 prompt
 */
export function assemblePrompt(agentContract, handoffContent, contextFiles = []) {
  const parts = [
    "# 角色契约\n",
    agentContract,
    "\n---\n\n# 任务 Handoff\n",
    handoffContent
  ];

  if (contextFiles.length > 0) {
    parts.push("\n---\n\n# 上下文文件\n");
    contextFiles.forEach(f => parts.push(f, "\n---\n"));
  }

  return parts.join("\n");
}
```

### 3.2 `workflows/lib/result-parser.js`

**职责：** 解析 SubAgent 返回结果，提取结构化信息。

```js
/**
 * 从 SubAgent 输出中提取完成回报
 * @param {string} agentOutput - SubAgent 的原始输出
 * @returns {object} { status, outputFiles, summary, issues }
 */
export function parseReport(agentOutput) {
  const status = agentOutput.includes("status: failed") ? "failed"
               : agentOutput.includes("status: done") ? "done"
               : "unknown";

  const outputFiles = [];
  const filePattern = /output_files:\s*\n((?:\s*-\s*.+\n?)+)/;
  const match = agentOutput.match(filePattern);
  if (match) {
    outputFiles.push(...match[1].split("\n")
      .filter(l => l.trim().startsWith("-"))
      .map(l => l.trim().replace(/^-\s*/, ""))
    );
  }

  return { status, outputFiles, raw: agentOutput };
}

/**
 * 判断 TE 审计是否通过
 * @param {string} teOutput - TE SubAgent 输出
 * @returns {boolean}
 */
export function isAuditPassed(teOutput) {
  // 优先看明确结论
  if (teOutput.includes("结论: PASS") || teOutput.includes("conclusion: PASS")) return true;
  if (teOutput.includes("结论: FAIL") || teOutput.includes("conclusion: FAIL")) return false;
  // 兜底：无 FAIL 关键字视为通过
  return !teOutput.includes("FAIL");
}
```

---

## 4. Skill 精简设计

### 4.1 精简原则

- **保留：** 人机交互步骤、质量门禁清单、异常处理描述
- **移除：** 并行派发的详细步骤、handoff 文件路径模板、SubAgent spawn 指令
- **替换为：** "调用 Workflow `{name}`，传入参数 `{schema}`"

### 4.2 `mh-propose.md` 精简后结构（~100行）

```markdown
# Skill: mh-propose（精简版）

## 前置检查（不变）

## fast 模式（不变，无并行）

## standard 模式

Step 1: 产出结构协商（人机交互，不变）

Step 2: 并行调度 SA∥TE
1. [PM] 生成 SA handoff 内容（按 handoff-template 格式）
2. [PM] 生成 TE handoff 内容
3. [PM] 调用 Workflow `propose-parallel`:
   - args.saPrompt = agents/sa.md + SA handoff
   - args.tePrompt = agents/te.md + TE handoff
4. Workflow 返回后，执行质量门禁（agents/pm.md 清单）
5. 不通过 → 生成驳回 handoff，重新调用 Workflow
6. 通过 → 更新 .state.md

Step 3: PM 计划编排（不变）

## full 模式

Step 1: BA 需求分析（不变，单 agent 无需 Workflow）

Step 2: 并行调度 SA∥TE
（同 standard Step 2）

Step 3-4: 计划编排 + SR1（不变）
```

### 4.3 `mh-apply-standard.md` 精简后结构（~100行）

```markdown
# mh-apply: standard/full 模式（精简版）

Step 1: 并行批次开发+审计

  读取 plan-action.md，计算批次（逻辑不变）

  FOR 每个 Batch:
    1. [PM] 生成 Batch 内各 Task 的 DE handoff
    2. [PM] 调用 Workflow `apply-batch-dev`:
       - args.tasks = [{taskId, prompt: DE契约+handoff}, ...]
    3. Workflow 返回后，逐 Task 执行质量门禁
    4. 不通过的 Task → 驳回重新调用
    5. [PM] 生成 Batch 内各 Task 的 TE handoff
    6. [PM] 调用 Workflow `apply-batch-test`:
       - args.tasks = [{taskId, prompt: TE契约+handoff}, ...]
    7. Workflow 返回后，检查审计结论
    8. FAIL → 修复循环（mh-apply-repair.md，不变）
    9. 人工批量确认（不变）
  END FOR

Step 1.5: 集成预检（不变）

Step 2: SR2 功能评审（不变）

Step 3: TE 最终审计
  1. [PM] 生成最终审计 handoff
  2. [PM] 调用 Workflow `apply-final-audit`
  3. 结论处理（不变）

Step 4: SR3 最终评审（不变）
```

---

## 5. 状态管理与断点恢复

### 5.1 .state.md 兼容

Workflow 调用前后，PM 主会话负责 .state.md 的更新：

```
[PM 更新 state: current_step=REQ-2+REQ-3]
    ↓
[调用 Workflow propose-parallel]
    ↓ (后台执行)
[Workflow 返回]
    ↓
[PM 质量门禁]
    ↓
[PM 更新 state: current_step=REQ-4 或 重试]
```

.state.md schema 不变，Workflow 不直接写 .state.md。

### 5.2 断点恢复策略

| 中断时机 | 恢复策略 |
|----------|----------|
| Workflow 调用前中断 | PM 从 .state.md 读取 current_step，重新生成 handoff 并调用 Workflow |
| Workflow 执行中中断 | .state.md 仍为"进行中"状态，恢复时重新调用整个 Workflow（幂等） |
| Workflow 返回后、state 更新前中断 | PM 检查产出文件是否存在且非空，存在则跳过 Workflow 直接质量门禁 |

**幂等保证：** Workflow 内的 SubAgent 每次执行会重新生成产出物，覆盖已有文件。中断重试不会产生增量副作用。

---

## 6. PM 会话层精简后的职责清单

重构后 PM 在主会话中的工作：

| 职责 | 触发条件 | 需要 LLM 判断 |
|------|----------|--------------|
| 人机交互 | 模式选择、结构协商、SR gates | ✅ |
| Handoff 内容生成 | 每次调用 Workflow 前 | ✅（需理解需求上下文） |
| Workflow 调用 | 并行节点 | ❌（确定性：调用 Workflow 工具） |
| 质量门禁 | Workflow 返回后 | ✅（按清单逐项核对） |
| 状态更新 | 质量门禁通过后 | ❌（确定性：写入 .state.md） |
| 修复循环根因分析 | TE 审计 FAIL | ✅ |
| 经验采集 | SR 驳回、用户纠正、修复≥2轮 | ✅ |

---

## 7. 迁移实施计划

### Phase 0: 前置修复（已完成 ✅）

- [x] role-guard.sh 支持逗号分隔多角色并行（`current_role: SA,TE`）
- [x] 验证 Workflow SubAgent 继承 PreToolUse Hook
- [x] 单角色向后兼容测试通过

### Phase 1: 基础设施（Day 1）

- [ ] 创建 `workflows/` 目录结构
- [ ] 实现 `lib/prompt-assembler.js`
- [ ] 实现 `lib/result-parser.js`
- [ ] 不触碰任何现有文件

### Phase 2: propose 并行迁移（Day 2）

- [ ] 实现 `workflows/propose-parallel.js`
- [ ] 精简 `skills/mh-propose.md`（保留原文件为 `.md.bak` 备份）
- [ ] 端到端验证：standard 模式 propose 阶段

### Phase 3: apply 并行迁移（Day 3）

- [ ] 实现 `workflows/apply-batch-dev.js`
- [ ] 实现 `workflows/apply-batch-test.js`
- [ ] 实现 `workflows/apply-final-audit.js`
- [ ] 精简 `skills/mh-apply-standard.md`
- [ ] 端到端验证：standard 模式 apply 阶段

### Phase 4: 整合验证（Day 4）

- [ ] /mh-run 全流程测试（NEW + standard）
- [ ] /mh-run 全流程测试（CHANGE + standard）
- [ ] 断点恢复测试（各阶段中断重启）
- [ ] 删除 .bak 备份文件
- [ ] 更新 docs/design.md、docs/workflow.md

---

## 8. 风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| Workflow SubAgent 产出物写入路径不正确 | 中 | 质量门禁误判 | PM 在 Workflow 返回后显式检查文件存在性 |
| Prompt 过长导致 SubAgent 质量下降 | 中 | 产出物不完整 | prompt-assembler 控制总长度，超出阈值裁剪上下文 |
| Workflow 超时（复杂 Task） | 低 | 需重试 | .state.md 记录 Workflow 启动时间，超时后重新调用 |
| 精简后 skill 丢失关键指令 | 中 | 流程遗漏 | 保留 .bak 备份，Phase 4 对比验证 |
| role-guard.sh 在 Workflow SubAgent 中不生效 | ~~低~~ **已验证：不存在此风险** | 越权写入 | ✅ 实测确认：Hook 在 Workflow agent() SubAgent 中完全继承生效（2026-06-09 验证） |

---

## 9. 不变量（重构后必须仍成立的断言）

1. `deliverables/{REQ-ID}/` 目录结构与现有完全一致
2. `.state.md` schema 与 `templates/state-template.md` 完全一致
3. Handoff 文件内容格式与 `templates/handoff-template.md` 完全一致
4. `scripts/verify*.sh` 无需任何修改即可通过
5. 所有 SR gates 仍需人工确认后才能推进
6. 修复循环仍限于 5 轮，发散条件不变
7. 经验采集点（CP-1/2/3）仍正常触发

---

## 10. 历史问题兼容性验证

本章逐一验证 CR-001/002/003 中识别的所有历史问题，确认重构后仍被有效防御。

### 10.1 REQ001 暴露的问题

| 问题 | 原防御机制 | 重构后是否仍生效 | 分析 |
|------|-----------|:---:|------|
| SR4 驳回 16 次（代码修复泄漏到归档阶段） | CR-001-H: mh-archive.md 明确 SR4 不做代码修复 + verify-archive.sh 前置校验 | ✅ | mh-archive.md 不变；verify-archive.sh 不变；SR4 gate 仍在 PM 会话层 |
| SA 设计 9 轮返工（结构反复） | CR-002-A: PM 在派发前与用户协商 structure_skeleton | ✅ | 结构协商是人机交互步骤，保留在 PM 会话层；协商结果写入 handoff 传给 Workflow |
| SR2 后 5 轮修复（TE 审计维度不完整） | CR-001-A: TE 在 propose 阶段产出 audit-dimensions.md | ✅ | TE 在 propose-parallel Workflow 中执行，handoff 明确要求产出 audit-dimensions.md |
| dev-test 跳过率 100% | DE 契约（agents/de.md）+ dev-test skill 约束 | ✅ | DE agent 契约不变，通过 prompt-assembler 注入 Workflow SubAgent |
| .venv 归档到 output/ | CR-001-B: .archiveignore + verify-archive.sh ARC-1 | ✅ | 归档阶段不涉及 Workflow，mh-archive.md + verify-archive.sh 完全不变 |
| spec/ 归档不完整 | verify.sh 文件存在性检查 | ✅ | verify.sh 不变 |
| Agent 超时无规则 | mh-apply.md "超时+产出完整=OK" 规则 | ✅ | Workflow 有内置超时；PM 会话层保留产出物完整性检查逻辑 |
| 多 Task 合并 code-report | mh-apply-standard.md "1 Task = 1 report" 规则 | ✅ | 每个 Task 独立 agent() 调用，天然隔离；质量门禁在 PM 层逐 Task 检查 |
| Handoff 完成回报为空 | PM 代填机制 + verify.sh 检测 | ✅ | result-parser.js 解析 SubAgent 输出，status=unknown 时 PM 代填 |
| process.log 只有 2 行 | logging-standard.md + verify.sh 行数检查 | ✅ | 日志写入仍由 PM 会话层执行（非 Workflow 职责），verify.sh 不变 |

### 10.2 REQ002 暴露的问题（CR-003 域）

| 问题域 | 原防御机制 | 重构后是否仍生效 | 分析 |
|--------|-----------|:---:|------|
| **域1: PM 越权修改技术产物** | role-guard.sh PreToolUse Hook | ✅ | Hook 在 .claude/settings.json 中配置，PM 主会话层仍受约束；Workflow SubAgent 也继承 Hook |
| **域2: 质量门禁失败路径缺失** | quality-gate-report-template.md | ✅ | 质量门禁在 PM 会话层执行（Workflow 返回后），模板不变 |
| **域3: DE 写入根目录 output/** | role-guard.sh 限制 DE 写入路径 | ⚠️ 需验证 | Workflow agent() 内 SubAgent 是否继承 Hook 需实测确认（列入 Phase 4 验证项） |
| **域4: 归档路径非隔离** | verify-archive.sh ARC-5 REQ-ID 隔离检查 | ✅ | 归档阶段不涉及 Workflow，脚本不变 |
| **域5: .archiveignore 存在但未使用** | verify-archive.sh ARC-1 FAIL 级别执行 | ✅ | 归档阶段不变 |
| **域6: Token 超支/盲目探索** | handoff-template.md 环境限制 + Token 预算 + 执行前必读 | ✅ | prompt-assembler 组装 handoff 时包含这些字段，SubAgent 收到完整约束 |
| **域7: SR4 审批混淆** | verify-archive.sh ARC-0~6 前置完成 | ✅ | 归档阶段不变 |
| **域8: custom output_type 无验证策略** | verify.sh: output_type=custom + test_strategy 空 → FAIL | ✅ | verify.sh 不变 |
| **域9: CP→EXP 经验不一致** | SR4 人工审阅 | ✅ | 经验采集在 PM 会话层，SR4 gate 不变 |
| **域10: 大 Task 粒度** | handoff Token 预算参考字段 | ✅ | handoff-builder 生成时包含 Token 预算 |
| **域11: 归档路径自适应** | verify-archive.sh ARC-5 结构探测 | ✅ | 归档阶段不变 |

### 10.3 CR-002 Token 优化措施兼容性

| 优化项 | 机制 | 重构后兼容性 | 分析 |
|--------|------|:---:|------|
| CR-002-A: SA 结构预协商 | PM 人机交互 → structure_skeleton 写入 handoff | ✅ | 协商在 PM 会话层，结果通过 args 传入 Workflow |
| CR-002-B: DE 批量合并派发（≤3 Task/handoff） | mh-apply-standard.md 规则 | ⚠️ 需适配 | Workflow 默认 1 Task = 1 agent()；需在 apply-batch-dev.js 中支持合并模式（同模块无共享依赖的 Task 合入一个 agent() 调用） |
| CR-002-C: Apply 集成预检 | mh-apply-standard.md Step 1.5 | ✅ | 集成预检在 PM 会话层执行（Bash 命令），不涉及 Workflow |
| CR-002-D: Handoff 行数上限 ≤150 | verify-qa.sh QA-11 | ✅ | prompt-assembler 生成 handoff 后可检查行数；verify-qa.sh 不变 |
| CR-002-E: Reference 摘要 + 访问级别 | mh-clarify.md + mh-propose.md 白名单标注 | ✅ | 摘要在 clarify 阶段生成（不变），白名单标注写入 handoff 传给 Workflow |
| CR-002-F: TE 审计脚本预检（grep 先行） | mh-apply-standard.md SR2 前 PM grep | ✅ | PM 会话层执行 grep，仅未通过项派发 TE Workflow |

### 10.4 需特别关注的兼容性风险

| 风险项 | 原始问题 | 重构可能引入的退化 | 防护措施 |
|--------|----------|-------------------|----------|
| role-guard.sh 在 Workflow SubAgent 中失效 | 域1/域3: PM 越权、DE 路径越界 | ~~Workflow agent() 可能不继承主会话 Hook~~ | ✅ **已验证消除**（2026-06-09）：Hook 完全继承，越权写入被正确阻止。附带修复：role-guard.sh 支持逗号分隔多角色并行 |
| DE 批量合并派发退化 | CR-002-B 优化 | apply-batch-dev.js 默认 1:1 映射可能丢失合并逻辑 | 在 args 中支持 `mergedTasks` 参数，兼容合并模式 |
| Handoff 完成回报协议 | P0-1: 回报为空 | Workflow SubAgent 输出格式可能与直接 spawn 不同 | result-parser.js 兼容多种输出格式；PM 层保留代填兜底 |
| 修复循环状态连续性 | repair_round 跨 Workflow 调用 | 每次 Workflow 是独立执行，repair 状态需在外部维护 | .state.md 由 PM 层管理（不变），Workflow 不触碰修复状态 |
| 经验采集时机 | CP-1/2/3 实时记录 | Workflow 后台执行期间用户纠正/驳回发生在 PM 层 | CP 触发点全部在 PM 会话层（SR 驳回、用户纠正），不受 Workflow 影响 |

### 10.5 兼容性验证清单（Phase 4 必须全部通过）

```
[x] V-01: role-guard.sh 在 Workflow SubAgent 中阻止越权写入 ✅ (2026-06-09 已验证)
[ ] V-02: SA 产出 .archiveignore + verify-strategy.md（propose-parallel Workflow）
[ ] V-03: TE 产出 audit-dimensions.md（propose-parallel Workflow）
[ ] V-04: DE code-report 每 Task 独立（apply-batch-dev Workflow）
[ ] V-05: DE 写入路径限于 deliverables/{REQ-ID}/output/
[ ] V-06: Handoff 内容 ≤150 行（prompt-assembler 生成）
[ ] V-07: 修复循环 repair_round 跨多次 Workflow 调用正确递增
[ ] V-08: 断点恢复后 Workflow 重跑不产生重复文件/冲突
[ ] V-09: verify.sh + verify-qa.sh + verify-archive.sh 全部 PASS（零修改）
[ ] V-10: SR1/SR2/SR3/SR4 全部正常暂停等待人工确认
[ ] V-11: 经验采集 CP-1（SR驳回）CP-2（用户纠正）CP-3（修复≥2轮）正常触发
[ ] V-12: Token 预算字段在 SubAgent prompt 中可见
[ ] V-13: DE 批量合并派发模式可用（≤3 Task 合入单 agent）
[ ] V-14: 集成预检（Step 1.5）在所有 Batch 完成后正常执行
[ ] V-15: CHANGE 模式增量开发流程正常（DE 白名单包含 output/）
```

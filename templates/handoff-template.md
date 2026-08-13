<!-- 协议规则：
  0. 本文件由 ORCHESTRATOR 独占写入；执行角色的完成回报写入独立文件（见文末「完成回报」节）
  1. 本文件一旦创建不可修改 — 重试时创建新文件（追加轮次后缀 R2, R3...）
  2. 白名单必须逐文件列出，禁止使用通配符（如 *.md）
  3. 执行角色仅可读取白名单中的文件，禁止读取其他任何文件
  4. 任务描述+约束+轮次信息合计不超过 150 行；超出内容写入独立文件并在白名单中引用
  5. R2+ 轮次仅传递本轮增量要求（新增/变更点 + 失败原因 + 修正方向），不重复前轮已明确的上下文
-->
---
handoff_id: "{REQ-ID}-{STEP-ID}-R{N}"
from: ORCHESTRATOR
to: "{THINKER|WORKER|VERIFIER}"
status: pending
track: "{code|ppt}"
thinker_phase: "{needs|design|visual}"
task_type: "{需求分析|架构设计|视觉设计|编码实现|审计验证}"
tech_stack: "{language}/{package_manager}"
created_at: "{YYYY-MM-DDTHH:MM:SSZ}"
completed_at: ""
---

## 任务描述

{一段话描述本次任务的目标和范围}

## 环境限制

<!-- Orchestrator 必填。标注 SubAgent 环境的关键限制，避免 Agent 无效尝试 -->
- Bash 权限: {有 | 无（仅代码实现，验证由 Orchestrator 外部执行）}
- 网络访问: {有 | 无}
- 可用工具: {Read, Write, Edit | 全部}

## 执行前必读文件（按顺序）

<!-- 区别于白名单：白名单是"允许读"，本节是"必须先读且按此顺序"，减少探索 -->
1. {file_path} — {读取目的}
2. {file_path} — {读取目的}

## Token 预算参考

- 预期复杂度: {极简<10k | 小<20k | 中<50k | 大<80k}
- 超出预算行为: 停止执行，在回报中标注 issues="token budget exceeded"

## 产出规格（大型产出或返工时 Orchestrator 填写，简单任务可删除本节）

- depth_level: {checklist | summary | full-architecture | code-level}
- quality_anchor: {标杆文件路径 | N/A}
- structure_skeleton: |
    {预期的文件/章节结构 — Thinker design/visual 任务必填，Orchestrator 须在派发前与用户协商确定}

## 输入文件（白名单）

- {file_path_1}
- {file_path_2}

## 期望输出

<!-- ⚠️ Orchestrator 自检: Worker 任务的输出路径必须以 deliverables/{REQ-ID}/ 开头，且符合 design.md "产出物目录结构" 章节规划的路径，禁止自行决定路径 -->
- `{output_path}`

## 约束

- {constraint_1}
- {constraint_2}

## 参考 Skill

- `skills/{skill-file}.md` Step {N}

## 轮次信息

- 当前轮次: {N}/5
- 上轮失败原因: {摘要或 N/A}
- 失败报告路径: {path 或 N/A}

## 用户反馈原文（R2+ 轮次必填，R1 时删除本节）

<!-- Orchestrator 禁止摘要/裁剪用户反馈，原文粘贴于此。超过 500 行时写入独立文件并在白名单中引用 -->
{用户反馈原文}

## 设计对标清单（Worker 编码任务时 Orchestrator 填写，其他角色删除本节）

<!-- Orchestrator 从设计文档中摘录 Worker 必须实现的关键项，Worker 完成后逐项 ✓ -->

### 必须实现的接口/方法
- [ ] {从设计文档摘录}

### 集成调用链路
- [ ] {A.method() → B.method()}

### 关键约束
- [ ] {从设计文档摘录的常量/配置/安全要求}

## 上下文裁剪指示（Worker 任务白名单文件较大时 Orchestrator 填写，可选）

<!-- Orchestrator 标注白名单文件中执行角色需要精读的段落范围，减少无关上下文 -->
- {file_path}: 精读 `## {section_name}`（其余跳过）
- {file_path}: 仅读取 Task-{N} 相关段落

## 修复上下文（仅修复轮次填写，R1 时删除本节）

- 失败特征: {错误类型 + 关键错误信息}
- 根因假设: {Orchestrator 基于 Verifier 报告的分析}
- 建议修复方向: {具体指导}
- 历史尝试: {前几轮尝试了什么，为什么没成功}

## 完成回报（执行角色必填 — 未填写则任务视为未完成）

<!-- ⚠️ 回报不写在本文件内。本文件是 ORCHESTRATOR 独占（任务描述+白名单+约束+修复上下文），
     执行角色写入一律被 role-guard 拒绝。回报写入下方派生路径的独立文件。 -->

- 回报文件: `deliverables/{REQ-ID}/.engine/reports/{本 handoff 的文件名去掉 .md}.report.md`
- 填写者: 本 handoff `to` 字段声明的角色（THINKER / WORKER / VERIFIER）。SubAgent 失联或驳回轮次时 ORCHESTRATOR 兜底代填
- 回报文件内容（五个字段，均须行首无缩进，门禁按行首锚定读取）:

```
status: {done | failed}
output_files: ["{file_path}"]
read_files: ["{实际读取的文件路径}"]
summary: "{一句话描述完成内容}"
issues: "{错误信息或 N/A}"
```

> 回报文件名由本 handoff 的 basename 机械派生，门禁与守卫据此关联两者，不依赖内容里的自述指针（自述指针可被改写，路径派生不能）。
> 回报格式示例见 `templates/handoff-examples.md`
> Orchestrator 验收时将回报文件的 read_files 与本文件的白名单对比，不匹配则驳回。
> 两侧分处两个文件、两套写权（回报执行角色可写，白名单不可写），故执行角色无法改写被比较的一侧使越权自洽。

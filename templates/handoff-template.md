<!-- 协议规则：
  1. 本文件一旦创建不可修改 — 重试时创建新文件（追加轮次后缀 R2, R3...）
  2. 白名单必须逐文件列出，禁止使用通配符（如 *.md）
  3. 执行角色仅可读取白名单中的文件，禁止读取其他任何文件
-->
---
handoff_id: "{REQ-ID}-{STEP-ID}-R{N}"
from: PM
to: "{BA|SA|DE|TE|UX}"
status: pending
task_type: "{需求分析|架构设计|编码实现|审计验证|测试用例设计|设计}"
output_type: "{output_type}"
tech_stack: "{language}/{package_manager}"
created_at: "{YYYY-MM-DDTHH:MM:SSZ}"
completed_at: ""
---

## 任务描述

{一段话描述本次任务的目标和范围}

## 产出规格（大型产出或返工时 PM 填写，简单任务可删除本节）

- depth_level: {checklist | summary | full-architecture | code-level}
- quality_anchor: {标杆文件路径 | N/A}
- structure_skeleton: |
    {预期的文件/章节结构，可选}

## 输入文件（白名单）

- {file_path_1}
- {file_path_2}

## 期望输出

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

<!-- PM 禁止摘要/裁剪用户反馈，原文粘贴于此。超过 500 行时写入独立文件并在白名单中引用 -->
{用户反馈原文}

## 设计对标清单（DE 编码任务时 PM 填写，其他角色删除本节）

<!-- PM 从设计文档中摘录 DE 必须实现的关键项，DE 完成后逐项 ✓ -->

### 必须实现的接口/方法
- [ ] {从设计文档摘录}

### 集成调用链路
- [ ] {A.method() → B.method()}

### 关键约束
- [ ] {从设计文档摘录的常量/配置/安全要求}

## 修复上下文（仅修复轮次填写，R1 时删除本节）

- 失败特征: {错误类型 + 关键错误信息}
- 根因假设: {PM 基于 TE 报告的分析}
- 建议修复方向: {具体指导}
- 历史尝试: {前几轮尝试了什么，为什么没成功}

## 完成回报（执行角色必填 — 未填写则任务视为未完成）

<!-- ⚠️ SubAgent 必须在结束前填写本节，否则 PM 将驳回 -->
- status: {done | failed}
- output_files: ["{file_path}"]
- read_files: ["{实际读取的文件路径}"]
- summary: "{一句话描述完成内容}"
- issues: "{错误信息或 N/A}"

> 回报格式示例见 `templates/handoff-examples.md`
> PM 验收时将 read_files 与白名单对比，不匹配则驳回。

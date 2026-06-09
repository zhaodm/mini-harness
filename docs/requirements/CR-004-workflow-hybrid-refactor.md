# CR-004: 混合架构重构 — 编排逻辑从 Markdown SOP 迁移至 JS Workflow

> 日期: 2026-06-09
> 状态: 设计中
> 优先级: P1
> 关联: CR-003（框架改进的延续）

---

## 执行摘要

将 mini-harness 的编排调度逻辑从"LLM 解读 Markdown SOP"迁移为"JS Workflow 确定性执行 + PM 会话层人机交互"的混合架构。核心动机：消除编排层对 LLM 指令遵循的依赖，将并行调度、状态推进、模式路由等确定性逻辑交给代码执行。

## 问题陈述

### 当前架构的系统性缺陷

| # | 问题 | 影响 | 根因 |
|---|------|------|------|
| 1 | 并行执行依赖 LLM 理解 | SA∥TE 并行偶尔退化为串行 | PM 需"读懂"markdown 中的并行指令 |
| 2 | PM 每轮加载 400-600 行 skill | Token 消耗高，响应慢 | 编排逻辑与领域知识混合在 markdown 中 |
| 3 | 调度 bug（跳步/漏更新 state） | 流程不确定性 | 自然语言描述的状态机无编译期保证 |
| 4 | 模式路由逻辑散落多文件 | 新增模式需改 5+ 文件 | 路由条件以散文形式存在于各 skill |
| 5 | 修复循环收敛追踪易遗漏 | repair_round 未更新导致无限循环 | "每轮开始时必须更新"是自然语言约束 |

### CR-003 的教训验证

CR-003 已证明：**自然语言约束对 AI Agent 无效，脚本硬约束才是真正的防线。** 本 CR 将这一原则从验证脚本层扩展到编排调度层——编排逻辑本身也应该是代码，而非自然语言。

## 需求定义

### 功能需求

| ID | 需求 | 优先级 |
|----|------|--------|
| F-1 | 将 propose 阶段的 SA∥TE 并行封装为 JS Workflow 脚本 | P0 |
| F-2 | 将 apply 阶段的批量 DE 并行封装为 JS Workflow 脚本 | P0 |
| F-3 | 将 apply 阶段的批量 TE 并行审计封装为 JS Workflow 脚本 | P0 |
| F-4 | 将最终审计封装为 JS Workflow 脚本 | P1 |
| F-5 | 提供 lib/ 工具函数（handoff 生成、state 读写、质量门禁） | P0 |
| F-6 | 精简对应 Markdown skill 文件，调度逻辑改为"调用 Workflow" | P1 |
| F-7 | 保留所有人工审批节点（SR1-4、Batch 确认）在 PM 主会话层 | P0 |

### 非功能需求

| ID | 需求 |
|----|------|
| NF-1 | 兼容现有 deliverables/ 目录结构和 .state.md schema |
| NF-2 | 兼容现有断点恢复机制 |
| NF-3 | Agent 契约文件（agents/*.md）零修改 |
| NF-4 | 硬验证脚本（scripts/verify*.sh）零修改 |
| NF-5 | 渐进式迁移——新旧机制可共存，逐步切换 |

### 约束

- Claude Code Workflow 是后台执行的，不支持中途暂停等待用户输入
- SubAgent 通过 agent() 的 prompt 参数注入角色契约和 handoff 内容
- Workflow 脚本必须是自包含的 JS（export const meta + 执行体）
- role-guard.sh Hook 在 SubAgent 内仍需生效

## 范围

### 包含

- workflows/ 目录及 4 个 Workflow 脚本
- workflows/lib/ 工具函数
- skills/ 中 mh-propose.md、mh-apply-standard.md 的精简重写
- docs/designs/ 下的技术设计文档

### 不包含

- mh-clarify.md 重构（纯人机交互，无并行需求）
- mh-archive.md 重构（顺序执行，无并行需求）
- mh-apply-repair.md 重构（根因分析需 LLM 判断力，不适合代码化）
- Agent 契约、模板、验证脚本的修改
- .state.md schema 变更

## 验收标准

1. standard 模式 /mh-run 全流程可正常执行，propose 阶段 SA∥TE 通过 Workflow 并行
2. apply 阶段批量 DE/TE 通过 Workflow 并行，结果与原流程一致
3. 所有人工审批节点正常暂停等待用户输入
4. 断点恢复（中断后重新 /mh-run）可从 .state.md 正确恢复
5. PM 每轮加载的 skill 行数降低 50% 以上
6. 现有 verify*.sh 脚本全部 PASS

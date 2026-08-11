# Roles

> 本域指南描述角色契约体系的内部机制。修改本域代码前请先阅读。
> 对应源码: `agents/`

## 职责与边界

**做什么：**
- 定义 3 个被派发角色（thinker/worker/verifier）的完整契约：身份、职责、输入、输出、阻塞条件、禁止事项
- 定义 orchestrator 编排器的主会话行为契约（调度循环、质量门禁、人机交互）
- 定义 Thinker 三相位设计（needs/design/visual）的激活条件与产出
- 保证角色隔离原则：写需求的人不审需求，写代码的人不做终验

**不做什么（由其他域负责）：**
- 各阶段具体执行步骤 → 见 [skills.md](skills.md)
- 并行编排逻辑 → 见 [workflow.md](workflow.md)
- 角色写入权限硬拦截 → 见 [guards.md](guards.md)
- handoff 模板格式 → 见 [templates.md](templates.md)

## 内部结构

```
agents/
├── orchestrator.md    主会话编排器（不计被派发角色）
├── thinker.md         需求 + 设计 + 视觉（三相位）
├── worker.md          编码实现
└── verifier.md        独立验证
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| orchestrator | 流程调度 + 质量门禁 + 人机交互 + 经验采集 | `agents/orchestrator.md` |
| thinker | 需求规格 → 技术设计/视觉设计（track 激活相位） | `agents/thinker.md` |
| worker | TDD 编码 + 自测 + 精装交付 | `agents/worker.md` |
| verifier | 独立验证 + 覆盖分析 + 缺陷报告 | `agents/verifier.md` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `agents/orchestrator.md` | 编排器角色契约：调度循环、质量门禁、经验采集 | `skills/mh-codeflow/SKILL.md`、`docs/designs/design.md` §3、`docs/designs/source-of-truth.md` |
| `agents/thinker.md` | Thinker 角色契约：三相位设计、需求规格产出 | `skills/mh-design/SKILL.md`、`skills/mh-slideflow/SKILL.md`、`docs/designs/design.md` §3 |
| `agents/worker.md` | Worker 角色契约：TDD 编码、自测、精装交付 | `skills/mh-build/SKILL.md`、`docs/designs/design.md` §3 |
| `agents/verifier.md` | Verifier 角色契约：独立验证、覆盖分析、缺陷报告 | `skills/mh-verify/SKILL.md`、`skills/mh-self-test/SKILL.md`、`docs/designs/design.md` §3 |

## 约束与陷阱

<!-- 待后续 CR 填充 -->

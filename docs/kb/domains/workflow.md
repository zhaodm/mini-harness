# Workflow

> 本域指南描述 JS 并行编排层的内部机制。修改本域代码前请先阅读。
> 对应源码: `workflows/`

## 职责与边界

**做什么：**
- 实现并行扇出编排（Thinker 相位、批量 Worker、批量 Verifier）
- 确定性执行 Workflow 脚本，替代 Agent 记忆式调度
- 提供 lib/ 工具函数（prompt 组装、结果解析、决策逻辑库）
- 支持 code track 与 ppt track 的步骤编排

**不做什么（由其他域负责）：**
- 角色契约定义 → 见 [roles.md](roles.md)
- 执行步骤 SOP → 见 [skills.md](skills.md)
- 脚本硬校验 → 见 [guards.md](guards.md)
- 外部项目知识库生成（ARC-8）→ 独立模块，不交叉

## 内部结构

```
workflows/
├── thinker-design.js       Thinker 相位执行
├── apply-batch-dev.js       Batch Worker 并行开发
├── apply-batch-test.js      Batch Verifier 并行审计
├── apply-final-audit.js     Verifier 最终审计
└── lib/                     工具函数库
    ├── prompt-assembler.js   Prompt 组装
    ├── result-parser.js      结果解析
    ├── auto-advance.js       自动推进状态机
    ├── calculate-batches.js  批量计算
    ├── code-review-rules.js  Code Review 规则
    ├── decide-repair.js       修复决策
    ├── detect-archive-mode.js 归档模式检测
    ├── detect-scenario.js     场景检测
    ├── knowledge-base.js      项目知识库生成（ARC-8，独立）
    ├── recommend-type-mode.js 类型模式推荐
    ├── regression-suite.js    回归套件
    └── archive-merge.js       归档合并
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| thinker-design | Thinker 相位执行 | `workflows/thinker-design.js` |
| apply-batch-dev | Batch Worker 并行开发 | `workflows/apply-batch-dev.js` |
| apply-batch-test | Batch Verifier 并行审计 | `workflows/apply-batch-test.js` |
| apply-final-audit | Verifier 最终审计 | `workflows/apply-final-audit.js` |
| lib/ | 工具函数库 | `workflows/lib/*.js` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `workflows/thinker-design.js` | Thinker 相位执行编排 | `skills/mh-design/SKILL.md`、`agents/thinker.md` |
| `workflows/apply-batch-dev.js` | Batch Worker 并行开发编排 | `skills/mh-build/SKILL.md`、`agents/worker.md` |
| `workflows/apply-batch-test.js` | Batch Verifier 并行审计编排 | `skills/mh-verify/SKILL.md`、`agents/verifier.md` |
| `workflows/apply-final-audit.js` | Verifier 最终审计编排 | `skills/mh-verify/SKILL.md` |
| `workflows/lib/prompt-assembler.js` | Prompt 组装工具函数 | `workflows/thinker-design.js`、`workflows/apply-*.js` |
| `workflows/lib/result-parser.js` | 结果解析工具函数 | `workflows/apply-*.js` |
| `workflows/lib/auto-advance.js` | 自动推进状态机 | `skills/mh-codeflow/SKILL.md` |
| `workflows/lib/calculate-batches.js` | 批量计算 | `workflows/apply-batch-*.js` |
| `workflows/lib/code-review-rules.js` | Code Review 规则 | `workflows/apply-batch-test.js` |
| `workflows/lib/decide-repair.js` | 修复决策逻辑 | `skills/mh-repair/SKILL.md` |
| `workflows/lib/detect-archive-mode.js` | 归档模式检测 | `skills/mh-deliver/SKILL.md` |
| `workflows/lib/detect-scenario.js` | 场景检测 | `workflows/lib/auto-advance.js` |
| `workflows/lib/knowledge-base.js` | 项目知识库生成（ARC-8，独立） | `skills/mh-deliver/SKILL.md` |
| `workflows/lib/recommend-type-mode.js` | 类型模式推荐 | `workflows/thinker-design.js` |
| `workflows/lib/regression-suite.js` | 回归套件 | `workflows/apply-batch-test.js` |
| `workflows/lib/archive-merge.js` | 归档合并 | `skills/mh-deliver/SKILL.md` |

## 约束与陷阱

<!-- 待后续 CR 填充 -->

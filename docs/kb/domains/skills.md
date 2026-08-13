# Skills

> 本域指南描述执行规程体系的内部机制。修改本域代码前请先阅读。
> 对应源码: `skills/`

## 职责与边界

**做什么：**
- 定义各阶段的固定执行 SOP（标准操作规程），不依赖记忆
- 实现 track 感知裁剪：code track 与 ppt track 各自独立流水线步骤
- 承载角色的工作流程步骤（Developer/Tester/Auditor 的 SOP）
- 定义 SR Gate 通过标准

**不做什么（由其他域负责）：**
- 角色身份与禁止事项定义 → 见 [roles.md](roles.md)
- 并行扇出编排逻辑 → 见 [workflow.md](workflow.md)
- 脚本硬校验实现 → 见 [guards.md](guards.md)
- 产出格式模板 → 见 [templates.md](templates.md)

## 内部结构

```
skills/
├── mh-codeflow/       code track 全流程编排 SOP
├── mh-slideflow/      ppt track 全流程 SOP
├── mh-intake/         需求初始化与澄清 SOP
├── mh-design/         Thinker 设计相位 SOP
├── mh-build/          Worker 开发 SOP
├── mh-deliver/        归档 + 经验沉淀 SOP
├── mh-repair/         修复收敛 SOP
├── mh-self-test/      Verifier 自测 SOP
└── mh-verify/         Verifier 验证 SOP
```

### mh-dev 内部 skills

```
tools/mh-dev/skills/
├── mh-dev/          Planner 职责 SOP
├── mh-dev-develop/  Developer 工作流程 SOP
├── mh-dev-test/     Tester 工作流程 SOP
└── mh-dev-audit/    Auditor 工作流程 SOP
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| mh-codeflow | code track 全流程自动推进 SOP | `skills/mh-codeflow/SKILL.md` |
| mh-slideflow | ppt track 全流程 SOP | `skills/mh-slideflow/SKILL.md` |
| mh-intake | 需求初始化与澄清 SOP | `skills/mh-intake/SKILL.md` |
| mh-design | Thinker 设计相位 SOP | `skills/mh-design/SKILL.md` |
| mh-build | Worker 开发 SOP | `skills/mh-build/SKILL.md` |
| mh-deliver | 归档 + 经验沉淀 SOP | `skills/mh-deliver/SKILL.md` |
| mh-repair | 修复收敛 SOP | `skills/mh-repair/SKILL.md` |
| mh-self-test | Verifier 自测 SOP | `skills/mh-self-test/SKILL.md` |
| mh-verify | Verifier 验证 SOP | `skills/mh-verify/SKILL.md` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `skills/mh-codeflow/SKILL.md` | code track 全流程编排、调度协议、质量门禁 | `agents/orchestrator.md`、`docs/designs/design.md` §4、`docs/designs/source-of-truth.md` |
| `skills/mh-slideflow/SKILL.md` | ppt track 全流程骨架 + 按需加载索引；视觉叙事原则（人类判断项）。硬约束数值下沉至 ppt-quality-rules.md，入口不复述 | `docs/designs/design.md` §6、`templates/ppt-quality-rules.md`、`templates/ppt-templates/registry.json` |
| `skills/mh-intake/SKILL.md` | 需求初始化与澄清 | `agents/thinker.md` |
| `skills/mh-design/SKILL.md` | Thinker 设计相位、SR1 通过标准 | `agents/thinker.md`、`docs/designs/design.md` §4 |
| `skills/mh-build/SKILL.md` | Worker 开发 SOP、SR3 通过标准 | `agents/worker.md`、`docs/designs/design.md` §4 |
| `skills/mh-deliver/SKILL.md` | 归档 + 经验沉淀、ARC-5/6/7/8 | `docs/designs/design.md` §8、`templates/metrics-template.md` |
| `skills/mh-repair/SKILL.md` | 修复收敛、repair_history | `docs/designs/design.md` §6、`templates/state-template.md` |
| `skills/mh-self-test/SKILL.md` | Verifier 自测 SOP | `agents/verifier.md` |
| `skills/mh-verify/SKILL.md` | Verifier 验证 SOP | `agents/verifier.md` |
| `tools/mh-dev/skills/mh-dev/SKILL.md` | mh-dev Planner 职责 SOP | `tools/mh-dev/CLAUDE.md`、`docs/designs/source-of-truth.md` |
| `tools/mh-dev/skills/mh-dev-develop/SKILL.md` | Developer 工作流程 SOP | `tools/mh-dev/agents/developer.md` |
| `tools/mh-dev/skills/mh-dev-test/SKILL.md` | Tester 工作流程 SOP | `tools/mh-dev/agents/tester.md` |
| `tools/mh-dev/skills/mh-dev-audit/SKILL.md` | Auditor 工作流程 SOP | `tools/mh-dev/agents/auditor.md` |

## 约束与陷阱

<!-- 待后续 CR 填充 -->

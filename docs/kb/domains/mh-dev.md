# mh-dev

> 本域指南描述框架自开发工具的内部机制。修改本域代码前请先阅读。
> 对应源码: `tools/mh-dev/`

## 职责与边界

**做什么：**
- 实现 Mini-Harness 框架自身的开发、治理、验证与候选发布流程
- 提供三档轨道判定（fast/light/formal），根据改动复杂度选择流程
- 实现状态机管理（intake → propose → develop → verify → done）
- 提供开发者变更快照、机械预检、独立 Tester/Auditor 结论
- 实现开发-测试-审计循环（最多 max_rounds 轮 repair）

**不做什么（由其他域负责）：**
- 外部项目交付流程 → 见 [workflow.md](workflow.md)
- 角色契约定义 → 见 [roles.md](roles.md)
- 脚本硬校验 → 见 [guards.md](guards.md)
- 产出格式模板 → 见 [templates.md](templates.md)

## 内部结构

```
tools/mh-dev/
├── CLAUDE.md                Planner 职责定义
├── README.md                工具说明
├── start.sh                 启动入口
├── agents/                  角色定义
│   ├── developer.md
│   ├── tester.md
│   └── auditor.md
├── scripts/                 工具脚本
│   ├── reset-session.sh
│   ├── scope-scan.sh
│   ├── capture-snapshot.sh
│   ├── validate-changes.sh
│   ├── validate-dev-completion.sh
│   ├── check-transition.sh
│   ├── transition-state.sh
│   ├── precondition-check.sh
│   ├── validate-outputs.sh
│   ├── audit-preflight.sh
│   └── verify.sh
├── skills/                  工作流程 SOP
│   ├── mh-dev/SKILL.md
│   ├── mh-dev-develop/SKILL.md
│   ├── mh-dev-test/SKILL.md
│   └── mh-dev-audit/SKILL.md
├── templates/               工具模板
│   ├── state.json.template
│   ├── dispatch-prompts.md
│   ├── dev-report-template.md
│   ├── test-report-template.md
│   ├── audit-report.md
│   ├── requirement.md
│   ├── acceptance-criteria.json
│   ├── acceptance-criteria.md
│   ├── semantic-verdict.json
│   ├── semantic-verdict.md
│   ├── auditor-methodology.md
│   ├── tester-methodology.md
│   └── developer-workflow.md
└── tests/                   工具测试
    └── *.sh
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| CLAUDE.md | Planner 职责：需求澄清、设计审批、调度循环 | `tools/mh-dev/CLAUDE.md` |
| agents | Developer/Tester/Auditor 角色协议 | `tools/mh-dev/agents/*.md` |
| scripts | 状态机、快照、校验、发布脚本 | `tools/mh-dev/scripts/*.sh` |
| skills | 各角色工作流程 SOP | `tools/mh-dev/skills/mh-dev*/SKILL.md` |
| templates | 工具内模板 | `tools/mh-dev/templates/*` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `tools/mh-dev/CLAUDE.md` | Planner 职责定义 | `README.md`、`docs/designs/source-of-truth.md` |
| `tools/mh-dev/start.sh` | mh-dev 启动入口 | `.claude/commands/mh-dev.md` |
| `tools/mh-dev/agents/developer.md` | Developer 角色协议 | `tools/mh-dev/skills/mh-dev-develop/SKILL.md` |
| `tools/mh-dev/agents/tester.md` | Tester 角色协议 | `tools/mh-dev/skills/mh-dev-test/SKILL.md` |
| `tools/mh-dev/agents/auditor.md` | Auditor 角色协议 | `tools/mh-dev/skills/mh-dev-audit/SKILL.md` |
| `tools/mh-dev/scripts/reset-session.sh` | 开局清理和 state 初始化 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/scope-scan.sh` | 影响范围搜索 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/capture-snapshot.sh` | 角色快照采集 | `tools/mh-dev/agents/developer.md`、`tools/mh-dev/agents/tester.md` |
| `tools/mh-dev/scripts/validate-changes.sh` | 变更归属校验 | `tools/mh-dev/agents/developer.md`、`tools/mh-dev/agents/tester.md` |
| `tools/mh-dev/scripts/validate-dev-completion.sh` | 开发后质量门禁 | `tools/mh-dev/agents/developer.md` |
| `tools/mh-dev/scripts/check-transition.sh` | 只读状态转换谓词 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/transition-state.sh` | 原子状态写入 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/precondition-check.sh` | 开发前置检查 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/validate-outputs.sh` | 阶段输出校验 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/audit-preflight.sh` | 机械预检 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/scripts/verify.sh` | 工具内总门禁 | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/skills/mh-dev/SKILL.md` | Planner 职责 SOP | `tools/mh-dev/CLAUDE.md` |
| `tools/mh-dev/skills/mh-dev-develop/SKILL.md` | Developer 工作流程 SOP | `tools/mh-dev/agents/developer.md` |
| `tools/mh-dev/skills/mh-dev-test/SKILL.md` | Tester 工作流程 SOP | `tools/mh-dev/agents/tester.md` |
| `tools/mh-dev/skills/mh-dev-audit/SKILL.md` | Auditor 工作流程 SOP | `tools/mh-dev/agents/auditor.md` |
| `tools/mh-dev/templates/state.json.template` | 状态 schema 模板 | `tools/mh-dev/scripts/check-transition.sh` |
| `tools/mh-dev/templates/dispatch-prompts.md` | 调度 prompt 模板 | `tools/mh-dev/CLAUDE.md` |

## 约束与陷阱

<!-- 待后续 CR 填充 -->

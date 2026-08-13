# Templates

> 本域指南描述模板体系的内部机制。修改本域代码前请先阅读。
> 对应源码: `templates/`

## 职责与边界

**做什么：**
- 定义各产出物的标准格式模板（handoff、state、日志、指标、经验沉淀）
- 定义 PPT 设计系统模板（ppt-base.css、ppt-light.css、ppt-base.html 单文件骨架、版式登记表、布局模板）
- 定义知识库模板（system-map、domain、recipe、kb-verify）
- 定义金标准产出示例和产出结构参考

**不做什么（由其他域负责）：**
- 何时使用模板 → 见 [skills.md](skills.md)
- 模板内容校验 → 见 [guards.md](guards.md)（verify-qa.sh）
- 角色契约 → 见 [roles.md](roles.md)
- 框架自开发模板 → 见 [mh-dev.md](mh-dev.md)

## 内部结构

```
templates/
├── handoff-template.md          任务派发格式
├── state-template.md            状态 schema
├── state-pointer-template.md    全局指针模板
├── logging-standard.md          日志格式规范
├── metrics-template.md          执行指标模板
├── lessons-template.md          经验沉淀模板
├── orchestrator-quality-gate.md 质量门禁清单
├── needs-spec-template.md       需求规格模板
├── design-spec-template.md       设计规格模板
├── ppt-slide-spec-template.md   PPT 幻灯片规格模板
├── ppt-quality-rules.md         PPT 硬约束数值权威源
├── ppt-base.css                  PPT 设计系统（低密度 speaker 档）
├── ppt-base.html                 PPT 单文件骨架（舞台缩放+导航+演讲者模式）
├── ppt-light.css                 PPT 浅色主题（高密度 reading 档）
├── frontend-design-skill.md      前端设计指南
├── code-report-template.md       代码报告模板
├── test-report-template.md       测试报告模板
├── quality-gate-report-template.md 质量门禁报告模板
├── regression-suite-template.md   回归套件模板
├── output-structure.md           产出结构参考
├── examples/                     金标准产出示例
│   ├── code-report-example.md
│   ├── design-example.md
│   ├── repair-context-example.md
│   ├── requirement-spec-example.md
│   └── test-report-example.md
├── output-guides/               产出结构参考
│   ├── backend-api.md
│   ├── cli-tool.md
│   └── web-app.md
├── ppt-templates/
│   ├── registry.json             PPT 版式登记（ID/类型/密度归属）
│   └── layouts/                  PPT 布局模板
│       ├── L01-cover-summary.html
│       ├── L02-executive-summary.html
│       └── ... (共 17 个布局，L 系列低密度 / W 系列高密度)
└── kb/                            知识库模板
    ├── system-map-template.md
    ├── domain-template.md
    ├── recipe-template.md
    └── kb-verify-template.sh
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| 流程模板 | handoff、state、pointer、logging | `templates/handoff-template.md` 等 |
| 质量模板 | 指标、经验、门禁清单 | `templates/metrics-template.md` 等 |
| 需求/设计模板 | 需求规格、设计规格 | `templates/needs-spec-template.md` 等 |
| PPT 模板 | 设计系统、单文件骨架、版式登记、布局 | `templates/ppt-*.css`、`templates/ppt-base.html`、`templates/ppt-templates/registry.json`、`templates/ppt-templates/layouts/` |
| 报告模板 | 代码报告、测试报告 | `templates/code-report-template.md` 等 |
| 示例 | 金标准产出示例 | `templates/examples/*.md` |
| 产出参考 | 结构参考指南 | `templates/output-guides/*.md` |
| KB 模板 | 知识库生成模板 | `templates/kb/*` |

## 核心数据结构

<!-- 待后续 CR 填充 -->

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `templates/handoff-template.md` | 任务派发格式 | `agents/orchestrator.md`、`docs/designs/design.md` §5.3 |
| `templates/state-template.md` | 状态 schema | `docs/designs/design.md` §4.4、`skills/mh-repair/SKILL.md` |
| `templates/state-pointer-template.md` | 全局指针模板 | `skills/mh-intake/SKILL.md` |
| `templates/logging-standard.md` | 日志格式规范 | `agents/*.md` |
| `templates/metrics-template.md` | 执行指标模板 | `skills/mh-deliver/SKILL.md` ARC-5 |
| `templates/lessons-template.md` | 经验沉淀模板 | `skills/mh-deliver/SKILL.md` ARC-6 |
| `templates/orchestrator-quality-gate.md` | 质量门禁清单 | `skills/mh-codeflow/SKILL.md` |
| `templates/needs-spec-template.md` | 需求规格模板 | `skills/mh-intake/SKILL.md` |
| `templates/design-spec-template.md` | 设计规格模板 | `skills/mh-design/SKILL.md` |
| `templates/ppt-slide-spec-template.md` | PPT 幻灯片规格模板 | `skills/mh-slideflow/SKILL.md` |
| `templates/ppt-quality-rules.md` | PPT 硬约束数值权威源（字号分档/几何阈值/豁免/布局规则） | `skills/mh-slideflow/SKILL.md`、`scripts/verify-ppt.sh` |
| `templates/ppt-base.css` | PPT 设计系统（低密度 speaker 档字阶） | `skills/mh-slideflow/SKILL.md` |
| `templates/ppt-base.html` | PPT 单文件骨架（舞台缩放+导航+演讲者模式） | `skills/mh-build/SKILL.md`、`skills/mh-slideflow/SKILL.md` |
| `templates/ppt-light.css` | PPT 浅色主题（高密度 reading 档字阶） | `skills/mh-slideflow/SKILL.md` |
| `templates/ppt-templates/registry.json` | PPT 版式登记（ID/类型/密度归属/图形 class） | `scripts/verify-ppt.sh`、`skills/mh-slideflow/SKILL.md` |
| `templates/frontend-design-skill.md` | 前端设计指南 | `skills/mh-slideflow/SKILL.md` |
| `templates/code-report-template.md` | 代码报告模板 | `skills/mh-build/SKILL.md` |
| `templates/test-report-template.md` | 测试报告模板 | `skills/mh-verify/SKILL.md` |
| `templates/quality-gate-report-template.md` | 质量门禁报告模板 | `skills/mh-codeflow/SKILL.md` |
| `templates/regression-suite-template.md` | 回归套件模板 | `skills/mh-verify/SKILL.md` |
| `templates/output-structure.md` | 产出结构参考 | `skills/mh-build/SKILL.md` |
| `templates/examples/*.md` | 金标准产出示例（5 份） | `agents/*.md` |
| `templates/output-guides/*.md` | 产出结构参考（3 份） | `skills/mh-build/SKILL.md` |
| `templates/ppt-templates/layouts/*.html` | PPT 布局模板（17 份） | `skills/mh-slideflow/SKILL.md` |
| `templates/kb/system-map-template.md` | 知识库 system-map 模板 | `skills/mh-deliver/SKILL.md` ARC-8 |
| `templates/kb/domain-template.md` | 知识库域指南模板 | `skills/mh-deliver/SKILL.md` ARC-8 |
| `templates/kb/recipe-template.md` | 知识库食谱模板 | `skills/mh-deliver/SKILL.md` ARC-8 |
| `templates/kb/kb-verify-template.sh` | 知识库校验脚本模板 | `skills/mh-deliver/SKILL.md` ARC-8 |

## 约束与陷阱

<!-- 待后续 CR 填充 -->

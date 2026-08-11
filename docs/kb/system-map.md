# Mini-Harness — 系统全景

> 供 AI 和贡献者快速定位任务涉及的模块并跳转到域指南。
> 生成自: CR-011 | 技术栈: Shell + JS Workflow + Markdown 契约

## 项目定位

Mini-Harness 是 AI Agent 驱动的研发流程框架，实现从需求到高质量交付的自动化生产。三个 AI Agent 角色（Thinker/Worker/Verifier）+ 一个编排器协作，四层递进防线保障质量。核心价值：脚本硬约束优先于自然语言软约束，角色隔离保证上下文纯净。

## 核心概念速览

### 六域

| 域 | 一句话 |
|----|--------|
| Roles | 3 被派发角色 + orchestrator 编排器，角色契约结构 |
| Skills | 各阶段执行 SOP，track 感知裁剪 |
| Workflow | JS 并行编排层，确定性扇出 + 决策逻辑库 |
| Guards | 硬校验体系 + role-guard Hook + 三层校验 |
| Templates | handoff/state/ppt/examples/output-guides/kb 模板 |
| mh-dev | 框架自开发工具，轨道 + 状态机 + 快照 + 验证 |

### 四层递进防线

1. **Rules** — 行为约束（CLAUDE.md，精简纪律）
2. **Skills** — 标准操作规程（固定步骤 SOP）
3. **Agents + Workflow** — 角色制衡 + 并行编排
4. **Scripts + 人工** — 硬校验（退出码为唯一判据）

### 关键术语

- **track**: 交付类型（code/ppt），clarify 阶段确定后只读
- **SR Gate**: 审批门禁节点（SR1 设计审批、SR3 交付审批）
- **handoff**: 角色间结构化信息传递文件
- **verify\*.sh**: 硬校验脚本，退出码驱动
- **/mh-dev**: 框架自身开发入口，独立轨道（fast/light/formal）

## 数据流总览

### 主线交付流程

```
clarify → propose → apply → archive → DONE
   ↑         ↑         ↑         ↑
 RESUME    SR1驳回   SR2/3驳回  SR4驳回
```

### mh-dev 流程

```
intake → propose → develop → verify → done
                       │          │
                       └──────────┴── FAIL/BLOCKED → repair → develop
```

### 状态机

- 外部项目: `init → propose → apply → archive → DONE`
- 框架自身: `intake → propose → develop → verify → done | blocked`

## 六域速查表

| 域 | 职责 | 核心文件 | 域指南 |
|----|------|---------|--------|
| Roles | 3 被派发角色(thinker/worker/verifier)契约 + orchestrator 编排器 | `agents/*.md` | → [domains/roles.md](domains/roles.md) |
| Skills | 各阶段执行 SOP，track 感知裁剪 | `skills/mh-*/SKILL.md` | → [domains/skills.md](domains/skills.md) |
| Workflow | JS 并行编排层，确定性扇出 + 决策逻辑库 | `workflows/*.js` | → [domains/workflow.md](domains/workflow.md) |
| Guards | 硬校验体系(verify\*.sh) + role-guard Hook + 三层校验 | `scripts/*.sh` | → [domains/guards.md](domains/guards.md) |
| Templates | handoff/state/ppt/examples/output-guides/kb 模板 | `templates/**` | → [domains/templates.md](domains/templates.md) |
| mh-dev | 框架自开发工具，轨道 + 状态机 + 快照 + 验证 | `tools/mh-dev/**` | → [domains/mh-dev.md](domains/mh-dev.md) |

## 跨域约束铁律

- **脚本硬约束优先于自然语言软约束** — 以脚本退出码为准，Agent 自述不作为通过依据
- **角色隔离** — Thinker 写需求，Worker 写代码，Verifier 做终验，职责不交叉
- **SR 门不可自主跨越** — 审批节点必须人工通过
- **track 只读** — clarify 阶段确定后不可切换
- **契约即文档** — 每个角色的定义文件即完整规范
- **模板即标准** — 交付格式由模板定义，不依赖记忆

## 扩展场景导航

| 常见任务 | 食谱 |
|---------|------|
| 添加新 Skill | → [recipes/add-skill.md](recipes/add-skill.md) |

<!-- 后续 CR 填充更多食谱 -->

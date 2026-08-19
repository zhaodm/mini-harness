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

## 宿主原生能力 ↔ 框架自建机制对应表（CR-020 R7）

本表用于复查「某机制是否已被原生化」。**框架早期自建的一些机制，宿主后来提供了原生强制点；
继续用软性替代承载即是自愿放弃强制力。** 新增机制前先查本表：宿主是否已有原生形态。

| 宿主原生能力 | 框架曾用的替代 | 现状 |
|-------------|--------------|------|
| subagent `tools:` frontmatter（工具粒度强制） | prompt 文本注入角色契约，靠角色自觉 | **已归位**（CR-020 R1，repair 1 补齐接入）：`agents/{thinker,worker,verifier}.md` 声明最小工具集，`.claude/agents/` 以 symlink 同源进入宿主项目级发现路径，四个 workflow 的 `agent()` 传 `agentType` 按角色名派发。**声明 + 发现面 + 派发链三者齐备才生效**——缺任一条宿主即套用内置 `workflow-subagent`（`tools: ["*"]`），声明退化为死声明 |
| 插件 `agents/` + `skills/` 仓库根布局 | command 正文的文本加载指令 | **布局合规，触发语义未生效**（CR-020 R3/R6）：本仓布局本已合规，加清单即插件根，**未迁移任何目录**。但 skill 的 `description` 触发语义须本仓**作为插件被安装**（或位于 `.claude/skills/`）才进入宿主发现面；当前九个 `mh-*` skill 仍由 command 正文的文本加载指令显式引用——该路径在仓库内解析、可正常工作，故不同于 `tools:` 那种「声明存在却无人读取」的形态 |
| 9 个 hook 事件 | 仅 `PreToolUse` + 角色自觉调用 `verify*.sh` | **部分归位**（CR-020 R4）：新增 `SessionStart` sensor；`verify*.sh` 因阶段性约束有意不上事件；**Bash 命令形态仍无强制点**——宿主提供 `permissions` 与 hook matcher 两条路线，本 CR 评估后未采用，理由见 [guards.md](domains/guards.md) 残留缺口登记 |
| `.claude-plugin/plugin.json` 可分发形态 | clone 整仓 | **已归位**（CR-020 R6）：两形态共存，`tools/mh-dev/` 不进入插件组件面，自开发流程不受影响 |

**已归位不等于全覆盖。** 工具白名单只表达工具粒度，路径粒度仍由 `role-guard.sh` 承担；
二者串联而非并联，分工的单一权威记录在 [guards.md](domains/guards.md)。

**「布局合规」不等于「机制生效」。** CR-020 round 0 曾把 `agents/` 已在仓库根这一布局事实
当成 `tools:` 已生效，实际上派发侧未传 `agentType`、发现侧不在 `.claude/agents/`，声明无任何
机制读取——与本表要消除的「软性替代冒充强制点」同形态。**判据取可观测行为**（如实测
Thinker 侧 Bash 不可用），不取声明是否写下；机械守护见 `scripts/check-harness.sh` 的同源与
派发链检查、`tests/test-session-context.sh` 的声称↔机制一致性断言。

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

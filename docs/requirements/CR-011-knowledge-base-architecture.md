---
id: CR-011
title: 框架知识库体系架构 + docs 目录重构
status: draft
design_doc: docs/designs/CR-011-knowledge-base-architecture-design.md
created: 2026-08-11
---

# CR-011: 框架知识库体系架构 + docs 目录重构

> 归档路径: docs/requirements/CR-011-knowledge-base-architecture.md
> 运行态精简: tools/mh-dev/.mh-dev/requirement.md（基于本单精简为 Developer 可执行指令）

## 背景

mini-harness 当前缺一套描述框架自身的知识基础设施。现有 `docs/` 平铺：`design.md`（架构地图）+ `workflow.md`（流程总览）+ `source-of-truth.md`（权威源映射）+ `requirements/` + `designs/` + `audits/` + `retrospectives/`，没有目录导航 README，也没有按模块边界分域的结构化知识。

两个痛点：

1. **快速了解全项目难**——新会话/新贡献者要读散落的 `design.md`/`source-of-truth.md`/`README.md`，缺少单一入口全景图。
2. **定位变动影响范围难**——改一个 skill 文件不知道会牵连哪些脚本/workflow/template；改一个 workflow 脚本不知道哪些 skill 引用它。没有"文件清单与影响范围"矩阵。

参考 psdt-agent `9.knowledge-base-design.md` 的设计思想（Layer 0 全景入口 → Layer 1 域指南 → Layer 2 操作食谱，三重维护保障），但 mini-harness 模块边界不同（无独立 Engine/Schema 代码包，角色精简为 3+1），域划分须重新适配。

**关键区分：** 本次设计的是**框架自描述知识库**（`docs/kb/`），描述 mini-harness 框架自身模块，供贡献者/AI 理解框架。它与 `/mh-run` 的 ARC-8（`workflows/lib/knowledge-base.js` 为外部项目生成 `deliverables/{REQ-ID}/docs/kb/`）是两个不同目的，不共享代码路径。

## 需求

### R1 — 知识库三层分层架构

在仓库根 `docs/kb/` 下建立三层分层知识库：

- **Layer 0** `system-map.md`：全景入口（≤150 行），AI/人读后能判断任务涉及哪个模块，直接跳转 Layer 1。含项目定位、核心概念速览、数据流总览、模块速查表（每模块一句话职责+核心文件+→Layer 1 链接）、跨模块约束、扩展场景导航。
- **Layer 1** `domains/`：6 份域指南（每份 ≤400 行），每份含统一骨架——职责边界 → 内部结构 → 核心数据结构 → 关键流程 → 对外接口 → **文件清单与影响范围** → 约束与陷阱。
- **Layer 2** `recipes/`：操作食谱（每份 ≤80 行），含场景描述、涉及文件、前置条件、操作步骤、验证命令。

6 域划分（适配 mini-harness 模块边界）：

| 域 | 覆盖范围 | 核心源码 |
|----|----------|---------|
| Roles | `agents/`（orchestrator + thinker/worker/verifier 三被派发角色，角色契约结构） | `agents/*.md` |
| Skills | `skills/`（9 个 SKILL，阶段 SOP，track 感知裁剪，按需加载子文件） | `skills/mh-*/SKILL.md` |
| Workflow | `workflows/`（JS 并行编排层，5 主脚本 + lib/ 工具函数，决策逻辑库） | `workflows/*.js` |
| Guards | `scripts/`（verify*.sh 硬校验体系，role-guard.sh Hook，三层校验） | `scripts/*.sh` |
| Templates | `templates/`（handoff/state/ppt/examples/output-guides/kb 模板体系） | `templates/**` |
| mh-dev | `tools/mh-dev/`（自开发工具，fast/light/formal 轨道，状态机+快照+验证） | `tools/mh-dev/**` |

### R2 — docs 目录重构

按团队职责域重组 `docs/` 目录，新增 `docs/README.md` 目录导航。目标结构：

```
docs/
├── README.md               目录导航（新增）
├── kb/                     框架知识库（本次新建，R1）
│   ├── system-map.md
│   ├── domains/  (6 份)
│   ├── recipes/  (骨架)
│   └── kb-verify.sh
├── designs/                设计文档归集（重组）
│   ├── design.md           架构地图（从 docs/ 根迁入）
│   ├── workflow.md         流程总览（从 docs/ 根迁入）
│   ├── source-of-truth.md  权威源映射（从 docs/ 根迁入，新增 kb 路径映射）
│   ├── modules/            子模块设计文档（新建目录，本次留空）
│   └── cr-designs/         CR 设计文档（现有 5 份 CR-*-design.md 迁入）
├── requirements/           CR 需求单（保留）
├── audits/                 审计报告（保留）
└── retrospectives/         复盘报告（保留）
```

三个根级设计文档（`design.md`/`workflow.md`/`source-of-truth.md`）SHALL 从 `docs/` 根迁入 `docs/designs/`；现有 5 份 `docs/designs/CR-*-design.md` SHALL 迁入 `docs/designs/cr-designs/`；新建 `docs/designs/modules/` 目录（本次留空，后续子模块设计文档填入）。

所有引用这三个文档路径的文件 SHALL 同步更新：`README.md`、`scripts/check-harness.sh`、`tools/mh-dev/scripts/audit-preflight.sh`、`tools/mh-dev/scripts/validate-changes.sh`、`tools/mh-dev/skills/mh-dev-develop/SKILL.md`、`tools/mh-dev/CLAUDE.md`、以及三个文档内部的相互引用（`design.md` 引用 `source-of-truth.md`、`source-of-truth.md` 引用 `design.md`）。

`design.md` SHALL 在开头加注指向知识库域指南；`source-of-truth.md` SHALL 新增知识库路径映射条目。

### R3 — kb-verify.sh 校验脚本

从 `templates/kb/kb-verify-template.sh` 派生 `docs/kb/kb-verify.sh`，校验框架知识库自身的新鲜度与覆盖：结构完整性（system-map + domains 存在）、行数约束（Layer 0 ≤150、Layer 1 ≤400、Layer 2 ≤80）、路径有效性、域指南新鲜度（源码比域指南新则 WARN）。

### R4 — 骨架交付范围

本次交付**架构+骨架**，不写满域指南内容：

- `docs/kb/system-map.md` **写满内容**（R1 全部章节）
- 6 份 `docs/kb/domains/*.md` **创建骨架**（按 `templates/kb/domain-template.md` 结构，填充各域的真实职责/边界/文件清单，但关键流程/对外接口留占位待后续 CR 填充）
- `docs/kb/recipes/` 创建目录 + 1 份示范食谱骨架
- `docs/kb/kb-verify.sh` 从模板派生并适配 6 域路径映射
- `docs/README.md` 新增
- 三个根级设计文档迁入 `docs/designs/` + 现有 CR 设计文档迁入 `docs/designs/cr-designs/` + 新建 `docs/designs/modules/`
- 所有路径引用同步更新（README.md、check-harness.sh、audit-preflight.sh、validate-changes.sh、mh-dev-develop/SKILL.md、tools/mh-dev/CLAUDE.md、三个文档内部互引）

## 非目标

- **不写满 6 域指南全部内容**——关键流程、对外接口的详细描述留后续 CR 逐域填充
- **不修改 `workflows/lib/knowledge-base.js`**——它服务于 ARC-8 外部项目知识库生成，本次不改
- **不修改 `scripts/verify-archive.sh`**——它校验 `deliverables/{REQ-ID}/docs/kb/`，本次框架知识库在 `docs/kb/`，不交叉
- **不把 kb-verify 集成进 mh-dev verify.sh**——框架知识库维护是手动行为，本次只交付脚本不强制门禁
- **不新增 CLAUDE.md 知识库协议段落**——框架知识库协议后续 CR 再定
- **不填充 `docs/designs/modules/`**——本次只建目录，子模块设计文档后续 CR 填入

## 影响范围

scope-scan 结果（196 处匹配）确认本次影响面集中在：

| 文件/目录 | 操作 | 说明 |
|----------|------|------|
| `docs/kb/` | 新建目录树 | system-map + domains/(6) + recipes/(1) + kb-verify.sh |
| `docs/README.md` | 新建 | 目录导航 |
| `docs/designs/design.md` | 迁入+加注 | 从 docs/ 根迁入，开头指向知识库域指南 |
| `docs/designs/workflow.md` | 迁入 | 从 docs/ 根迁入 |
| `docs/designs/source-of-truth.md` | 迁入+新增映射 | 从 docs/ 根迁入，新增 kb 路径映射条目 |
| `docs/designs/cr-designs/` | 迁入 | 现有 5 份 CR-*-design.md 迁入此子目录 |
| `docs/designs/modules/` | 新建目录 | 留空，后续子模块设计文档填入 |
| `README.md` | 修改 | 4 处路径引用更新 |
| `scripts/check-harness.sh` | 修改 | 目录检查新增 designs/modules + cr-designs |
| `tools/mh-dev/scripts/audit-preflight.sh` | 修改 | 2 处 grep 路径更新 |
| `tools/mh-dev/scripts/validate-changes.sh` | 修改 | doc_sync 映射路径更新 |
| `tools/mh-dev/skills/mh-dev-develop/SKILL.md` | 修改 | 1 处路径引用更新 |
| `tools/mh-dev/CLAUDE.md` | 修改 | designs 路径引用更新（cr-designs 子目录） |
| `templates/kb/*` | 不动 | 已有模板，本次消费方在 docs/kb/ |

**不受影响（显式排除）：** `workflows/lib/knowledge-base.js`、`scripts/verify-archive.sh`、`skills/mh-deliver/SKILL.md`（ARC-8 描述不动）、`CLAUDE.md`。

## 轨道建议

**formal**。理由：docs/ 目录重构（含三个根级文档迁入 designs/ + CR 设计文档迁入 cr-designs/）+ 新建 ~10 个文档骨架 + 新增校验脚本 + 多个脚本/配置路径同步更新，涉及设计决策（6 域划分、行数约束、整合方案、目录拓扑），目录重构不可局部回滚（影响面广）。

## testcase_adding_required

`false`。本次是文档/脚本变更，无运行时行为变化。但 `kb-verify.sh` 作为新增校验脚本，Tester 须验证其退出码行为（PASS/WARN/strict 模式）。

## 风险与回滚

- **回滚**：`docs/kb/` 为纯新增目录，`git revert` 即可删除；`docs/README.md` 同理；`design.md`/`source-of-truth.md` 仅加注/加行，revert 即可恢复。
- **风险**：低。不触及运行时代码、不改现有脚本行为、不交叉 ARC-8 路径。

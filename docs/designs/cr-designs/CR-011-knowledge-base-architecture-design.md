# CR-011 设计文档 — 框架知识库体系架构 + docs 目录重构

> 归档路径: docs/designs/cr-designs/CR-011-knowledge-base-architecture-design.md
> 需求单: docs/requirements/CR-011-knowledge-base-architecture.md
> 轨道: formal | testcase_adding_required: false

---

## 1. 架构定位

```
┌─────────────────────────────────────────────────────────┐
│                    Mini-Harness 框架                      │
├─────────────────────────────────────────────────────────┤
│  运行时层: agents/ + skills/ + workflows/ + scripts/     │
├─────────────────────────────────────────────────────────┤
│  模板层: templates/ (handoff/state/ppt/kb)               │
├─────────────────────────────────────────────────────────┤
│  自开发层: tools/mh-dev/ (轨道+状态机+快照+验证)          │
├─────────────────────────────────────────────────────────┤
│  ▶ 知识层: docs/kb/  ◀  ← 本设计                         │
├─────────────────────────────────────────────────────────┤
│  设计参考层: docs/designs/ (架构地图+流程+权威源+CR设计)  │
└─────────────────────────────────────────────────────────┘
```

**定位说明：**
- 属于"知识基础设施"层，不影响运行时行为
- 描述框架自身模块，供贡献者/AI 理解框架（非外部项目交付知识库）
- 与 ARC-8（`workflows/lib/knowledge-base.js` 为 `deliverables/{REQ-ID}/docs/kb/` 生成项目知识库）完全独立，不共享代码路径

---

## 2. 上下游关系

### 2.1 上游（谁消费知识库）

| 上游 | 使用方式 |
|------|----------|
| Claude Code 新会话 | AI 读取知识库建立框架心智模型 |
| mh-dev Developer Agent | 开发前阅读理解框架模块；开发后更新知识库 |
| mh-dev Tester Agent | 理解模块上下文辅助验收测试设计 |
| mh-dev Auditor Agent | 审计时参照知识库判断实现合规性 |
| 人类贡献者 | 快速了解项目全貌 + 定位变更影响范围 |

### 2.2 下游（知识库描述谁）

| 下游 | 依赖方式 |
|------|----------|
| `agents/` | 知识库描述角色契约体系 |
| `skills/` | 知识库描述执行规程与 track 裁剪 |
| `workflows/` | 知识库描述并行编排与决策逻辑 |
| `scripts/` | 知识库描述硬校验体系 |
| `templates/` | 知识库描述模板体系 |
| `tools/mh-dev/` | 知识库描述自开发工具 |

---

## 3. 知识库分层架构设计

### 3.1 目录结构

```
docs/kb/
├── system-map.md              ← Layer 0: 全景入口（≤150行）
├── domains/                   ← Layer 1: 域指南（6份，每份≤400行）
│   ├── roles.md                   Roles 域（agents/）
│   ├── skills.md                  Skills 域（skills/）
│   ├── workflow.md                Workflow 域（workflows/）
│   ├── guards.md                  Guards 域（scripts/）
│   ├── templates.md               Templates 域（templates/）
│   └── mh-dev.md                  mh-dev 域（tools/mh-dev/）
├── recipes/                   ← Layer 2: 操作食谱（每份≤80行）
│   └── add-skill.md               示范食谱骨架
├── kb-verify.sh               ← 新鲜度与覆盖校验脚本
└── README.md                  ← 知识库使用说明
```

### 3.2 Layer 0: system-map.md 结构

目标：AI 读完后能判断任务涉及哪个域，直接跳转 Layer 1。

**内容骨架（≤150 行）：**

```
1. 项目定位（3-5行）
   - 一句话定义 + 核心价值主张

2. 核心概念速览（~20行）
   - 六域各一句话定义
   - 四层递进防线（Rules→Skills→Agents+Workflow→Scripts+人工）
   - 关键术语（track, SR gate, handoff, verify*.sh 等）

3. 数据流总览（~30行）
   - 主线交付流程（clarify → propose → apply → archive）
   - 状态机（init → propose → apply → archive → DONE）
   - mh-dev 流程（intake → propose → develop → verify → done）

4. 六域速查表（~20行）
   - 每域：一句话职责 | 核心文件 | → Layer 1 链接

5. 跨域约束与铁律（~15行）
   - 脚本硬约束优先于自然语言软约束
   - 角色隔离
   - SR 门不可自主跨越
   - track 只读

6. 扩展场景导航（~10行）
   - 常见任务 → 对应食谱链接
```

### 3.3 Layer 1: 域指南统一骨架

每份域指南的结构（基于 `templates/kb/domain-template.md`）：

```
> 本域指南描述 {模块} 的内部机制。修改本域代码前请先阅读。
> 对应源码: {source_paths}

## 职责与边界          ← 必须填充（真实内容）
## 内部结构            ← 必须填充（ASCII 图 + 子模块表）
## 核心数据结构        ← 可留占位
## 关键流程            ← 可留占位
## 对外接口            ← 可留占位
## 文件清单与影响范围  ← 必须填充（影响范围定位矩阵，核心价值）
## 约束与陷阱          ← 可留占位
```

**"文件清单与影响范围"章节格式：**

```markdown
## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| {path} | {desc} | {related_files} |
```

这是本 CR 的核心价值——**定位变动影响范围的矩阵**。改一个文件时，"改动时需同步检查"列直接告诉你哪些文件需要连带检查。

### 3.4 Layer 2: 操作食谱骨架

基于 `templates/kb/recipe-template.md`，每份 ≤80 行：

```
1. 场景描述（一句话）
2. 涉及文件（完整列表）
3. 前置条件
4. 操作步骤（逐步，含代码模板片段）
5. 注册/关联步骤（⚠️ 标记容易遗漏的环节）
6. 验证命令
```

本次交付 1 份示范食谱 `add-skill.md`（骨架，后续 CR 填充步骤）。

### 3.5 六域职责速查

| 域 | 覆盖范围 | 核心源码 | 预计复杂度 |
|----|----------|---------|-----------|
| Roles | 3 被派发角色(thinker/worker/verifier)+orchestrator 编排器，角色契约结构 | `agents/*.md` | 中（~200行） |
| Skills | 9 个 SKILL，阶段 SOP，track 感知裁剪 | `skills/mh-*/SKILL.md` | 中（~250行） |
| Workflow | JS 并行编排层，5 主脚本 + lib/ 工具函数 + 决策逻辑库 | `workflows/*.js` | 中（~250行） |
| Guards | verify*.sh 硬校验体系，role-guard.sh Hook，三层校验 | `scripts/*.sh` | 中（~200行） |
| Templates | handoff/state/ppt/examples/output-guides/kb 模板体系 | `templates/**` | 低（~150行） |
| mh-dev | 自开发工具，fast/light/formal 轨道，状态机+快照+验证 | `tools/mh-dev/**` | 中（~250行） |

---

## 4. kb-verify.sh 设计

从 `templates/kb/kb-verify-template.sh` 派生，适配框架知识库。

**检查项：**

| 检查项 | 逻辑 | 严重级 |
|--------|------|--------|
| 结构完整性 | system-map.md + domains/ 存在且非空 | ERROR |
| 行数约束 | Layer 0 ≤150、Layer 1 ≤400、Layer 2 ≤80 | WARN（strict→ERROR） |
| 路径有效性 | 域指南引用的文件路径存在 | WARN |
| 新鲜度检测 | 域指南不比对应源码旧（源码更新则 WARN） | WARN（strict→ERROR） |

**域→源码映射：**

| 域指南 | 对应源码路径 |
|--------|-------------|
| domains/roles.md | agents/ |
| domains/skills.md | skills/ |
| domains/workflow.md | workflows/ |
| domains/guards.md | scripts/ |
| domains/templates.md | templates/ |
| domains/mh-dev.md | tools/mh-dev/ |

**退出码语义：**
- 无 ERROR 无 WARN → exit 0
- 有 WARN 无 ERROR → exit 0（普通）/ exit 1（--strict）
- 有 ERROR → exit 1

---

## 5. docs/ 目录重构设计

### 5.1 目标结构

```
docs/
├── README.md               目录导航（新增）
├── kb/                     框架知识库（本次新建）
│   ├── system-map.md
│   ├── domains/ (6 份)
│   ├── recipes/ (骨架)
│   ├── kb-verify.sh
│   └── README.md
├── designs/                设计文档归集（重组）
│   ├── design.md           架构地图（从 docs/ 根迁入）
│   ├── workflow.md         流程总览（从 docs/ 根迁入）
│   ├── source-of-truth.md  权威源映射（从 docs/ 根迁入）
│   ├── modules/            子模块设计文档（新建目录，留空）
│   └── cr-designs/         CR 设计文档（现有 5 份迁入）
├── requirements/           CR 需求单（保留）
├── audits/                 审计报告（保留）
└── retrospectives/         复盘报告（保留）
```

**设计原则：**
- `docs/designs/` 成为所有设计文档的归集点
- `modules/` 留给后续子模块深度设计文档（如 "Workflow 决策逻辑库设计"、"Guards 三层校验体系设计"）
- `cr-designs/` 把 CR 设计文档从 `docs/designs/` 根下沉一层，避免与框架级设计文档混放
- 三个根级文档迁入 `designs/` 后，`docs/` 根只剩 `README.md`（导航）+ 功能子目录

### 5.2 文件迁移清单

| 源路径 | 目标路径 | 操作 | 附加修改 |
|--------|---------|------|---------|
| `docs/design.md` | `docs/designs/design.md` | git mv | 开头加注指向 `docs/kb/domains/` |
| `docs/workflow.md` | `docs/designs/workflow.md` | git mv | 无 |
| `docs/source-of-truth.md` | `docs/designs/source-of-truth.md` | git mv | 新增 kb 映射条目 + 内部引用更新 |
| `docs/designs/CR-004-*-design.md` | `docs/designs/cr-designs/CR-004-*-design.md` | git mv | 无 |
| `docs/designs/CR-006-*-design.md` | `docs/designs/cr-designs/CR-006-*-design.md` | git mv | 无 |
| `docs/designs/CR-008-*-design.md` | `docs/designs/cr-designs/CR-008-*-design.md` | git mv | 无 |
| `docs/designs/CR-009-*-design.md` | `docs/designs/cr-designs/CR-009-*-design.md` | git mv | 无 |
| `docs/designs/CR-010-*-design.md` | `docs/designs/cr-designs/CR-010-*-design.md` | git mv | 无 |
| — | `docs/designs/modules/.gitkeep` | 新建 | 空目录占位 |

### 5.3 路径引用同步更新清单

| 文件 | 引用数 | 修改内容 |
|------|--------|---------|
| `README.md` | 4 | `docs/design.md`→`docs/designs/design.md`、`docs/workflow.md`→`docs/designs/workflow.md`、`docs/source-of-truth.md`→`docs/designs/source-of-truth.md`（L127-129, L137） |
| `scripts/check-harness.sh` | 1 | 目录检查数组新增 `docs/designs/modules` `docs/designs/cr-designs`（L46） |
| `tools/mh-dev/scripts/audit-preflight.sh` | 2 | `docs/workflow.md`→`docs/designs/workflow.md`、`docs/source-of-truth.md`→`docs/designs/source-of-truth.md`（L30-31） |
| `tools/mh-dev/scripts/validate-changes.sh` | 2 | doc_sync 映射 `docs/workflow.md`→`docs/designs/workflow.md`、`docs/source-of-truth.md`→`docs/designs/source-of-truth.md`（L87-88） |
| `tools/mh-dev/skills/mh-dev-develop/SKILL.md` | 1 | `docs/source-of-truth.md`→`docs/designs/source-of-truth.md`（L39） |
| `tools/mh-dev/CLAUDE.md` | 2 | `docs/designs/CR-*-design.md`→`docs/designs/cr-designs/CR-*-design.md`（L70, L158） |
| `docs/designs/source-of-truth.md`（内部） | ~10 | `docs/design.md`→`docs/designs/design.md`（L15-28, L65-66） |
| `docs/designs/design.md`（内部） | 1 | `docs/source-of-truth.md`→`docs/designs/source-of-truth.md`（L5） |

**不更新（显式排除）：** `CHANGELOG.md`（历史记录，不改）、`docs/requirements/*.md`（历史 CR 需求单，不改）、`docs/designs/cr-designs/CR-*-design.md`（历史设计文档，不改）、`docs/audits/*`（历史审计报告，不改）。

### 5.4 docs/README.md 设计

目录导航，参考 psdt-agent `docs/README.md` 结构：

```markdown
# docs/ 目录导航

## 目录结构

| 目录 | 用途 |
|------|------|
| `kb/` | 框架知识库（system-map + domains + recipes + kb-verify.sh） |
| `designs/` | 设计文档（架构地图 + 流程总览 + 权威源 + 模块设计 + CR 设计） |
| `designs/modules/` | 子模块深度设计文档 |
| `designs/cr-designs/` | CR 设计文档 |
| `requirements/` | CR 需求单 |
| `audits/` | 审计报告 |
| `retrospectives/` | 复盘报告 |

> 知识库是 AI/开发者理解框架的主要入口。修改框架代码后建议同步更新对应域指南。
```

---

## 6. 骨架交付范围说明

本次交付**架构+骨架**，不写满域指南内容：

| 产出 | 完成度 |
|------|--------|
| system-map.md | **写满**（全部章节） |
| 6 份 domains/*.md | **骨架**（职责/边界/内部结构/文件清单填充真实内容；核心数据结构/关键流程/对外接口/约束陷阱留占位） |
| recipes/add-skill.md | **骨架**（场景描述 + 涉及文件；步骤留占位） |
| kb-verify.sh | **完成**（从模板派生，适配 6 域） |
| README.md (kb/) | **完成** |
| README.md (docs/) | **完成** |
| docs 重构（迁移+引用更新） | **完成** |

**后续 CR 填充计划：** 每个域指南的"关键流程"和"对外接口"章节可独立成一个 CR 逐域填充，避免单轮 mh-dev 过载。

---

## 7. 影响分析

### 7.1 影响总结

| 模块 | 影响程度 | 修改类型 |
|------|----------|----------|
| `docs/kb/` | 高 | 新建：分层知识库目录树 |
| `docs/designs/` | 高 | 重组：三个根级文档迁入 + CR 设计文档下沉 + modules/ 新建 |
| `docs/README.md` | 中 | 新建：目录导航 |
| `README.md` | 低 | 修改：4 处路径引用 |
| `scripts/check-harness.sh` | 低 | 修改：目录检查数组 |
| `tools/mh-dev/scripts/*` | 低 | 修改：3 处路径引用 |
| `tools/mh-dev/skills/mh-dev-develop/SKILL.md` | 低 | 修改：1 处路径引用 |
| `tools/mh-dev/CLAUDE.md` | 低 | 修改：2 处路径引用 |
| `workflows/lib/knowledge-base.js` | 无 | 不改（ARC-8 独立） |
| `scripts/verify-archive.sh` | 无 | 不改（deliverables/ 路径） |
| `CLAUDE.md` | 无 | 不改（协议后续 CR） |

### 7.2 风险评估

- **风险等级：低-中**
- 文档迁移是纯文件移动 + 路径引用更新，不改运行时代码
- 主要风险：路径引用遗漏导致 check-harness.sh 或 audit-preflight.sh 失败
- 缓解：AX-08 验收条目专门检测旧路径残留；AX-05 回归测试确保框架完整性

### 7.3 回退策略

- `docs/kb/` 为纯新增，`git revert` 即可删除
- 文档迁移用 `git mv`，`git revert` 自动恢复原位
- 路径引用更新为文本替换，revert 自动恢复

---

## 8. 验收标准映射

见 `tools/mh-dev/.mh-dev/acceptance-criteria.md`：
- AC-01~AC-12：功能验收（知识库结构 + 内容完整性 + 文档迁移 + 路径同步）
- AX-01~AX-08：对抗性验收（行数约束 + 退出码语义 + 缺失检测 + 路径有效性 + 回归 + 影响隔离 + 新鲜度 + 旧路径残留）

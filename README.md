# Mini-Harness - AI Agent 驱动的研发流程框架

从需求到高质量交付的自动化生产。三个 AI Agent 角色 + 一个编排器协作，四层递进防线保障质量。

---

## 核心理念

**四层递进防线**，每层弥补上层的固有缺口：

1. **Rules** — 行为约束（CLAUDE.md，精简纪律）
2. **Skills** — 标准操作规程（固定步骤的 SOP，不依赖记忆）
3. **Agents + Workflow** — 角色制衡（写需求的人不审需求，写代码的人不做终验）
4. **Scripts + 人工** — 硬校验（退出码为唯一判据，Agent 说啥都不算）

**设计原则：** 脚本硬约束优先于自然语言软约束。契约即文档，模板即标准，脚本即验证。

---

## 三角色 + 编排器

| 角色 | 职责 |
|------|------|
| Orchestrator | 流程调度 + 质量门禁 + 人机交互 + 经验采集（主会话，不计被派发角色） |
| Thinker | 需求规格 → 技术设计/视觉设计（track 激活相位） |
| Worker | TDD 编码 + 精装交付 |
| Verifier | 独立验证 + 缺陷报告（不产验收标准） |

---

## 研发流程

### 外部项目交付：双 Track

| Track | 命令 | 流水线 |
|-------|------|--------|
| code | `/mh-run` | clarify → Thinker[needs→design] → SR1 → Worker → Verifier → SR3 → archive |
| ppt | `/mh-ppt` | clarify → Thinker[needs→visual] → SR1(wireframe) → Worker → Verifier[verify-ppt.sh] → SR3 → archive |

### 框架自身开发：/mh-dev

`/mh-dev` 专门开发、治理、验证和准备发布 **Mini-Harness 自身**。它直接修改本仓库的角色、技能、脚本、工作流、模板、文档与测试；运行态位于 `tools/mh-dev/.mh-dev/`，与 `/mh-run` 的外部项目产出隔离。

mh-dev 使用 fast/light/formal 轨道、开发者变更快照、机械预检、独立 Tester/Auditor 结论和 release candidate。它不会自动 commit、tag、push 或发布；这些外发操作始终需要人工显式授权。

---

## 产出类型

框架支持任意类型开发，在 clarify 阶段通过 track 选择确定流水线：
- `/mh-run` → code track（代码交付）
- `/mh-ppt` → ppt track（PPT 类 HTML 页面）

---

## 使用方式

### 支持平台

- Claude Code CLI（终端）
- VSCode Cline 插件
- VSCode Claude Code 插件

### 前置准备

1. 将需求相关参考资料放入 `reference/` 目录
2. 在对话框输入 `/mh-run`

`/mh-run` 的对外项目生命周期是 `clarify → propose → apply → archive`。开发本框架自身时改用 `/mh-dev`，不要把框架变更作为外部项目产出。

### 命令一览

| 命令 | 作用 |
|------|------|
| `/mh-run` | 外部项目/功能的全流程自动推进（推荐） |
| `/mh-dev` | Mini-Harness 自身的开发、治理、验证与候选发布 |
| `/mh-ppt` | PPT 类 HTML 开发快捷入口 |

### 最终产出

归档完成后，所有交付物位于 `deliverables/{REQ-ID}/` 目录（产出即归档，不存两份）：

```
deliverables/{REQ-ID}/
├── .engine/                引擎运行态（.state.md、handoffs/、process.log 等）
├── ORCHESTRATOR-init-*.md  Orchestrator 产出
├── THINKER-propose-*.md    Thinker 产出（需求规格、技术设计）
├── WORKER-apply-*.md       Worker 产出（代码报告）
├── VERIFIER-apply-*.md     Verifier 产出（测试报告）
├── docs/                   项目文档（spec、metrics、lessons、kb）
├── src/ tests/ deploy/     项目代码（按设计文档规划）
└── reference/              参考资料归档
```

---

## 质量保障

三层脚本硬校验，不依赖 Agent 自述：

| 脚本 | 职责 |
|------|------|
| verify.sh | 结构校验（文件、流程、契约） |
| verify-qa.sh | 内容质量校验（模糊词、测试结果、报告完整性） |
| verify-ppt.sh | PPT 专项（字号底线、导航、视口） |

role-guard.sh 按角色限制写入路径：WORKER 可写 `deliverables/{REQ-ID}/` 下除 `.engine/`（大小写不敏感）、其他角色产出（`THINKER-*.md`、`VERIFIER-*.md`、`ORCHESTRATOR-*.md`）、`.archiveignore` 外的所有路径（含 `src/`、`tests/`、`deploy/` 等项目代码路径）；全局路径穿越检测拒绝包含 `..` 组件的写入路径；mh-dev 分支在 `jq index()` 匹配前将绝对路径剥离仓库根前缀转为相对路径，与 `approved_scope` 精确匹配。

---

## 经验记忆

框架内置经验沉淀机制——每次执行中的调教和纠正自动采集，跨需求累积：

- 执行过程中 Orchestrator 自动采集（SR驳回、用户纠正、修复根因）
- 归档时用户补充改进建议
- 下次执行自动加载历史经验
- 框架开发者可将共性经验固化为规则

---

## 文档

| 文档 | 说明 |
|------|------|
| CLAUDE.md | 全局规则（最高约束） |
| docs/designs/design.md | 架构设计文档 |
| docs/designs/workflow.md | 流程总览 + 状态机 |
| docs/designs/source-of-truth.md | 权威源映射 |
| docs/retrospectives/ | 复盘报告（执行数据 + 问题分析） |
| docs/requirements/ | 变更请求（框架改进方案） |
| agents/*.md | 角色契约定义（thinker/worker/verifier/orchestrator） |
| skills/*.md | 执行规程 |

---

> 详细架构设计见 `docs/designs/design.md`

# Mini-Harness - AI Agent 驱动的研发流程框架

从需求到高质量交付的自动化生产。六个 AI Agent 角色协作，四层递进防线保障质量。

---

## 核心理念

**四层递进防线**，每层弥补上层的固有缺口：

1. **Rules** — 行为约束（CLAUDE.md，精简纪律）
2. **Skills** — 标准操作规程（固定步骤的 SOP，不依赖记忆）
3. **Agents + Workflow** — 角色制衡（写需求的人不审需求，写代码的人不做终验）
4. **Scripts + 人工** — 硬校验（退出码为唯一判据，Agent 说啥都不算）

**设计原则：** 脚本硬约束优先于自然语言软约束。契约即文档，模板即标准，脚本即验证。

---

## 六个 Agent 角色

| 角色 | 职责 |
|------|------|
| PM | 流程调度 + 质量门禁 + 人机交互 + 经验采集 |
| BA | 模糊需求 → 结构化需求规格（SHALL + GWT） |
| SA | 需求 → 技术方案 → Tasks 清单 |
| DE | TDD 编码 + 精装交付 |
| TE | 独立验证 + 缺陷报告 |
| UX | 视觉/结构设计 + 视觉叙事 |

---

## 研发流程

### 外部项目交付：/mh-run

`/mh-run` 使用 Mini-Harness 为外部项目或功能交付产物：

```
/mh-run: clarify  →  propose  →  apply  →  archive
              需求澄清       分析+设计       开发+审计       归档+结项
```

三档模式适配不同规模：
- **fast** — 小调整（5-10分钟）
- **standard** — 新功能（15-20分钟）
- **full** — 大型需求（30+分钟）

### 框架自身开发：/mh-dev

`/mh-dev` 专门开发、治理、验证和准备发布 **Mini-Harness 自身**。它直接修改本仓库的角色、技能、脚本、工作流、模板、文档与测试；运行态位于 `tools/mh-dev/.mh-dev/`，与 `/mh-run` 的外部项目产出隔离。

mh-dev 使用 fast/light/formal 轨道、开发者变更快照、机械预检、独立 Tester/Auditor 结论和 release candidate。它不会自动 commit、tag、push 或发布；这些外发操作始终需要人工显式授权。

---

## 产出类型

框架支持任意类型开发，在 clarify 阶段通过 output_type 指定：

web-app / backend-api / cli-tool / data-pipeline / infrastructure / documentation / ppt / library / custom

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
| `/mh-retro` | 复盘 + 变更请求（为 mh-dev 提供改进输入） |

### 最终产出

归档完成后，所有交付物位于 `output/` 目录：

```
output/
├── spec/               需求/设计文档（全量累积）
├── reference/          参考资料归档
├── lessons-learned.md  经验沉淀（越用越好）
└── {产出物}            代码/产品/PPT
```

---

## 质量保障

三层脚本硬校验，不依赖 Agent 自述：

| 脚本 | 职责 |
|------|------|
| verify.sh | 结构校验（文件、流程、契约） |
| verify-qa.sh | 内容质量校验（模糊词、测试结果、报告完整性） |
| verify-ppt.sh | PPT 专项（字号底线、导航、视口） |

---

## 经验记忆

框架内置经验沉淀机制——每次执行中的调教和纠正自动采集，跨需求累积：

- 执行过程中 PM 自动采集（SR驳回、用户纠正、修复根因）
- 归档时用户补充改进建议
- 下次执行自动加载历史经验
- 框架开发者可将共性经验固化为规则

---

## 文档

| 文档 | 说明 |
|------|------|
| CLAUDE.md | 全局规则（最高约束） |
| docs/design.md | 架构设计文档（10章） |
| docs/workflow.md | 流程总览 + 状态机 |
| docs/source-of-truth.md | 权威源映射 |
| docs/retrospectives/ | 复盘报告（执行数据 + 问题分析） |
| docs/requirements/ | 变更请求（框架改进方案） |
| agents/*.md | 角色契约定义 |
| skills/*.md | 执行规程 |

---

> 详细架构设计见 `docs/design.md`

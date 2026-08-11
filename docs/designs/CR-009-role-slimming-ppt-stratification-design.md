# CR-009 设计文档：角色文件瘦身 + PPT 分层沉淀 + skill 标准化

> 需求: docs/requirements/CR-009-role-slimming-ppt-stratification.md
> 轨道: formal

## 1. 设计目标

1. 将 7 个角色文件（共 1676 行）瘦身为纯角色契约（每个 ~35-60 行）
2. SOP/方法论下沉到 skill 文件，纯格式骨架放 templates
3. PPT 专用约束从 thinker/worker/orchestrator 沉淀到 mh-ppt skill + templates
4. 消除 mh-run 与 orchestrator.md/CLAUDE.md §6 的三处语义重复
5. 所有 skill 转为 Claude Code 标准格式（目录化 + frontmatter），实现真正的按需加载
6. mh-dev 工具内容集中到 tools/mh-dev/，三角色方法论拆为独立 skill

## 2. 核心设计原则

1. **角色文件 = 身份契约**：只回答"我是谁、能做什么、不能做什么"。不含"怎么做"。
2. **Skill = SOP/方法论**：回答"怎么做事"——思考框架、质量标准、执行规则、工作流程 Step。按需加载。
3. **Templates = 格式骨架**：回答"产出物长什么样"——空表格、JSON 结构、markdown 骨架。纯结构，无方法论。
4. **Skill 标准格式**：每个 skill 是 `skills/<name>/SKILL.md` 目录，含 `name`+`description` frontmatter，实现渐进式加载（metadata 常驻 → body 按需 → resources 按需）。
5. **track-agnostic 角色文件**：角色文件不含任何 PPT 专用条款。

## 3. 内容分类规则

| 内容类型 | 归属 | 例子 |
|---------|------|------|
| 身份/职责/输入输出/阻塞/禁止/白名单/铁律 | 角色文件 (agents/) | "Thinker 是需求规格化者"、"禁止编写实现代码" |
| 思考框架步骤/质量标准/反模式/自检清单 | Skill | needs 相位思考 5 步、PASS/FAIL 条件 |
| test_strategy 执行规则/TDD 流程/工作流程 Step | Skill | e2e 降级规则、Red/Green/Refactor |
| 审计方法论/Code Review 规则/回归规则/失败分类 | Skill | Auditor Phase 0-7、FAIL_IMPL/FAIL_DESIGN |
| 经验采集规则/修复轮次指导 | Skill | CP-1/CP-2/CP-3 触发表 |
| PPT 视觉约束/实现品质要求 | Skill (mh-ppt) | 视口 1920×1080、字号底线、布局规则 |
| 纯格式骨架（空表格/JSON 结构/markdown 模板） | Templates | slide-spec 格式、test-report 格式、verdict JSON |

## 4. 角色文件瘦身映射

### 4.1 agents/orchestrator.md（187 → ~55 行）

| 当前内容 | 行号 | 去向 |
|---------|------|------|
| 身份+职责+输入/输出/阻塞/禁止 | L1-67 | **保留** |
| 经验采集规则 | L22-38 | → skills/mh-deliver/SKILL.md（ARC-6 扩展） |
| 调度协议（8步循环+Handoff纪律+停止条件+六条铁律+平台适配） | L69-116 | → skills/mh-codeflow/SKILL.md（调度协议节） |
| 质量门禁（Step0白名单+各角色验收+驳回标准） | L118-181 | → skills/mh-codeflow/SKILL.md（质量门禁节） |
| 模型建议 | L185-187 | 保留 |

### 4.2 agents/thinker.md（334 → ~55 行）

| 当前内容 | 行号 | 去向 |
|---------|------|------|
| 身份+三相表+职责+输入/输出/阻塞/禁止 | L1-64 | **保留** |
| 思考框架（needs/design/visual） | L67-93 | → skills/mh-design/SKILL.md |
| 质量标准（needs/design/visual） | L96-122 | → skills/mh-design/SKILL.md |
| 反模式 | L125-150 | → skills/mh-design/SKILL.md |
| PPT 视觉约束 | L153-178 | → skills/mh-slideflow/SKILL.md |
| needs 格式模板 | L185-215 | → templates/needs-spec-template.md |
| design 格式模板 | L217-262 | → templates/design-spec-template.md |
| slide-spec 格式模板 | L264-296 | → templates/ppt-slide-spec-template.md |
| 交付自检清单 | L300-328 | → skills/mh-design/SKILL.md |
| 模型建议 | L332-334 | 保留 |

### 4.3 agents/worker.md（206 → ~45 行）

| 当前内容 | 行号 | 去向 |
|---------|------|------|
| 身份+职责+输入/输出/阻塞/禁止 | L1-47 | **保留** |
| 思考框架 | L50-63 | → skills/mh-build/SKILL.md |
| 质量标准+反模式 | L66-89 | → skills/mh-build/SKILL.md |
| TDD 流程 | L92-105 | → skills/mh-build/SKILL.md |
| 修复轮次指导 | L108-117 | → skills/mh-repair/SKILL.md |
| 代码报告格式模板 | L120-144 | → templates/code-report-template.md |
| PPT 实现品质要求 | L148-184 | → skills/mh-slideflow/SKILL.md + templates/ppt-quality-rules.md |
| 交付自检清单 | L187-201 | → skills/mh-build/SKILL.md |
| 模型建议 | L204-206 | 保留 |

### 4.4 agents/verifier.md（295 → ~50 行）

| 当前内容 | 行号 | 去向 |
|---------|------|------|
| 身份+职责+输入/输出/阻塞/禁止 | L1-51 | **保留** |
| 思考框架 | L54-66 | → skills/mh-verify/SKILL.md |
| 质量标准（PASS/FAIL+严重程度） | L69-96 | → skills/mh-verify/SKILL.md |
| 反模式 | L99-110 | → skills/mh-verify/SKILL.md |
| test_strategy 执行细则 | L113-145 | → skills/mh-verify/SKILL.md |
| Code Review 职责 | L149-193 | → skills/mh-verify/SKILL.md |
| 回归测试执行格式 | L197-224 | → skills/mh-verify/SKILL.md |
| 测试报告格式模板 | L228-276 | → templates/test-report-template.md |
| 交付自检清单 | L280-291 | → skills/mh-verify/SKILL.md |
| 模型建议 | L293-295 | 保留 |

### 4.5 tools/mh-dev/agents/auditor.md（264 → ~40 行）

| 当前内容 | 行号 | 去向 |
|---------|------|------|
| 身份+输出语言+输入+白名单+禁止路径+前置条件 | L1-44 | **保留** |
| 审计方法论 Phase 0-5 | L46-133 | → tools/mh-dev/skills/mh-dev-audit/SKILL.md |
| Phase 6 报告输出（verdict JSON + report 模板） | L136-229 | → tools/mh-dev/skills/mh-dev-audit/SKILL.md（SOP）+ templates（格式骨架） |
| Phase 7 自检 | L231-242 | → tools/mh-dev/skills/mh-dev-audit/SKILL.md |
| 审计铁律 10 条 | L243-264 | **保留**（角色约束） |
| 报告质量标准 | L257-264 | → tools/mh-dev/skills/mh-dev-audit/SKILL.md |

### 4.6 tools/mh-dev/agents/developer.md（141 → ~40 行）

| 当前内容 | 行号 | 去向 |
|---------|------|------|
| 身份+输出语言+输入+白名单+禁止路径+完成条件 | L1-40 | **保留** |
| 工作流程 Step 1-6 | L42-103 | → tools/mh-dev/skills/mh-dev-develop/SKILL.md |
| Step 7 产出报告格式 | L106-126 | → tools/mh-dev/skills/mh-dev-develop/SKILL.md（SOP）+ templates/dev-report-template.md（格式骨架） |
| 规则 13 条 | L128-141 | **保留**（精简，保留约束性条款） |

### 4.7 tools/mh-dev/agents/tester.md（249 → ~40 行）

| 当前内容 | 行号 | 去向 |
|---------|------|------|
| 身份+核心原则+输出语言+输入+白名单+禁止路径 | L1-36 | **保留** |
| 硬性验收要求 6 条 | L38-48 | **保留**（角色约束） |
| 失败分类规则+判定原则 | L49-64 | → tools/mh-dev/skills/mh-dev-test/SKILL.md |
| 测试用例规范 | L66-74 | → tools/mh-dev/skills/mh-dev-test/SKILL.md |
| 工作流程阶段一-五 | L76-136 | → tools/mh-dev/skills/mh-dev-test/SKILL.md |
| 阶段六产出（test-report + test-verdict 模板） | L138-226 | → tools/mh-dev/skills/mh-dev-test/SKILL.md（SOP）+ templates（格式骨架） |
| 规则 11 条 | L228-249 | **保留**（精简） |

## 5. mh-run skill 去重设计

### 当前 mh-run "工作流纪律"节处理

| 节 | 处理 | 去向 |
|----|------|------|
| 命令入口表 | **保留** | mh-run（专属） |
| 角色定义表 | **删除** | 引用 agents/*.md + docs/design.md |
| 流程纪律 | **删除** | 引用 CLAUDE.md §6 |
| 角色隔离 | **删除** | 引用 orchestrator.md + role-guard.sh |
| 产物保护 | **删除** | 引用 orchestrator.md |
| 自检纪律 | **精简保留** | 独有部分（脚本硬约束优先） |
| 断点恢复 | **保留** | mh-run（专属） |
| 平台适配 | **删除** | 引用 orchestrator.md |

同时 mh-run 新增"调度协议"节，接收从 orchestrator.md 下沉的 8 步循环+Handoff 纪律+停止条件+六条铁律+平台适配+质量门禁。

## 6. PPT 内容分层沉淀设计

### 6.1 skills/mh-slideflow/SKILL.md 扩展（107 → ~200 行）

新增节：
- **PPT 视觉约束**（接收自 thinker.md L153-178）：视口、ppt_design_mode、视觉叙事原则、视觉多样性要求
- **PPT 实现品质要求**（接收自 worker.md L148-184）：字号底线表、布局规则、导航交互、必须做到 5 条
- 引用 `templates/ppt-slide-spec-template.md`、`templates/ppt-quality-rules.md`

### 6.2 角色文件 PPT 条款清除

- thinker.md：删除 L153-178 + L264-296，加引用行
- worker.md：删除 L148-184，加引用行
- orchestrator.md：PPT 专项验收清单移到 mh-run 质量门禁节

## 7. skill 标准化设计（R8）

### 7.1 目录化 + 改名

所有 skill 从扁平文件转为目录结构，并按实际职责改名（slash 命令名和 phase 值不变）：

| 旧路径 | 新路径 | 改名理由 |
|--------|--------|---------|
| `skills/mh-run.md` | `skills/mh-codeflow/SKILL.md` | code track 全流程编排 |
| `skills/mh-ppt.md` | `skills/mh-slideflow/SKILL.md` | slide track 全流程编排 |
| `skills/mh-clarify.md` | `skills/mh-intake/SKILL.md` | 核心是需求初始化 |
| `skills/mh-propose.md` | `skills/mh-design/SKILL.md` | 核心是设计方案+计划 |
| `skills/mh-apply.md` | `skills/mh-build/SKILL.md` | 核心是构建+验证 |
| `skills/mh-archive.md` | `skills/mh-deliver/SKILL.md` | 核心是交付+沉淀 |
| `skills/mh-apply-repair.md` | `skills/mh-repair/SKILL.md` | 精简，直接说明修复 |
| `skills/dev-test.md` | `skills/mh-self-test/SKILL.md` | 加前缀，避免与 mh-dev 混淆 |
| `skills/post-verify.md` | `skills/mh-verify/SKILL.md` | 核心是验证校验 |
| `skills/mh-dev.md` | `tools/mh-dev/skills/mh-dev/SKILL.md` | 移入 mh-dev 工具目录 |

### 7.2 frontmatter 格式

每个 SKILL.md 首行必须有：
```yaml
---
name: <skill-name>
description: This skill should be used when the user asks to "<trigger phrase 1>", "<trigger phrase 2>", or when <context description>. <What the skill does.>
---
```

`description` 字段须覆盖阶段流转的触发条件，使自匹配可靠。例如 mh-design 的 description 应包含"Thinker design 相位"、"SR1 方案确认"、"技术设计方案"等触发短语。

### 7.2b 加载机制：入口显式 + 阶段自匹配

两种加载机制共存：
- **入口路由（显式）**：`.claude/commands/*.md` 保留显式引用（如"读取 skills/mh-codeflow/SKILL.md"），将用户命令路由到入口 skill。
- **阶段流转（自匹配）**：skill 内部不写"执行 mh-xxx skill"链式强制加载。阶段流转靠 `description` 自匹配——当上下文出现阶段信号，Claude 自动加载对应 skill。

skill 文件内部的"执行 mh-xxx skill"、"读取 skills/xxx.md"等链式加载指令须移除或改为弱引用（"下一阶段见 mh-xxx skill"作为指引，不强制加载）。

### 7.3 命名统一 + 改名

- 所有 skill 使用 mh- 前缀
- 改名（按实际职责，非按工作流阶段名）：
  - `dev-test` → `mh-self-test`（避免与 mh-dev 工具名混淆）
  - `post-verify` → `mh-verify`（核心是验证校验）
  - `mh-clarify` → `mh-intake`（核心是需求初始化）
  - `mh-propose` → `mh-design`（核心是设计方案+计划编排）
  - `mh-apply` → `mh-build`（核心是构建+验证交付）
  - `mh-apply-repair` → `mh-repair`（精简）
  - `mh-archive` → `mh-deliver`（核心是交付归档+沉淀）
  - `mh-run` → `mh-codeflow`（code track 全流程编排）
  - `mh-ppt` → `mh-slideflow`（slide track 全流程编排）
- slash 命令名不变：`/mh-run`、`/mh-ppt`、`/mh-dev` 保持不变
- `.state.md` phase 值不变：`init`/`propose`/`apply`/`archive` 保持不变
- 只改 skill 目录名，命令文件内部引用指向新路径

### 7.4 字段名不变

`code-report.md` 中 `dev-test: PASS` / `post-verify: PASS` 字段名不变。`verify-qa.sh` 的 grep 逻辑不变。skill 名与产出物字段名解耦。

## 8. mh-dev 工具 skill 设计（R7）

### 8.1 目录结构

```
tools/mh-dev/skills/
├── mh-dev/SKILL.md          # 入口路由（原 skills/mh-dev.md）
├── mh-dev-develop/SKILL.md   # Developer 工作流程 SOP
├── mh-dev-test/SKILL.md      # Tester 工作流程+失败分类 SOP
└── mh-dev-audit/SKILL.md     # Auditor 审计方法论 SOP
```

### 8.2 引用更新

| 文件 | 当前引用 | 更新为 |
|------|---------|--------|
| `.claude/commands/mh-dev.md` | `skills/mh-dev.md` | `tools/mh-dev/skills/mh-dev/SKILL.md` |
| `scripts/check-harness.sh` | `skills/mh-dev.md` | `tools/mh-dev/skills/mh-dev/SKILL.md` |
| `tools/mh-dev/scripts/audit-preflight.sh` | `skills/mh-dev.md` | `tools/mh-dev/skills/mh-dev/SKILL.md` |
| `docs/source-of-truth.md` | `skills/mh-dev.md` | `tools/mh-dev/skills/mh-dev/SKILL.md` |

## 9. 新增 templates 文件汇总（纯格式骨架）

| 文件 | 来源 | 内容 |
|------|------|------|
| `templates/orchestrator-quality-gate.md` | orchestrator.md L118-181 | 质量门禁检查清单骨架 |
| `templates/needs-spec-template.md` | thinker.md L185-215 | needs spec 格式骨架 |
| `templates/design-spec-template.md` | thinker.md L217-262 | design spec 格式骨架 |
| `templates/ppt-slide-spec-template.md` | thinker.md L264-296 | slide-spec 格式骨架 |
| `templates/ppt-quality-rules.md` | worker.md L152-184 | PPT 视觉硬约束详情 |
| `templates/code-report-template.md` | worker.md L120-144 | code-report 格式骨架 |
| `templates/test-report-template.md` | verifier.md L228-276 | 测试报告格式骨架 |
| `tools/mh-dev/templates/dev-report-template.md` | developer.md L106-126 | dev-report 格式骨架 |
| `tools/mh-dev/templates/test-report-template.md` | tester.md L138-226 | test-report 格式骨架 |

注：`tools/mh-dev/templates/audit-report.md` 已存在，扩展接收 auditor 报告格式骨架。

## 10. source-of-truth.md 更新

| 设计概念 | 旧权威源 | 新权威源 |
|---------|---------|---------|
| 工作流纪律 | skills/mh-run.md | orchestrator.md + CLAUDE.md §6 + skills/mh-codeflow/SKILL.md |
| 角色质量标准与思考框架 | agents/*.md | skills/mh-design/SKILL.md + skills/mh-build/SKILL.md + skills/mh-verify/SKILL.md |
| Orchestrator 调度协议 | orchestrator.md | skills/mh-codeflow/SKILL.md |
| Orchestrator 质量门禁清单 | orchestrator.md | skills/mh-codeflow/SKILL.md（SOP）+ templates/orchestrator-quality-gate.md（骨架） |
| PPT track 规则 | skills/mh-ppt.md | skills/mh-slideflow/SKILL.md（扩展） |
| 经验采集规则 | orchestrator.md | skills/mh-deliver/SKILL.md |
| mh-dev 协议 | tools/mh-dev/CLAUDE.md | 辅助参考改为 tools/mh-dev/skills/mh-dev/SKILL.md |

## 11. check-harness.sh 更新

skill 清单路径全部更新：
```bash
# 旧
for skill in mh-run mh-ppt mh-dev mh-clarify mh-propose mh-apply mh-archive mh-apply-repair dev-test post-verify; do
  require_file "skills/$skill.md"
done

# 新
for skill in mh-codeflow mh-slideflow mh-intake mh-design mh-build mh-deliver mh-repair mh-self-test mh-verify; do
  require_file "skills/$skill/SKILL.md"
done
require_file "tools/mh-dev/skills/mh-dev/SKILL.md"
require_file "tools/mh-dev/skills/mh-dev-develop/SKILL.md"
require_file "tools/mh-dev/skills/mh-dev-test/SKILL.md"
require_file "tools/mh-dev/skills/mh-dev-audit/SKILL.md"
```

新增 templates 文件加入文件存在性校验清单。

## 12. 执行顺序

1. **skill 目录化 + frontmatter**：所有 skill 转为 `skills/<name>/SKILL.md` 目录结构，补全 frontmatter。dev-test→mh-self-test, post-verify→mh-post-verify 重命名。mh-dev.md 移到 tools/mh-dev/skills/。新建 3 个 mh-dev 角色 skill。
2. **创建新 templates 文件**：9 个纯格式骨架文件。
3. **扩展 skill 文件**：各 skill 接收下沉的 SOP 内容。
4. **瘦身角色文件**：7 个角色文件删除已下沉内容，加引用行（引用使用新 skill 路径）。
5. **更新引用方**：.claude/commands/、.clinerules、check-harness.sh、audit-preflight.sh、source-of-truth.md、docs/design.md。
6. **验证**：check-harness.sh + test-role-guard.sh + 引用完整性 grep。

## 13. 回滚方案

git revert 即可——不涉及脚本逻辑变更（check-harness.sh/audit-preflight.sh 只改路径清单），所有改动是 Markdown 文件 + 目录化，回滚干净。

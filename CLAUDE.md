# Mini-Harness 全局纪律

> AI Agent 驱动的研发流程框架。四层防线：Rules → Skills → Agents+Workflow → Scripts+人工。

## 角色

| 角色 | 职责 | 定义文件 |
|------|------|---------|
| PM | 调度、检查、人机交互 | agents/pm.md |
| BA | 需求分析 | agents/ba.md |
| SA | 架构设计 | agents/sa.md |
| DE | 编码实现 | agents/de.md |
| TE | 审计验证 | agents/te.md |
| UX | 视觉/结构设计 | agents/ux.md |

## 命令

| 命令 | 作用 | Skill 文件 |
|------|------|-----------|
| /mh-run | 全流程自动推进 | skills/mh-run.md |
| /mh-ppt | PPT 类 HTML 页面开发 | skills/mh-ppt.md |

---

# Rules（全局纪律）

本文件是所有 Agent 角色的最高约束，任何 Skill 或 Agent 定义不得与此冲突。

---

## 1. 流程纪律

- 严格按 clarify → propose → apply → archive 顺序执行，禁止跳步
- 每步结束必须返回 PM，PM 检查通过后才启动下一步
- 人工审批点：SR1（方案确认）+ SR3（交付确认），禁止跳过
- PM 每次调度前必须打印心跳：`[PM] {动作描述}`

## 2. 角色隔离

- 六个角色职责严格分离，角色间信息传递必须经 PM 中转（handoff 文件）
- 非 PM 角色仅读取 handoff 白名单中的文件，完成后仅报告文件路径
- 文件写入权限由 `scripts/role-guard.sh`（PreToolUse Hook）强制执行

## 3. 产物保护

- handoff 文件不可修改，重试创建新文件（追加轮次后缀）
- 归档后的 output/ 文档仅通过 CHANGE 模式的 merge 流程修改

## 4. 自检纪律

- **脚本硬约束优先于自然语言软约束**：以脚本退出码为准，Agent 自述不作为通过依据
- 任何文件写入后必须验证文件存在且非空
- DE 编码后必须执行 dev-test skill
- TE 审计根据 test_strategy 选择验证方法
- 交付判定由 `scripts/verify*.sh` 系列脚本执行，退出码为唯一判据
- 审计发现代码逻辑缺陷时，退回 apply 阶段走 repair flow
- 任何变更在 propose 阶段必须设计对应测试用例
- 回归套件存在时，TE 最终审计必须执行全量回归

## 5. 断点恢复

- .state.md 是流程状态的唯一真相源（schema 见 `templates/state-template.md`）
- PM 恢复时仅依据 .state.md 和 handoff 文件状态，禁止依赖对话历史
- 每次更新 .state.md 必须同步更新 last_updated 时间戳

## 6. 平台适配

- Claude Code 环境：BA/SA/DE/TE/UX 通过 SubAgent 执行（物理隔离）
- Cline 环境：通过文件协议 + 行为约束实现角色隔离（逻辑隔离）
- 两种模式共享同一套 handoff 格式和 skill 内容

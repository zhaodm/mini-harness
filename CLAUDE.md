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
| /mh-clarify | 需求初始化与澄清 | skills/mh-clarify.md |
| /mh-propose | 分析→设计→用例→评审 | skills/mh-propose.md |
| /mh-apply | 开发→审计→人工审批 | skills/mh-apply.md |
| /mh-archive | 归档+结项 | skills/mh-archive.md |
| /mh-run | 全流程自动推进 | skills/mh-run.md |
| /mh-ppt | PPT 类 HTML 页面开发 | skills/mh-ppt.md |
| /mh-retro | 复盘+变更请求 | skills/mh-retro.md |

---

# Rules（全局纪律）

本文件是所有 Agent 角色的最高约束，任何 Skill 或 Agent 定义不得与此冲突。

---

## 1. 流程纪律

- 严格按 clarify → propose → apply → archive 顺序执行，禁止跳步
- 每步结束必须返回 PM，PM 检查通过后才启动下一步
- 禁止跳过人工审批节点（SR1/SR2/SR3/SR4）
- PM 每次调度前必须打印心跳：`[PM] {动作描述}`
- /mh-run 模式下允许阶段间自动推进，但阶段内审批节点仍禁止跳过

## 2. 角色隔离

- 六个角色（PM/BA/SA/DE/TE/UX）职责严格分离
- 角色间信息传递必须经 PM 中转，通过 handoff 文件实现
- 非 PM 角色仅读取 handoff 白名单中的文件
- 非 PM 角色完成后仅报告文件路径，不展开产物内容
- **文件写入权限由 `scripts/role-guard.sh`（PreToolUse Hook）强制执行**

## 3. 产物保护

- handoff 文件不可修改，重试创建新文件（追加轮次后缀）— role-guard.sh 强制
- 归档后的 output/ 文档仅通过 CHANGE 模式的 merge 流程修改

## 4. 自检纪律

- **脚本硬约束优先于自然语言软约束**：以脚本退出码为准，Agent 自述不作为通过依据
- 任何文件写入后必须验证文件存在且非空
- DE 编码后必须执行 dev-test skill（根据 tech_stack 路由测试命令）
- TE 审计根据 test_strategy 选择验证方法；E2E 环境不可用时降级并标注
- 交付判定五层校验：verify.sh + verify-qa.sh + verify-code-review.sh + verify-ppt.sh + verify-archive.sh
- SR4 阶段发现代码逻辑缺陷时，退回 apply 阶段走 repair flow
- 质量门禁失败时 PM 使用 `templates/quality-gate-report-template.md` 归因并派发修复
- TE Code Review 范围由 `deriveReviewScope()` 计算注入 handoff，TE 不自行判断
- TE 审计报告格式由 `scripts/verify-code-review.sh` 硬校验（CR-1~5），退出码为准
- 回归套件完整性由 `scripts/verify-qa.sh` QA-12（回归覆盖）+ QA-13（沉淀完整性）硬校验
- 归档阶段调用 `regression-suite.js` 的 `aggregateToSuite()` 沉淀用例，不依赖 NL 描述
- 任何变更（新增/修改/修复）在 propose 阶段必须设计对应测试用例
- 回归套件存在时，TE 最终审计必须执行全量回归，任何用例失败视为 FAIL，不可降级

## 5. 断点恢复

- PM 恢复时仅依据 .state.md 和 handoff 文件状态，禁止依赖对话历史
- .state.md 是流程状态的唯一真相源（完整 schema 见 `templates/state-template.md`）
- 每次更新 .state.md 必须同步更新 last_updated 时间戳
- 修复循环中每轮开始时必须更新 repair_round 字段，任务通过后重置为 0
- 恢复时如 handoff 为 pending 且 last_updated 超过 30 分钟，自动重新派发
- 恢复时必须读取 repair_round 字段，避免重复修复或超限

## 6. 平台适配

- Claude Code 环境：BA/SA/DE/TE/UX 通过 SubAgent 执行（物理隔离）
- Cline 环境：通过文件协议 + 行为约束实现角色隔离（逻辑隔离）
- 两种模式共享同一套 handoff 格式和 skill 内容

## 7. 产出类型体系（output_type）

框架支持任意类型的需求开发，通过 output_type 参数驱动流程适配：

| output_type | 说明 | 默认 test_strategy |
|-------------|------|-------------------|
| web-app | Web 应用（前端/全栈） | e2e / integration |
| backend-api | 后端服务/API | integration |
| cli-tool | 命令行工具 | integration |
| data-pipeline | 数据管道/ETL | smoke |
| infrastructure | 基础设施代码 | smoke |
| documentation | 文档/规格 | manual |
| ppt | 演示文稿/HTML slides | manual |
| library | 库/SDK | unit |
| custom | 自定义 | 用户指定 |

- output_type 与 mode 正交：mode 控制流程严谨度，output_type 控制产出物类型和验证方式
- output_type 在 clarify 阶段确定，写入 .state.md，贯穿全流程
- 各角色根据 output_type 和 tech_stack 选择对应的工具和验证方法

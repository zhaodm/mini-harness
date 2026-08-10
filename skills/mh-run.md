# Skill: mh-run

全流程自动推进。PM 主导，一次性执行 clarify → propose → apply → archive，仅在人工审批节点暂停。

**日志规则：** 同各阶段 skill 定义，追加日志到 `deliverables/{REQ-ID}/process.log`

---

## 工作流纪律（`/mh-run` 显式调用后生效）

> 以下规则原属根 CLAUDE.md，现归入本 skill，仅在用户执行 `/mh-run` 后适用。
> 根目录默认会话不启动任何多角色流程，不得自行假定当前角色为 PM、创建 handoff、状态文件或触发 SR 审批。

### 命令入口

| 命令 | 作用 | 激活的 Skill |
|------|------|-------------|
| `/mh-run` | 外部项目全流程自动推进（多角色） | skills/mh-run.md |
| `/mh-ppt` | PPT 类 HTML 页面开发 | skills/mh-ppt.md |

### 角色定义

| 角色 | 职责 | 定义文件 |
|------|------|---------|
| PM | 调度、检查、人机交互 | agents/pm.md |
| BA | 需求分析 | agents/ba.md |
| SA | 架构设计 | agents/sa.md |
| DE | 编码实现 | agents/de.md |
| TE | 审计验证 | agents/te.md |
| UX | 视觉/结构设计 | agents/ux.md |

### 流程纪律

- 严格按 clarify → propose → apply → archive 顺序执行，禁止跳步
- 每步结束必须返回 PM，PM 检查通过后才启动下一步
- 人工审批点：SR1（方案确认）+ SR3（交付确认），禁止跳过
- PM 每次调度前必须打印心跳：`[PM] {动作描述}`

### 角色隔离

- 六个角色职责严格分离，角色间信息传递必须经 PM 中转（handoff 文件）
- 非 PM 角色仅读取 handoff 白名单中的文件，完成后仅报告文件路径
- 文件写入权限由 `scripts/role-guard.sh`（PreToolUse Hook）强制执行

### 产物保护

- handoff 文件不可修改，重试创建新文件（追加轮次后缀）
- 归档后的 output/ 文档仅通过 CHANGE 模式的 merge 流程修改

### 自检纪律

- **脚本硬约束优先于自然语言软约束**：以脚本退出码为准，Agent 自述不作为通过依据
- 任何文件写入后必须验证文件存在且非空
- DE 编码后必须执行 dev-test skill
- TE 审计根据 test_strategy 选择验证方法
- 交付判定由 `scripts/verify*.sh` 系列脚本执行，退出码为唯一判据
- 审计发现代码逻辑缺陷时，退回 apply 阶段走 repair flow
- 任何变更在 propose 阶段必须设计对应测试用例
- 回归套件存在时，TE 最终审计必须执行全量回归

### 断点恢复

- .state.md 是流程状态的唯一真相源（schema 见 `templates/state-template.md`）
- PM 恢复时仅依据 .state.md 和 handoff 文件状态，禁止依赖对话历史
- 每次更新 .state.md 必须同步更新 last_updated 时间戳

### 平台适配

- Claude Code 环境：BA/SA/DE/TE/UX 通过 SubAgent 执行（物理隔离）
- Cline 环境：通过文件协议 + 行为约束实现角色隔离（逻辑隔离）
- 两种模式共享同一套 handoff 格式和 skill 内容

---

## 核心机制

**每个阶段步骤完成后，调用 `autoAdvance()`**（`workflows/lib/auto-advance.js`）：
- 输入: `{ phase, currentStep, srStatus, repairRound, autoAdvance: true }`
- 输出: `{ action, nextPhase?, reason }`

| action | PM 行为 |
|--------|---------|
| advance | 打印推进心跳，读取 nextPhase skill 继续执行 |
| pause | 暂停等待用户决策 |
| end | 打印最终摘要，流程结束 |

在 `.state.md` 写入 `auto_advance: true` 用于断点恢复识别。

---

## 暂停点（脚本硬编码）

- SR1 方案确认（proposal 评审）
- SR3 交付确认（最终审计后）
- Batch 人工确认
- 修复循环发散或耗尽（由 `decideRepair()` 触发）

## 状态重置

`autoAdvance()` 返回 `stateResets` 字段时，PM 必须同步更新 `.state.md`：
- SR3-DONE → archive: 重置 `repair_round=0, repair_task=""`

---

## 执行序列

1. **Init**: 写入 auto_advance=true → 执行 mh-clarify → INIT-DONE → advance
2. **Propose**: 执行 mh-propose → SR1 通过 → advance
3. **Apply**: 执行 mh-apply（人工审批照常暂停）→ SR3-DONE → advance
4. **Archive**: 执行 mh-archive → phase=done → end

---

## 断点恢复机制

重新 `/mh-run` 时检测 `auto_advance: true`，从 phase + current_step 恢复继续。

## 异常处理

- SubAgent status=failed → 修复循环内处理，不影响阶段间推进
- 修复发散/耗尽 → pause，用户解决后从当前位置继续
- 人工驳回 → 回退重新执行，完成后继续自动推进

---

## 最终摘要格式

```
══════════════════════════════════════
[/mh-run 全流程完成]
需求编号: {REQ-ID}
归档产物: output/
项目状态: DONE
══════════════════════════════════════
```

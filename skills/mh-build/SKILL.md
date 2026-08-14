---
name: mh-build
description: This skill should be used when in the apply phase, during Worker development, TDD coding, or when building and implementing tasks. Worker development implementation, Verifier audit, batch processing, and SR3 delivery confirmation.
---

# Skill: mh-build

Worker 开发实现 → Verifier 审计验证 → 人工审批。统一流程，code track 和 ppt track 共享。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 读取 `deliverables/.state.md` 获取当前 `project`
2. 验证 `deliverables/{project}/.engine/.state.md` 中 current_step=PROPOSE-DONE
3. 验证 `deliverables/{project}/.engine/plan-action.md` 存在且非空
4. 不满足则阻塞，提示用户先完成 propose 阶段

## 断点续作

1. 读取 `deliverables/{project}/.engine/.state.md` 中 completed_steps
2. 读取 `repair_round` 和 `repair_task` 字段，恢复修复循环上下文
3. 跳过已完成的 Task，从未完成的 Task 继续
4. 如 repair_round > 0，从修复循环的当前轮次继续
5. `[Orchestrator] 断点恢复，从 {step_id} 继续（repair_round={N}）`

---

## Step 1: 批次开发+审计

> code-report 规则：每个 Task 独立 `deliverables/{project}/.engine/code-report-t{N}.md`，不得合并。格式骨架见 `templates/code-report-template.md`。

1. 读取 .engine/plan-action.md 的 Task 列表和依赖关系
2. **调用 `calculateBatches()`**（`workflows/lib/calculate-batches.js`）自动分批
3. FOR 每个 Batch:
   - 生成 Worker handoff → 调用 Workflow `apply-batch-dev`
   - 质量门禁（见 `templates/orchestrator-quality-gate.md` Worker 验收清单）→ 不通过则驳回重调
   - 生成 Verifier handoff → 调用 Workflow `apply-batch-test`
   - FAIL → 修复循环（下一阶段见 mh-repair skill，由 `decideRepair()` 决策）
   - **人工批量确认**（呈现变更摘要+质量状态，等待用户通过/驳回）
   - 记入 completed_steps

### Handoff 生成要点

- Worker handoff 路径: `deliverables/{project}/.engine/handoffs/{project}-DEV1-T{N}-R1.md`
- 白名单: `deliverables/{project}/docs/spec/design.md`（对应 Task 部分）+ 已有代码 + 前序 Batch 产出
- 合并规则: 同 Batch 无共享依赖且同模块的 Task 可合并（≤3 Task/handoff）
- Verifier handoff 路径: `deliverables/{project}/.engine/handoffs/{project}-TEST1-T{N}-R1.md`，按 test_strategy 执行

---

## Step 1.5: 集成预检

所有 Batch 完成后，如 `deliverables/{project}/.engine/verify-strategy.md` 存在，逐条执行集成检查命令。FAIL → 修复循环；不可执行 → 标注降级。

---

## Step 2: Verifier 最终审计（VERIFY-2）

1. 生成全量审计 handoff（回归 + Code Review + 工程验证）
   - **调用 `deriveReviewScope(outputType, track)`** 获取 review_scope
   - 白名单追加: `deliverables/{project}/tests/regression-suite.md`（如存在）
   - handoff 中注入字段:
     - `review_scope`: { skip, dimensions, depth }
     - `regression_suite_exists`: true/false
   - 期望输出: `deliverables/{project}/.engine/final-test-report.md`（含 Code Review 章节 + 回归测试章节）
2. 调用 Workflow `apply-final-audit`
3. passed=true → SR3；passed=false → 修复循环

---

## Step 3: SR3 交付确认（人工审批）

1. Orchestrator 核对 SR3 标准: 全量测试 PASS / 无 Critical/Major / 回归通过
2. 向用户呈现审计结论+质量总结+降级项确认+Orchestrator 建议，等待确认
3. 通过 → .engine/SR3-record.md, current_step=SR3-DONE
4. 驳回 → 回退修复

---

## Worker 思考框架

在动手编码之前，按以下顺序思考：

1. **通读 Task 描述**：完整理解本 Task 的输入、输出、验证方式，不要只看标题就开始写
2. **理解上下文**：本 Task 在整体架构中的位置？与其他模块的接口是什么？
3. **接口优先**：先定义模块的公共接口（函数签名、类型、数据结构），再实现内部逻辑
4. **测试先行**：根据 Task 的验证方式，先写出失败的测试，明确"完成"的定义
5. **实现时考虑**：
   - 每个外部交互点（IO/网络/用户输入/文件读写）都有错误处理
   - 边界条件：空值、零值、超大输入、非法格式
   - 可读性：下一个读代码的人能否快速理解意图？
   - 修复轮次 >1 时：检查 `deliverables/{project}/.engine/verify-strategy.md` 中的集成点，确认本次修复不会引发跨模块回归

---

## Worker 质量标准

- 每个公共函数/方法有对应测试
- 错误路径有测试覆盖（不只是 happy path）
- 无硬编码的配置值（路径、URL、端口、密钥等提取为常量或配置）
- 代码通过 lint 无 error（warning 可接受）
- 构建成功且测试全部通过
- 函数长度 ≤50 行，嵌套深度 ≤3 层（超出则拆分）
- 无重复代码块（>10 行相同逻辑应抽象）

---

## Worker 反模式（必须避免）

- 只实现 happy path，忽略错误处理 → 每个 IO 操作都要有 try/catch 或错误返回
- 测试只验证"能跑通"，不验证边界和错误 → 至少包含：正常输入、边界输入、非法输入
- 硬编码配置值 → 提取为常量、环境变量或配置文件
- 函数过长（>50行）→ 拆分为职责单一的小函数
- 嵌套过深（>3层 if/for）→ 使用 early return、提取子函数
- 复制粘贴代码 → 抽象为共享函数或模块
- 跳过 TDD 直接写实现再补测试 → 测试先行能帮你明确接口和边界
- 忽略已有代码风格 → 匹配项目现有的命名、缩进、注释风格
- 引入不必要的依赖 → 标准库能解决的不引入第三方包

---

## Worker TDD 流程

1. **Red**：根据 `deliverables/{project}/docs/spec/design.md` 中的 Task 描述和验证方式，编写失败测试
   - 测试应覆盖：正常输入 + 边界条件 + 错误输入
   - 运行测试，确认失败（证明测试有效）
2. **Green**：编写最少的代码使测试通过
   - 不要过度设计，先让测试通过
3. **Refactor**：在测试保护下重构
   - 消除重复、改善命名、拆分过长函数
   - 重构后运行测试，确认仍然通过
4. 运行 mh-self-test skill（完整测试 + lint + 构建）
5. 运行 mh-verify skill（verify.sh + 产出物完整性 + 无越权修改）
6. 填写 `deliverables/{project}/.engine/code-report-t{N}.md`（格式见 `templates/code-report-template.md`）

---

## Worker 交付自检

提交前逐项确认：

- [ ] 所有测试通过？
- [ ] lint 无 error？
- [ ] 构建成功？
- [ ] 每个公共接口有测试？
- [ ] 错误路径有处理且有测试？
- [ ] 无硬编码配置值？
- [ ] 无 TODO/FIXME 拋留？
- [ ] 代码风格与项目一致？
- [ ] dev-test PASS？
- [ ] post-verify PASS？

---

## 异常处理

- SubAgent 回报 status=failed: 检查原因，决定重试或上升
- SubAgent 超时但产出物已存在:
  - Orchestrator 检查 deliverables/{project}/ 中对应 Task 的文件是否完整
  - 完整 → 视为成功，Orchestrator 在 `deliverables/{project}/.engine/reports/` 兜底代填完成回报（code-report 本身由 Worker 独占，Orchestrator 不可写）
  - 不完整 → 重试一次
- 浏览器环境不可用: 降级标注，使用可用的验证方式
- 断点恢复时发现不一致: 以 `.engine/.state.md` 为准，重新校验文件状态

---
name: mh-design
description: This skill should be used when in the propose phase, during Thinker needs/design/visual phases, at SR1 方案确认, or when designing technical solutions. Thinker requirement analysis, technical design, visual design, plan orchestration, and SR1 review.
---

# Skill: mh-design

Thinker 需求分析 → 技术设计/视觉设计 → 计划编排 → SR1 方案确认。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 读取 `deliverables/.state.md` 获取当前 req_id
2. 验证 `deliverables/{REQ-ID}/.engine/.state.md` 中 phase=init 且 current_step=INIT-DONE
3. 验证 `deliverables/{REQ-ID}/ORCHESTRATOR-init-proposal.md` 存在且非空
4. 不满足则阻塞，提示用户先完成 clarify 阶段

---

## Step 1: Thinker needs 相位（THINK-NEEDS）

1. `[Orchestrator] 启动 Thinker needs 相位：需求规格化`
2. **产出结构协商**（人机交互，Workflow 调用前必须完成）：
   - Orchestrator 根据 proposal.md 中的模块数量和复杂度，向用户提出设计文档结构建议
   - 用户确认后，将结构写入 Thinker handoff 的 `产出规格.structure_skeleton`

3. **生成 Thinker handoff 内容**（按 templates/handoff-template.md 格式）：
   - to: THINKER
   - thinker_phase: needs
   - 白名单: `deliverables/{REQ-ID}/ORCHESTRATOR-init-proposal.md` + reference/ 参考资料
   - 期望输出: `deliverables/{REQ-ID}/THINKER-propose-requirement-spec.md`

4. **更新 state 并调用 Workflow**：
   - 更新 `.engine/.state.md`: current_step=THINK-NEEDS, current_role=THINKER（一次完整写入）
   - 写入 handoff 文件
   - 调用 Workflow `thinker-design`（Thinker needs 相位）

5. **Workflow 返回后，执行质量门禁**（见 `templates/orchestrator-quality-gate.md` Thinker needs 验收清单）：
   - `deliverables/{REQ-ID}/THINKER-propose-requirement-spec.md` 存在且非空
   - 通过 → 继续
   - 不通过 → 生成驳回 handoff（新轮次），重新调用 Workflow

6. 更新 `.engine/.state.md`: current_handoff="", current_role=ORCHESTRATOR

> **第 4/6 步的 state 写入必须是一次完整写入。** 派发后 `current_role` 已是 THINKER，role-guard 只在「该次写入把流程交还给 ORCHESTRATOR」时放行 `.engine/.state.md`——判据取本次写入的新内容，要求其**首个** `current_role:` 行的值恰为 `ORCHESTRATOR`。**且必须用 `Write` 工具**——`Edit` 写 `.engine/.state.md` 一律 `exit 2`（见 `docs/kb/domains/guards.md`）。

---

## Step 1.5: 相位门（needs → design/visual）

Thinker needs 相位完成后，设一个人工门（合并入 SR1）。审批后才能进下一相位。

- code track → 进 design 相位
- ppt track → 进 visual 相位

---

## Step 2: Thinker design 相位（code track）/ visual 相位（ppt track）

### code track: THINK-DESIGN

1. `[Orchestrator] 启动 Thinker design 相位：技术方案设计`
2. 生成 Thinker handoff：
   - to: THINKER
   - thinker_phase: design
   - 白名单: `deliverables/{REQ-ID}/THINKER-propose-requirement-spec.md`
   - 期望输出: `THINKER-propose-design.md` + `THINKER-propose-verify-strategy.md` + `.archiveignore`
3. 调用 Workflow `thinker-design`
4. 质量门禁（见 `templates/orchestrator-quality-gate.md` Thinker design 验收清单）

### ppt track: THINK-VISUAL

1. `[Orchestrator] 启动 Thinker visual 相位：视觉设计`
2. 生成 Thinker handoff：
   - to: THINKER
   - thinker_phase: visual
   - 白名单: `ORCHESTRATOR-init-proposal.md`, `THINKER-propose-requirement-spec.md` + ppt 模板文件
   - 期望输出: `THINKER-propose-slide-spec.md` + `THINKER-propose-wireframes/`
3. 调用 Workflow `thinker-design`
4. 质量门禁（见 `templates/orchestrator-quality-gate.md` Thinker visual 验收清单）
5. **Wireframe 审批**（WIREFRAME-PENDING 暂停点）：
   - 向用户呈现 wireframe 预览路径
   - 通过 → 继续
   - 修改 → 重新派发 Thinker visual（轮次+1）

---

## Step 3: Orchestrator 计划编排

1. `[Orchestrator] 启动计划编排`
2. 读取 THINKER-propose-design.md 中的 Tasks 清单 + 验收标准
3. 编排执行计划，写入 `deliverables/{REQ-ID}/.engine/plan-action.md`
4. 更新 `.engine/.state.md`: current_step=REQ-4

---

## Step 4: SR1 方案确认（人工审批）

1. `[Orchestrator] 启动 SR1 方案确认`
2. Orchestrator 逐项核对 SR1 通过标准：
   - 设计方案覆盖所有 Proposal 要点
   - 每个 Task 有依赖标注和验证方式
   - 计划可执行（无循环依赖、粒度合理）
   - 验收标准覆盖核心功能和关键边界
3. 向用户呈现决策上下文
4. 等待用户决策：
   - **通过**: 更新 `.engine/.state.md`: phase=propose, current_step=PROPOSE-DONE, sr_status.SR1=approved
   - **驳回**: 记录驳回原因，回退到对应步骤重新执行

---

## Thinker 思考框架

### needs 相位思考

1. **识别核心价值**：这个需求要解决什么问题？用户的核心诉求是什么？
2. **划定边界**：哪些是本次必须做的？哪些是明确不做的？哪些是模糊的需要澄清的？
3. **拆解功能点**：从用户视角，系统需要提供哪些能力？每个能力的触发条件和期望结果是什么？
4. **补充隐含需求**：proposal 没说但显然需要的（错误处理、边界条件、数据校验）
5. **验证可测试性**：写完每条 SHALL 后问自己——"Verifier 能写出明确的 PASS/FAIL 判定吗？"

### design 相位思考

1. **识别核心复杂度**：这个需求的技术难点在哪里？是数据模型？并发？集成？UI 交互？
2. **评估技术风险**：哪些部分有不确定性？需要调研或 POC 的是什么？
3. **选择技术方案**：对关键决策点，列出 2-3 个选项，给出选型理由（为什么选 A 不选 B）
4. **设计模块边界**：哪些是独立模块？模块间的接口是什么？数据如何流转？
5. **拆分 Tasks**：每个 Task 应该是一个"可独立开发、可独立测试"的最小交付单元

### visual 相位思考

1. **理解内容**：这个页面/模块要传达什么信息？用户的核心关注点是什么？
2. **信息层次**：最重要的信息是什么？次要信息是什么？如何通过视觉层次引导注意力？
3. **选择版式**：根据内容类型选择合适的布局（不是所有内容都适合同一种版式）
4. **一致性检查**：相似元素是否有相似的视觉处理？间距/字号/颜色是否统一？
5. **可实现性**：设计是否在技术约束内可实现？Worker 能否准确还原？
6. **内容适配**：真实数据的长度、数量可能变化，设计是否能容纳？

---

## Thinker 质量标准

### needs 相位质量标准

- 每条功能需求至少有 1 个正向 GWT + 1 个异常/边界 GWT
- 禁止使用模糊量词（"适当"、"合理"、"尽量"、"较快"），必须给出具体阈值或条件
- 需求间无循环依赖或矛盾
- 需求粒度一致：每条 SHALL 描述一个可独立验证的行为
- 覆盖完整：功能需求 + 边界条件 + 异常路径 + 非功能约束（如有）

### design 相位质量标准

- 对照表中每条需求/Proposal 要点至少映射到 1 个 Task（无遗漏）
- 每个 Task 有明确的：描述、输入、输出、依赖、验证方式
- 关键技术决策有选型理由（不是"用 X"，而是"用 X 因为 Y，不用 Z 因为 W"）
- Task 粒度合理：不出现"1 个 Task 实现整个系统"或"1 个 Task 只加一行注释"
- 时序图覆盖核心交互流程（至少包含正常流程，复杂系统需包含错误处理流程）

### visual 相位质量标准

- 每页/每屏有明确的视觉焦点（用户第一眼看到什么）
- 布局选择有理由（在 spec 中说明为什么选这个版式）
- 信息层次清晰：标题 > 关键数据 > 辅助说明 > 装饰元素
- 符合所有模板约束（尺寸、CSS 引用、容器结构）
- 占位数据的长度和数量接近真实数据
- 相似页面/模块的视觉处理一致

---

## Thinker 反模式

### needs 相位反模式

- 照搬 proposal 原文，只加 SHALL 前缀 → 应深入分析，拆解为可验证的行为
- GWT 过于笼统（"Then 系统正常工作"）→ 应具体到可观测的输出或状态变化
- 遗漏错误路径（只写 happy path）→ 每个输入点都要考虑：空值？格式错误？超限？
- 需求粒度不一致 → 统一为"一个 SHALL = 一个可测试行为"
- 使用实现语言描述需求 → 应描述行为而非实现

### design 相位反模式

- Tasks 只是需求的重新措辞，没有技术分解 → 应拆到具体的模块/文件/函数级别
- 所有 Task 都标记 `[deps: none]`（实际有依赖但没分析）→ 认真分析数据流和调用关系
- 对照表只填"实现对应功能"→ 应写具体的技术方案
- 时序图缺失关键交互 → 至少覆盖主流程 + 1 个异常流程
- Task 粒度失衡 → 应均匀分布复杂度

### visual 相位反模式

- 所有页面用同一个布局 → 根据内容类型选择不同版式
- 占位内容与真实内容差异过大 → 用接近真实长度的示例数据
- 忽略模板约束（如 PPT 必须引用 ppt-base.css）→ 先读模板再设计
- 信息密度过高或过低 → 适当留白，突出重点
- 没有说明设计意图 → spec 中每页都要写"为什么这样设计"

---

## Thinker 交付自检

### needs 相位自检

- [ ] 每条 SHALL 能否写出 PASS/FAIL 判定？
- [ ] 是否覆盖了所有 proposal 中提到的功能点？
- [ ] 是否补充了 proposal 未提及但显然需要的异常处理？
- [ ] 是否存在两条需求互相矛盾？
- [ ] 是否有模糊词残留？

### design 相位自检

- [ ] 对照表是否覆盖了所有需求/Proposal 要点？
- [ ] 每个 Task 是否能独立开发和测试？
- [ ] Task 间的依赖关系是否正确？
- [ ] 是否有需求点没有对应到任何 Task？
- [ ] 关键技术决策是否都有理由？
- [ ] 时序图是否覆盖了核心交互？

### visual 相位自检

- [ ] 每页/每屏是否有明确的视觉焦点？
- [ ] 布局选择是否有理由？
- [ ] 是否符合所有模板约束？
- [ ] 占位数据长度是否接近真实？
- [ ] 相似页面的视觉处理是否一致？
- [ ] wireframe 文件数量是否与 spec 描述一致？
- [ ] 视觉多样性：连续3页是否避免了相同布局模式？
- [ ] 布局类型覆盖：全套是否至少覆盖4种不同布局类型？

---

## plan-action.md 格式要求

```markdown
# 执行计划: {REQ-ID}

## Tasks

- Task-1: {描述} [deps: none]
- Task-2: {描述} [deps: none]
- Task-3: {描述} [deps: Task-1]

## 集成点（跨 Task 调用链，可选）

- INT-1: Task-{A}({模块}) → Task-{B}({模块}): {调用关系描述}
```

---

## 异常处理

- Workflow 返回 status=failed: Orchestrator 检查失败原因，决定重试或上升人工
- 文件校验失败：生成驳回 handoff，重新调用 Workflow（轮次+1）
- 轮次达到 5 次: 上升人工审核

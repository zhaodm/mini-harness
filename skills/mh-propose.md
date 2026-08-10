# Skill: mh-propose

Thinker 需求分析 → 技术设计/视觉设计 → 计划编排 → SR1 方案确认。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 读取 `deliverables/.state.md` 获取当前 req_id
2. 验证 `deliverables/{REQ-ID}/.state.md` 中 phase=init 且 current_step=INIT-DONE
3. 验证 `deliverables/{REQ-ID}/proposal.md` 存在且非空
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
   - 白名单: `deliverables/{REQ-ID}/proposal.md` + reference/ 参考资料
   - 期望输出: `deliverables/{REQ-ID}/thinker/requirement-spec.md`

4. **更新 state 并调用 Workflow**：
   - 更新 `.state.md`: current_step=THINK-NEEDS, current_role=THINKER
   - 写入 handoff 文件
   - 调用 Workflow `thinker-design`（Thinker needs 相位）

5. **Workflow 返回后，执行质量门禁**（agents/orchestrator.md "Thinker needs 产出验收"清单）：
   - `deliverables/{REQ-ID}/thinker/requirement-spec.md` 存在且非空
   - 通过 → 继续
   - 不通过 → 生成驳回 handoff（新轮次），重新调用 Workflow

6. 更新 `.state.md`: current_handoff="", current_role=ORCHESTRATOR

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
   - 白名单: `deliverables/{REQ-ID}/thinker/requirement-spec.md`
   - 期望输出: `thinker/design.md` + `thinker/verify-strategy.md` + `.archiveignore`
3. 调用 Workflow `thinker-design`
4. 质量门禁（Orchestrator "Thinker design 产出验收"清单）

### ppt track: THINK-VISUAL

1. `[Orchestrator] 启动 Thinker visual 相位：视觉设计`
2. 生成 Thinker handoff：
   - to: THINKER
   - thinker_phase: visual
   - 白名单: `proposal.md`, `thinker/requirement-spec.md` + ppt 模板文件
   - 期望输出: `thinker/slide-spec.md` + `thinker/wireframes/`
3. 调用 Workflow `thinker-design`
4. 质量门禁（Orchestrator "Thinker visual 产出验收"清单）
5. **Wireframe 审批**（WIREFRAME-PENDING 暂停点）：
   - 向用户呈现 wireframe 预览路径
   - 通过 → 继续
   - 修改 → 重新派发 Thinker visual（轮次+1）

---

## Step 3: Orchestrator 计划编排

1. `[Orchestrator] 启动计划编排`
2. 读取 design.md 中的 Tasks 清单 + 验收标准
3. 编排执行计划，写入 `deliverables/{REQ-ID}/plan-action.md`
4. 更新 `.state.md`: current_step=REQ-4

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
   - **通过**: 更新 `.state.md`: phase=propose, current_step=PROPOSE-DONE, sr_status.SR1=approved
   - **驳回**: 记录驳回原因，回退到对应步骤重新执行

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

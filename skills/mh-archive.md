# Skill: mh-archive

产物归档 + 结项确认。PM 执行，支持首次归档和变更归档两种模式。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

1. 读取 `deliverables/.state.md` 获取当前 req_id
2. 读取 `deliverables/{REQ-ID}/.state.md` 中 mode 和 sr_status.SR3
3. 验证 sr_status.SR3=approved（standard/full）或 sr_status.SR3=approved（fast，在apply中已设置）
4. 验证 `deliverables/{REQ-ID}/output/` 存在且非空
5. 不满足则阻塞，提示用户先完成 /mh-apply

## 归档模式检测

- **首次归档**: output/spec/ 目录为空或不存在 → 直接复制
- **变更归档**: output/spec/ 目录已有文件 → merge 模式

## Step ARC-1: 需求归档

**执行角色:** PM

1. `[PM] 启动 ARC-1 需求归档`
2. fast 模式: 跳过（无 requirement-spec.md）
3. standard 模式: 跳过（无 requirement-spec.md，仅有 design.md）
4. full 模式:
   - 首次归档: 复制 `deliverables/{REQ-ID}/ba/requirement-spec.md` → `output/spec/requirement-spec.md`
   - 变更归档: merge 到 `output/spec/requirement-spec.md`
5. 校验目标文件存在且非空（full 模式）
6. `[PM] ARC-1 完成`

## Step ARC-2: 设计归档

**执行角色:** PM

1. `[PM] 启动 ARC-2 设计归档`
2. fast 模式: 跳过（无 design.md）
3. standard/full 模式:
   - 首次归档: 复制 `deliverables/{REQ-ID}/sa/design.md` → `output/spec/design.md`
   - 变更归档: 合并新设计内容到 `output/spec/design.md`，更新 Tasks 清单和对照表
4. 校验目标文件存在且非空（standard/full 模式）
5. `[PM] ARC-2 完成`

## Step ARC-3: 产出物归档（output_type 感知）

**执行角色:** PM

1. `[PM] 启动 ARC-3 产出物归档`
2. 读取 .state.md 中 output_type
3. 根据 output_type 执行归档策略：

| output_type | 归档源 | 归档目标 | 额外归档 |
|-------------|--------|---------|---------|
| ppt | deliverables/{REQ-ID}/output/ | output/ | deliverables/{REQ-ID}/ux/wireframes/ → output/wireframes/ |
| web-app | deliverables/{REQ-ID}/output/ | output/ | — |
| backend-api | deliverables/{REQ-ID}/output/ | output/ | — |
| cli-tool | deliverables/{REQ-ID}/output/ | output/ | — |
| library | deliverables/{REQ-ID}/output/ | output/ | — |
| data-pipeline | deliverables/{REQ-ID}/output/ | output/ | — |
| infrastructure | deliverables/{REQ-ID}/output/ | output/ | — |
| documentation | deliverables/{REQ-ID}/output/ | output/ | — |
| custom | deliverables/{REQ-ID}/output/ | output/ | 由 plan-action.md 指定 |

> 注：归档目标 `output/` 是项目根目录下与 `deliverables/` 平级的目录。所有交付相关产物统一归档于此（含 spec/、reference/、产出物）。

4. 首次归档: 直接复制全部文件（排除开发环境目录）
5. 变更归档: 覆盖已有同名文件，保留不冲突的已有文件
6. 校验根目录 `output/` 非空
7. `[PM] ARC-3 完成`

> 归档排除规则（复制时跳过以下目录/文件）：
> .venv/, node_modules/, __pycache__/, .pytest_cache/, .ruff_cache/,
> .git/, .DS_Store, *.pyc, *.pyo, .env

## Step ARC-4: 参考资料归档

**执行角色:** PM

1. `[PM] 启动 ARC-4 参考资料归档`
2. 检查 `reference/` 目录是否存在且非空
3. 如存在: 复制 `reference/` → `output/reference/`（覆盖已有同名文件）
4. 如不存在或为空: 跳过
5. `[PM] ARC-4 完成`

## Step ARC-5: 执行指标生成

**执行角色:** PM

1. `[PM] 启动 ARC-5 执行指标生成`
2. 根据 .state.md 中的数据（repair_history、sr_status、task_started_at 等）填写 `templates/metrics-template.md`
3. 保存为 `deliverables/{REQ-ID}/metrics.md`
4. 校验文件存在且非空
5. `[PM] ARC-5 完成，执行指标已生成`

---

## Step SR4: 项目结项确认（人工审批）

**执行角色:** PM（人机交互）

**fast 模式：** 跳过 SR4，直接结项。
- 更新 `deliverables/{REQ-ID}/.state.md`: phase=done, sr_status.SR4=skipped
- `[PM] 项目结项完成（fast模式）。需求 {REQ-ID} 已归档。`

**standard 模式：** 简化 SR4（一句确认）。
- `[PM] 归档完成，请确认结项（Y/N）`
- 用户确认:
  - 更新 `deliverables/{REQ-ID}/.state.md`: phase=done, sr_status.SR4=approved
  - `[PM] 项目结项完成。需求 {REQ-ID} 已归档。`

**full 模式：** 完整 SR4。
1. `[PM] 启动 SR4 项目结项确认`
2. PM 逐项核对 SR4 通过标准：
   ```
   SR4 通过标准:
   - [ ] 归档完整（output/spec/ 和 output/ 产出物非空）
   - [ ] 产出物可用（output/ 中文件与 plan-action.md 对应）
   - [ ] 文档一致（output/spec/ 内容与实际实现匹配）
   - [ ] 无遗漏归档（output_type 对应的额外归档已执行）
   ```
3. 向用户呈现决策上下文：
   ```
   [人工审批节点]
   评审节点: SR4（结项确认）

   归档概况:
     - 归档模式: {首次/变更}
     - 产出类型: {output_type}
     - 归档文件数: output/spec/ {N} 个, output/ 产出物 {N} 个

   质量状态:
     - 最终审计: SR3 已通过
     - 需求覆盖: 100%（SR3 已确认）
     - 修复总轮次: {累计修复次数}

   归档清单:
     - 需求规格: output/spec/requirement-spec.md
     - 技术设计: output/spec/design.md
     - 参考资料: output/reference/
     - 最终产物: output/ {文件列表}

   本次需求编号: {REQ-ID}
   PM 建议: {确认结项/建议复查} ({理由})
   请确认: 确认结项 / 驳回（请说明原因）
   ```
4. 等待用户决策：
   - **确认结项**:
     - 写入 `deliverables/{REQ-ID}/SR4-record.md`
     - 更新 `deliverables/{REQ-ID}/.state.md`:
       ```yaml
       phase: done
       current_step: SR4-DONE
       sr_status.SR4: approved
       ```
     - `[PM] 项目结项完成。需求 {REQ-ID} 已归档。`
   - **驳回**:
     - 记录原因，根据问题回退到对应阶段

## CHANGE 模式特殊处理

> 注：变更归档前，将当前 output/spec/ 的文件备份到 `deliverables/{REQ-ID}/baselines/`，与 propose 阶段 SR1 的过程快照统一存放在同一位置，方便回溯。

1. 归档前自动备份当前 output/spec/ 到 deliverables/{REQ-ID}/baselines/
   - deliverables/{REQ-ID}/baselines/requirement-spec.v{N}.md
   - deliverables/{REQ-ID}/baselines/design.v{N}.md
2. 版本号自动递增（检测已有 baseline 文件确定 N）
3. merge 时保持已有内容结构，仅追加或更新变更部分

## 变更归档 Merge 策略

归档时按以下规则处理 output/spec/ 文件的合并：

### 新增需求（本次 REQ-ID 引入的全新内容）
- 追加到 spec 文件末尾
- 用 `<!-- REQ-{ID} START -->` / `<!-- REQ-{ID} END -->` 注释标注来源
- 保持已有内容不变

### 修改需求（本次 REQ-ID 修改了已有内容）
- 定位到对应 REQ-ID 标注的段落
- 替换该段落内容
- 更新注释标注为最新 REQ-ID

### 删除需求（本次 REQ-ID 废弃了已有内容）
- 不物理删除原文
- 在对应段落开头添加: `[DEPRECATED by REQ-{ID}] — {废弃原因}`
- 保留原文供追溯

### 无标注的历史内容
- 首次遇到无 REQ-ID 标注的内容视为初始版本，不做修改
- 如需修改，先补充标注再执行替换

## 异常处理

- 目标目录不存在: 自动创建
- 文件复制失败: 重试一次，仍失败则报错上升人工
- merge 冲突（变更归档）: 呈现冲突内容，请求人工决策

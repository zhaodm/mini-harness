# Skill: mh-ppt

PPT 类 HTML 页面开发。可通过 `/mh-ppt` 快捷触发（自动设置 output_type=ppt 并执行 /mh-run），
也可在主流程中当 output_type=ppt 时自动加载本补充规则。

**日志规则：** 见 `templates/logging-standard.md`

---

## 快捷触发行为

当用户输入 `/mh-ppt` 时：
1. 如无活跃 REQ-ID: 执行 mh-clarify.md，但自动设置 output_type=ppt、test_strategy=manual
2. 如有活跃 REQ-ID 且 output_type=ppt: 从当前断点继续
3. 设置后自动进入 /mh-run 流程

## 主流程集成点

当 output_type=ppt 时，主流程在以下位置加载本补充规则：

| 阶段 | 集成行为 |
|------|---------|
| clarify | 自动设置 output_type=ppt, test_strategy=manual |
| propose | SA 方案后追加 UX wireframe 步骤 + 用户审批 wireframe |
| apply | DE 基于 wireframe 实现，TE 使用 verify-ppt.sh 校验 |
| archive | 额外归档 ux/wireframes/ → output/wireframes/ |

---

## 模式裁剪

| 模式 | SA | UX | 审批 | DE |
|------|----|----|------|----|
| fast | 跳过 | 直接从需求设计 | 1次人工确认 | 批量实现 |
| standard | 简版方案 | 基于方案设计 | wireframe审批 + 完成确认 | 逐页实现 |
| full | 完整方案 | 基于方案设计 | SR1 + wireframe审批 + SR3 | 逐页实现 |

---

## PPT 特有步骤（propose 阶段追加）

### UX Wireframe 设计

1. `[PM] 派发 UX wireframe 设计任务`
2. 创建目录结构：`deliverables/{REQ-ID}/ux/wireframes/`
3. 写入 handoff: `deliverables/{REQ-ID}/handoffs/{REQ-ID}-DESIGN1-R1.md`
   - to: UX
   - 白名单: `deliverables/{REQ-ID}/proposal.md`, `deliverables/{REQ-ID}/sa/design.md`(如有), `templates/ppt-base.css`, `templates/ppt-templates/layouts/`, `templates/frontend-design-skill.md`
   - 期望输出: `deliverables/{REQ-ID}/ux/slide-spec.md`, `deliverables/{REQ-ID}/ux/wireframes/`
4. 派发任务给 UX
5. 接收回报，校验 wireframe 文件存在且非空
6. `[PM] UX 设计完成，共 {N} 页`

### 用户审批 Wireframe

1. `[PM] 请在浏览器中预览 wireframe，确认版式`
2. 向用户呈现：
   ```
   [版式审批]
   Wireframe 文件: deliverables/{REQ-ID}/ux/wireframes/
   版式规格: deliverables/{REQ-ID}/ux/slide-spec.md
   请在浏览器中打开 wireframe HTML 文件预览。
   确认: 通过 / 修改（请说明哪页需要调整）
   ```
3. 通过 → 继续 apply 阶段
4. 修改 → 重新派发 UX（轮次+1，附修改意见）

---

## PPT 特有步骤（apply 阶段）

### fast 模式: DE 批量实现

1. `[PM] 派发 DE 实现任务`
2. 写入 handoff: `deliverables/{REQ-ID}/handoffs/{REQ-ID}-DEV1-R1.md`
   - to: DE
   - 白名单: `deliverables/{REQ-ID}/ux/wireframes/`, `deliverables/{REQ-ID}/ux/slide-spec.md`, `templates/ppt-base.css`, `templates/frontend-design-skill.md`
   - 期望输出: `deliverables/{REQ-ID}/output/`
   - 约束: 基于 wireframe 精装实现，填充真实数据，接入图表库，保持 16:9 约束
3. 派发任务给 DE
4. 接收回报，校验输出文件存在
5. `[PM] DE 实现完成`

### standard/full 模式: DE 逐页实现

```
FOR 每页 slide IN slide-spec.md:
    DE 实现该页 → TE 校验（verify-ppt.sh）→ 人工确认
    → 记入 completed_steps，继续下一页
END FOR
```

---

## TE 校验规则

TE 使用 `scripts/verify-ppt.sh` 执行硬校验：
- 每页 HTML 必须包含 viewport meta（width=1920）
- 每页必须有 .slide 容器
- 每页必须引用 ppt-base.css
- 页数与 slide-spec.md 一致
- 无占位符残留（检测 "Lorem"、"placeholder"、"TODO"）

## 修复循环

同主流程修复循环规则：最多 5 轮，超过上升人工。

## 异常处理

- UX wireframe 审批驳回: 记录修改意见，重新派发 UX
- DE 实现与 wireframe 不符: TE 标记差异，回退 DE
- verify-ppt.sh 失败: 按失败项逐一修复

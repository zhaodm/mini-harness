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

## 前置环境检查

1. 检测 `frontend-design` plugin 是否已启用（项目 `.claude/settings.json` 已配置）
2. 如 plugin 不可用（如提示 skill 未找到）：告知用户执行以下命令安装
   ```
   claude plugins:install frontend-design@claude-plugins-official
   ```
3. 确认 `templates/frontend-design-skill.md` 存在（SubAgent 白名单兜底用）

## 设计方案选择

在 clarify 阶段 Proposal 确认后、模式选择前，PM 向用户呈现设计方案选择：

```
[PPT 设计方案]
请选择本次 PPT 的设计方案：

  A. 设计系统模式（ppt-base.css）
     使用框架内置设计系统，统一的字体/配色/间距规范，产出风格一致。
     适合：企业汇报、系列化演示、需要品牌一致性的场景。

  B. 自由创意模式（frontend-design）
     基于 Anthropic frontend-design skill，每次根据内容主题从零设计。
     大胆独特的视觉风格，不受 ppt-base.css 视觉约束。
     适合：创意提案、产品展示、需要视觉冲击力的场景。

请选择（A/B）:
```

选择结果写入 `deliverables/{REQ-ID}/.state.md`: `ppt_design_mode: system | creative`

### A. 设计系统模式（ppt_design_mode: system）

- UX/DE 严格遵循 `templates/ppt-base.css` 设计体系
- 字体、配色、间距、圆角等使用 CSS 变量，不可自行覆盖
- 版式创意在设计系统约束内发挥（布局、信息层次、内容编排）
- verify-ppt.sh 全部检查项适用
- **可吸收 frontend-design 的互补建议**（不违反设计系统前提下）：
  - 动效：页面加载交错淡入、hover 状态增强
  - 空间构图：在 .slide 内尝试不对称布局、层次重叠
  - 视觉细节：渐变背景、微妙纹理、阴影层次感

### B. 自由创意模式（ppt_design_mode: creative）

- 以 `templates/frontend-design-skill.md` 为设计指导
- **仅保留硬性结构约束**：
  - 视口 1920×1080，16:9
  - 必须有 `.slide` 容器，禁止滚动
  - verify-ppt.sh 的结构类检查项适用（文件存在性、.slide 容器、viewport meta）
- **不受约束**：
  - 无需引用 ppt-base.css（可选引用其布局工具类）
  - 字体、配色、间距、背景、动效完全自由
  - 鼓励：独特字体、大胆配色、创意布局、丰富动效、氛围背景
- **可吸收设计系统的互补经验**（非强制）：
  - CSS 变量管理色彩/间距的工程实践
  - 信息层次原则（标题 > 关键数据 > 辅助说明）
  - 占位数据长度接近真实数据
  - 相似页面视觉处理一致性

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
   - 白名单（按 ppt_design_mode 区分）：
     - **system 模式**: `deliverables/{REQ-ID}/proposal.md`, `deliverables/{REQ-ID}/sa/design.md`(如有), `templates/ppt-base.css`, `templates/ppt-templates/layouts/`
     - **creative 模式**: `deliverables/{REQ-ID}/proposal.md`, `deliverables/{REQ-ID}/sa/design.md`(如有), `templates/frontend-design-skill.md`
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
   - 白名单（按 ppt_design_mode 区分）：
     - **system 模式**: `deliverables/{REQ-ID}/ux/wireframes/`, `deliverables/{REQ-ID}/ux/slide-spec.md`, `templates/ppt-base.css`
     - **creative 模式**: `deliverables/{REQ-ID}/ux/wireframes/`, `deliverables/{REQ-ID}/ux/slide-spec.md`, `templates/frontend-design-skill.md`
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

**通用检查（两种模式均适用）：**
- 每页 HTML 必须包含 viewport meta（width=1920）
- 每页必须有 .slide 容器
- 页数与 slide-spec.md 一致
- 无占位符残留（检测 "Lorem"、"placeholder"、"TODO"）

**仅 system 模式：**
- 每页必须引用 ppt-base.css

## 修复循环

同主流程修复循环规则：最多 5 轮，超过上升人工。

## 异常处理

- UX wireframe 审批驳回: 记录修改意见，重新派发 UX
- DE 实现与 wireframe 不符: TE 标记差异，回退 DE
- verify-ppt.sh 失败: 按失败项逐一修复

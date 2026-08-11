---
name: mh-slideflow
description: This skill should be used when the user runs "/mh-ppt" or when working on PPT/slide track. Slide track full-flow orchestration with PPT-specific visual constraints, implementation quality requirements, and verify-ppt.sh validation.
---

# Skill: mh-slideflow

PPT track 全流程。通过 `/mh-ppt` 触发，走 clarify → propose → apply → archive 流程，共享 3-role spine + 状态机。

**日志规则：** 见 `templates/logging-standard.md`

---

## 流程概览

```
/mh-ppt → clarify(track=ppt) → Thinker[needs→visual] → SR1(wireframe审批) → Worker[implement] → Verifier[verify-ppt.sh] → SR3 → archive
```

test_strategy 固定为 `manual`，Verifier 使用 `scripts/verify-ppt.sh` 校验。

---

## 前置环境检查

1. 检测 `frontend-design` plugin 是否已启用
2. 如不可用，告知用户安装：`claude plugins:install frontend-design@claude-plugins-official`
3. 确认 `templates/frontend-design-skill.md` 存在

---

## Clarify 阶段

1. 正常执行 mh-intake（需求澄清 + tech_stack 检测）
2. 写入 `track: ppt` 到 `.engine/.state.md`
3. 固定写入 `test_strategy: manual`
4. **设计方案选择**（Proposal 确认后）：

```
[PPT 设计方案]
请选择本次 PPT 的设计方案：

  A. 设计系统模式（ppt-base.css）
     使用框架内置设计系统，统一的字体/配色/间距规范。
     适合：企业汇报、系列化演示、品牌一致性场景。

  B. 自由创意模式（frontend-design）
     基于 Anthropic frontend-design skill，从零设计。
     适合：创意提案、产品展示、视觉冲击力场景。

请选择（A/B）:
```

选择结果写入 `.engine/.state.md`: `ppt_design_mode: system | creative`

### A. 设计系统模式

- Thinker/Worker 严格遵循 `templates/ppt-base.css` 设计体系
- 字体、配色、间距使用 CSS 变量，不可覆盖
- verify-ppt.sh 全部检查项适用

### B. 自由创意模式

- 以 `templates/frontend-design-skill.md` 为设计指导
- 仅保留硬性结构约束：视口 1920×1080、`.slide` 容器、禁止滚动
- 字体、配色、间距、动效完全自由

---

## Propose 阶段

1. Thinker needs 相位（需求规格化）
2. **Thinker visual 相位**（Wireframe 设计）
   - 创建 `deliverables/{REQ-ID}/THINKER-propose-wireframes/`
   - 写入 handoff，白名单按 ppt_design_mode 区分：
     - **system**: ORCHESTRATOR-init-proposal.md, THINKER-propose-requirement-spec.md, ppt-base.css, ppt-templates/layouts/
     - **creative**: ORCHESTRATOR-init-proposal.md, THINKER-propose-requirement-spec.md, frontend-design-skill.md
   - 期望输出: THINKER-propose-slide-spec.md + THINKER-propose-wireframes/
3. **用户审批 Wireframe**（WIREFRAME-PENDING 暂停点）
   - 向用户呈现 wireframe 预览路径，请求确认
   - 通过 → 继续 apply
   - 修改 → 重新派发 Thinker visual（轮次+1）
4. Orchestrator 编排 .engine/plan-action.md → SR1 方案确认

---

## Apply 阶段

1. Worker 基于 wireframe 实现
   - 白名单按 ppt_design_mode 区分
   - 约束: 精装实现，真实数据，保持 16:9
2. Verifier 使用 `scripts/verify-ppt.sh` 校验
   - **通用检查**：viewport meta、.slide 容器、页数一致、无占位符
   - **仅 system 模式**：必须引用 ppt-base.css
3. FAIL → 修复循环（最多 5 轮）
4. SR3 交付确认

---

## Archive 阶段

1. 归档产出物到 deliverables/{REQ-ID}/ 产品区
2. 额外归档 THINKER-propose-wireframes/ → deliverables/{REQ-ID}/assets/wireframes/
3. 流程结束

---

## PPT 视觉约束

> 以下约束适用于 Thinker visual 相位和 Worker 实现阶段。

### 视口与布局

- 视口固定 1920×1080，16:9 比例
- 禁止滚动，单页完整展示
- 使用占位数据（真实数据由 Worker 填充）
- ppt_design_mode=system 时基于 templates/ppt-base.css；creative 时参考 templates/frontend-design-skill.md
- 可引用 templates/ppt-templates/layouts/ 中的布局模板
- 输出 slide-spec.md 包含每页的布局选择、内容区域定义、数据字段映射

### PPT 视觉叙事原则

1. **节奏感**：全套 PPT 要有视觉节奏——密集页与留白页交替、信息页与冲击页搭配
2. **页面个性**：连续3页以上禁止使用同一种布局模式
3. **情绪传达**：每页必须定义"情绪"，设计服务于情绪
4. **视觉焦点唯一性**：每页只有一个视觉焦点，3秒内观众能抓住核心信息
5. **动效加分**：关键页面设计入场动画
6. **留白是设计**：敢于让一整页只有一句话 + 大量留白

### PPT 视觉多样性要求

Thinker 在 visual 相位设计 slide-spec 时，必须确保全套页面涵盖以下布局类型中的至少4种：

- 全屏大字、图文混排、多栏对比、时间线/流程图、数据展示、全出血背景、问答/互动

---

## PPT 实现品质要求

> 以下要求适用于 Worker 实现阶段。字号底线详情见 `templates/ppt-quality-rules.md`。

Worker 不只是"把 wireframe 翻译成代码"，而是要做"精装交付"：

### 视觉硬约束（verify-ppt.sh 会检查）

字号底线（1920×1080 视口）见 `templates/ppt-quality-rules.md`。

布局规则：

| 规则 | 正确做法 | 反模式 |
|------|---------|--------|
| 卡片高度由内容决定 | `align-items: start/center` | ❌ `flex:1` + `align-items:stretch` 强制等高 |
| grid 行高自适应 | `grid-template-rows: auto` | ❌ `1fr 1fr` 强制等高行 |
| padding 有上限 | 卡片 ≤ 28px，页面 ≤ 56px | ❌ padding: 80px 挤压内容 |
| 结论/摘要正常文档流 | flex/grid 自然排列 | ❌ `position: absolute` 定位底部 |

导航与交互：
- **每页必须包含方向键导航**（←↑上一页，→↓下一页）
- 交互页：方向键走导航，其他键触发内容显示
- 导航脚本统一引用 `js/navigator.js`，不每页重写

### 必须做到

1. **忠实还原 slide-spec 的设计意图**：情绪、视觉焦点、布局类型都要体现
2. **实现入场动效**：slide-spec 中标注了动效的页面，必须用 CSS animation 实现
3. **禁止内联样式堆砌**：所有视觉样式抽取为 CSS class
4. **真实数据填充**：不允许残留 placeholder/Lorem/TODO
5. **排版精细度**：字间距、行高、元素对齐必须像素级精确

---

## 异常处理

- Wireframe 审批驳回: 记录修改意见，重新派发 Thinker visual
- Worker 实现与 wireframe 不符: Verifier 标记差异，回退 Worker
- verify-ppt.sh 失败: 按失败项逐一修复

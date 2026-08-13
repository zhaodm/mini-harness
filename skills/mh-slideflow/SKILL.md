---
name: mh-slideflow
description: This skill should be used when the user runs "/mh-ppt" or when working on PPT/slide track. Slide track full-flow orchestration with PPT-specific visual constraints, implementation quality requirements, and verify-ppt.sh validation.
---

# Skill: mh-slideflow

PPT track 全流程。通过 `/mh-ppt` 触发，走 clarify → propose → apply → archive 流程，共享 3-role spine + 状态机。

**日志规则：** 见 `templates/logging-standard.md`

---

## 按需加载索引

入口只承载流程骨架与路由。详细规格按需读取，不在此复述：

| 需要什么 | 读哪个文件 | 何时读 |
|---------|-----------|-------|
| 字号分档、渲染几何阈值、豁免规则、布局规则、演讲者模式 | `templates/ppt-quality-rules.md` | Thinker visual / Worker 实现 |
| 版式 ID、类型、密度归属 | `templates/ppt-templates/registry.json` | Thinker 选版式 |
| 单文件骨架（舞台缩放 + 导航 + 演讲者模式） | `templates/ppt-base.html` | Worker 实现 |
| 版式规格产出格式 | `templates/ppt-slide-spec-template.md` | Thinker visual |
| 创意模式设计指导 | `templates/frontend-design-skill.md` | creative 模式 |
| 布局参考实现（17 份） | `templates/ppt-templates/layouts/` | Thinker / Worker |

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
4. **渲染测量依赖**：确认 `npm ls playwright` 就绪。缺失时 `verify-ppt.sh` 以退出码 3 阻断，
   不降级放行——须先 `npm install`

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

写入 `.engine/.state.md`: `ppt_design_mode: system | creative`

5. **密度模式选择**：

```
[PPT 密度模式]
请选择本次 PPT 的信息密度：

  A. 低密度演讲型
     大字、大留白，一页一个核心信息。字号绝对下限 18px。
     适合：投影演讲、路演、金句冲击。

  B. 高密度阅读型
     信息密集、多卡片/表格并置。字号绝对下限 14px。
     适合：仪表盘、经营分析、需细读的材料。

请选择（A/B）:
```

写入 `.engine/.state.md`: `ppt_density: speaker | reading`

未选择时 `verify-ppt.sh` 按 `speaker`（更严格档）判定。

### A. 设计系统模式

- Thinker/Worker 严格遵循 `templates/ppt-base.css`（speaker）或 `templates/ppt-light.css`（reading）
- 字体、配色、间距使用 CSS 变量，不可覆盖
- 设计系统可外链亦可内联进 `<style>`（自包含分发形态）。门禁判据是**设计系统在效**——
  外链文件名或内联 token 定义（`--font-body`、`--slide-width`）二者任一即通过
- 版式须取自 `registry.json` 登记集合
- verify-ppt.sh 全部检查项适用

### B. 自由创意模式

- 以 `templates/frontend-design-skill.md` 为设计指导
- 仅保留硬性结构约束：舞台 1920×1080、`.slide` 容器、禁止滚动、单文件形态
- 版式标识可自定义，但**必须声明** `data-layout` 与 `data-layout-type`（多样性统计依赖）
- 字号底线、渲染几何约束仍然适用

---

## Propose 阶段

1. Thinker needs 相位（需求规格化）
2. **Thinker visual 相位**（Wireframe 设计）
   - 创建 `deliverables/{REQ-ID}/THINKER-propose-wireframes/`
   - 写入 handoff，白名单按 ppt_design_mode 区分：
     - **system**: ORCHESTRATOR-init-proposal.md, THINKER-propose-requirement-spec.md, ppt-quality-rules.md, ppt-templates/registry.json, ppt-templates/layouts/
     - **creative**: ORCHESTRATOR-init-proposal.md, THINKER-propose-requirement-spec.md, ppt-quality-rules.md, frontend-design-skill.md
   - 期望输出: THINKER-propose-slide-spec.md + THINKER-propose-wireframes/
   - slide-spec 每页须标注版式 ID 与布局类型（供多样性统计与 Worker 落声明）
3. **用户审批 Wireframe**（WIREFRAME-PENDING 暂停点）
   - 向用户呈现 wireframe 预览路径，请求确认
   - 通过 → 继续 apply
   - 修改 → 重新派发 Thinker visual（轮次+1）
4. Orchestrator 编排 .engine/plan-action.md → SR1 方案确认

---

## Apply 阶段

1. Worker 基于 wireframe 实现**单一 HTML 文件**（骨架见 `templates/ppt-base.html`）
   - 白名单按 ppt_design_mode 区分，另加 `templates/ppt-quality-rules.md`
   - 约束: 精装实现，真实数据，舞台 1920×1080 等比缩放
   - 每页声明 `data-layout` + `data-slide-id`；讲稿备注写 `data-notes`
2. Verifier 使用 `scripts/verify-ppt.sh all {REQ-ID}` 校验四类检查
   - **A** 文件存在性与单文件形态 · **B** 静态合规（字号/版式/结构）
   - **C** 内容完整性与页数一致 · **D** 渲染几何测量（真实浏览器）
   - 退出码：0 通过 · 1 有失败项 · 3 渲染环境不可用（须先装依赖，不可跳过）
3. FAIL → 修复循环（最多 5 轮）。**溢出改布局，不回调字号**
4. SR3 交付确认

---

## Archive 阶段

1. 归档产出物到 deliverables/{REQ-ID}/ 产品区（单 HTML + CSS）
2. 额外归档 THINKER-propose-wireframes/ → deliverables/{REQ-ID}/assets/wireframes/
3. 流程结束

---

## PPT 视觉叙事原则

> 适用于 Thinker visual 相位。机器可判定项（字号、几何、版式多样性）见
> `templates/ppt-quality-rules.md`，此处只列需要人类判断的设计原则。

1. **节奏感**：全套 PPT 要有视觉节奏——密集页与留白页交替、信息页与冲击页搭配
2. **页面个性**：连续 3 页以上禁止使用同一种布局模式（脚本硬拦）
3. **情绪传达**：每页必须定义"情绪"，设计服务于情绪
4. **视觉焦点唯一性**：每页只有一个视觉焦点，3 秒内观众能抓住核心信息
5. **动效加分**：关键页面设计入场动画
6. **留白是设计**：敢于让一整页只有一句话 + 大量留白（低密度档容许大留白）

布局类型须涵盖至少 4 种（取值见 `registry.json` 的 `layout_types`）：
全屏大字、图文混排、多栏对比、时间线流程、数据展示、全出血背景、问答互动。

---

## PPT 实现品质要求

> 适用于 Worker。硬约束数值一律见 `templates/ppt-quality-rules.md`，不在此复述。

Worker 不只是"把 wireframe 翻译成代码"，而是要做"精装交付"：

1. **忠实还原 slide-spec 的设计意图**：情绪、视觉焦点、布局类型都要体现
2. **实现入场动效**：slide-spec 中标注了动效的页面，必须用 CSS animation 实现
3. **禁止内联样式堆砌**：所有视觉样式抽取为 CSS class
4. **真实数据填充**：不允许残留 placeholder/Lorem/TODO
5. **排版精细度**：字间距、行高、元素对齐必须像素级精确
6. **导航只实现一次**：单文件形态下导航内联于产出，不逐页重写

---

## 异常处理

- Wireframe 审批驳回: 记录修改意见，重新派发 Thinker visual
- Worker 实现与 wireframe 不符: Verifier 标记差异，回退 Worker
- verify-ppt.sh 退出码 1: 按失败项逐一修复
- verify-ppt.sh 退出码 3: 渲染环境不可用，先 `npm install`，**不得以此状态判定交付**
- 检查器自检失败（"检查器自身失效"）: 校验脚本本身被改坏，先修脚本再谈产出

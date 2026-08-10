# Skill: mh-ppt

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

1. 正常执行 mh-clarify（需求澄清 + tech_stack 检测）
2. 写入 `track: ppt` 到 `.state.md`
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

选择结果写入 `.state.md`: `ppt_design_mode: system | creative`

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
   - 创建 `deliverables/{REQ-ID}/thinker/wireframes/`
   - 写入 handoff，白名单按 ppt_design_mode 区分：
     - **system**: proposal.md, thinker/requirement-spec.md, ppt-base.css, ppt-templates/layouts/
     - **creative**: proposal.md, thinker/requirement-spec.md, frontend-design-skill.md
   - 期望输出: thinker/slide-spec.md + thinker/wireframes/
3. **用户审批 Wireframe**（WIREFRAME-PENDING 暂停点）
   - 向用户呈现 wireframe 预览路径，请求确认
   - 通过 → 继续 apply
   - 修改 → 重新派发 Thinker visual（轮次+1）
4. Orchestrator 编排 plan-action.md → SR1 方案确认

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

1. 归档产出物到 output/
2. 额外归档 thinker/wireframes/ → output/assets/wireframes/
3. 流程结束

---

## 异常处理

- Wireframe 审批驳回: 记录修改意见，重新派发 Thinker visual
- Worker 实现与 wireframe 不符: Verifier 标记差异，回退 Worker
- verify-ppt.sh 失败: 按失败项逐一修复

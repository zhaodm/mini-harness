# Skill: mh-ppt

PPT 类 HTML 页面开发。独立入口，通过 `/mh-ppt` 触发，走完整的 clarify → propose → apply → archive 流程。

**日志规则：** 见 `templates/logging-standard.md`

---

## 流程概览

```
/mh-ppt → clarify(需求+设计方案选择) → propose(SA+UX wireframe+审批) → apply(DE实现+TE校验) → archive
```

test_strategy 固定为 `manual`，TE 使用 `scripts/verify-ppt.sh` 校验。

---

## 前置环境检查

1. 检测 `frontend-design` plugin 是否已启用
2. 如不可用，告知用户安装：`claude plugins:install frontend-design@claude-plugins-official`
3. 确认 `templates/frontend-design-skill.md` 存在

---

## Clarify 阶段

1. 正常执行 mh-clarify（需求澄清 + tech_stack 检测）
2. 固定写入 `test_strategy: manual`
3. **设计方案选择**（Proposal 确认后）：

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

- UX/DE 严格遵循 `templates/ppt-base.css` 设计体系
- 字体、配色、间距使用 CSS 变量，不可覆盖
- verify-ppt.sh 全部检查项适用

### B. 自由创意模式

- 以 `templates/frontend-design-skill.md` 为设计指导
- 仅保留硬性结构约束：视口 1920×1080、`.slide` 容器、禁止滚动
- 字体、配色、间距、动效完全自由

---

## Propose 阶段

1. SA 架构设计（简版：页面结构 + 数据来源）
2. **UX Wireframe 设计**
   - 创建 `deliverables/{REQ-ID}/ux/wireframes/`
   - 写入 handoff，白名单按 ppt_design_mode 区分：
     - **system**: proposal.md, sa/design.md, ppt-base.css, ppt-templates/layouts/
     - **creative**: proposal.md, sa/design.md, frontend-design-skill.md
   - 期望输出: ux/slide-spec.md + ux/wireframes/
3. **用户审批 Wireframe**
   - 向用户呈现 wireframe 预览路径，请求确认
   - 通过 → 继续 apply
   - 修改 → 重新派发 UX（轮次+1）
4. PM 编排 plan-action.md → SR1 方案确认

---

## Apply 阶段

1. DE 基于 wireframe 实现
   - 白名单按 ppt_design_mode 区分
   - 约束: 精装实现，真实数据，保持 16:9
2. TE 使用 `scripts/verify-ppt.sh` 校验
   - **通用检查**：viewport meta、.slide 容器、页数一致、无占位符
   - **仅 system 模式**：必须引用 ppt-base.css
3. FAIL → 修复循环（最多 5 轮）
4. SR3 交付确认

---

## Archive 阶段

1. 归档产出物到 output/
2. 额外归档 ux/wireframes/ → output/assets/wireframes/
3. 流程结束

---

## 异常处理

- UX wireframe 审批驳回: 记录修改意见，重新派发 UX
- DE 实现与 wireframe 不符: TE 标记差异，回退 DE
- verify-ppt.sh 失败: 按失败项逐一修复

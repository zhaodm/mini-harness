# CR-007: 框架内部矛盾修复 + 文档同步

> 来源: v0.7.0 → v0.8.0 架构审查报告（经二次核实）
> 日期: 2026-06-10
> 状态: 待实施
> 优先级: P0
> 关联: CR-003（框架改进）、CR-005（决策逻辑脚本化）
> 设计原则: 消除矛盾 > 补全引用链 > 文档同步

---

## 执行摘要

v0.8.0 架构审查报告指出 12 项问题。经逐项核实，其中 2 项不成立（P1-7 workflows 已有注释；P1-5 "三层"与"五层"描述不同维度），2 项为功能建议而非缺陷（P0-4/P0-5 脚本拆分无明确规则支撑；P1-6 快速路径为设计选择）。

本 CR 聚焦于经核实确认的 7 项真实问题：

1. **P0 硬伤**：SR 跳过规则矛盾（运行时行为不确定）、版本号严重滞后
2. **P1 引用链不完整**：source-of-truth 引用不精确、角色定义缺产出物声明、design.md 工具清单过时
3. **P1 schema 缺失**：state-template 缺字段

## 问题陈述（核实后）

| 编号 | 问题 | 核实结论 | 优先级 |
|------|------|----------|--------|
| P0-1 | mh-clarify.md:56 声称 full 模式可跳过 SR，CLAUDE.md §1 明确禁止 | ✅ 矛盾确认，PM 运行时会收到冲突指令 | P0 |
| P0-2 | package.json version "0.1.0" vs 实际 v0.8.0 | ✅ 确认，7 个大版本偏差 | P0 |
| P1-1 | source-of-truth.md 第 24-26 行引用 mh-apply.md 的修复相关内容 | ⚠️ 引用未断（mh-apply.md 存在），但指向路由层而非实际定义文件 mh-apply-repair.md | P1 |
| P1-2 | state-template.md 缺 ppt_design_mode 字段 | ✅ mh-ppt.md 写入该字段但 schema 无定义 | P1 |
| P1-3 | sa/verify-strategy.md 在 mh-propose.md 中被列为"额外期望输出"，但 agents/sa.md 无此产出定义 | ✅ SA SubAgent 不知道要产出此文件 | P1 |
| P1-4 | te/audit-dimensions.md 同上——mh-propose.md 期望产出，agents/te.md 无定义 | ✅ 与 code-review-rules.js 定位重叠，需明确 | P1 |
| P1-5 | design.md §9 工具体系缺 verify-archive.sh / verify-code-review.sh / role-guard.sh | ✅ 新增 3 个脚本未同步到设计文档 | P1 |

### 审查报告中不成立/降级的问题

| 原编号 | 审查报告说法 | 核实结论 | 处置 |
|--------|-------------|----------|------|
| 原 P0-4/P0-5 | verify.sh 546 行、verify-qa.sh 504 行"超 500 行拆分阈值" | design.md §6 阈值是 skill 文件 350 行，不适用于脚本。无脚本行数规则 | 降为 P2 建议，不纳入本 CR |
| 原 P1-5 | design.md §7 "三层"与 CLAUDE.md "五层"矛盾 | "三层质量注入"是架构分层概念，"五层校验"是 5 个脚本。不同维度，无矛盾 | 与 P1-5 合并（§9 脚本清单过时是真问题） |
| 原 P1-6 | propose 产出结构协商缺快速路径 | 保守协商是有意设计，防止结构不合理。功能建议非缺陷 | 不纳入 |
| 原 P1-7 | workflows/ JS 文件缺头部注释 | 核实发现所有 JS 文件已有完整注释 | ❌ 不成立 |

---

## 需求定义

### 功能需求

| ID | 需求 | 优先级 | 关联 |
|----|------|--------|------|
| F-1 | 删除 mh-clarify.md:56 "full 模式跳过 SR" 的描述 | P0 | P0-1 |
| F-2 | package.json version 更新为 "0.8.0" | P0 | P0-2 |
| F-3 | source-of-truth.md 第 24-26 行引用精确化为 `skills/mh-apply-repair.md` | P1 | P1-1 |
| F-4 | state-template.md 新增 `ppt_design_mode` 字段（枚举：system / creative） | P1 | P1-2 |
| F-5 | agents/sa.md 输出清单补充 `sa/verify-strategy.md`，注明格式和触发条件 | P1 | P1-3 |
| F-6 | 明确 te/audit-dimensions.md 定位——建议废弃，由 code-review-rules.js 取代；从 mh-propose.md 移除该引用 | P1 | P1-4 |
| F-7 | design.md §9 工具体系补充 verify-archive.sh / verify-code-review.sh / role-guard.sh | P1 | P1-5 |

### 非功能需求

| ID | 需求 | 优先级 |
|----|------|--------|
| NF-1 | 所有修改不引入新的交叉引用断裂 | P0 |
| NF-2 | 修改后现有测试套件全量通过 | P0 |

---

## 影响范围分析

| 文件 | 变更类型 | 风险 |
|------|----------|------|
| skills/mh-clarify.md | 删除 1 行 | 无 |
| package.json | 修改 version 字段 | 无 |
| docs/source-of-truth.md | 修改 3 行引用路径 | 无 |
| templates/state-template.md | 新增 1 字段定义 | 无 |
| agents/sa.md | 新增产出格式段落 | 低 |
| skills/mh-propose.md | 移除 audit-dimensions.md 引用 | 低——需确认无其他依赖 |
| docs/design.md | §9 新增 3 行 | 无 |

---

## 实施策略

### Phase 1: P0 矛盾消除（5 分钟）

- F-1: 删除 mh-clarify.md:56
- F-2: package.json version → "0.8.0"

### Phase 2: P1 引用修复 + 文档同步（15 分钟）

- F-3: source-of-truth.md 引用精确化
- F-4: state-template.md 补字段
- F-5: agents/sa.md 补产出定义
- F-6: 废弃 audit-dimensions.md 引用
- F-7: design.md §9 补脚本

---

## 验收标准

- [ ] `grep -n "跳过所有人工审核" skills/mh-clarify.md` 返回空
- [ ] `node -e "console.log(require('./package.json').version)"` 输出 `0.8.0`
- [ ] source-of-truth.md 修复相关条目引用 `mh-apply-repair.md`
- [ ] `grep "ppt_design_mode" templates/state-template.md` 返回非空
- [ ] `grep "verify-strategy" agents/sa.md` 返回非空
- [ ] `grep "audit-dimensions" skills/mh-propose.md` 返回空
- [ ] `grep "verify-archive.sh\|verify-code-review.sh\|role-guard.sh" docs/design.md` 三个均命中
- [ ] `npm test` 退出码 0

---

## 附录：未纳入但建议后续关注

| 项目 | 建议 | 触发条件 |
|------|------|----------|
| verify.sh 546 行 / verify-qa.sh 504 行 | 按维度拆分为子模块 | 当新增规则导致任一文件超 700 行时执行 |
| mh-propose.md 产出结构协商 | 为 standard 模式增加"PM 自决"路径 | 用户反馈协商环节过重时执行 |
| CLAUDE.md §4 规则数量膨胀（12 条） | 分组或提取子文件 | 超过 15 条时执行 |

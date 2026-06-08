# CR-001: propose 阶段增加验证规划 + 归档硬校验 + handoff 质量强化

> 来源: REQ001 实战复盘（docs/improvement-report-REQ001.md）
> 日期: 2026-06-07
> 状态: 待实施

---

## 变更背景

REQ001（PSDT-Agent Web UI，full 模式，30 Tasks）执行过程中暴露三大系统性效率瓶颈：

1. **SR4 被驳回 16 次** — 归档质量问题、代码修复泄露到归档阶段、PM 角色越权、文件方向混乱
2. **SA 设计 9 轮返工** — handoff 缺乏产出深度期望、质量标杆、目录结构预定义；PM 裁剪用户反馈
3. **SR2 后 5 轮修复** — TE 审计维度不全（逐轮发现新问题）、DE 无设计对标清单

## 变更目标

- SR4 驳回从 16 次降至 2-3 次（-85%）
- SA 设计轮次从 9 轮降至 3-4 轮（-55%）
- 总耗时从 ~6h 降至 ~2.5h（-58%）
- CLAUDE.md 膨胀控制在 +2 行

## 设计原则

1. **脚本硬约束 > 模板约束 > 自然语言软约束**
2. **框架提供机制，不写死策略** — 项目专属规则在 propose 阶段由角色生成
3. **技术栈解耦** — 所有改进适用于任意 output_type 和 tech_stack

---

## 变更清单

### CR-001-A: propose 阶段新增验证规划产出

**影响文件:** `skills/mh-propose.md`

**变更内容:**

SA 在 standard/full 模式下额外产出：
- `deliverables/{REQ-ID}/.archiveignore` — 项目专属的归档排除列表（构建产物、过程文件、测试端口等）
- `deliverables/{REQ-ID}/sa/verify-strategy.md` — Batch 级验证命令 + 降级方案 + 集成点列表

TE 在 standard/full 模式下额外产出：
- `deliverables/{REQ-ID}/te/audit-dimensions.md` — 本项目 SR2/SR3 应覆盖的审计维度清单

plan-action.md 格式增加可选节：
- `## 集成点` — 跨 Task 调用链

**理由:** 不同项目的构建产物、审计维度、验证方式完全不同，不能在框架中写死。由角色在 propose 阶段根据项目实际情况规划。

---

### CR-001-B: 新增 verify-archive.sh 归档校验脚本

**影响文件:** `scripts/verify-archive.sh`（新增）

**变更内容:**

通用检查（写入脚本）：
- 文件重复检测（同名文件不应同时存在于 deliverables 顶层和 output/）
- 更新方向检测（output 文件不应比 deliverables 源文件时间戳更新）

项目专属检查（从 `.archiveignore` 读取）：
- 禁止项模式列表（如 node_modules、.venv、dist 等，由 SA 在 propose 阶段定义）

**理由:** 归档质量问题导致 5 次 SR4 驳回，全部可通过脚本自动拦截。

---

### CR-001-C: CLAUDE.md 最小化修改

**影响文件:** `CLAUDE.md`

**变更内容（仅 2 行）:**
- §4 自检纪律：将"三层校验"改为"四层校验"，增加 verify-archive.sh
- §4 自检纪律追加：SR4 发现代码逻辑缺陷时，退回 apply 阶段走 repair flow

**理由:** SR4 内循环修复代码导致 7 次驳回，明确 SR4 职责边界为"归档完整性确认"。

---

### CR-001-D: handoff 模板增加可选节

**影响文件:** `templates/handoff-template.md`

**新增可选节:**
- `## 产出规格` — depth_level / quality_anchor / structure_skeleton（PM 为 SA 填写）
- `## 用户反馈原文` — 返工轮次时 PM 粘贴原文（禁止裁剪）
- `## 设计对标清单` — PM 为 DE 填写必须实现的接口/调用链/约束

**理由:** 消除"做到什么程度"歧义（SA 9 轮根因）+ 消除信息损耗（PM 裁剪反馈）+ 消除设计偏差（DE 5 P0 根因）。

---

### CR-001-E: PM 角色边界强化

**影响文件:** `agents/pm.md`

**变更内容:** 禁止事项追加一条：
- 用户说"安排XX做"时必须通过 handoff 派发对应角色，禁止 PM 自行顶替执行

**理由:** CP-7 PM 越权导致 SR4 驳回，现有"禁止参与编码实现"表述不够具体。

---

### CR-001-F: verify-qa.sh 增加通用检查

**影响文件:** `scripts/verify-qa.sh`

**新增检查项:**
- QA-8: 返工轮次(R2+)的 handoff 须包含用户反馈内容
- QA-9: repair_round > 0 时须有对应 de/code-report-r{N}.md
- QA-10: TE 审计报告须覆盖 audit-dimensions.md 中的所有维度

**理由:** 全部为通用逻辑（检查文件/关键词是否存在），不含技术栈细节。

---

### CR-001-G: verify.sh SA 多文件支持

**影响文件:** `scripts/verify.sh`

**变更内容:** B 类检查 SA 产出时，支持 design.md（单文件）或 overview.md（多文件）两种模式。

**理由:** REQ001 实际产出为 12 文件结构，当前脚本只检查 design.md 会误报 FAIL。

---

### CR-001-H: mh-archive.md SR4 职责明确 + ARC-5 单一真相源

**影响文件:** `skills/mh-archive.md`

**变更内容:**
- SR4 full 模式增加：verify-archive.sh 作为前置自动检查
- SR4 驳回处理增加：如问题属于代码逻辑缺陷，退回 apply 阶段
- ARC-5：metrics 直接写入最终归档位置，不在 deliverables 顶层创建副本

**理由:** 消除 SR4 内代码修复循环 + 消除文件重复导致的权威性混乱。

---

## 不做的事

- 不在框架中写死任何技术栈相关的检查规则
- 不大幅膨胀 CLAUDE.md（仅 +2 行）
- 不修改角色间通信协议（handoff 格式向后兼容）
- 不新增角色或流程阶段

## 验证方式

- `scripts/verify-archive.sh` 在 mh-out 归档目录上执行，确认通用检查生效
- 现有 verify.sh / verify-qa.sh 向后兼容（无 .archiveignore 时跳过项目专属检查）

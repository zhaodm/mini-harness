# CR-002: Token 消耗优化

> 来源: REQ001 实战复盘（docs/retrospectives/improvement-report-REQ001.md）
> 日期: 2026-06-07
> 状态: 实施中

---

## 变更背景

REQ001（PSDT-Agent Web UI，full 模式，30 Tasks）执行消耗了巨量 token。通过分析执行过程，定位出六大消耗热点：

| 热点 | 估算占比 | 根因 |
|------|---------|------|
| SA 设计 9 轮重写 | ~40-50% | 每轮产出 ~6000 行，结构翻来覆去（拆→分层→合回来） |
| SR4 被打回 16 次 | ~20-25% | 代码写完 177 文件后才在归档阶段发现集成问题 |
| DE 30 任务各自重读 SA 文档 | ~15% | 每个任务读 2-4 个模块文档（400-700 行/个） |
| 参考文档被 SA 重复读 9 次 | ~10% | 无摘要机制，每轮全量重读 11+ 个文件 |
| SR2 六个并行 Agent 审计 | ~5% | 80% 的检查是"grep X 是否存在"级别的机械操作 |

## 变更目标

- 总 token 消耗降低 50-60%
- SA 轮次从 9 降至 4（-55%）
- SR4 驳回从 16 降至 2-3（-85%）
- DE 上下文读取量降低 85%
- CLAUDE.md 不新增任何行

## 设计原则

1. **框架提供机制，不写死策略** — 所有优化通过流程规则和模板约束实现
2. **脚本硬约束 > 模板约束 > 自然语言软约束**
3. **技术栈解耦** — 适用于任意 output_type 和 tech_stack
4. **向后兼容** — 所有新增节为可选，不破坏现有 handoff 协议

---

## 变更清单

### CR-002-A: SA 轮次结构预协商

**影响文件:** `skills/mh-propose.md`, `templates/handoff-template.md`, `agents/pm.md`

**问题:** SA 9 轮中 3 轮在改文件组织结构，内容本身没大变化。PM handoff 缺乏对产出结构的预定义。

**变更:**
1. `templates/handoff-template.md` — `产出规格` 节增加注释：structure_skeleton 为 SA/UX 任务必填项
2. `skills/mh-propose.md` — SA handoff 派发前，PM 必须在 structure_skeleton 中明确设计文档的文件/章节结构
3. `agents/pm.md` — SA 产出验收增加：产出文件/章节结构须符合 structure_skeleton 预定义

**预期效果:** 消除结构翻烧饼，SA 轮次 9→4

---

### CR-002-B: DE 任务批量派发 + 接口契约摘要

**影响文件:** `agents/sa.md`, `skills/mh-apply-standard.md`, `templates/handoff-template.md`

**问题:** 30 个 DE 任务逐个派发，每个都要读完整设计文档。巨量重复读取。

**变更:**
1. `agents/sa.md` — 输出格式增加 `## 6. 接口契约摘要`：仅含类型定义、函数签名、模块间调用关系（≤200 行）
2. `skills/mh-apply-standard.md` — 同 Batch 内无共享依赖的 Task 允许合并派发（上限 3 Task/handoff）
3. `templates/handoff-template.md` — 新增可选节 `## 上下文裁剪指示`：PM 标注白名单中 DE 需精读的段落范围

**预期效果:** DE 读取量从 ~2000 行/任务降至 ~300 行；spawn 次数从 30 降至 ~15

---

### CR-002-C: apply 阶段前置集成检查

**影响文件:** `skills/mh-apply-standard.md`, `agents/de.md`

**问题:** SR4 的 16 次打回中大部分是可自动检测的集成问题，在 archive 阶段才发现太晚。

**变更:**
1. `skills/mh-apply-standard.md` — 所有 Batch 完成后、SR2 之前增加 Step 1.5 集成预检：读取 sa/verify-strategy.md 中的集成检查命令并执行
2. `agents/de.md` — 思考框架增加：修复轮次 >1 时检查 verify-strategy.md 集成点

**预期效果:** 集成问题在 apply 阶段拦截，SR4 驳回 16→2-3

---

### CR-002-D: Handoff 行数上限 + 增量传递

**影响文件:** `templates/handoff-template.md`, `agents/pm.md`

**问题:** R8 handoff 有 271 行（内嵌完整对比分析），累积上下文越来越大。

**变更:**
1. `templates/handoff-template.md` — 协议规则增加：任务描述+约束+轮次信息总计不超 150 行；R2+ 仅传递增量
2. `agents/pm.md` — R2+ handoff 仅包含本轮增量要求 + 失败原因 + 修正方向，禁止复制前轮全文

**预期效果:** 单 handoff 从 ~270 行降至 ≤150 行；多轮 token 累积下降 ~40%

---

### CR-002-E: 参考文档摘要化 + 按需查阅分级

**影响文件:** `skills/mh-clarify.md`, `skills/mh-propose.md`

**问题:** reference/ 下 11+ 个文件在 SA 的 9 轮中被反复全量读取（~12000 行 × 9 轮）。

**变更:**
1. `skills/mh-clarify.md` — reference/ 含 3+ 文件或 >1000 行时，PM 在 proposal.md 附加参考摘要（每文件 ≤5 行）
2. `skills/mh-propose.md` — SA 白名单支持 `[SUMMARY]`/`[FULL]` 访问级别标注

**预期效果:** 参考文档读取从 ~12000×9 降至 ~500×9 + 按需精读 1-2 次

---

### CR-002-F: TE 审计脚本化预检

**影响文件:** `agents/sa.md`, `skills/mh-apply-standard.md`

**问题:** SR2 派 6 个并行 Agent 做一致性审计，80% 是 grep 级别的机械操作。

**变更:**
1. `agents/sa.md` — 输出格式增加 `## 7. 机器可检查清单`（可选）：`CHECK: {pattern} IN {glob} — {desc}`
2. `skills/mh-apply-standard.md` — SR2 前 PM 先执行 grep 检查，仅 FAIL 项派发 TE Agent

**预期效果:** TE Agent 数量从 6 降至 2-3，节省 ~50% 审计 token

---

### CR-002-G: verify-qa.sh 增加 handoff 行数检查

**影响文件:** `scripts/verify-qa.sh`

**变更:** 新增 QA-11：handoffs/ 目录中 >200 行 WARN，>300 行 ERROR

**预期效果:** 硬约束兜底，防止 handoff 膨胀

---

## 不做的事

- 不修改四阶段状态机
- 不新增角色
- 不写死技术栈相关规则
- 不膨胀 CLAUDE.md
- 不破坏 handoff 协议向后兼容性

## 实施顺序

1. CR-002-D — Handoff 行数限制（模板 + pm.md）
2. CR-002-A — SA 结构预协商（propose + handoff + pm.md）
3. CR-002-G — verify-qa.sh QA-11（脚本兜底）
4. CR-002-C — apply 集成预检（apply-standard + de.md）
5. CR-002-B — DE 批量派发 + 接口摘要（sa.md + apply-standard + handoff）
6. CR-002-E — 参考文档摘要化（clarify + propose）
7. CR-002-F — TE 审计脚本化（sa.md + apply-standard）

## 验证方式

- verify-qa.sh QA-11 在 mh-out 的 handoffs/ 上执行，确认能检测超长 handoff
- 所有修改后的 skill/agent/template 文件通过人工 review 确认逻辑一致性
- 现有 verify.sh / verify-qa.sh / verify-archive.sh 向后兼容（新增节均为可选）

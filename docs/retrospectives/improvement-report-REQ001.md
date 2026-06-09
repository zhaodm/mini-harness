# 框架改进报告：基于 REQ001 实战案例分析

> 基于 PSDT-Agent Web UI（REQ001）完整执行案例的复盘，识别 mini-harness 框架的系统性改进机会。
> 数据来源: ~/Codes/temp/mh-out/deliverables/REQ001/
> 日期: 2026-06-07

---

## 执行概况

| 指标 | 数据 |
|------|------|
| 需求规模 | 39 FR + 12 NFR，30 Tasks，4 Batches |
| 执行模式 | full |
| 总耗时 | ~6 小时（跨多个会话） |
| SA 设计轮次 | 9 轮（理想 2-3 轮） |
| SR4 驳回次数 | **16 次**（最严重的效率瓶颈） |
| 修复循环 | 5 轮（R2→R5，全部发生在 SR4 阶段内） |
| dev-test 执行率 | 0%（全部 SKIP） |
| 最终结果 | 通过（177 文件，集成 27/27，冒烟 22/22） |

---

## 改进方法论

### 原则一：脚本硬约束 > 模板约束 > 自然语言软约束

| 层级 | 载体 | 上下文成本 | 执行力 |
|------|------|-----------|--------|
| L1 脚本 | scripts/verify-*.sh | 零 | 硬（exit code） |
| L2 模板 | templates/*.md | 按需读取 | 中（格式引导） |
| L3 Skill | skills/*.md | 按需读取 | 中（流程步骤） |
| L4 自然语言 | CLAUDE.md / agents/*.md | 常驻 | 软（可违反） |

### 原则二：框架提供机制，不写死策略

REQ001 是 TypeScript Web App，但框架同样服务于 Python CLI、PPT、Go 后端等完全不同的技术栈。改进方案必须：
- **通用检查**（文件重复、更新方向）→ 写入脚本
- **项目专属检查**（构建产物名、端口号、审计维度）→ 在 propose 阶段由角色生成，写入项目配置文件

---

## 一、SR4 归档阶段（16 次驳回）— 根因与机制性改进

### 1.1 归档规则缺失 — 增加 propose 阶段"归档规划"步骤

**现象:** node_modules 混入、过程文件混入、同步遗漏（CP-3，3 次驳回）

**根因:** 框架没有要求项目在开始前规划"什么该归档、什么不该归档"。不同项目的构建产物完全不同（node_modules vs .venv vs target/），不能写死。

**方案:** propose 阶段新增一个步骤，由 SA 输出项目专属的 `.archiveignore`：

`skills/mh-propose.md` 中 SA 产出追加：
```
SA 额外产出（写入 deliverables/{REQ-ID}/.archiveignore）：
- 构建产物排除列表（基于 tech_stack 判断）
- 过程文件模式列表（如 *-self-assessment.md）
- 测试端口/进程标识（如有 E2E 测试场景）
```

`scripts/verify-archive.sh` 改为**读取项目配置**：
```bash
#!/bin/bash
# verify-archive.sh — 归档质量校验（读取项目专属配置）
ERRORS=0
REQ_DIR="deliverables/${1:-$(grep '^req_id:' deliverables/.state.md | awk '{print $2}')}"
OUTPUT_DIR="output"
IGNORE_FILE="$REQ_DIR/.archiveignore"

# 1. 基于 .archiveignore 检查禁止项（项目专属）
if [ -f "$IGNORE_FILE" ]; then
  while IFS= read -r pattern; do
    [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
    if find "$OUTPUT_DIR" -name "$pattern" 2>/dev/null | grep -q .; then
      echo "FAIL: output/ 包含 .archiveignore 中的禁止项: $pattern"
      ERRORS=$((ERRORS + 1))
    fi
  done < "$IGNORE_FILE"
else
  echo "WARN: .archiveignore 不存在，跳过项目专属检查"
fi

# 2. 通用检查：文件重复（同名文件不应同时存在于顶层和 output/）
for f in metrics.md lessons.md; do
  if [ -f "$REQ_DIR/$f" ] && find "$OUTPUT_DIR" -name "$f" 2>/dev/null | grep -q .; then
    echo "FAIL: $f 同时存在于 $REQ_DIR/ 顶层和 output/（违反单一真相源）"
    ERRORS=$((ERRORS + 1))
  fi
done

# 3. 通用检查：更新方向（output 不应比 deliverables 源更新）
while IFS= read -r out_file; do
  rel_path="${out_file#$OUTPUT_DIR/}"
  src_file="$REQ_DIR/output/$rel_path"
  if [ -f "$src_file" ] && [ "$out_file" -nt "$src_file" ]; then
    echo "WARN: $out_file 比源文件更新（可能直接编辑了归档目录）"
  fi
done < <(find "$OUTPUT_DIR" -type f 2>/dev/null | head -100)

exit $((ERRORS > 0 ? 1 : 0))
```

**脚本中只有通用逻辑（文件重复、方向检测），项目专属规则从 .archiveignore 配置文件读取。**

### 1.2 代码审计修复泄露到 SR4 — L3 Skill 修改

**现象:** R2-R5 共 19 项代码修复在 SR4 内完成（7 次驳回）

**方案:** `skills/mh-archive.md` SR4 步骤增加前置条件：
```
SR4 检查范围仅限归档完整性，不含代码逻辑审计。
如 SR4 阶段发现代码缺陷 → 退回 apply 阶段走 repair flow。
```

这是通用规则，与技术栈无关。

### 1.3 PM 角色越权 — L4（仅 agents/pm.md 一行）

**现象:** PM 直接做技术裁决和代码修改（CP-7）

**方案:** `agents/pm.md` 增加：
```
- PM 禁止执行技术分析/代码修改，用户说"安排XX做"必须派发 handoff
```

不可脚本化的行为约束，只能用自然语言。只加一行。

### 1.4 deliverables 文件重复 — L1 脚本（已在 1.1 中覆盖）

verify-archive.sh 第 2 项通用检查已处理。同时 `skills/mh-archive.md` 修改 ARC-5/ARC-6：metrics/lessons 直接写入 output/ 目标路径，不在 deliverables 顶层创建副本。

### 1.5 文件更新方向 — L1 脚本（已在 1.1 中覆盖）

verify-archive.sh 第 3 项通用检查已处理。

---

## 二、Handoff 质量问题（SA 9 轮返工）

### 2.1 产出深度模糊 + 质量标杆缺失 — L2 模板

**现象:** SA 不知道做到什么程度，无对标参考（ROOT-1）

**方案:** `templates/handoff-template.md` 增加：
```markdown
## 产出规格（PM 必填）

- depth_level: {checklist | summary | full-architecture | code-level}
- quality_anchor: {标杆文件路径 | N/A}
- structure_skeleton: |
    {预期目录/文件结构，大型产出时填写}
```

通用字段，不含技术栈细节。PM 按项目实际情况填写。

### 2.2 PM 信息裁剪 — L2 模板 + L1 脚本

**现象:** PM 摘要简化用户反馈（ROOT-1）

**方案:**
- handoff-template.md 增加 `## 用户反馈原文` 节
- verify-qa.sh 增加通用检查：R2+ 轮次的 handoff 必须包含"用户反馈"关键词

```bash
# QA-8: 返工轮次 handoff 须含用户反馈
check_handoff_feedback() {
  for hf in "$REQ_DIR"/handoffs/*-R[2-9]*.md; do
    [ -f "$hf" ] || continue
    if ! grep -q "用户反馈\|用户原文\|user_feedback" "$hf" 2>/dev/null; then
      echo "WARN: $(basename $hf) 为返工轮次但无用户反馈原文"
      WARNS=$((WARNS + 1))
    fi
  done
}
```

### 2.3 大型产出结构返工 — L2 模板（已在 2.1 覆盖）

structure_skeleton 字段即可解决。PM 首轮指定目录结构。

---

## 三、TE 审计不全 — propose 阶段生成项目专属审计清单

### 3.1 审计维度与技术栈强相关，不能写死

**现象:** 每轮审计只覆盖部分维度（接口→协议→权限→类型→配置→ESM），逐轮发现新问题

**根因:** 框架没有要求在 propose 阶段规划"本项目应该审什么"。一个 Web App 需要审接口契约/WS 协议/权限，一个 PPT 项目需要审字号/导航/布局，一个 CLI 工具需要审参数解析/退出码/错误信息。

**方案:** propose 阶段新增步骤，由 TE 输出项目专属的审计清单：

`skills/mh-propose.md` 中 TE 产出追加：
```
TE 额外产出（与 testcases.md 一同输出）：
- deliverables/{REQ-ID}/te/audit-dimensions.md
- 内容：本项目 SR2/SR3 应覆盖的审计维度列表
- 每个维度含：检查方法、典型问题模式、PASS/FAIL 判定标准
- 基于 output_type + tech_stack + 设计文档 推导

TE SR2/SR3 审计时，必须逐行覆盖 audit-dimensions.md，未覆盖视为审计不完整。
```

verify-qa.sh 增加通用检查：
```bash
# QA-10: SR2/SR3 审计报告须覆盖所有维度
check_audit_coverage() {
  local dims="$REQ_DIR/te/audit-dimensions.md"
  local report="$REQ_DIR/te/final-test-report.md"
  [ -f "$dims" ] && [ -f "$report" ] || return

  local dim_count=$(grep -c "^|.*|.*|" "$dims" 2>/dev/null || echo 0)
  dim_count=$((dim_count - 1))  # 去掉表头
  local covered=$(grep -c "✅\|❌\|PASS\|FAIL" "$report" 2>/dev/null || echo 0)

  if [ "$covered" -lt "$dim_count" ]; then
    echo "WARN: audit-dimensions 有 $dim_count 个维度，报告仅覆盖 $covered 项"
    WARNS=$((WARNS + 1))
  fi
}
```

### 3.2 DE 设计对标清单 — L2 模板（PM 按项目填写）

**方案:** handoff-template.md 增加可选节：
```markdown
## 设计对标清单（PM 按设计文档为 DE 填写，DE 完成后逐项 ✓）

### 必须实现的接口/方法
- [ ] {从设计文档摘录}

### 集成调用链路
- [ ] {A.method() → B.method()}

### 关键约束
- [ ] {从设计文档摘录的常量/配置/安全要求}
```

模板只定义结构，具体内容由 PM 从 SA 设计文档中摘录填入。不写死任何技术细节。

---

## 四、DE 开发阶段

### 4.1 dev-test 全跳过 — propose 阶段规划验证策略

**现象:** 30 个 Task 全部 `dev-test: SKIP`

**方案:** 框架已有 dev-test skill 按 tech_stack 路由，问题在于"环境不可用时的降级策略"未定义。

`skills/mh-propose.md` 中 SA 产出追加：
```
SA 额外产出（写入 plan-action.md 或 deliverables/{REQ-ID}/sa/verify-strategy.md）：
- Batch 级验证命令（基于 tech_stack，如 tsc --noEmit / python -m py_compile / go build）
- 环境不可用时的降级方案
- 集成点列表（跨 Task 调用链，标注哪些 Task 完成后需要联调验证）
```

PM 在每个 Batch 完成后执行 SA 规划的验证命令。不在框架脚本中写死 `tsc` 或 `npx`。

### 4.2 跨模块集成遗漏 — L2 模板

**方案:** plan-action.md 模板增加"集成点"节：
```markdown
## 集成点（SA 填写，跨 Task 调用链）

- INT-{N}: Task-{A}({模块}) ↔ Task-{B}({模块}): {调用关系描述}
```

通用结构，具体内容由 SA 按项目填写。

### 4.3 前后端接口契约不一致 — 仅适用于含前后端的项目

**方案:** 这是 web-app output_type 的专属问题。在 SA 设计阶段，如 output_type=web-app 且有前后端分离架构，SA 应输出接口契约表。

不写入框架通用规则，而是作为 web-app 类型的 output-guide 建议（已有 `templates/output-guides/web-app.md`，在其中追加）。

---

## 五、验证体系

### 5.1 verify.sh — SA 多文件支持（通用改进）

```bash
# 替换 B 类检查中的 SA 部分
if [ "$mode" != "fast" ]; then
  if [ -s "$REQ_DIR/sa/design.md" ] || [ -s "$REQ_DIR/sa/overview.md" ]; then
    echo "PASS: SA 设计文档存在"
  else
    echo "FAIL: sa/ 目录缺少 design.md 或 overview.md"
    ERRORS=$((ERRORS + 1))
  fi
fi
```

### 5.2 verify-qa.sh — 增加通用检查项

- QA-8: 返工轮次 handoff 须含用户反馈（见 2.2）
- QA-9: repair_round > 0 时须有对应 code-report-r{N}.md
- QA-10: SR2/SR3 审计覆盖度检查（见 3.1）

这些检查都是通用逻辑（检查文件是否存在、关键词是否包含），不含技术栈细节。

### 5.3 verify-archive.sh — 通用 + 项目配置

通用部分：文件重复检测、更新方向检测（见 1.1）
项目部分：从 `.archiveignore` 读取禁止项列表

---

## 六、CLAUDE.md 变更（最小化）

仅增加 **2 行**：
```markdown
## 4. 自检纪律
（追加）
- SR4 发现代码逻辑缺陷时，退回 apply 阶段走 repair flow，禁止在 SR4 内循环修复
- 交付判定四层校验：verify.sh + verify-qa.sh + verify-ppt.sh + verify-archive.sh
```

---

## 七、propose 阶段新增产出物汇总

核心思路：**把项目专属的验证规则前置到 propose 阶段设计**，而非在框架中写死。

| 产出物 | 产出角色 | 内容 | 消费者 |
|--------|---------|------|--------|
| `.archiveignore` | SA | 构建产物排除列表 + 过程文件模式 | verify-archive.sh |
| `te/audit-dimensions.md` | TE | 本项目审计维度 + 检查方法 + 判定标准 | TE SR2/SR3 审计时 |
| `sa/verify-strategy.md` | SA | Batch 验证命令 + 降级方案 + 集成点 | PM Batch 边界 |
| plan-action.md 集成点节 | SA | 跨 Task 调用链 | DE handoff |

这些产出物在 propose 阶段生成，与 testcases.md、design.md 同级别。框架只定义"必须产出这些文件"，不定义文件内容（内容由角色根据项目实际情况填写）。

---

## 八、改进落地清单

| 优先级 | 改进项 | 载体 | 通用性 | 预期效果 |
|--------|--------|------|--------|---------|
| **P0** | verify-archive.sh（通用检查 + 读取 .archiveignore） | L1 脚本 | ✅ 全通用 | SR4 -5 次 |
| **P0** | SR4 不修代码，退回 apply（CLAUDE.md 1 行） | L4 | ✅ 全通用 | SR4 -7 次 |
| **P0** | propose 阶段输出 .archiveignore | L3 Skill | ✅ 机制通用 | 归档质量 |
| **P0** | handoff-template 增加 depth_level/quality_anchor/skeleton | L2 模板 | ✅ 全通用 | SA -4 轮 |
| **P1** | propose 阶段 TE 输出 audit-dimensions.md | L3 Skill | ✅ 机制通用 | SR4 -3 次 |
| **P1** | propose 阶段 SA 输出 verify-strategy.md | L3 Skill | ✅ 机制通用 | 修复 -3 轮 |
| **P1** | handoff-template 增加用户反馈原文节 | L2 模板 | ✅ 全通用 | SA -3 轮 |
| **P1** | handoff-template 增加设计对标清单节 | L2 模板 | ✅ 全通用 | SR2 P0 -5 项 |
| **P1** | plan-action.md 增加集成点节 | L2 模板 | ✅ 全通用 | 集成 bug |
| **P2** | verify-qa.sh QA-8/9/10（通用检查） | L1 脚本 | ✅ 全通用 | 追溯性 |
| **P2** | verify.sh SA 多文件支持 | L1 脚本 | ✅ 全通用 | 兼容性 |
| **P2** | PM 禁止技术越权（agents/pm.md 一行） | L4 | ✅ 全通用 | CP-7 类 |
| **P2** | ARC-5/6 单一真相源 | L3 Skill | ✅ 全通用 | 文件重复 |

**总计：CLAUDE.md +2行，脚本 +1文件，模板修改 1文件，Skill 修改 2文件。所有改进与技术栈解耦。**

---

## 九、量化预期

| 指标 | 当前 | 预期 | 改善幅度 |
|------|------|------|---------|
| SR4 驳回次数 | 16 次 | 2-3 次 | **-85%** |
| SA 设计轮次 | 9 轮 | 3-4 轮 | -55% |
| SR2 后修复轮次 | 5 轮 | 1 轮 | -80% |
| 总耗时 | ~6 小时 | ~2.5 小时 | -58% |
| CLAUDE.md 膨胀 | — | +2 行 | 几乎为零 |
| 技术栈耦合度 | — | 零 | 可用于任何项目类型 |

---

## 附录 A：SR4 驳回分类与防御映射

```
[归档质量] 5 次 → verify-archive.sh + .archiveignore
  R01: 构建产物混入     → .archiveignore 列出（SA propose 阶段生成）
  R02: 修复未同步       → verify-archive.sh 方向检测（通用）
  R03: 过程文件混入     → .archiveignore 列出（SA propose 阶段生成）
  R04: rsync 误删       → 归档同步脚本化（SA verify-strategy.md 定义同步命令）
  R06: 残留进程         → SA verify-strategy.md 定义测试端口和清理方式

[代码修复] 7 次 → "SR4 不修代码"规则
  R05/R08/R11/R13/R14/R15/R16 → 全部退回 apply

[流程纪律] 3 次 → 通用脚本 + 自然语言
  R07: 更新方向错误     → verify-archive.sh 时间戳检测（通用）
  R09: PM 越权          → agents/pm.md 铁律
  R10: 角色目录未更新   → verify-qa.sh QA-9 检测 repair report 存在性（通用）

[文档] 1 次
  R12: CHANGELOG 缺失   → .archiveignore 的反面：SA 在 verify-strategy.md 中列出必要交付文件
```

## 附录 B：执行全景时间线

```
clarify (30min)
  → BA R1 失败（读了设计文档）→ R2 通过
propose (3.5h)  ← 改进后此阶段增加 .archiveignore + audit-dimensions + verify-strategy 产出
  → SA R1-R9 → TE testcases R1 通过 → SR1 通过
apply (1.5h)
  → DE Batch 1-4 → SR2 审计（按 audit-dimensions 全覆盖）→ SR3 通过
archive + SR4
  → verify-archive.sh 自动拦截归档问题
  → 代码缺陷退回 apply（不在 SR4 内循环）
  → SR4 仅确认归档完整性 → 通过
```

---

## 附录 C：执行层问题（v0.6.0 优化发现）

> 以下问题来自同一次 REQ001 实战的执行层分析，聚焦 SubAgent 行为、日志落盘、归档细节等"设计正确但执行失败"的问题。

### P0-1: Handoff 完成回报机制失效

- **现象:** 所有 5 个 handoff 的完成回报区域全部为空（status/output_files/read_files/summary 均未填写）
- **根因:** SubAgent 倾向于"完成任务就结束"，而非"回到协议文件中做记录"
- **改善方向:** 三层防御——模板强制提示 + PM 代填容错 + verify.sh 检测

### P0-2: process.log 仅 2 行

- **现象:** 整个 43 分钟执行过程（14 Task、4 Batch、4 SR Gate），process.log 只记录了 INIT-1 的 2 行心跳
- **根因:** logging-standard.md 只是描述性规范，PM 将心跳打印到 stdout 但没有执行写入动作
- **改善方向:** 强制落盘规则 + verify.sh 行数下限检查

### P1-1: SR3 覆盖率标准与实际执行不一致

- **现象:** SR3 通过标准写死"覆盖率 = 100%"，但实际以 93% 覆盖率通过（48/50 FR + 5/7 NFR）
- **根因:** 过于刚性的标准在实际中必然被绕过
- **改善方向:** 改为"≥ 95% + 未覆盖项有降级机制"

### P1-2: .venv 被归档到 output/

- **现象:** deliverables/REQ001/output/ 下包含完整的 .venv/ 目录，产出体积从 ~8000 行膨胀到 47MB
- **根因:** mh-archive.md ARC-3 只说"直接复制全部文件"，没有排除规则
- **改善方向:** 归档排除规则 + .archiveignore 机制（已在主报告 §1.1 设计）

### P1-3: spec/ 归档不完整

- **现象:** spec/ 下只有 _templates/，没有 requirement-spec.md 和 design.md
- **根因:** ARC-1/ARC-2 归档步骤可能没有正确执行
- **改善方向:** verify.sh 增加 spec/ 必要文件存在性检查

### P2-1: Agent 超时无处理规则

- **现象:** 3/14 任务超时（21%），其中 T-05 需重试，T-03/T-09 代码已完整无需重试
- **根因:** 框架没有定义"超时但代码完整"的处理规则
- **改善方向:** 超时 + 产出完整 = 成功，PM 代填 code-report

### P2-2: 多 Task 合并 code-report

- **现象:** T-12/T-13/T-14 合并为一个 code-report-t12-13-14.md，违反逐 Task 独立约定
- **改善方向:** 明确规则——每个 Task 独立 code-report，禁止合并

---

## 附录 D：Metrics 数据驱动优化设计

### 为什么需要 metrics

框架前五轮优化（v0.5.0-v0.5.4）全部是静态分析——读代码、找冗余、猜问题。两个根本局限：
1. 无法发现"设计正确但执行失败"的问题
2. 边际收益递减（到 v0.5.3 改动量已降到 50 行级别）

metrics.md 将优化模式从"读代码猜问题"转向"跑需求看数据"。

### 数据如何驱动优化

- **纵向（单次执行）:** metrics.md → 发现异常值 → 根因分析 → 定向修复
- **横向（多次对比）:** metrics[REQ001] vs metrics[REQ002] → 发现趋势 → 结构性优化

### REQ001 数据总结

| 维度 | 数据 | 结论 |
|------|------|------|
| 端到端成功率 | 100% | 框架可用 |
| SR 一次通过率 | 100% | 决策上下文卡有效 |
| Agent 超时率 | 21% (3/14) | 需要超时容忍机制 |
| Handoff 回报率 | 0% (0/5) | 协议执行严重失败 |
| 日志完整度 | 2 行/预期>10 | 落盘机制缺失 |
| 需求覆盖率 | 93% | 标准需弹性化 |
| 归档质量 | .venv 混入 | 需排除规则 |

**核心发现：框架的"设计层"（角色、流程、门禁）运转良好，但"执行层"（SubAgent 行为、日志落盘、归档细节）存在系统性的"说到没做到"问题。**

# Skill: mh-retro

需求执行复盘 + 变更请求生成。PM 主导，两阶段产出，确保"先诊断再开方"。

**日志规则：** 见 `templates/logging-standard.md`

---

## 触发条件

用户要求对已完成需求进行复盘/总结/改进分析时触发。

## 前置检查

1. 确认复盘目标：
   - 用户指定 REQ-ID，或
   - 用户提供产出目录路径（如 `~/Codes/temp/mh-out/deliverables/REQ-XXX/`）
2. 确认目标需求已完成（phase=done 或有完整产出）
3. 如 `docs/retrospectives/` 目录不存在则创建
4. 如 `docs/requirements/` 目录不存在则创建
5. 检查是否已有该 REQ-ID 的复盘报告（避免重复）

---

## Phase 1: 复盘报告（Retrospective Report）

**产出文件:** `docs/retrospectives/improvement-report-{REQ-ID}.md`

**性质:** 纯事实性记录与分析，不含解决方案。

### Step RET-1: 数据采集

`[PM] 启动 RET-1 数据采集`

读取以下文件（按可用性逐一检查）：

| 文件 | 用途 |
|------|------|
| `deliverables/{REQ-ID}/.state.md` | 执行模式、阶段历史 |
| `deliverables/{REQ-ID}/metrics.md` | 角色派发/驳回次数、修复轮次 |
| `deliverables/{REQ-ID}/lessons.md` | 实时捕获的经验条目（CP-N） |
| `deliverables/{REQ-ID}/process.log` | 流程日志 |
| `deliverables/{REQ-ID}/handoffs/` | Handoff 文件（看驳回和返工模式） |
| `deliverables/{REQ-ID}/te/` | 审计报告 |
| `deliverables/{REQ-ID}/sa/` | 设计轮次 |

如目标产出在外部路径，按用户提供的路径读取。

`[PM] RET-1 完成，采集 {N} 个数据源`

### Step RET-2: 执行概况

`[PM] 启动 RET-2 执行概况`

生成结构化数据表：

```markdown
## 执行概况

| 指标 | 数据 |
|------|------|
| 需求规模 | {FR数 + NFR数，Task数，Batch数} |
| 执行模式 | {fast/standard/full} |
| 产出类型 | {output_type} |
| 总耗时 | {估算} |
| SA 设计轮次 | {N} 轮 |
| SR4 驳回次数 | {N} 次 |
| 修复循环 | {N} 轮 |
| dev-test 执行率 | {百分比} |
| 最终结果 | {通过/终止/升级} |
```

`[PM] RET-2 完成`
### Step RET-3: 问题清单

`[PM] 启动 RET-3 问题清单`

从 lessons.md（CP-N 条目）和 process.log 中提取问题，每个问题包含：

```markdown
### CP-{N}: {问题标题}

- **现象:** {发生了什么}
- **根因:** {为什么发生}
- **影响:** {造成了什么后果——驳回次数/Token浪费/时间损耗}
```

要求：
- 按时间顺序编号
- 区分个案问题（仅本次发生）和系统性问题（框架缺陷导致）
- 标注问题严重度：P0（流程阻塞）/ P1（效率损耗）/ P2（可优化）

`[PM] RET-3 完成，识别 {N} 个问题（P0: {n}, P1: {n}, P2: {n}）`

### Step RET-4: 历史改善效果验证

`[PM] 启动 RET-4 历史改善效果验证`

如果之前有 CR 已实施，逐项验证本次执行中的效果：

```markdown
## 历史 CR 效果验证

| CR 项 | 约束层级 | 本次效果 | 结论 |
|--------|---------|---------|------|
| {CR-ID} ({描述}) | {脚本/模板/自然语言} | ✅/❌ {描述} | {有效/无效+原因} |
```

规律提炼：哪个层级的改善生效了，哪个没有。

如无历史 CR，跳过本步。

`[PM] RET-4 完成`

### Step RET-5: 经验总结

`[PM] 启动 RET-5 经验总结`

从问题清单中提炼可复用经验（EXP-N），每条包含：

```markdown
### EXP-{N}: {经验标题}

- 来源: {CP-N 编号}
- 经验: {具体结论}
- 适用场景: {什么情况下应用}
```

`[PM] RET-5 完成，沉淀 {N} 条经验`

### Step RET-6: 改进方向概览

`[PM] 启动 RET-6 改进方向概览`

列出系统性问题的改进方向（1-2 句话），但**不展开具体方案**。方案留给 Phase 2。

```markdown
## 改进方向概览

1. **{方向名}** — {一句话描述}
2. ...

具体方案见 Phase 2 产出的变更请求文档。
```

`[PM] RET-6 完成`

### Step RET-7: 写入与确认

`[PM] 启动 RET-7 写入复盘报告`

1. 将 RET-2 ~ RET-6 内容组装为完整文档
2. 写入 `docs/retrospectives/improvement-report-{REQ-ID}.md`
3. 验证文件存在且非空
4. 向用户展示摘要（执行概况表 + 问题数量 + 经验数量）
5. **询问用户：是否继续进入 Phase 2（生成变更请求）？**

`[PM] Phase 1 完成 ✅`

⚠️ **纪律：Phase 1 结束必须等待用户确认，才能进入 Phase 2。用户可选择仅保留复盘报告。**

---
## Phase 2: 变更请求（Change Request）

**产出文件:** `docs/requirements/CR-{NNN}-{slug}.md`

**性质:** 处方性文档，从复盘中提炼具体改进方案。

**前置:** Phase 1 完成 + 用户确认继续。

### Step CR-1: CR 编号分配

`[PM] 启动 CR-1 编号分配`

1. 扫描 `docs/requirements/` 目录，找到最大 CR 编号
2. 新编号 = 最大编号 + 1
3. slug 从复盘报告标题中提炼（kebab-case，限 40 字符）

`[PM] CR-1 完成，分配编号 CR-{NNN}`

### Step CR-2: 筛选系统性问题

`[PM] 启动 CR-2 筛选系统性问题`

从 Phase 1 问题清单中筛选：
- 仅保留**系统性问题**（框架缺陷，非个案操作失误）
- 按严重度排序：P0 → P1 → P2
- 相关问题合并为同一"问题域"

`[PM] CR-2 完成，{N} 个问题归入 {M} 个问题域`

### Step CR-3: 分层设计方案

`[PM] 启动 CR-3 分层设计方案`

对每个问题域，按约束力从强到弱选择改善层级：

| 优先级 | 层级 | 载体 | 适用场景 |
|--------|------|------|---------|
| 1 | 脚本硬约束 | scripts/*.sh / Hook | 可机械判定的违规 |
| 2 | 模板结构约束 | templates/*.md | 需引导正确行为 |
| 3 | Skill 流程约束 | skills/*.md | 需流程步骤保障 |
| 4 | 自然语言软约束 | CLAUDE.md / agents/*.md | 无法脚本化的行为 |

设计原则：
- **能用脚本阻止的，不靠文字描述**
- **框架提供机制，不写死策略** — 项目专属规则用配置文件
- **技术栈解耦** — 适用于任意 output_type
- **最小文档膨胀** — CLAUDE.md/skills/agents 只加指针

每个问题域的方案格式：

```markdown
## 问题域 {N}: {标题}（{P0/P1/P2}）

### 问题描述
{从 Phase 1 引用，标注 CP-N 编号}

### 根因
{从 Phase 1 引用}

### 改善方案
**{层级}层：**
- {具体改动}
```

`[PM] CR-3 完成`

### Step CR-4: 交付物汇总

`[PM] 启动 CR-4 交付物汇总`

按层级汇总所有需修改/新增的文件：

```markdown
## 实际交付物汇总

### 脚本层
| 文件 | 作用 | 覆盖问题域 |

### 模板层
| 文件 | 作用 | 覆盖问题域 |

### 规则层
| 文件 | 改动量 | 覆盖问题域 |
```

`[PM] CR-4 完成`

### Step CR-5: 写入与确认

`[PM] 启动 CR-5 写入变更请求`

1. 组装完整 CR 文档，头部包含：
   ```markdown
   # CR-{NNN}: {标题}

   > 来源: docs/retrospectives/improvement-report-{REQ-ID}.md
   > 日期: {当天日期}
   > 状态: 待实施
   ```
2. 写入 `docs/requirements/CR-{NNN}-{slug}.md`
3. 验证文件存在且非空
4. 向用户展示：问题域数量 + 交付物清单摘要
5. 询问用户是否需要立即实施（进入 /mh-apply 流程）

`[PM] Phase 2 完成 ✅`

---

## 关键纪律

1. **Phase 1 和 Phase 2 必须分文件产出** — 禁止合并为一个文档
2. **Phase 1 完成后必须等用户确认** — Phase 2 是可选的
3. **复盘报告（Phase 1）不含解决方案** — 只记录事实和分析
4. **变更请求（Phase 2）必须引用 CP-N 编号** — 保持追溯链接
5. **方案设计遵循"脚本 > 模板 > 自然语言"层级** — 不走捷径
6. **CR 中不重复复盘内容** — 通过 CP-N 编号引用 Phase 1

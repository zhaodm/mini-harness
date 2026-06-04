# Mini-Harness 设计文档

> 本文档是架构地图，不是百科全书。每个概念一句话 + 指向权威源。
> 执行权威为 skills/*.md 和 agents/*.md，冲突时以它们为准。
> 权威源完整映射见 `docs/source-of-truth.md`。

---

## 1. 设计目标

四层递进防线，每层弥补上层的固有缺口：

```
Rules (CLAUDE.md)        → 行为约束（弱：随上下文复杂度下降）
Skills (skills/*.md)     → 标准 SOP（中：仍属指令层）
Agents + Handoff         → 角色制衡（中：缺少客观验证）
Scripts + 人工 (SR1-4)   → 硬校验（强：退出码为唯一判据）
```

---

## 2. 架构总览

### 模块全景

| 模块 | 权威源 | 一句话 |
|------|--------|--------|
| 全局规则 | CLAUDE.md | 最高约束，98 行精简 |
| 角色契约 | agents/*.md | 6 角色身份+质量标准+思考框架+调度协议(PM) |
| 执行规程 | skills/mh-*.md | 各阶段 SOP，mode 感知裁剪 |
| 硬校验 | scripts/*.sh | A/B/C/D/E 类检查，退出码驱动 |
| 模板体系 | templates/ | handoff/state/日志/示例/结构参考 |
| 文档 | docs/ | 本文件(地图) + source-of-truth(映射) + workflow(图集) |

### 目录结构

```
mini-harness/
├── CLAUDE.md                    全局规则
├── agents/                      6 角色契约（含 PM 调度协议+质量门禁）
├── skills/                      8 个执行规程
├── scripts/                     4 个硬校验脚本
├── templates/
│   ├── handoff-template.md      任务派发格式
│   ├── state-template.md        状态 schema
│   ├── logging-standard.md      日志格式
│   ├── examples/                金标准产出示例（5 个）
│   └── output-guides/           产出结构参考（3 个）
├── docs/                        设计参考（人工阅读，PM 运行时不读）
├── deliverables/                运行时产物（按 REQ-ID 隔离）
├── deliverables/                运行时产物（按 REQ-ID 隔离）
└── output/                      最终交付（spec/ + reference/ + 产出物）
```

---

## 3. 角色总览

| 角色 | 核心职责 | 权威源 |
|------|----------|--------|
| PM | 调度 + 质量门禁 + 人机交互 | agents/pm.md |
| BA | 模糊需求 → SHALL+GWT 规格 | agents/ba.md |
| SA | 需求 → 技术方案 → Tasks | agents/sa.md |
| DE | TDD 编码 + 自测 + 交付校验 | agents/de.md |
| TE | 独立验证 + 覆盖分析 + 缺陷报告 | agents/te.md |
| UX | 视觉/结构设计制品 | agents/ux.md |

隔离方式：Claude Code = SubAgent 物理隔离；Cline = 文件协议逻辑隔离。

---

## 4. 流程设计

### 四阶段 + 状态机

```
clarify → propose → apply → archive → DONE
   ↑         ↑         ↑         ↑
 RESUME    SR1驳回   SR2/3驳回  SR4驳回
```

详见：skills/mh-clarify.md, mh-propose.md, mh-apply.md, mh-archive.md

### 三档 Mode

| Mode | 场景 | 裁剪 | 详见 |
|------|------|------|------|
| fast | ≤5 文件小调整 | 跳过 BA/SA/TE propose，合并审批 | 各 skill "fast 模式"节 |
| standard | 单模块新功能 | 跳过 BA，SA∥TE 并行 | 各 skill "standard 模式"节 |
| full | 跨模块大需求 | 完整流程 | 各 skill "full 模式"节 |

### SR Gate 通过标准

| Gate | 通过标准 | 详见 |
|------|----------|------|
| SR1 | 需求覆盖完整 + 设计覆盖所有需求 + 计划可执行 | skills/mh-propose.md Step 4 |
| SR2 | 所有 Task 通过审计 + 代码质量达标 | skills/mh-apply.md Step 2 |
| SR3 | 全量测试通过 + 覆盖无遗漏 + 无 Critical/Major | skills/mh-apply.md Step 4 |
| SR4 | 归档完整 + 产出物可用 + 文档一致 | skills/mh-archive.md SR4 |

### PM 调度循环 + 六条铁律

详见：agents/pm.md "调度协议"节

---

## 5. 上下文管控

| 约束 | 实现 |
|------|------|
| 不读对话历史 | SubAgent 独立子会话 |
| 不改上游 | agents 禁止事项 + PM 验收 |
| 不引用他人推理 | prompt 仅含 handoff + 本角色契约 |
| 白名单隔离 | handoff 精确列出可读文件 |
| 白名单验证 | 回报中 read_files 字段 + PM 校验 |

Handoff 协议详见：templates/handoff-template.md

---

## 6. 质量管控

### 三层质量注入（Agent 层）

每个 Agent 含：思考框架 + 反模式 + 交付自检。详见各 agents/*.md。

### PM 质量门禁（流程层）

PM 接收回报后逐项核对对应角色清单。详见 agents/pm.md "质量门禁"节。

### 修复收敛（机制层）

根因分析 → 结构化修复上下文 → repair_history 追踪 → 发散时提前升级。
详见 skills/mh-apply.md "修复循环"节。

### 硬校验（Scripts 层）

| 类型 | 检查内容 |
|------|---------|
| A 类 | 文件存在性 |
| B 类 | 阶段产出物完整性（mode+output_type 感知） |
| C 类 | 流程一致性 |
| D 类 | 流程健康度（修复耗尽/超时/TODO 残留） |
| E 类 | Handoff 契约一致性 |

详见：scripts/verify.sh

---

## 7. 模板体系

| 模板 | 用途 | 权威源 |
|------|------|--------|
| handoff-template.md | 任务派发 | templates/ |
| state-template.md | 状态 schema | templates/ |
| logging-standard.md | 日志格式 | templates/ |
| examples/*.md | 金标准示例（BA/SA/DE/TE/修复） | templates/examples/ |
| output-guides/*.md | 产出结构参考 | templates/output-guides/ |

---

## 8. 产出类型体系

output_type 与 mode 正交。详见 CLAUDE.md §7 + skills/mh-clarify.md Step 3。

---

## 9. 文档一致性

**原则：** 契约即文档、模板即标准、脚本即验证。

三层保障：结构化约束（预防）→ 自动检测（发现）→ 人工评审（兜底）。

详见：docs/source-of-truth.md

---

## 10. 经验记忆系统

### 设计目标

每次需求执行中的调教、纠正、最佳实践持久化沉淀，形成"越用越好"的正向循环：

```
执行 REQ-N → 采集经验 → output/lessons-learned.md → 执行 REQ-N+1 时加载
                                    ↓
                         框架开发者 review → 固化为框架规则
```

### 采集架构

| 采集点 | 触发时机 | 采集者 | 内容 |
|--------|---------|--------|------|
| CP-1 | SR 审批被用户驳回 | PM 自动 | 驳回原因 + 修正方向 |
| CP-2 | 用户主动纠正 Agent 行为 | PM 自动 | 纠正内容 + 原因 |
| CP-3 | 修复循环 ≥2 轮 | PM 自动 | 系统性根因分析 |
| CP-4 | ARC-6 结项前 | PM 主动询问用户 | 用户总结评价和改进建议 |

### 存储架构

```
deliverables/{REQ-ID}/lessons.md    ← 本次执行过程中的暂存（实时追加）
         │
         ▼ ARC-6 merge
output/lessons-learned.md           ← 全量累积文档（跨 REQ 持久化）
```

- `deliverables/{REQ-ID}/lessons.md`：过程暂存，随 REQ 生命周期存在
- `output/lessons-learned.md`：全量累积，每次归档时 merge 进新经验

### 消费方式

| 消费者 | 时机 | 方式 |
|--------|------|------|
| PM | mh-clarify 前置检查 | 读取 output/lessons-learned.md，传达相关经验给各角色 |
| 各 Agent | handoff 白名单 | PM 将相关经验条目附在 handoff 约束中 |
| 框架开发者 | 定期 review | 反复出现的经验固化为框架规则 |

### 经验固化路径

```
output/lessons-learned.md 中反复出现的模式
         │
         ▼ 框架开发者识别
┌────────────────────────────────────────┐
│ 设计类 → agents/*.md 质量标准/反模式    │
│ 验证类 → scripts/verify.sh 检查项      │
│ 流程类 → skills/*.md 步骤增强          │
│ 模板类 → templates/ 新增/改进          │
└────────────────────────────────────────┘
         │
         ▼ 固化后记录
output/lessons-learned.md "经验固化记录" 表
```

### 文件格式

经验条目格式（EXP-{N} 全局递增编号）：
```markdown
### EXP-{N}: {经验标题}
- 来源: {REQ-ID}
- 类别: {设计/实现/流程/测试/沟通}
- 角色: {PM/BA/SA/DE/TE/UX}
- 经验: {具体内容}
- 原因: {为什么这样做更好}
- 适用场景: {什么情况下应用此经验}
```

### 权威源

| 文件 | 职责 |
|------|------|
| agents/pm.md "经验采集规则" | CP-1~CP-3 采集行为定义 |
| skills/mh-archive.md ARC-6 | 归档流程 + CP-4 用户询问 |
| templates/lessons-template.md | 文档格式模板 |
| skills/mh-clarify.md 前置检查 | 启动时加载历史经验 |

---

## 11. 架构演进方向（未来）

| 方向 | 触发条件 | 做法 | 状态 |
|------|---------|------|------|
| Skill 按需加载 | 单个 skill > 350 行 | 拆分为 main.md + 子文件 | ✅ done (v0.6.1, mh-apply) |
| 脚本拆分 | verify.sh > 500 行 | 拆分为 verify-{A,B,C,D,E}.sh + verify.sh 入口 | planned |
| PM 上下文监控 | PM 固定负载 > 800 行 | 精简 pm.md 或 skill 文件 | planned |
| 状态机引擎 | PM 频繁写错 .state.md | scripts/state-engine.sh 封装转移 | planned |
| 契约测试 | Handoff 格式频繁不匹配 | verify.sh E 类检查增强 | ✅ done (v0.5.3) |
| 修复快照回退 | 修复发散需要代码回退 | repair_snapshots + git stash | planned |

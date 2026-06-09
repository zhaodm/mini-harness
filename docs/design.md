# Mini-Harness 设计文档

> 本文档是架构地图，不是百科全书。每个概念一句话 + 指向权威源。
> 执行权威为 skills/*.md 和 agents/*.md，冲突时以它们为准。
> 权威源完整映射见 `docs/source-of-truth.md`。

---

## §1 整体设计目标

### 核心命题

AI Agent 驱动的研发流程框架，实现从需求到高质量交付的自动化生产。

### 四层递进防线

每层弥补上层的固有缺口，形成闭环：

```
Rules (CLAUDE.md)        → 行为约束（弱：随上下文复杂度下降）
Skills (skills/*.md)     → 标准 SOP（中：仍属指令层）
Agents + Handoff         → 角色制衡（中：缺少客观验证）
Scripts + 人工 (SR1-4)   → 硬校验（强：退出码为唯一判据）
```

### 设计原则

| 原则 | 说明 |
|------|------|
| 脚本硬约束优先于自然语言软约束 | 凡可程序化验证的规则，以脚本退出码为准 |
| 角色隔离保证上下文纯净 | 不让上下文混乱或职责混乱，这是底线 |
| 契约即文档 | 每个角色的定义文件即完整规范 |
| 模板即标准 | 交付格式由模板定义，不依赖记忆 |
| 脚本即验证 | 交付判定不依赖 Agent 自述 |

---

## §2 一级架构总览

### 模块全景

| 模块 | 权威源 | 一句话 |
|------|--------|--------|
| 全局规则 | CLAUDE.md | 最高约束，精简纪律 |
| 角色契约 | agents/*.md | 6 角色身份+质量标准+思考框架+调度协议(PM) |
| 执行规程 | skills/mh-*.md | 各阶段 SOP，mode 感知裁剪 |
| 硬校验 | scripts/*.sh | 三层校验体系，退出码驱动 |
| 模板体系 | templates/ | handoff/state/日志/示例/结构参考/设计指南 |
| 文档 | docs/ | 本文件(地图) + source-of-truth(映射) |

### 目录结构

```
mini-harness/
├── CLAUDE.md                    全局规则
├── agents/                      6 角色契约
├── skills/                      执行规程（含子文件按需加载）
├── scripts/                     硬校验脚本 + 工具脚本
├── workflows/                   JS Workflow 并行编排层（CR-004）
│   ├── propose-parallel.js      SA∥TE 并行设计
│   ├── apply-batch-dev.js       Batch DE 并行开发
│   ├── apply-batch-test.js      Batch TE 并行审计
│   ├── apply-final-audit.js     TE 最终审计
│   └── lib/                     工具函数（prompt-assembler, result-parser）
├── tests/                       自动化测试套件
├── templates/
│   ├── handoff-template.md      任务派发格式
│   ├── state-template.md        状态 schema
│   ├── state-pointer-template.md 全局指针模板
│   ├── logging-standard.md      日志格式
│   ├── metrics-template.md      执行指标模板
│   ├── lessons-template.md      经验沉淀模板
│   ├── frontend-design-skill.md 前端设计指南（Anthropic官方）
│   ├── ppt-base.css             PPT 设计系统
│   ├── examples/                金标准产出示例
│   └── output-guides/           产出结构参考
├── docs/                        设计参考（人工阅读，PM 运行时不读）
├── deliverables/                运行时产物（按 REQ-ID 隔离，git忽略）
├── reference/                   用户参考资料输入
└── output/                      最终交付
    ├── spec/                    全量需求/设计文档归档
    ├── reference/               参考资料归档
    ├── lessons-learned.md       经验累积文档
    └── {产出物}                 代码/产品
```

---

## §3 SubAgent 设计

### 六角色体系

| 角色 | 核心职责 | 权威源 |
|------|----------|--------|
| PM | 调度 + 质量门禁 + 人机交互 + 经验采集 | agents/pm.md |
| BA | 模糊需求 → SHALL+GWT 规格 | agents/ba.md |
| SA | 需求 → 技术方案 → Tasks | agents/sa.md |
| DE | TDD 编码 + 自测 + 精装交付 | agents/de.md |
| TE | 独立验证 + 覆盖分析 + 缺陷报告 | agents/te.md |
| UX | 视觉/结构设计 + 视觉叙事 | agents/ux.md |

### 隔离方式

| 平台 | 隔离机制 |
|------|---------|
| Claude Code | SubAgent 物理隔离（独立子会话）+ JS Workflow 并行编排 |
| Cline | 文件协议 + 行为约束（逻辑隔离） |

### Agent 契约结构

每个 Agent 定义文件内嵌完整契约：

```
身份 → 职责 → 输入 → 输出 → 阻塞条件 → 禁止事项
     → 思考框架 → 质量标准 → 反模式 → 交付自检 → 模型建议
```

### PM 调度循环

```
读取 .state.md → 确定下一步 → 写 handoff → 派发 SubAgent
→ 接收回报 → 质量门禁 → 更新 .state.md → 循环
```

详见：agents/pm.md "调度协议"节

### 并行编排层（CR-004 Workflow）

并行扇出（SA∥TE、批量 DE、批量 TE）通过 JS Workflow 脚本确定性执行：

```
PM 主会话（人机交互 + 质量门禁）
    │
    ├── 生成 handoff 内容
    ├── 更新 .state.md: current_role={并行角色}
    ├── 调用 Workflow 工具 ──→ parallel([agent(SA), agent(TE)])
    ├── 接收结构化返回
    ├── 执行质量门禁
    └── 更新 .state.md: current_role=PM
```

- Workflow SubAgent 继承 PreToolUse Hook（role-guard.sh 权限控制仍生效）
- 支持逗号分隔多角色（`current_role: SA,TE`），任一角色有权即放行
- 工具函数: `workflows/lib/prompt-assembler.js` + `result-parser.js`
- 详见: `docs/designs/CR-004-hybrid-workflow-design.md`

---

## §4 开发流程设计

### 四阶段状态机

```
clarify → propose → apply → archive → DONE
   ↑         ↑         ↑         ↑
 RESUME    SR1驳回   SR2/3驳回  SR4驳回
```

### 三档 Mode

| Mode | 场景 | 裁剪 |
|------|------|------|
| fast | ≤5 文件小调整 | 跳过 BA/SA/TE propose，合并审批 |
| standard | 单模块新功能 | 跳过 BA，SA∥TE 并行 |
| full | 跨模块大需求 | 完整流程 |

### SR Gate 通过标准

| Gate | 通过标准 | 详见 |
|------|----------|------|
| SR1 | 需求覆盖完整 + 设计覆盖所有需求 + 计划可执行 | skills/mh-propose.md |
| SR2 | 所有 Task 通过审计 + verify-qa.sh PASS | skills/mh-apply-standard.md |
| SR3 | 全量测试通过 + 覆盖无遗漏 + 无 Critical/Major | skills/mh-apply-standard.md |
| SR4 | 归档完整 + 产出物可用 + 文档一致 | skills/mh-archive.md |

### 产出类型体系（output_type）

output_type 与 mode 正交：mode 控制流程严谨度，output_type 控制产出物和验证方式。

| output_type | 默认验证策略 |
|-------------|-------------|
| web-app | E2E / 集成测试 |
| backend-api | 集成测试 |
| cli-tool | 集成测试 |
| data-pipeline | 冒烟测试 |
| infrastructure | 冒烟测试 |
| documentation | 人工审阅 |
| ppt | 人工 + verify-ppt.sh |
| library | 单元测试 |
| custom | 用户指定 |

详见：CLAUDE.md §7 + skills/mh-clarify.md Step 3

---

## §5 上下文管控设计

### 隔离原则

> 角色隔离的目的是上下文的极致管控，不能让上下文混乱或角色职责混乱，这是底线。

| 约束 | 实现 |
|------|------|
| 不读对话历史 | SubAgent 独立子会话 |
| 不改上游 | agents 禁止事项 + PM 验收 |
| 不引用他人推理 | prompt 仅含 handoff + 本角色契约 |
| 白名单隔离 | handoff 精确列出可读文件 |
| 白名单验证 | 回报中 read_files 字段 + PM 校验 |

### Handoff 协议

PM 与各角色间信息传递的唯一通道。结构化文件，包含：
- 派发对象、白名单文件列表、期望输出、约束条件
- 完成报告：status、output_files、summary、issues

详见：templates/handoff-template.md

### PM 运行时上下文负载

PM 启动时读取：本文件(pm.md) + 当前 skill + .state.md + handoff。
不需要读取 design.md、source-of-truth.md（人工维护参考）。

---

## §6 Skill 设计

### Skill 体系

| 命令 | 职责 | 权威源 |
|------|------|--------|
| /mh-clarify | 需求初始化与澄清 | skills/mh-clarify.md |
| /mh-propose | 分析→设计→用例→评审 | skills/mh-propose.md |
| /mh-apply | 开发→审计→人工审批 | skills/mh-apply.md（路由到子文件） |
| /mh-archive | 归档+经验沉淀+结项 | skills/mh-archive.md |
| /mh-run | 全流程自动推进 | skills/mh-run.md |
| /mh-ppt | PPT 类 HTML 开发 | skills/mh-ppt.md |

### 按需加载设计

当单个 skill 文件 > 350 行时，拆分为 main.md + 子文件：

```
skills/mh-apply.md          ← 路由入口（45行）
skills/mh-apply-fast.md     ← fast 模式专用
skills/mh-apply-standard.md ← standard/full 模式
skills/mh-apply-repair.md   ← 修复循环（按需加载）
```

PM 仅加载路由文件 + 当前 mode 对应的子文件，减少上下文压力。

### PPT 双轨设计方案

output_type=ppt 时，用户可选择设计路径：

| 路径 | 约束 | 适用场景 |
|------|------|---------|
| system（ppt-base.css） | 严格设计系统，统一风格 | 企业汇报、品牌一致性 |
| creative（frontend-design） | 仅结构约束，视觉自由 | 创意提案、视觉冲击力 |

两条路径互相吸收不冲突的优点：
- system 可借鉴 frontend-design 的动效、空间构图
- creative 可借鉴设计系统的 CSS 变量管理、信息层次原则

详见：skills/mh-ppt.md "设计方案选择"节

---

## §7 质量管控设计

### 三层质量注入（Agent 层）

每个 Agent 定义中内含：思考框架 + 反模式 + 交付自检。

### PM 质量门禁（流程层）

PM 接收回报后逐项核对对应角色验收清单。详见 agents/pm.md "质量门禁"节。

### 修复收敛（机制层）

根因分析 → 结构化修复上下文 → repair_history 追踪 → 发散时提前升级（≤5轮）。
详见：skills/mh-apply-repair.md

### 硬校验（Scripts 层）

> **核心原则：脚本硬约束优先于自然语言软约束。** 凡是可程序化验证的规则，必须用脚本实现。

三层校验体系：

| 脚本 | 职责 | 检查内容 |
|------|------|---------|
| verify.sh | 结构校验 | 文件存在性(A)、阶段完整性(B)、流程一致性(C)、健康度(D)、契约(E) |
| verify-qa.sh | 内容质量校验 | 模糊词(QA-1)、测试结果(QA-2)、报告结论(QA-3)、报告完整性(QA-4)、设计规格(QA-5)、代码规范(QA-6)、经验采集(QA-7) |
| verify-ppt.sh | PPT 专项校验 | viewport、.slide容器、CSS引用、字号底线、方向键导航、页数一致性、占位符残留 |

**约束升级路径：** 自然语言约束 → 发现频繁违反 → 脚本化 → 硬性拦截

---

## §8 度量与记忆设计

### 执行度量（metrics）

每次 REQ 完成后，PM 在 ARC-5 步骤自动生成执行指标：
- 总耗时、角色派发/驳回次数、修复轮次与收敛性、SR审批结果、断点异常

模板：templates/metrics-template.md
产出：deliverables/{REQ-ID}/metrics.md

### 经验记忆（lessons-learned）

#### 设计目标

每次执行中的调教、纠正、最佳实践持久化沉淀，形成"越用越好"的正向循环。

#### 采集架构

| 采集点 | 触发时机 | 采集者 | 内容 |
|--------|---------|--------|------|
| CP-1 | SR 审批被用户驳回 | PM 自动 | 驳回原因 + 修正方向 |
| CP-2 | 用户主动纠正 Agent 行为 | PM 自动 | 纠正内容 + 原因 |
| CP-3 | 修复循环 ≥2 轮 | PM 自动 | 系统性根因分析 |
| CP-4 | ARC-6 结项前 | PM 主动询问用户 | 用户总结评价和改进建议 |

#### 存储架构

```
deliverables/{REQ-ID}/lessons.md    ← 过程暂存（实时追加）
         │
         ▼ ARC-6 merge
output/lessons-learned.md           ← 全量累积（跨 REQ 持久化）
```

#### 消费方式

| 消费者 | 时机 | 方式 |
|--------|------|------|
| PM | mh-clarify 前置检查 | 读取历史经验，传达给各角色 |
| 各 Agent | handoff 白名单 | PM 将相关经验条目附在约束中 |
| 框架开发者 | 定期 review | 反复出现的经验固化为框架规则 |

#### 经验固化路径

```
反复出现的经验 → 框架开发者识别 → 固化到对应层级
├── 设计类 → agents/*.md 质量标准/反模式
├── 验证类 → scripts/verify*.sh 检查项
├── 流程类 → skills/*.md 步骤增强
└── 模板类 → templates/ 新增/改进
```

详见：skills/mh-archive.md ARC-6 + agents/pm.md "经验采集规则"

---

## §9 工具体系设计

### 硬校验脚本

| 脚本 | 用途 | 调用时机 |
|------|------|---------|
| scripts/verify.sh | 结构校验（A/B/C/D/E 类） | TE 审计、SR 审批前 |
| scripts/verify-qa.sh | 内容质量校验（QA-1~7） | SR2 审批前 |
| scripts/verify-ppt.sh | PPT 专项校验 | PPT 类 TE 审计 |
| scripts/baseline.sh | 基线对比 | 检测非流程修改 |
| scripts/check-harness.sh | 框架自检 | 框架维护时 |

### 修复工具

| 脚本 | 用途 |
|------|------|
| scripts/fix-ppt-fonts.py | 批量修复 PPT 字号（< 18px 上调） |

### 内置能力（MCP/工具）

| 工具 | 用途 | 调用时机 |
|------|------|---------|
| WebSearch | 联网搜索 | SA 研究阶段 |
| WebFetch | 网页抓取 | 用户提供参考链接 |
| Read | 图片识别 | reference/ 含图片时 |

### 外部插件

| 插件 | 用途 | 配置 |
|------|------|------|
| frontend-design@claude-plugins-official | PPT creative模式设计指导 | .claude/settings.json |

---

## §10 模板体系

### 模板清单

| 模板 | 用途 | 消费者 |
|------|------|--------|
| handoff-template.md | 任务派发格式 | PM |
| state-template.md | .state.md 完整 schema | PM |
| state-pointer-template.md | 全局指针（首次运行自动拷贝） | PM |
| logging-standard.md | 日志格式规范 | 全角色 |
| metrics-template.md | 执行指标格式 | PM（ARC-5） |
| lessons-template.md | 经验沉淀文档格式 | PM（ARC-6） |
| frontend-design-skill.md | 前端设计指南（Anthropic官方） | UX/DE（PPT creative模式） |
| ppt-base.css | PPT 设计系统 | UX/DE（PPT system模式） |
| ppt-base.html | PPT HTML骨架 | DE |
| ppt-light.css | PPT 浅色主题 | UX/DE |
| examples/*.md | 金标准产出示例（BA/SA/DE/TE/修复） | 各角色参考 |
| output-guides/*.md | 产出结构参考 | DE |
| ppt-templates/layouts/ | PPT 布局模板 | UX |

### 模板使用原则

- 模板定义"标准格式"，Agent 照格式填充内容
- 首次运行时由 skill 自动拷贝模板到运行时位置
- 模板更新不影响已归档产物（归档后的文件独立于模板）

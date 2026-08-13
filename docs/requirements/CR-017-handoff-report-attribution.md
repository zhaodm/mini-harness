# CR-017 完成回报归属与 mh-dev 角色维度校验

- 状态: intake
- 轨道: formal
- 基线: `cad71365ad8f78db166a8ee5086f96427a0f0ca1`
- 触发来源: 外部项目 `~/Code/mini-agent` 使用本框架时撞到的制度冲突（其 `lessons.md` EXP-2），叠加 CR-016 遗留的一条未修缺陷

## 背景

两个问题共处同一主题：**授权判定的主体与真实主体不一致**。CR-016 已在量词、判定对象两个层面各修一次，本 CR 修剩下的归属层面。

### 问题一：协议要求执行角色填写完成回报，守卫禁止它写

`templates/handoff-template.md:106` 规定完成回报「执行角色必填 — 未填写则任务视为未完成」，108 行进一步写「SubAgent 必须在结束前填写本节」，`skills/mh-codeflow/SKILL.md:58` 第 6 步同口径。但 `handoffs/` 是 role-guard 的 ORCHESTRATOR 独占路径，THINKER/WORKER/VERIFIER 写入一律 `exit 2`（`Write` 与 `Edit` 均拦）。协议强制要求的动作，守卫结构性禁止。

已在沙箱复现，三个角色全部命中，非仅 Thinker：

```
THINKER  → handoffs/REQ001-THINK-NEEDS-R1.md  Edit   exit=2
THINKER  → handoffs/REQ001-THINK-NEEDS-R1.md  Write  exit=2
WORKER   → handoffs/REQ001-THINK-NEEDS-R1.md  Edit   exit=2
对照 THINKER → THINKER-needs-spec.md                 exit=0
```

`git log -S` 追溯到 `f150a4c`（CR-003），自 hook 落地首日即如此，非 CR-016 引入。潜伏十余个 CR 未被发现，因为它不阻塞流程——Orchestrator 收回持权代填即可绕过，代价隐蔽。

**真实代价不是流程阻塞，是证据链失效。** 代填后完成回报变为「Orchestrator 撰写、Orchestrator 审计」，质量门禁 Step 0 核对 `read_files` 的判定对象（回报）不再是真实对象（角色实际读了什么），退化为依赖 SubAgent 进程内返回值的诚实性，无落盘证据。同时擦着铁律②（Orchestrator 不对产出内容做判断）走。每次派发都复现。

### 问题二：mh-dev 分支缺角色维度校验

role-guard 的 mh-dev 分支只校验 `approved_scope` 命中，不区分写入者角色。Planner/Developer/Tester 共享同一张通行证。CR-016 交付期间 Planner 越权写了 11 个框架文件而未被拦截（记录见 CR-016「交付纪律偏差记录」DEV-01），正是从此处穿过。

## 需求条目

### R1 执行角色须能写入自己的完成回报

被派发的角色须有权写入本轮任务完成回报，无需 Orchestrator 代笔。回报归属须真实反映撰写者。

### R2 回报不得与任务约束同权

执行角色获得回报写权后，仍不得改写任务描述、输入白名单、约束、修复上下文等由 Orchestrator 设定的内容。质量门禁比较的两侧不得落入同一写权域——否则角色可通过改写被比较的一侧使越权自洽，形成自我认证。

### R3 read_files 核对须基于落盘证据

Step 0 白名单核对的输入须是可 diff、可留痕的落盘文件，不依赖 SubAgent 返回值。

### R4 既有回报门禁不得因本次改动静默失效

`scripts/verify.sh`（handoff 完成回报非空检查）与 `scripts/verify-qa.sh`（QA-4 四字段非空）当前从 handoff 文件读取回报字段，两者均为 WARN 级。若回报位置变更而门禁读取位置不变，门禁将永久静默通过——比硬失败更危险。门禁须与回报位置保持同源。

### R5 mh-dev 分支须按角色维度校验写权

框架治理分支须区分写入者角色，各角色仅可写入其职责范围内的路径。Planner 不得写入 Planner 白名单外的框架文件。

### R6 能力边界须如实声明

守卫无法识别真实写入者（hook payload 不含 `agent_type`，CR-016 已确认）。本 CR 提升的是落盘可追溯性，不是身份认证。文档不得把它表述为安全边界。

### R7 口径同步

改动涉及的所有文档须同步，不得出现规范自相矛盾——问题一的成因正是模板与守卫两处口径矛盾且无人核对。

## 已否决的方案

| 方案 | 否决理由 |
|---|---|
| 放开三角色对 `handoffs/*.md` 的写权 | 违反 R2。白名单与回报同处一个文件，放开写权即让执行角色同时掌握被比较的两侧：读了白名单外文件时改白名单即可自洽，比现状更糟（现状白名单至少可信）。顺带开了改任务描述与约束的口子，触碰铁律⑤ |
| 由 Orchestrator 代填并记入 lessons | 现状即此，是被绕过而非被解决。归属失真、证据链依赖进程内返回值 |
| 放宽模板要求为「可选填写」 | 放弃 R3，白名单核对彻底失去输入 |
| 在 hook 中识别 SubAgent 身份后按角色放行 | 技术不可行。payload 仅含 `session_id`/`tool_name`/`tool_input`/`cwd`/`permission_mode` |

## 影响范围

| 文件 | 变更性质 |
|---|---|
| `scripts/role-guard.sh` | 新增回报路径写权 + mh-dev 分支角色维度校验 |
| `templates/handoff-template.md` | 回报位置与填写者口径 |
| `templates/handoff-examples.md` | 示例同步 |
| `templates/orchestrator-quality-gate.md` | Step 0 核对来源 |
| `skills/mh-codeflow/SKILL.md` | 调度循环第 6 步、Step 0 |
| `scripts/verify.sh` | 回报读取位置（R4） |
| `scripts/verify-qa.sh` | QA-4 读取位置（R4） |
| `agents/orchestrator.md` | 写权清单 |
| `docs/designs/source-of-truth.md` | 守卫口径 |
| `docs/designs/workflow.md` | 守卫口径 |
| `docs/kb/domains/guards.md` | 归属层面复发记录 + EXP-2 归档 |
| `templates/output-structure.md` | 目录结构 |
| `CHANGELOG.md` | 变更记录 |
| `tests/**` | Tester 独占，不由 Developer 产出 |

## 不做

- 不改 handoff 派发格式与命名规则
- 不改 SR 门禁与三角色职责划分
- 不修白名单正则普遍缺左锚的既有问题（约 20 处，baseline 既有，独立 CR）
- 不修 `req_id` 未转义插入 ERE（同上）
- 不安装 playwright npm 包（与本主题无关）

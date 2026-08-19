# Roles

> 本域指南描述角色契约体系的内部机制。修改本域代码前请先阅读。
> 对应源码: `agents/`

## 职责与边界

**做什么：**
- 定义 3 个被派发角色（thinker/worker/verifier）的完整契约：身份、职责、输入、输出、阻塞条件、禁止事项
- 定义 orchestrator 编排器的主会话行为契约（调度循环、质量门禁、人机交互）
- 定义 Thinker 三相位设计（needs/design/visual）的激活条件与产出
- 保证角色隔离原则：写需求的人不审需求，写代码的人不做终验

**不做什么（由其他域负责）：**
- 各阶段具体执行步骤 → 见 [skills.md](skills.md)
- 并行编排逻辑 → 见 [workflow.md](workflow.md)
- 角色写入权限硬拦截 → 见 [guards.md](guards.md)
- handoff 模板格式 → 见 [templates.md](templates.md)

## 内部结构

```
agents/
├── orchestrator.md    主会话编排器（不计被派发角色）
├── thinker.md         需求 + 设计 + 视觉（三相位）
├── worker.md          编码实现
└── verifier.md        独立验证
```

| 子模块 | 职责 | 文件 |
|--------|------|------|
| orchestrator | 流程调度 + 质量门禁 + 人机交互 + 经验采集 | `agents/orchestrator.md` |
| thinker | 需求规格 → 技术设计/视觉设计（track 激活相位） | `agents/thinker.md` |
| worker | TDD 编码 + 自测 + 精装交付 | `agents/worker.md` |
| verifier | 独立验证 + 覆盖分析 + 缺陷报告 | `agents/verifier.md` |

## 核心数据结构

### 角色定义的宿主原生形态（CR-020 R1）

三个**被派发**角色的 `agents/*.md` 各含 YAML frontmatter，使宿主可直接识别并派发，
不再靠 prompt 文本注入通用 SubAgent：

```yaml
---
name: <role>          # 小写字母/数字/连字符
description: <触发条件>  # 供宿主判断何时派发
model: inherit        # 继承主会话模型，不与流程的模型选择耦合
color: <cyan|green|yellow>
tools: <逗号分隔工具名>   # 未列出即不可用
---
```

`tools:` 取**逗号分隔的裸工具名**形态（非 JSON 数组），三个角色统一。官方两种写法均被
同一分词器接受；择一并保持一致，避免同一字段在三个文件里三种形态。

**写下 `tools:` 不等于它生效**（CR-020 repair 1 的教训）。宿主强制需三段链路齐备：

1. **声明** — 本节的 frontmatter；
2. **发现面** — `.claude/agents/{thinker,worker,verifier}.md` 以 **symlink 指向 `agents/` 同名
   文件**（宿主项目级发现路径；实测两个目录扫描实现均跟随 symlink）。⛔ 不得改成手工副本，
   否则强制点取 `.claude/agents/` 那一份而文档按 `agents/` 描述，两份定义各自漂移；
3. **派发链** — 四个 `workflows/*.js` 的 `agent()` 传 `agentType`（自用形态取裸名 `thinker` /
   `worker` / `verifier`；对外分发形态取 `mini-harness:<role>`）。

缺任一条，宿主即套用内置 `workflow-subagent`（`tools: ["*"]`），本节整张表退化为文档约定。
机械守护：`scripts/check-harness.sh` 校验 symlink 同源与 `agentType` 齐备，
`tests/test-session-context.sh` 断言「文档声称 ↔ 派发链实况」一致。

可观测判据（实测 2.1.233，非仅看声明）：以 `agentType: "thinker"` 派发后，该 SubAgent
自报可用工具为 `Read, Write, Edit, WebSearch, WebFetch, Glob, Grep`，**Bash 不在其列**且
无法调用；同一 workflow 内不传 `agentType` 的对照 agent 则拿到默认全量工具池。

**`agents/orchestrator.md` 不加 frontmatter**，且**不得**后续补加：它是主会话行为契约，
不经 Agent tool 派发（文件自述如此）。加了会使它被宿主当作可派发角色出现在派发候选里。

### 各角色工具集与理由（最小权限）

| 角色 | tools | 理由 |
|------|-------|------|
| Thinker | `Read, Glob, Grep, Write, Edit, WebSearch, WebFetch` | 产出规格/设计需写入；需检索参考资料；**无 Bash**——思考者不执行 |
| Worker | `Read, Glob, Grep, Write, Edit, NotebookEdit, Bash` | TDD 编码需写入；`mh-self-test` 要跑测试/lint/build，故需 Bash |
| Verifier | `Read, Glob, Grep, Bash, Write` | 需跑 `verify*.sh` 与回归套件；`Write` 用于新建测试与缺陷报告；**无 Edit**——不就地改 Worker 产物，只报缺陷 |

三份清单互不相同，这是**角色隔离在宿主侧的体现**，不是巧合：清单相同即隔离退化为纯文档约定。
Verifier「有 Write 无 Edit」与归属表「VERIFIER 写 `tests/`」及其「只执行验证，不定义标准」
的契约一致——能新建，不能就地改。

工具粒度与路径粒度的分工（含 Bash 命令形态的残留缺口）见
[guards.md](guards.md)「宿主原生能力与 role-guard 的分工」，本域不重复定义。

## 关键流程

<!-- 待后续 CR 填充 -->

## 对外接口

<!-- 待后续 CR 填充 -->

## 文件清单与影响范围

| 文件 | 职责 | 改动时需同步检查 |
|------|------|----------------|
| `agents/orchestrator.md` | 编排器角色契约：调度循环、质量门禁、经验采集 | `skills/mh-codeflow/SKILL.md`、`docs/designs/design.md` §3、`docs/designs/source-of-truth.md` |
| `agents/thinker.md` | Thinker 角色契约：三相位设计、需求规格产出（含 frontmatter） | `skills/mh-design/SKILL.md`、`skills/mh-slideflow/SKILL.md`、`docs/designs/design.md` §3、`docs/kb/domains/roles.md` 工具集表 |
| `agents/worker.md` | Worker 角色契约：TDD 编码、自测、精装交付（含 frontmatter） | `skills/mh-build/SKILL.md`、`docs/designs/design.md` §3、`docs/kb/domains/roles.md` 工具集表 |
| `agents/verifier.md` | Verifier 角色契约：独立验证、覆盖分析、缺陷报告（含 frontmatter） | `skills/mh-verify/SKILL.md`、`skills/mh-self-test/SKILL.md`、`docs/designs/design.md` §3、`docs/kb/domains/roles.md` 工具集表 |

## 约束与陷阱

### 改 `tools:` 前先核对协议要求的动作

工具集是**最小权限**，不是**不足权限**。收窄前须对照该角色在 `skills/` 中被要求执行的动作：
Worker 必须能跑 `mh-self-test`（测试/lint/build → 需 `Bash`），Verifier 必须能跑回归套件
与 `verify*.sh`（需 `Bash`）。删掉一个工具而协议仍要求该动作，角色会在运行期硬卡住，
且失败形态是「SubAgent 声称做了但没有工具」——比启动失败更难诊断。

反向同理：加工具须说明哪条协议动作要求它。Thinker 的 `Bash` 缺失是**有意**的
（思考者不执行），不是遗漏，不得以「方便自查」为由补上。

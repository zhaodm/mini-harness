# DeepSeek Harness (dsh) 替代可行性评估报告

## §1 首屏摘要

### §1.1 基本信息

| 字段 | 值 |
|------|-----|
| 评估日期 | 2026-08-17 |
| 评估问题 | 能否用 DeepSeek Harness (`dsh`) 替代 Mini-Harness |
| 对照快照 | dsh `47f94385`（2026-08-13，`0.1.0-rc.5`）· Mini-Harness `966dde6`（CR-019） |
| 证据来源 | 两仓库一手源码/git/PDF 核验 + 103 个验证 agent 三票对抗 + 网络检索（受限） |
| **评估结论** | **不替代，部分借鉴** |

### §1.2 一句话结论

**"用 dsh 替代 Mini-Harness"是范畴错误。** dsh 是 agent 运行时（对标 Claude Code
本体），Mini-Harness 是寄生在运行时之上的流程纪律层，两者是宿主与住客的关系。真实
问题不是"替代"而是**"是否换宿主"**——以现状换宿主不划算。

### §1.3 关键发现（按行动优先级）

| 编号 | 发现 | 性质 |
|------|------|------|
| **K-01** | Claude Code 官方插件 `feature-dev` 已用 256 行原生实现 Mini-Harness 的骨架；而本仓 `agents/*.md` 无 frontmatter、不在 `.claude/agents/`，**未用上 CC 原生的 per-agent 工具限制** | 立即可做，比迁移便宜数个数量级 |
| **K-02** | 现有 matcher `Write\|Edit\|NotebookEdit` 在 dsh 上**命中集为空集**，role-guard 一次都不会触发，且是**静默失效** | 迁移的第一个硬障碍 |
| **K-03** | dsh 零 git tag、零 CHANGELOG、零 release，64 天龄，破坏性变更集中砸在外部框架挂载所依赖的接缝上 | 换宿主的主要风险 |
| **K-04** | dsh 原生提供单一拦截点 + 内核级沙箱，恰好反转 Mini-Harness 自陈的两个缺口 | 迁移的唯一实质收益 |
| **K-05** | `tests/test-role-guard-authority.sh:1105` 只断言 Bash 缺口**被写进文档**，未断言其被关闭 | 既有测试的判据错位 |

---

## §2 层级定位：为何"替代"是范畴错误

### §2.1 规模与性质对照（本地一手核验）

| 维度 | Mini-Harness | dsh |
|------|--------------|-----|
| 本质 | 流程/纪律层，纯 Markdown + Bash | agent 运行时，约 50 个 capability family |
| 规模 | 428 文件 / 36.5k 行 | 7404 文件，pnpm monorepo，640 个 `*.spec.ts` |
| 运行时代码 | **无** TS 运行时、无模型调用层、无工具注册 | 自有 LLM 适配层、工具注册表、拦截点、Web UI + CLI |
| 挂载面 | 宿主的 hook / skill / subagent 机制 | 自己就是那个宿主 |
| 年龄 | 迭代至 CR-019 | 首次提交 2026-06-10，HEAD 2026-08-13，**64 天** |

### §2.2 结论

Mini-Harness 的全部机制——四层递进防线、文件态角色状态机、PreToolUse 写权归属表
——都以宿主 harness 的能力为前提。因此可能的关系只有两种：跑在 Claude Code 上，或
跑在 dsh 上。**不存在"dsh 替代 Mini-Harness"这一选项。**

> 限定：本节层级判断来自两仓库本地勘察。业界对 harness/runtime 与 orchestration
> 层的术语共识**未能通过网络检索证实**（见 §8）。

---

## §3 换宿主的第一个硬障碍：matcher 命中集为空集（K-02）

三段机制链均在 dsh 源码一手核验，并用 node 复算了匹配逻辑。

| 环节 | 依据 | 事实 |
|------|------|------|
| matcher 主体是 dsh 内部工具名 | `hooks-claude-code/src/index.ts` `runPoint('PreToolUse', exec.name, …)` | 全仓**无任何 CC→dsh 工具名映射表** |
| claude 方言走字面量精确等值 | `hook-protocol/src/matcher.ts:61` `pattern.split('|').includes(query)` | `CLAUDE_LITERAL = /^[A-Za-z0-9_\|]+$/`，**无大小写归一** |
| dsh 工具名全小写 | `tool-fs` `write`/`edit`、`str_replace_editor`、`tool-bash` `bash` | **不存在 `NotebookEdit` 概念**（全仓 grep notebook 零命中） |

**复算结果：** `['Write','Edit','NotebookEdit'].includes('write'|'edit'|'bash')` 全
为 `false`；改走正则回退分支同样不命中。

**失效方式是静默的。** 该 pattern 是合法字面量，`matcherDiagnostic` 只对非法正则产
诊断，故返回 `undefined`、无任何告警——守卫看起来装好了，实际全程不存在。dsh 自带
测试 `matcher.spec.ts:26` 显式钉死 `'Edit|Write'` 不命中 `'EditFile'`，佐证该语义是
有意设计而非缺陷。

**修复成本：** matcher 改一行即可（`write|edit|str_replace_editor|bash|pwsh`）。真正
的成本在脚本侧路径参数提取需分叉——`write`/`edit` 用 `file_path`（与 CC 同名，可复
用），`str_replace_editor` 用 `path`，`NotebookEdit` 分支变死代码。

---

## §4 dsh 成熟度与项目风险（K-03）

### §4.1 投入是真的

组织性投入证据充分：`deepseek-ai` 命名空间、`@deepseek-ai` npm scope、landlock 原生
沙箱、i18n 三件套（每篇 doc 配 `.md`/`.zh.md`/`.i18n.yaml`）、`THIRD_PARTY_NOTICES`
门禁、`.agents/notes` 决策记录制度（688 篇）、37 位贡献者 / 12293 commits / 110 篇
英文文档。

### §4.2 发布史是空的

| 检查 | 结果 |
|------|------|
| GitHub Releases API | 返回 `[]` |
| GitHub Tags API / `git ls-remote --tags` | 返回 `[]` / 零行（同会话 `ls-remote HEAD` 成功，排除网络失败） |
| 全仓 `git ls-files` | 无 CHANGELOG / RELEASE / migration guide |
| CI `release.yml` | 自述发布锚点是 `dsh-v*` tag——**该 tag 在公开远端不存在** |

版本标识只活在 commit subject 与 npm publish 里。README 第 9-11 行自陈 developer
preview 且 **"THERE WILL BE COMPATIBILITY-BREAKING CHANGES."**，全文无任何
production-ready / stable / semver 承诺。

### §4.3 破坏性变更砸在挂载接缝上

`!:` 标记的破坏性提交共 14 条，其中 9 条落在 2026-08-04 至 08-09 六天内。逐条
`git show --stat` 确认改动面：

| 提交 | 改动对象 |
|------|----------|
| `0512b12714` | 配置源统一排序 + bootstrap deny rule，动 CLI 三个入口并删配置键 |
| `0d53752c49` | retire `skill.invoke` RPC，动 host/skill/sdk/api 下 12 文件 |
| `62d0f26fd6` | profile/bundle manifest 改名到 `dsh.profile`/`dsh.bundle` 命名空间 |
| `f32aa54aeb` | `dsh run` 改为 headless 入口 |

**这正是 CLI 入口、配置加载、插件 manifest、RPC 边界——外部框架挂载的全部接缝。**

两项限定：`!` 约定 2026-07-29 才启用，此前 46 条提交带明确 breaking 动词却无标记
（故真实破坏率高于 14，本条属低估）；14 条全部早于 08-13 首次公开 npm 发布，属公开
前 churn 而非已对外造成的破坏——但对"是否把框架挂到 pre-1.0 preview 上"这一决策，
接缝变更节奏仍是正确的风险指标。

### §4.4 理论基础尚未在本域验证

一手核验 Cordis 论文 PDF（2,140,840 字节 / 88 页，草稿日 2026-08-13）：

- 目录仅一个案例章节 §5.3 Case Study: **Koishi**（聊天机器人框架）
- 正文 grep `benchmark` / `we evaluate` / `experiment` **零命中**
- 论文自陈："observational rather than a controlled comparison… an
  existence-and-adoption result rather than a quantitative one"
- 结论章把 **self-evolving agent harnesses 列为 future work**
- 版本落差：脚注 4 明言 Koishi 用 Cordis **v3**，本文提出的 **v4** "refines the
  effect and coeffect semantics and redesigns the loader"；dsh 钉住 cordis 4.0.x，
  且全 dsh 仓库 grep `koishi` **零命中**（无共享验证面）

### §4.5 模型耦合：不是硬耦合

`llm-pi-ai` 的 `provider.ts:50` 在 `PROTOCOLS` 表注册 `anthropic-messages`，README
官方示例直接给 `anthropic` + `ANTHROPIC_API_KEY` + `claude-sonnet-4-5`，并存在打真
Anthropic 端点的带凭据 e2e。四项限定：所有 `examples/*/cordis.snapshot.yml` 默认挂
`dsh-llm-deepseek`；`sdk/server/README.md:48` 自陈自动挂载 "is DeepSeek-specific"；
`discovery.ts` 的 `LISTABLE_PROTOCOLS` **不含** `anthropic-messages`（端点 model
列表探测对 Anthropic 路由不可用）；该 checkout 的 `node_modules` 为空，未运行时验证。

### §4.6 社区与生产使用：无法证实也无法否证

多轮网络检索对 deepseek-harness / dsh / hooks-claude-code 等查询返回零链接，
GitHub/npm 网页被环境策略拦截。**"是否有人在生产环境使用 dsh"在公开资料层面既无法
证实也无法否证。** GitHub API 报的 stars ~130k 与"公开仅 4 天、远端仅 13 个 ref"严重
不协调，**不建议采信该数字**。

**DeepSeek 的战略意图（长期产品 vs 阶段性产物）无任何公开信号，不得据此推断。**

---

## §5 迁移的唯一实质收益（K-04）

dsh 恰好把 CLAUDE.md §5 自陈的两个缺口反转了。

### §5.1 缺口对照

| Mini-Harness 自陈（CLAUDE.md §5） | dsh 的对应形态 |
|-----------------------------------|----------------|
| "`Bash` 通道不在 hook matcher 内、不受守卫覆盖" | **所有**工具调用经同一条 `tools/pre-execute` waterfall；`core/tools/src/index.ts:1476` 是唯一调用点，两条入口均汇入；`invariant.ts:94-110` 把"不得重复/不得绕过"断言为**运行期不变量**，结构性禁止绕过 |
| "判据存放在被治理方自己可写的文件中，故为**自授权机制**"；"防误撞而非安全边界" | 执行层**内核级**（Linux Landlock / macOS Seatbelt / Windows ACL restricted-token）；沙箱不可用时以结构化 `SANDBOX_UNAVAILABLE` **fail closed**；升权须 `ctx.approval` 人工批准且**仅作用于该次调用**；**模式写入路径不可被模型触达**（`setSandboxMode` 唯一调用者是 `/permissionPresets` 人类命令）；已提交的 settings 变更只在下次会话创建时读取 |

出厂即默认开启：`bundle/base/cordis.patch.yml:166-192` 为每个 CLI 模式挂
`sandbox-local` + `sandbox-policy`（默认 `workspace-write`）+ `bash-sandbox` +
`user-approval(policy:'ask')`。

### §5.2 两项必要收窄

1. **写 `bash` 不够。** 只覆盖 `tool-bash`；dsh 另注册 `pwsh`、`run_code`（Code Mode
   执行任意 TS/Python）、`cordis_run`、`terminal_open`/`terminal_send` 等任意代码执行
   面。全覆盖须枚举或用 `*`。
2. **沙箱只管文件效应**，网络与进程可见性有意不限制；`danger-full-access` 可整体关闭
   约束。组合可换（`examples/` 多处用未沙箱的 `dsh-bash-local`），故"原生"成立于出厂
   CLI bundle 形态，而非该接缝无条件成立。

### §5.3 抵扣项：桥的三个缺口

| 缺口 | 依据 | 对本框架的影响 |
|------|------|----------------|
| `configPath` **进程级、load 时读一次** | `index.ts:101` "Parse once at load"；`TODO(per-session-hook-config)` 在桥 README、Agent Note、姊妹 Codex 桥三处重复登记 | 一份进程级 `hooks.json` 无法按会话切换项目，与 `deliverables/` 多项目并存形态**直接冲突**；`${CLAUDE_PROJECT_DIR}` 亦在 load 期以进程级值替换 |
| PreToolUse 仅实现子集 | README:92 自陈 deny/ask 可用，**allow 不预批、defer 不支持、additionalContext 被忽略、updatedInput 只记日志** | exit-2 硬判据落在可用子集内；但守卫无法从"拦截"升级为"修正" |
| 只跑 `type: 'command'` shell hook | `http`/`mcp_tool`/`prompt`/`agent` 解析后跳过并告警；`args`/`async`/`if`/`once` 等选项不生效；匹配 hook **串行**执行（CC 为并行 + 去重） | 当前 role-guard 是 shell command hook，落在支持范围内 |

**缓解因素（已核验）：** `role-guard.sh:51` 的 `ROOT` 由 `${BASH_SOURCE[0]}` 推导，
`POINTER_FILE` 等全部 `$ROOT` 相对，**零处依赖进程 cwd**——故 cwd 敏感性这类痛点不
存在。且桥的 hook 确实跑在会话工作区（`index.ts:145-147` workdir 取
`session.header.cwd`，coverage 用例断言 "hook runs in the session cwd, not the
server cwd"）。

> **迁移前必须实机验证（对抗验证否决了"已保真"的强主张）：** exit 2 + stderr reason
> 经桥折叠后 reason 是否真的回传给模型；以及枚举 shell 工具名后参数面能否统一处理。

---

## §6 更要紧的发现：CC 官方已原生化本框架的一部分（K-01）

此项不在原始检索计划内，是勘察 Claude Code 插件市场时发现的。

### §6.1 官方插件 `feature-dev` 的形态

路径：`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/feature-dev`
（author: Anthropic）。**256 行做了 Mini-Harness 的骨架：**

| feature-dev | 对应本框架 |
|-------------|-----------|
| Phase 1 Discovery / Phase 2 Codebase Exploration | clarify |
| Phase 3 Clarifying Questions（标注 **CRITICAL / DO NOT SKIP**） | clarify 的追问纪律 |
| Phase 4 Architecture Design（并行 2-3 个 `code-architect`，分 minimal / clean / pragmatic 三取向）+ **Ask user which approach** | Thinker[design] + SR1 |
| Phase 5 Implementation（**DO NOT START WITHOUT USER APPROVAL**） | Worker |
| Phase 6 Quality Review（并行 3 个 `code-reviewer`，分 简洁性 / 正确性 / 项目约定） | Verifier + 质量门禁 |
| Phase 7 Summary | archive |

三个子代理 `code-explorer` / `code-architect` / `code-reviewer` 的 frontmatter 均声明
**`tools:` 白名单 + `model:` 选择 + `description:`**。

### §6.2 本框架的差距

```
本仓 agents/*.md：无 YAML frontmatter，且不在 .claude/agents/
→ 不是 CC 原生 subagent 定义
→ 角色契约以 prompt 文本注入通用 subagent（skills/mh-codeflow/SKILL.md:97）
→ 未使用 CC 原生的 per-agent 工具限制
```

**这意味着：** 用 345 行 Bash 在 hook 里做写权归属的同时，CC 允许在子代理定义里直接
声明它能用哪些工具。二者不互斥，但后者是免费的、且强制点在宿主侧而非被治理方可写侧。

> 限定：Claude Code 2026 年 hooks/subagents/skills/plugins 的**完整**能力边界未能
> 证实（搜索预算耗尽 200/200 + `docs.claude.com` 被网络策略拦截）。上述是本地官方
> 插件产物的一手证据，不是官方文档全貌。

### §6.3 既有测试的判据错位（K-05）

`tests/test-role-guard-authority.sh:1105-1111`（AC-08）断言的是
`docs/kb/domains/guards.md` 里**提到** `Bash`：

```bash
grep -q 'Bash' "$REPO/docs/kb/domains/guards.md"
```

即该测试确认缺口**被写进了文档**，而非确认缺口**被关闭**。这与 CR-019
"测试不变量的判据对象归位"是同一类问题的另一个实例。

---

## §7 建议

### §7.1 结论：不替代，部分借鉴

成本收益错配。收益集中在一处（单一拦截点 + 内核级沙箱可把自授权守卫升级为真边界），
成本是把 2898 行 Bash 重写为 Cordis 插件、学习 pnpm monorepo + Cordis 范式，并把整套
流程纪律押在一个零 tag、零 changelog、64 天龄、正在 CLI 入口/配置源/manifest/RPC 上
连续 breaking 的 developer preview 上。

### §7.2 五条行动项（按优先级）

| # | 动作 | 理由 |
|---|------|------|
| 1 | **先用 CC 原生能力替掉自研**：给 `agents/*.md` 加 frontmatter、移入 `.claude/agents/`、声明 `tools:` 白名单 | 直接削掉 role-guard 的一部分职责，无需迁移；参照 §6.1 官方形态 |
| 2 | **把守卫判据移出被治理方可写区**：`.engine/.state.md` 由持权角色自己写是自授权的根因，改为 ORCHESTRATOR 独占写入的独立判据文件 | **可在不迁移的前提下独立求解**，其答案会显著改变迁移的性价比 |
| 3 | **处理 Bash 逃逸口**：纳入 matcher 或以脚本包装收窄 | 不要停在"已自陈"；并修正 §6.3 的判据错位 |
| 4 | **吸收 dsh 的 `.agents/notes` 决策记录制度** | 与现有 CR-0xx 编号体系天然兼容 |
| 5 | **按 fail-closed 复核默认放行分支** | CLAUDE.md 已列五种 `exit 0` 放行形态，逐条复核是否应收紧 |

### §7.3 重估触发信号

| 信号 | 含义 |
|------|------|
| dsh 出现首个 stable tag + CHANGELOG | 当前两者皆无，最直接的成熟度闸门 |
| `TODO(per-session-hook-config)` 关闭 | 多项目并行的硬前提 |
| 桥支持 allow 预批与 `updatedInput` 生效 | 决定守卫能否从"拦截"升级为"修正" |
| **需求从"防误撞"升级为"真安全边界"** | 多租户或执行不可信代码时，CC 的 hook 模型本身不够，dsh 的 Landlock/Seatbelt 路线是现成答案（与 dsh 成熟度无关，同等重要） |

---

## §8 证据强度与未覆盖项

### §8.1 证据结构失衡（最重要）

本报告在**代码机制**维度证据极强（两仓库一手源码/git/PDF 核验 + 103 个验证 agent
三票对抗），在**社区、采用、竞品格局**维度**证据极弱**——网络检索近乎全空，搜索预算
在验证阶段耗尽（200/200），`docs.claude.com` 与 `json.schemastore.org` 被网络策略
拦截。

因此 §7 "留在 Claude Code" 的建议建立在**"迁移成本高"**之上，而非
**"CC 已原生覆盖全部机制"**——后者仅有 §6 的局部证据，需单独调研。

### §8.2 明确未覆盖

- **8 步调度循环 / handoff 契约 / SR 断点能否落到 dsh 的 workflow / subagent /
  preset / goal 上——零主张通过验证。** `subagent-claude-code` 的
  `inheritsParentContext: false`（子 agent 拿不到父上下文/persona/tool filter/结构化
  输出契约）对"角色严格隔离"是天然契合还是致命障碍（它同时意味着 handoff 语境无法经
  上下文传递）——**这是迁移可行性的最大未知块**
- dsh skill 发现不含 `.claude/skills`（默认根为 `.dsh/skills` 100 / `.agents/skills`
  200 / custom 300 / `~/.dsh` 400 / `~/.agents` 500）的实际迁移代价：symlink 是否够
  用，还是须改写 frontmatter
- LangGraph / CrewAI / AutoGen / OpenHands / Kiro spec-driven / Cline / Roo Code /
  Aider 的横向对比——全部未获证据
- 业界 harness/runtime vs orchestration 层的术语共识——未证实

### §8.3 时效性

所有 dsh 事实基于 2026-08-13 快照（HEAD `47f94385`，`0.1.0-rc.5`）；本报告日期
2026-08-17。该仓库历史速率约 **192 commits/day** 且自陈随时 breaking，故行号、工具
名、TODO 状态均是"该 commit 的事实"而非持久 API 保证。npm 上已出现比公开 master 更新
的 `0.1.0-rc.6`。

### §8.4 已被对抗验证否决、不得引用

- npm 下载量的有机性分析、兼容桥单独发包的下载量与 dist-tag 落后论
- "Issues 被关闭故缺陷不可外部审计"
- "Koishi 的 4000 插件采用证据不适用于 v4"
- **"deny 语义完整保真故脚本无需改写"**（0-3 被否）
- **"把 bash 写进 matcher 即可覆盖 shell 通道"**

后两条尤需注意——都须迁移前实机验证，不得按已确认处理。

### §8.5 两项精度提醒

- dsh 的"40 位提交者"是**邮箱身份数**（distinct 人名 37，真实人头 ≤37）；
  `@deepseek.com` 邮箱仅占提交的 **18%**（最大贡献者 42.6% 用 GitHub noreply），故
  "公司投入"结论靠**组织命名空间与发布工程**成立，而非邮箱域
- "dsh 任何 API 都未经稳定周期"的全称说法过宽：vendor 层的 cordis / cosmokit /
  schemastery 有多年上游历史，而它恰是改写插件时要依赖的 API 面；真正 ≤64 天的是
  dsh 自有的约 50 个 capability family

---

## §9 参考来源

**本地一手核验**

- `/Users/dz/Code/deepseek-harness`（HEAD `47f94385`）
- `/Users/dz/Code/mini-harness`（HEAD `966dde6`）
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/feature-dev`

**网络来源**（由子代理访问；主会话直接 fetch 时 GitHub / npm / docs 域被拦截）

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) ·
  [releases（返回空）](https://github.com/deepseek-ai/deepseek-harness/releases)
- [cordiverse/cordis](https://github.com/cordiverse/cordis) ·
  [Cordis 论文](https://github.com/cordiverse/paper)
- [@earendil-works/pi-ai](https://www.npmjs.com/package/@earendil-works/pi-ai) ·
  [@deepseek-ai/node-addon-landlock-run](https://www.npmjs.com/package/@deepseek-ai/node-addon-landlock-run)

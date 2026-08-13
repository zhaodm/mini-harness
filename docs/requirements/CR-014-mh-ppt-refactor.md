---
id: CR-014-mh-ppt-refactor
title: mh-ppt 整体重构 —— 渲染态门禁 + 版式登记 + 单文件形态 + 密度模型
status: draft
design_doc: docs/designs/cr-designs/CR-014-mh-ppt-refactor-design.md
created: 2026-08-12
---

# CR-014: mh-ppt 整体重构

> 归档路径: docs/requirements/CR-014-mh-ppt-refactor.md（本文件）
> 运行态精简: tools/mh-dev/.mh-dev/requirement.md（基于本单精简为 Developer 可执行指令）
> 洞察来源: docs/audits/2026-08-12-mh-ppt-competitive-analysis.md（该目录被 .gitignore 忽略，不入版本控制）

## 背景

对比分析（2026-08-12）以三个同类 AI Agent Skill 项目为对标——guizang-ppt-skill（23.8k star）、frontend-slides（27.3k star）、ppt-master（45.0k star），得出结论：**mh-ppt 在流程治理上领先所有对标项目，在质量门禁的实现上落后一代。**

领先项（对标项目均不具备）：阻塞式 wireframe 审批（SR1 在生成前拦截，对手都是生成后才让人看）、Thinker/Worker/Verifier 强隔离（对手均为单 agent 自检）、全链路过程留痕。

落后项及其根因——现有门禁存在三个已实测复现的失效缺陷：

| 缺陷 | 位置 | 实测表现 |
|---|---|---|
| 字号检查静默失效 | `scripts/verify-ppt.sh:137` | `grep -oP` 是 GNU 扩展，macOS BSD grep 不支持；`2>/dev/null` 吞报错 + `\|\| true` 吞退出码 → 检查恒定通过。同一文件交互 shell 检出 42 处违规，纯 bash 脚本检出 0 处 |
| 页数检查必然误报 | `scripts/verify-ppt.sh:206` | 漏 `-maxdepth 1`（L60 有），wireframe 子目录被重复计数。实测 3 页 spec + 3 产出 + 3 wireframe → 报"实际 6 页 FAIL" |
| 整数比较报错被吞 | `scripts/verify-ppt.sh:204` | `grep -c` 无匹配时输出 `0` 且返回码 1，`\|\| echo "0"` 产出 `"0\n0"`，`[` 报语法错但仍 exit 0 虚假通过 |

更根本的问题：**CLAUDE.md §5「脚本硬约束优先于自然语言软约束」在 PPT 轨上没有落地。** 硬约束是空转的，实际生效的仍只有软约束——投入最多笔墨的"字号底线"从未被脚本拦住过一次。

同时，`verify-ppt.sh` 全部检查均为 grep 字符串匹配，机制上无法感知页面溢出、元素重叠、留白过多——而这恰是 `docs/retrospectives/` 与框架记忆中反复出现的痛点。对标项目已进入渲染态测量（实测 DOM 与视觉溢出像素）。用 grep 防"空白太多"，机制上不可能成立。

## 需求

### R1: 校验范式从静态匹配升级为渲染态测量

PPT 门禁须在真实浏览器渲染后测量每页的几何事实，而非匹配 HTML 源码字符串。须能测得并报告：

- 页面内容是否超出舞台边界（区分 DOM 溢出与视觉溢出）
- 元素之间是否存在意外重叠
- 页面留白占比是否过大（防止修溢出时过度收缩，反向制造"空白太多"）
- 标题与相邻内容的间距是否低于可读下限

失败报告须可定位到具体元素与偏差量，使修复无需人工逐页目测比对。

渲染测量环境缺失时，门禁须**报错并以非 0 退出码阻断**，不得降级为"跳过该项但整体通过"。理由：静默降级正是本次三个缺陷的共同成因，与 CLAUDE.md §5「以脚本退出码为准」直接冲突。

⛔ 本条要求「测量渲染结果」，不指定测量工具、不指定实现语言。

### R2: 版式须可声明、可统计，使视觉多样性约束成为机器事实

`skills/mh-slideflow/SKILL.md` 现有的视觉叙事原则（至少涵盖 4 种布局类型、连续 3 页以上禁止同一布局、视觉焦点唯一性等）目前只能靠 Verifier 目测，脚本零覆盖。

须建立版式声明机制：每页在产出中声明其所用版式标识，使"版式分布"成为可被脚本统计的事实，从而将上述软约束转为可验证的门禁项。

约束强度须按 `ppt_design_mode` 区分：

- **system 模式**：声明的版式须来自框架登记的版式集合
- **creative 模式**：只要求声明标识以支撑多样性统计，不限制取值

⛔ creative 模式不得被版式集合锁定——对标项目 guizang 的硬锁定服务于"单一风格保真"，而 mh-ppt 的 creative 模式以自由创意为存在理由，锁定会使其失去意义。

### R3: 产出形态改为单文件，舞台等比缩放适配视口

当前每页一个 HTML（`templates/output-structure.md` L105）导致三个后果：无法整体分发、导航须每页重复实现、且是演讲者模式与导出能力的前置障碍。三个对标项目均为单文件。

须改为：整套演示稿为单一 HTML 文件产出；导航逻辑在文件内实现一次，不逐页重复。

同时舞台须支持等比缩放：内部按 1920×1080 固定尺寸布局，整体等比缩放至实际视口，允许留边（letterbox/pillarbox），但**禁止因视口变化而重排页面内容**。理由：投影仪与外接屏分辨率不总是 1920×1080，当前固定视口在非标准分辨率下会出现裁切或滚动。

附带须解决：`skills/mh-slideflow/SKILL.md` L160 与 `templates/ppt-quality-rules.md` L27 要求"统一引用 `js/navigator.js`"，但该文件在框架内不存在（全仓库仅 2 处文字提及，无实体）。

### R4: 引入内容密度模式，字号底线按密度分档

当前字号底线（`templates/ppt-quality-rules.md`）只有一套数值，把演讲型与阅读型两种场景强行合并。实测框架自带模板有 141 处 font-size < 18px，其中 W01-W05 五个浅色版式占 131 处（最小 9px）——这些是仪表盘/数据表型高密度版式，其小字号是有意的密度选择，而非实现错误。用单一底线判定它们"违规"，判断本身就是错的。

须引入密度模式并在需求澄清阶段确认：

- **低密度（演讲型）**：一页一个观点、大字号、留白充裕
- **高密度（阅读型/仪表盘）**：自包含信息、结构化网格与数据表、紧凑但有意的间距

字号底线须按密度分档，两档各有独立数值。同时须区分**可读文字**与**图形装饰符号**——`templates/ppt-light.css` 的 `.trend-arrow` 使用 8px 承载 ▲▼ 箭头字符，它是图形元素而非阅读内容，不应受文字底线约束。

密度选择须影响：字号底线档位、页数规划、每页信息量。

据此，各模板的定性如下。

⚠️ **前提修正（设计阶段实测发现）：** 两套主题声明**相同的 1920×1080 画布**，但字阶相差约 1.9 倍——`ppt-base.css` 的 `--font-body: 26px` / `--font-caption: 18px`，`ppt-light.css` 为 `14px` / `11px`。1920 画布上 14px 正文属网页尺度而非演示尺度。git 时序印证：W 系列（`bf29dad`）早于字号经验 commit（`c1a9720`），而该 commit 只上调了 `ppt-base.css`，从未触及 `ppt-light.css` 或任何 W 文件。W01 的 22 处 9px 全部是 `color:var(--text-muted)` 标签——正是 `--font-caption` 应服务的角色，而深色主题该值为 18px。

因此"131 处均为有意的密度选择"只有一半成立：W03/W04 的表格与卡片标签确属密度需要，而整套 `ppt-light.css` 变量集是未迁移的遗留尺度。若全部正名，等于永久制度化两套主题的尺度分歧。**高密度底线须以字排依据取值（定为 14px），而非以 W 系列现状取值。**

| 对象 | 定性 | 处置 |
|---|---|---|
| `ppt-light.css` 变量集 | 未迁移的遗留尺度，非密度选择 | 整体上调（caption 11→14、body 14→18、subtitle 17→22、title 24→32） |
| `W03`/`W04` 的 13px 小幅违规 | 高密度需要，接近底线 | 上调至 14px 达标 |
| `W01`/`W05` 的 9-11px（87 处） | 大量依赖 caption 级别，随变量集迁移 | 重构至高密度底线 |
| `ppt-light.css` 的 8px ▲▼ | 图形装饰符号 | 归为图形元素，不受文字底线约束 |
| `L02`（3 处 11px）、`L09`（4 处 10px） | 深色 L 系列，低密度定位 | 视为违规，须修正至低密度底线 |

高密度档底线定为 **14px**（1920 画布上约等于 1024 画布的 7.5px，偏小但仪表盘场景可接受）；低密度档沿用现有 ≥18px 体系。

⛔ 无论分档如何设计，字号检查须覆盖 CSS 文件——现有检查只扫 `*.html`（`verify-ppt.sh` L99/L177），而设计体系模式下字号主要来自 CSS 变量与 class，仅查 HTML 会使 `ppt-light.css` 内的字号完全逃逸。

### R5: 补齐演讲者模式骨架与导出能力

"上台演讲"与"发给他人"是演示稿的基本使用场景，当前两者皆无。

须提供演讲者模式，范围限定为骨架：双屏同步、计时、讲稿备注。须提供导出为可分发静态文件的能力。

⛔ 明确不做：排练记录、激光笔、圈选、黑白屏、断线恢复、演前检查。对标 guizang 的完整演讲者模式规模庞大（其 checklist P0 首条即数十行约束），全量引入与 CR-009 刚完成的上下文瘦身成果冲突。

### R6: 修复三个已确认的门禁失效缺陷

背景节表格所列三个缺陷须全部修复，且修复后须能证明门禁真实生效（即：能对违规输入产生非 0 退出码）。

⛔ 校验脚本不得依赖 GNU grep 专有扩展（`-P`/`\K`/`(?=)`）。仓库运行于 macOS，`/usr/bin/grep` 为 BSD grep；交互 shell 中的 `grep` 可能被 ugrep 等实现接管而支持 `-P`，导致人工验证通过、脚本执行失效——两者不是同一个 grep。

⛔ 校验逻辑不得以 `2>/dev/null` 配合 `|| true` 包裹关键检查，使错误与退出码同时被吞没。

### R7: 上下文成本不得随能力增长而失控

CR-009 刚完成角色文件瘦身与上下文分层（`skills/mh-slideflow/SKILL.md` 现 176 行）。本次新增能力（密度模式、版式登记、演讲者模式）会带来文档增量。

须采用渐进式加载：入口只承载轻量索引与路由，详细规格在实际需要时才加载。对标 frontend-slides 的分层做法（先读轻量 preview 卡片，用户选定后才加载完整 design.md）。

⛔ 不得将对标项目的文档体量整体搬入（guizang 为 632 行 SKILL + 数千行 references）——那会直接推翻 CR-009 的重构成果。

### R8: 引用完整性与既有契约保持

重构后所有跨文件引用须仍指向有效位置。`skills/mh-slideflow/SKILL.md`、`templates/ppt-*`、`scripts/verify-ppt.sh`、`scripts/check-harness.sh`、`docs/designs/source-of-truth.md`、`docs/kb/domains/templates.md` 等引用方须同步更新。

`docs/designs/source-of-truth.md` 须同步更新概念归属映射。

## 非目标

- 不改变 mh-ppt 的流程骨架（clarify → propose → apply → archive）与 SR 审批节点——这是本方案相对对标项目的核心优势，须完整保留
- 不改变 3-role spine 的角色划分与职责边界
- 不改变 `role-guard.sh` 权限模型（已确认其按角色名前缀而非单文件归属放行，单文件产出无需调整权限模型）
- 不改变 `/mh-run` code track 的任何行为
- 不引入模板包扩张（对标 frontend-slides 有 40+ 模板包、582KB；mh-ppt 现有 17 个版式数量够用，问题在约束力不在数量）
- 不引入 skill 开局检查上游更新机制（guizang 需要它是因为其为独立分发的 skill；mh-ppt 是本仓库组成部分）
- 不做 `.pptx` 原生输出（ppt-master 的路线，与 HTML 演示稿定位不同）

## 影响范围

初步识别如下，须在设计阶段以 `scope-scan.sh` 确认完整列表：

### 脚本
- `scripts/verify-ppt.sh` — 三缺陷修复 + 渲染态测量 + 版式统计 + 密度分档校验（主体重构）
- `scripts/fix-ppt-fonts.py` — 定位复核结论：**已移除**。门禁前移至生成时拦截后，事后批量上调字号的补救手段与密度分档不兼容（其映射表按单一 18px 底线设计），且会破坏密度设计意图
- `scripts/check-harness.sh` — 同步框架完整性清单（新增/移除文件）

### Skill 与模板
- `skills/mh-slideflow/SKILL.md` — 密度模式澄清、版式声明要求、单文件形态、渐进式加载改造
- `templates/ppt-quality-rules.md` — 字号底线按密度分档 + 文字/图形符号区分
- `templates/ppt-slide-spec-template.md` — 密度字段、版式标识字段
- `templates/ppt-base.css`、`templates/ppt-light.css` — 舞台等比缩放；`ppt-light.css` 的 8px 定性标注
- `templates/ppt-base.html` — 单文件骨架 + 导航
- `templates/ppt-templates/layouts/L02`、`L09` — 字号修正至低密度底线
- `templates/ppt-templates/layouts/W01`-`W05` — 标注为高密度版式（不改字号）
- `templates/ppt-templates/layouts/*` — 全部 17 个补版式标识
- `templates/output-structure.md` — ppt 产出形态描述（L105）
- 新增：导航/演讲者模式脚本实体（解决 `js/navigator.js` 缺失）

### 文档
- `docs/designs/source-of-truth.md` — 概念归属映射
- `docs/designs/design.md` — 脚本与模板清单（L363、L396）
- `docs/kb/domains/templates.md` — 模板体系内部结构（L37、L105）

### 依赖
- `package.json` — 新增渲染测量依赖（当前仅 4 行占位，无 dependencies；node v22.22.1 已就绪，playwright 未安装）

### 测试
- `tests/` — 由 Tester 独占产出，本单不指派具体测试文件

## 轨道判定

**formal。**

为何不够 light 轨：light 轨要求「无状态机/角色边界/发布契约变化」且「可局部回滚」。本单同时违反两条——R1 新增渲染态门禁契约、R2 新增版式声明契约、R3 变更产出形态（产品区文件结构），属发布契约变化；且 R3 的产出形态变更与 R1/R2/R4 的校验契约相互耦合（单文件是演讲者模式前提、密度模型是字号门禁前提），无法逐项局部回滚。

另有多处设计决策需 formal 轨的设计审批：渲染测量的实现选型与失败语义、版式登记表的粒度、密度分档的具体数值、演讲者模式的骨架边界。

## testcase_adding_required

**true** — 涉及脚本逻辑重构（`verify-ppt.sh` 主体）、新增校验能力（渲染态测量、版式统计、密度分档）、行为变化（门禁从恒定通过变为真实拦截）。

尤其须覆盖：三个已确认缺陷的回归测试（含 BSD grep 环境下的字号检查真实生效性），以及渲染测量环境缺失时的阻断行为。

## 风险与回滚

**风险：**

1. **门禁真实生效后暴露既有违规** —— 现有 141 处字号问题中，131 处经 R4 正名为合法高密度版式，7 处（L02/L09）须修正。若密度分档数值设计不当，可能出现大面积意外 FAIL
2. **渲染测量引入环境硬依赖** —— 首次运行需下载约 150MB Chromium；未装环境者无法运行 PPT 门禁。这是 R1 明确接受的代价（已确认硬依赖优于静默降级）
3. **单文件形态改变产出结构** —— 归档、`verify-archive.sh`、`output-structure.md` 等下游可能有隐含假设
4. **渲染测量执行耗时** —— 逐页启动浏览器测量比 grep 慢若干数量级，可能影响修复循环的迭代速度
5. **上下文膨胀** —— R7 是防护条款，但新增能力的文档增量与瘦身目标存在张力

**回滚：** 涉及脚本逻辑、模板结构、依赖三处变更，且产出形态变更影响下游。回滚不干净——须整体 `git revert` 本次 commit，不可逐项回退。回滚后 `package.json` 新增依赖须一并移除。

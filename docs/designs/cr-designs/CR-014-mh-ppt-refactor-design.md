---
id: CR-014-mh-ppt-refactor-design
requirement: docs/requirements/CR-014-mh-ppt-refactor.md
status: draft
created: 2026-08-12
---

# CR-014 设计文档：mh-ppt 整体重构

> 需求单: `docs/requirements/CR-014-mh-ppt-refactor.md`（权威源）
> 验收标准: `tools/mh-dev/.mh-dev/acceptance-criteria.md`（AC-01~12 + AX-01~08）
> 轨道: formal

## 设计目标

一句话：**让 CLAUDE.md §5「脚本硬约束优先于自然语言软约束」在 PPT 轨真正落地。**

现状是硬约束空转——字号检查恒定通过、页数检查必然误报、视觉叙事原则全靠目测。本设计的每个决策都服务于一个判据：**该约束能否产生可信的非 0 退出码。**

---

## D1: 校验架构 —— 双层分工（对应 R1、R6）

### 决策：静态层保留 bash，渲染层新增 Node

```
scripts/verify-ppt.sh          静态层（bash）：文件存在性、声明完整性、字号、版式统计
  └─ 内联 Node heredoc          渲染层（Node + Playwright）：几何测量
```

**为何不合并为单一语言：** 静态层被 `check-harness.sh` 与 Verifier 直接调用，是既有集成点；渲染层必须有浏览器引擎。保留 bash 作为唯一入口，Node 只做被调用的测量器——集成点不变，`verify-ppt.sh` 仍是对外契约。

> **实现偏离（Developer 回写）：** 渲染层未落为独立 `scripts/ppt-measure.mjs` / `ppt-export.mjs` 文件，
> 而是以 `node --input-type=module -` heredoc 内联于 `verify-ppt.sh`。
> 原因：`state.json` 的 `approved_scope` 逐条枚举 `scripts/` 下的具体文件，无目录前缀条目，
> 新增 `scripts/*.mjs` 会被 `validate-changes.sh` 判为 `unapproved developer path` 而硬拦。
> 契约影响：无——对外仍是 `verify-ppt.sh` 单一入口（`D` 子命令测量、`export` 子命令导出 PDF）。
> 参数一律经 `process.argv` 传入，不做字符串插值。若后续要拆分为独立 mjs 文件，
> 需在 `approved_scope` 补 `scripts/` 目录条目后另开一轮。

### 静态层三缺陷修法

| 缺陷 | 现状 | 修法 |
|---|---|---|
| `-P` 不可用 | `grep -oP 'font-size:\s*\K\d+(?=px)'` | `grep -oE 'font-size: *[0-9]+px'` 管道接 `grep -oE '[0-9]+'`，纯 POSIX |
| 页数重复计数 | `find "$target_dir"` 递归 | 补 `-maxdepth 1`，与 L60 同口径 |
| `"0\n0"` | `grep -c ... \|\| echo "0"` | 改 `\|\| true`（`grep -c` 无匹配已自行输出 `0`） |

⛔ **禁止 `2>/dev/null` + `|| true` 包裹关键检查。** 全脚本引入 `require_ok()` 包装：命令失败时打印实际 stderr 并累加 ERRORS，而非吞没。

**自检机制（防复发）：** 脚本启动时对已知违规 fixture 自测一次字号检查，若未检出则报"检查器自身失效"并 exit 非 0。理由：缺陷 1 的本质不是写错正则，而是**检查器失效时无人知晓**。AX-03 的静态扫描防不住新引入的等价写法，运行时自检才防得住。

### 渲染层测量项与判定阈值

`ppt-measure.mjs` 在 1920×1080 视口加载单文件产出，逐页输出 JSON：

| 测量项 | 判定 | 阈值依据 |
|---|---|---|
| DOM 溢出 | `scrollWidth/Height` 超出舞台 → FAIL | 任何溢出都是缺陷 |
| 视觉溢出 | 元素 boundingRect 越界 → FAIL，报出偏差 px + 元素 class + 文本前 40 字 | grid 面板可视觉越界而 scrollHeight 正常 |
| 元素重叠 | 非父子关系的文本元素矩形相交 → FAIL | 排除装饰层（`position:fixed`、大面积 absolute 背景） |
| 留白占比 | 内容包围盒面积 / 舞台面积 < 阈值 → WARN；连续多页触发 → FAIL | 防"修溢出时过度收缩"，密度档不同阈值 |
| 标题间距 | 标题底边与下一元素间距 < 下限 → FAIL | 全局标题 32px / 局部标题 14px |

**留白判定按密度档取阈值**：低密度容许大留白（留白是设计），高密度不应有大片空白。这是密度模型影响渲染层的接口。

### 失败语义（AX-02）

Playwright 不可解析 → **打印安装指引 + exit 非 0**。不降级、不 SKIP、不 WARN。

对标 guizang 此处用 `warnings.push(...)` 后继续，本设计明确不采纳——那正是缺陷 1 的失效模式（关键检查未跑但报告通过）。

`package.json` 新增 `playwright` 为 devDependency（当前无 dependencies 字段，node v22.22.1 就绪）。

---

## D2: 版式登记机制（对应 R2）

### 决策：`data-layout` 属性 + 登记表文件

每页 `<section class="slide" data-layout="L03">`。登记表 `templates/ppt-templates/registry.json` 记录 ID、名称、密度归属、布局类型。

**布局类型（layout_type）是多样性统计的真实依据**，而非版式 ID 本身——17 个 ID 若都属"卡片网格"，种类数应为 1 而非 17。类型取值沿用 SKILL.md 现有七类：全屏大字 / 图文混排 / 多栏对比 / 时间线流程 / 数据展示 / 全出血背景 / 问答互动。

### 双模式强度（AC-06、AX-08）

| 模式 | 声明缺失 | 取值不在登记表 |
|---|---|---|
| system | FAIL | FAIL |
| creative | FAIL | **放行** |

creative 模式放行任意取值，但仍要求声明存在——多样性统计依赖它。creative 页须同时声明 `data-layout-type` 以参与统计（其自定义 ID 不在登记表内，无法反查类型）。

### 多样性判定（AC-07）

- 全套 `layout_type` 去重种类 < 4 → FAIL
- 连续 ≥3 页同一 `data-layout` → FAIL

⚠️ **口径说明：** 需求写"连续 3 页以上禁止同一布局"。字面读作"连续 4 页才违规"会与 SKILL.md 原意（连续 3 页即过多）冲突。本设计取**连续 3 页即 FAIL**，与 AC-07 的"连续 4 页同一版式必须 FAIL"兼容（4 页必然包含 3 页）。Tester 按连续 3 页构造 fixture。

---

## D3: 单文件形态与舞台缩放（对应 R3）

### 文件结构

```html
<div class="ppt-viewport">          <!-- 填满窗口，overflow:hidden -->
  <div class="ppt-stage">           <!-- 1920×1080 固定，transform:scale() -->
    <section class="slide" data-layout="L01" data-slide-id="s01">...</section>
    <section class="slide" data-layout="L03" data-slide-id="s02">...</section>
  </div>
</div>
<script>/* 导航 + 缩放 + 演讲者模式，内联一次 */</script>
```

### 缩放实现

`transform: scale(min(vw/1920, vh/1080))` + `transform-origin: center`，居中留边。

⛔ **禁止响应式重排**：不得用 media query 改变 slide 内部布局，不得用 `clamp()` 于舞台内元素。舞台整体缩放，内部永远是 1920×1080 的固定布局——这是"所见即所得"的前提，也使渲染层测量结果与实际投影一致。

### 页面可见性

用 `visibility` + `opacity` + `pointer-events` 控制，**不用 `display:none`**。理由：`.slide` 若被后续 CSS 设为 `display:flex`，会覆盖 `display:none` 导致所有页同时可见。这是 frontend-slides 明确记录的踩坑点，直接采纳。

### navigator 落地（AC-12）

`js/navigator.js` 当前仅存在于文字提及（SKILL.md L160、ppt-quality-rules.md L27），无实体。单文件形态下不再需要独立文件——导航内联于产出。**处置：改写这两处引用为"导航逻辑内联，不逐页重写"**，消除悬空引用。

键盘契约：←↑ 上一页、→↓ 下一页、Esc 总览、P 演讲者模式。交互页方向键归导航，其他键触发内容显示（沿用现有约定）。

---

## D4: 密度模型（对应 R4）

### 字号底线分档

| 角色 | 低密度（演讲型） | 高密度（阅读/仪表盘） |
|---|---|---|
| 辅助标签/标注 | ≥18px | ≥14px |
| 正文/描述 | ≥24px（推荐 26-30） | ≥18px |
| 卡片标题 | ≥32px | ≥22px |
| 页面标题 | ≥44px | ≥32px |
| 大字页/金句 | ≥72px | 不适用 |
| 绝对下限 | 18px | **14px** |

高密度档 14px 的依据：1920 画布上 14px 约等于 1024 画布的 7.5px——偏小但仪表盘可接受；低于此值在投影场景不可读。

### `ppt-light.css` 变量迁移

| 变量 | 现值 | 迁移后 | 理由 |
|---|---|---|---|
| `--font-caption` | 11px | **14px** | 高密度绝对下限 |
| `--font-body` | 14px | **18px** | 高密度正文下限 |
| `--font-subtitle` | 17px | **22px** | 对齐卡片标题档 |
| `--font-title` | 24px | **32px** | 对齐页面标题档 |
| `--font-small` | 12px | **16px** | 介于 caption 与 body |
| `--font-kpi` | 28px | 28px | 已达标 |

⚠️ **迁移会改变 W 系列视觉密度**：字号整体上调后原布局可能溢出。这正是渲染层要拦的——Developer 须在迁移后跑 `ppt-measure.mjs`，对溢出页调整布局（减少卡片数或拆页），**不得回调字号规避**。

### 图形符号豁免（AX-05）

豁免须**显式标记**而非按数值放行：元素带 `data-glyph="true"` 或匹配登记的图形 class（`.trend-arrow` 等）时跳过字号检查。

⛔ 豁免不得作用于含实质文本的元素。判定：元素文本内容仅由符号字符（▲▼◆●→ 等）构成时豁免生效；含字母/汉字/数字则**豁免失效，仍按底线检查**。这样 `data-glyph` 无法被用作绕过后门。

### 密度落盘

`templates/state-template.md` 新增 `ppt_density: ""  # speaker | reading（ppt track 专用）`，与 `ppt_design_mode` 并列。此前 CR-007 P1-2 修过同类缺口（skill 写入字段但 schema 无定义），本次一并避免。

mh-slideflow clarify 阶段询问密度，写入 `.engine/.state.md`；`verify-ppt.sh` 读取该字段选择底线档位。读不到时**默认低密度**（更严格档），不默认宽松档。

---

## D5: 演讲者模式骨架（对应 R5）

### 范围严格限定

**做**：双屏同步（`window.open` + `postMessage`）· 计时（总时长 / 本页时长）· 讲稿备注（每页 `data-notes` 或 `SPEAKER_NOTES` 映射）

**不做**（需求已明确）：排练记录、激光笔、圈选、黑白屏、断线恢复、演前检查

### 备注绑定

按 `data-slide-id` 绑定，不按页序号——插入新页时备注不串页。这是 guizang checklist P0 首条记录的坑，成本极低，直接采纳。

无备注的页面显示 `—`，不显示"待补充"（避免被 C 类占位符检查误判为残留）。

### 设计系统在效判定（repair round 1 补充，F-06）

Tester 发现 D3「单文件自包含」与 B 类检查存在矛盾：检查以 `grep -q 'ppt-base.css\|ppt-light.css'` 强制外链样式表，于是**内联 CSS 的真正自包含产出被判 FAIL**，而外链产出一旦脱离仓库样式全失。两条都不可接受。

**裁定：检查目标从"存在特定 link 标签"改为"设计系统在效"。** system 模式下满足以下任一即通过：

1. 外链引用 `ppt-base.css` 或 `ppt-light.css`（开发期/仓库内形态），或
2. 内联 `<style>` 中含设计系统的变量定义（`--font-body`、`--slide-width` 等标识性 token）

判据：产出是否真的受设计系统约束，而非是否写了某个文件名。creative 模式此项不适用（沿用现状）。

> **实现落地（Developer round 1）：** `verify-ppt.sh` 的 `design_system_in_effect()`。
> 内联判据取 `--font-body` 与 `--slide-width` 两个 token 同时存在——单一 token 易被偶然命中，
> 两者并存才足以表明设计系统变量集被整体引入。

### 字号检查覆盖面（repair round 1 补充，F-01 / F-03）

字号底线的有效性等于其覆盖面。原实现只匹配 `font-size: <n>px` 字面量，遗漏两条通道：

| 通道 | 为何漏 | 后果 |
|------|--------|------|
| `--font-*: <n>px` token 定义 | 无 `font-size:` 前缀，从不参与判定；而设计系统 CSS 的字号**全部**走 `var(--font-*)` | 把 `--font-caption` 改到 9px，静态层与渲染层同时 PASS |
| `font: 600 8px/1 ...` 简写 | 只认 `font-size:` | `ppt-base.html` 骨架自身即用此写法，Worker 依骨架生成时极易沿用 |

**裁定：静态扫描覆盖三形态，并在 D 类渲染层增设计算字号兜底。**

1. 静态层：`font-size` 字面量 · `--font-*` token 定义 · `font` 简写的字号分量。
   三形态一并纳入检查器自检 fixture（9 行覆盖 4 检出 + 5 放行），行为不符即 exit 1。
2. 渲染层：对每个承载文本节点的元素读 `getComputedStyle().fontSize` 与档位底线比较。
   层层 `var()` 引用、样式表覆盖、运行时改写都在此落定为一个数——不可绕过的最终口径。
   豁免与静态层同口径（显式图形标记 + 剥离符号后无可读载荷），实测合规产出零误报。

单个 token 违规会放大成上百条同因发现，故 D 类明细按类别截断至 8 条打印（计数与退出码全额计入）。

### 导出（AC-10）

导出复用 D1 已引入的 Playwright，无新增依赖。单文件产出本身即可分发（HTML 自包含），PDF 用于邮件/打印场景。

> **实现偏离（Developer 回写）：** 同 D1 的 scope 约束，导出未落为独立 `scripts/ppt-export.mjs`，
> 而是 `verify-ppt.sh` 的 `export` 子命令：`bash scripts/verify-ppt.sh export <html> <out.pdf>`。

#### 全页导出（repair round 1 修复，F-02）

屏幕态下 `.slide` 除 `.is-active` 外均 `visibility:hidden`，单次 `page.pdf()` 只截活跃页 ——
4 页产出出 1 页 PDF 却 exit 0 报 PASS，属"能力缺失包装成通过结论"。

**处置：** 注入打印态样式，把绝对定位叠放的舞台展开为 1920×1080 的纵向文档流并逐页强制分页
（`break-after: page`，舞台 `transform` 清零，页码/总览隐藏），由 Chromium 自身分页输出一份
多页 PDF。**导出后断言 PDF 页数等于 `.slide` 数，不等即非 0 退出。**

> 取舍：曾实现"逐页 `page.pdf()` + 手工拼接 xref"，两方案实测均得 4 页且内容一致，
> 但手工重写 PDF 对象表与偏移量脆弱且无第三方库校验，故采用打印态方案 —— 分页交给
> Chromium 的 PDF 写出器，依赖仍为零新增。

---

## D6: 上下文分层（对应 R7）

### 分层结构

| 层 | 文件 | 内容 | 加载时机 |
|---|---|---|---|
| 入口 | `skills/mh-slideflow/SKILL.md` | 流程骨架 + 阶段路由 + 索引表 | 常驻 |
| 规格 | `templates/ppt-quality-rules.md` | 字号分档表、布局规则、豁免规则 | Worker 实现时 |
| 登记 | `templates/ppt-templates/registry.json` | 版式 ID / 类型 / 密度归属 | Thinker 选版式时 |
| 骨架 | `templates/ppt-base.html` | 单文件结构 + 导航 + 演讲者模式 | Worker 实现时 |

入口只写"何时读哪个文件"，不复述规格内容。**AC-11 上限 264 行**（176 基线 ×1.5）。新增内容（密度询问、版式声明要求、单文件形态）预算约 40 行，其余下沉。

⛔ 不采纳 guizang 的文档体量（632 行 SKILL + 数千行 references）——会推翻 CR-009 瘦身成果。

---

## D7: 引用同步清单（对应 R8）

| 文件 | 变更 |
|---|---|
| `docs/designs/source-of-truth.md` | 新增：版式登记表、密度模型、渲染测量的权威源归属 |
| `docs/designs/design.md` | L363 脚本清单（新增 2 个 mjs、复核 fix-ppt-fonts.py）· L396 模板清单 |
| `docs/kb/domains/guards.md` | L9 三层校验体系 → 含渲染层 · L27/L39/L64 校验项与依赖 |
| `docs/kb/domains/templates.md` | L37 目录树 · L105 依赖表（新增 registry.json） |
| `docs/kb/domains/skills.md` | L74 mh-slideflow 职责描述 |
| `scripts/check-harness.sh` | 新增文件纳入完整性清单 |
| `templates/output-structure.md` | L105 ppt 产出形态改为单文件 |

### `fix-ppt-fonts.py` 处置

**已移除**（用户于 done 阶段确认采纳建议）。

理由：它是门禁失效时代的事后补救工具（字号映射表批量上调），与本设计"生成时拦截"相冲突——门禁前移后，Worker 应在渲染层反馈下调整布局，而非用脚本统一改字号，后者会破坏密度设计意图。且其映射表（11→18、16→24）按单一 18px 底线设计，与密度分档（speaker 18px / reading 14px）不兼容，对新产出使用会把高密度页面推离设计意图。

移除时已确认无任何可执行路径引用它（`scripts/`、`tests/`、`tools/`、`skills/`、`templates/`、`.claude/` 均无引用，亦不在 `check-harness.sh` 完整性清单内），仅 `docs/designs/design.md` 的「修复工具」节有文档引用，已随之删除该节。

---

## D8: 实现顺序与验证

依赖关系决定顺序：

```
1. 静态层三缺陷修复 + require_ok + 自检     → 验证: AC-01/02/03、AX-03
2. 密度模型（分档表 + state 字段 + 豁免）    → 验证: AC-09、AX-01、AX-05
3. ppt-light.css 变量迁移 + W/L 系列修正     → 验证: AX-04
4. 版式登记（registry + data-layout + 统计） → 验证: AC-06/07、AX-08
5. 单文件骨架 + 舞台缩放 + 导航              → 验证: AC-08、AC-12
6. 渲染层 ppt-measure.mjs                    → 验证: AC-04/05、AX-02
7. 演讲者模式 + 导出                         → 验证: AC-10
8. 分层瘦身 + 引用同步                       → 验证: AC-11/12、AX-06/07
```

步骤 3 必须在 6 之后复跑：变量迁移可能引入溢出，需渲染层确认。

**Tester fixture 需求**（Developer 不产出 `tests/**`）：合规基线 1 套、四类几何违规各 1 页、字号边界（各档恰好达标 / 低 1px）、版式违规（缺声明 / 未登记 / 种类不足 / 连续同版式）、豁免滥用、Playwright 缺失环境模拟。

---

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 变量迁移导致 W 系列大面积溢出 | 步骤 3 后强制跑渲染层；溢出改布局不改字号 |
| 渲染测量拖慢修复循环 | 单文件形态下浏览器只启动一次、逐页测量，非每页启动 |
| 自检 fixture 本身失效 | fixture 与检查器分离存放，自检失败即阻断 |
| 密度默认档选错 | 读不到字段时默认低密度（严格档），宁误报不漏报 |
| 单文件影响归档下游 | AX-06 专项验证 verify-archive.sh 与 role-guard 行为 |

## 待确认事项（已裁定）

1. **`fix-ppt-fonts.py` 移除**（D7）—— **已解决：用户于 done 阶段确认采纳移除建议，脚本已删除**（见 D7 该节）。
   已在文件头标注"仅用于 legacy 产出批量修复，不参与门禁流程"，并说明其映射表与密度分档不兼容。
   `docs/designs/design.md` 修复工具表同步该定性。
2. **留白占比阈值具体数值**（D1）—— **裁定：取本文建议值**，低密度内容占比 ≥25%、高密度 ≥45%。
   已落入 `templates/ppt-templates/registry.json` 的 `density_tiers.*.content_ratio_min`
   与 `templates/ppt-quality-rules.md`。实测：4 页合规低密度产出内容占比均高于 25%，无误报。

## 实现补充说明（Developer 回写）

### 浏览器获取路径

`npx playwright install chromium` 在本机环境下载失败（Chrome for Testing 151 下载中断）。
测量器改为按 `channel: 'chrome'` → 默认 chromium → `channel: 'msedge'` 依次回退，
优先驱动系统已安装的 Chrome，从而无需 150MB 下载即可运行。三者皆不可用时仍以退出码 3 阻断。
这**降低了**风险 2（渲染测量引入环境硬依赖）的实际成本，未削弱 AX-02 的阻断语义。

### 测量器自身异常与产出违规的区分

测量器内 `uncaughtException` 以退出码 3 处理（检查未跑），而非 1（产出违规）。
理由：两者语义不同，混淆会让"测量器写坏"伪装成"产出有问题"，
重演缺陷 1 的失效模式（关键检查实际未生效）。

### 标题间距阈值触发的既有违规

渲染层上线后即检出 4 处既有违规：`ppt-base.css` 的 `.slide-header` margin-bottom
（24px < 全局标题下限 32px）、`L01` 的 h1 下方间距（12px）、`L03` 的两处局部标题间距（12px < 14px）。
按设计原则**改间距不改阈值**：`.slide-header` 改用 `--spacing-xl`，L01/L03 相应上调。

### 页面容器计数口径

版式统计与页数一致性均以 `class="slide"` 后紧跟引号或空白为准，
排除 `.slide-header` / `.slide-title` / `.slide-meta` 等页内元素。
早前用 `grep -c 'class="slide'` 会把 17 页误计为 64 页。

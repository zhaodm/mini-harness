# PPT 视觉硬约束详情

> 被 mh-slideflow skill 引用。`scripts/verify-ppt.sh` 机械校验这些约束——本文件是字号分档、
> 布局规则、豁免规则的权威源。版式 ID 与类型归属见 `templates/ppt-templates/registry.json`。

## 密度模型

产出分两档，clarify 阶段询问后写入 `.engine/.state.md` 的 `ppt_density`。
**读不到该字段时按低密度（speaker）判定**——宁误报不漏报。

| 档位 | 字段值 | 定位 | 主题 | 绝对下限 |
|------|--------|------|------|---------|
| 低密度演讲型 | `speaker` | 投影演讲、金句冲击 | `ppt-base.css` | 18px |
| 高密度阅读型 | `reading` | 仪表盘、阅读材料 | `ppt-light.css` | 14px |

## 字号底线（1920×1080 舞台）

| 角色 | 低密度 speaker | 高密度 reading |
|------|---------------|----------------|
| 辅助标签/标注 | ≥ 18px | ≥ 14px |
| 正文/描述 | ≥ 24px（推荐 26-30） | ≥ 18px |
| 卡片标题 | ≥ 32px | ≥ 22px |
| 页面标题 | ≥ 44px | ≥ 32px |
| 大字页/金句 | ≥ 72px | 不适用 |
| **绝对下限** | **18px** | **14px** |

高密度 14px 的依据：1920 画布上 14px 约等于 1024 画布的 7.5px——偏小但仪表盘可接受；
低于此值在投影场景不可读。

**检查覆盖 HTML 与 CSS 两类文件。** 登记版式按其 registry 密度归属取档，
主题 CSS 按主题归属取档，其余按流程密度取档。

### 字号声明的三种形态均受约束

静态扫描覆盖以下全部形态——任何一种漏检即成为绕过通道：

| 形态 | 示例 | 说明 |
|------|------|------|
| `font-size` 字面量 | `font-size: 14px` | 最常见形态 |
| 设计系统字号 token | `--font-caption: 18px` | 设计系统 CSS 的字号只在 token 定义处出现字面值，其余全是 `var()` 引用；不判 token 取值等于底线对设计系统本体不生效 |
| `font` 简写 | `font: 600 18px/1 sans-serif` | 取值中首个 `<n>px` 即字号分量 |

**渲染层兜底：** D 类对每个承载文本的元素读 `getComputedStyle().fontSize` 与所属档底线
比较。层层 `var()` 引用、外部样式表覆盖、运行时改写都在此落定为一个数——这是不可绕过的
最终口径。豁免与静态层同口径（显式图形标记 + 剥离符号后无可读载荷）。

### 图形符号豁免

豁免须**显式标记**：元素带 `data-glyph="true"`，或命中登记的图形 class
（`trend-arrow`、`icon-dot`、`timeline-node`）。

⛔ **豁免不得作用于含实质文本的元素。** 判定：该元素文本内容剥离符号字符
（▲▼◆●→ 等）后，若残留字母、数字或汉字，则**豁免失效，仍按底线检查**。
`data-glyph` 无法被用作绕过后门。

## 渲染几何约束（verify-ppt.sh D 类，真实浏览器测量）

| 测量项 | 判定 |
|--------|------|
| DOM 溢出 | `scrollWidth/Height` 超出舞台 → FAIL |
| 视觉溢出 | 元素 boundingRect 越界 → FAIL（报偏差 px + 元素标识 + 文本前 40 字） |
| 元素重叠 | 非父子关系的文本元素矩形相交 > 2px → FAIL（排除装饰层） |
| 留白占比 | 内容包围盒占舞台 < 阈值 → WARN；连续 ≥3 页 → FAIL |
| 标题间距 | 全局标题下方 < 32px、局部标题 < 14px → FAIL |

留白阈值按档取值：低密度 ≥25%、高密度 ≥45%。低密度容许大留白（留白是设计），
高密度不应有大片空白。

⛔ **测量环境不可用时以退出码 3 阻断**，不降级为 SKIP 后报告整体通过。

## 版式声明与多样性

每页须声明 `data-layout` 与 `data-slide-id`：

```html
<div class="slide" data-layout="L03" data-slide-id="s02" data-layout-type="数据展示">
```

| 模式 | 声明缺失 | 取值不在登记表 |
|------|---------|---------------|
| system | FAIL | FAIL |
| creative | FAIL | 放行（须另声明 `data-layout-type` 以参与统计） |

多样性判定以 `layout_type` 为依据（17 个 ID 若都属"卡片网格"，种类数应为 1 而非 17）：

- 全套 `layout_type` 去重种类 < 4 → FAIL
- 连续 ≥ 3 页同一 `data-layout` → FAIL

## 单文件形态与舞台缩放

产出为**单一 HTML 文件**，导航在文件内实现一次。骨架见 `templates/ppt-base.html`。

- 舞台 1920×1080 固定，`transform: scale(min(vw/1920, vh/1080))` 居中留边
- ⛔ **禁止响应式重排**：不得用 media query 改变 slide 内部布局，不得对舞台内元素用 `clamp()`
- 页面可见性用 `visibility` + `opacity` + `pointer-events`，**不用 `display:none`**
  （`.slide` 若被后续 CSS 设为 `display:flex` 会覆盖它，导致所有页同时可见）
- 键盘契约：←↑ 上一页 · →↓ 下一页 · Esc 总览 · P 演讲者模式
- 交互页方向键归导航，其他键触发内容显示

## 布局规则

| 规则 | 正确做法 | 反模式 |
|------|---------|--------|
| 卡片高度由内容决定 | `align-items: start/center` | `flex:1` + `align-items:stretch` 强制等高 |
| grid 行高自适应 | `grid-template-rows: auto` | `1fr 1fr` 强制等高行 |
| padding 有上限 | 卡片 ≤ 28px，页面 ≤ 56px | padding: 80px 挤压内容 |
| 结论/摘要正常文档流 | flex/grid 自然排列 | `position: absolute` 定位底部 |

字号上调导致溢出时**调整布局（减少卡片数或拆页），不得回调字号规避**。

## 演讲者模式

`P` 键开启双屏：`window.open` + 主窗口同步、总时长/本页计时、讲稿备注。

备注按 `data-slide-id` 绑定（不按页序号——插入新页时备注不串页），
写在页面 `data-notes` 属性或 `window.SPEAKER_NOTES` 映射中。
无备注的页显示 `—`，**不写"待补充"**（会被占位符检查误判为残留）。

## 导出

`bash scripts/verify-ppt.sh export <html> <out.pdf>` 导出全部页面。

屏幕态下 `.slide` 除活跃页外均 `visibility:hidden`，单次 `page.pdf()` 只能截到 1 页。
故导出时注入打印态样式把叠放的舞台展开为纵向文档流、每页强制分页，由 Chromium 自身分页输出。

**导出后断言 PDF 页数等于 `.slide` 数，不等即非 0 退出。** 导出能力缺失不得以 PASS 收场。

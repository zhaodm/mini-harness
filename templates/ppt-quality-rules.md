# PPT 视觉硬约束详情

> 被 mh-slideflow skill 引用。verify-ppt.sh 会检查这些约束。

## 字号底线（1920×1080 视口）

- 辅助标签/标注：≥ 18px
- 正文/描述：≥ 24px（推荐 26-30px）
- 卡片标题：≥ 32px
- 页面标题：≥ 44px
- 大字页/金句：≥ 72px
- 绝对禁止：< 18px 的任何可见文字

## 布局规则

| 规则 | 正确做法 | 反模式 |
|------|---------|--------|
| 卡片高度由内容决定 | `align-items: start/center` | `flex:1` + `align-items:stretch` 强制等高 |
| grid 行高自适应 | `grid-template-rows: auto` | `1fr 1fr` 强制等高行 |
| padding 有上限 | 卡片 ≤ 28px，页面 ≤ 56px | padding: 80px 挤压内容 |
| 结论/摘要正常文档流 | flex/grid 自然排列 | `position: absolute` 定位底部 |

## 导航与交互

- **每页必须包含方向键导航**（←↑上一页，→↓下一页）
- 交互页：方向键走导航，其他键触发内容显示
- 导航脚本统一引用 `js/navigator.js`，不每页重写

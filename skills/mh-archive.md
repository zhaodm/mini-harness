# Skill: mh-archive

产物归档 + 结项确认。PM 执行，支持首次归档和变更归档两种模式。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

验证 SR3=approved 且 `deliverables/{REQ-ID}/output/` 非空。不满足则阻塞。

## 归档模式检测

**调用 `detectArchiveMode()`**（`workflows/lib/detect-archive-mode.js`）：
- 输入含 `outputType`，返回 `extraArchive` 规则（如 ppt → 额外归档 ux/wireframes/）
- 输出: `{ archiveMode, existingFiles, nextBaselineVersion, skipSpec?, extraArchive }`

---

## Step ARC-1~4: 文件归档（PM 机械执行）

| 步骤 | 动作 | first 模式 | change 模式 |
|------|------|-----------|-------------|
| ARC-1 | 需求归档(full) | 复制 ba/requirement-spec.md → output/spec/ | `archiveMerge()` merge |
| ARC-2 | 设计归档(standard/full) | 复制 sa/design.md → output/spec/ | `archiveMerge()` merge |
| ARC-3 | 产出物归档 | 复制 output/ → 项目根 output/ | 覆盖同名，保留已有 |
| ARC-4 | 参考资料归档 | 复制 reference/ → output/reference/ | 覆盖同名 |

- fast 模式跳过 ARC-1/ARC-2（skipSpec=true）
- 归档排除: .venv/, node_modules/, __pycache__/, .git/, .DS_Store, *.pyc, .env
- change 模式归档前自动备份 output/spec/ 到 `baselines/` (v{nextBaselineVersion})

### 变更合并

**调用 `archiveMerge()`**（`workflows/lib/archive-merge.js`）：
- append: 新增内容用 `<!-- REQ-{ID} START/END -->` 包裹追加
- replace: 定位已有标签段替换
- deprecate: 添加 `[DEPRECATED by REQ-{ID}]` 保留原文

---

## Step ARC-5: 执行指标

从 .state.md 填写 `templates/metrics-template.md` → 保存为 `output/metrics.md`。

## Step ARC-6: 经验沉淀（人机交互）

1. 读取 `deliverables/{REQ-ID}/lessons.md`（自动采集的 CP-N 条目）
2. 向用户呈现，询问补充经验
3. 归档到 `output/lessons-learned.md`（EXP-{N} 全局编号）

---

## SR4: 项目结项确认

- **fast**: 跳过，直接 phase=done
- **standard**: 简化确认（Y/N）
- **full**: 执行 `scripts/verify-archive.sh` → 逐项核对通过标准 → 向用户呈现归档概况+PM 建议
  - 确认 → phase=done, SR4=approved
  - 驳回原因属代码缺陷 → 退回 apply 走 repair flow
  - 驳回原因属归档问题 → PM 修复后重提

## 异常处理

- 目标目录不存在: 自动创建
- merge 冲突: 呈现冲突内容，请求人工决策

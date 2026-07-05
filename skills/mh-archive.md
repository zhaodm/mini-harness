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
| ARC-1 | 需求归档(full) | 复制 ba/requirement-spec.md → output/docs/spec/ | `archiveMerge()` merge |
| ARC-2 | 设计归档(standard/full) | 复制 sa/design.md → output/docs/spec/ | `archiveMerge()` merge |
| ARC-3 | 产出物归档 | 按分流规则复制 output/ → 项目根 output/{src,tests,deploy,assets}/ | 覆盖同名，保留已有 |
| ARC-4 | 参考资料归档 | 复制 reference/ → output/reference/ | 覆盖同名 |

- fast 模式跳过 ARC-1/ARC-2（skipSpec=true）
- 归档排除: .venv/, node_modules/, __pycache__/, .git/, .DS_Store, *.pyc, .env
- change 模式归档前自动备份 output/docs/spec/ 到 `baselines/` (v{nextBaselineVersion})
- **ARC-3 分流规则**见 `templates/output-structure.md`（src/tests/deploy/assets 按文件类型分类）

### 变更合并

**调用 `archiveMerge()`**（`workflows/lib/archive-merge.js`）：
- append: 新增内容用 `<!-- REQ-{ID} START/END -->` 包裹追加
- replace: 定位已有标签段替换
- deprecate: 添加 `[DEPRECATED by REQ-{ID}]` 保留原文

---

## Step ARC-5: 测试用例沉淀

**调用 `regression-suite.js` 的 `aggregateToSuite()`：**

1. `[PM] 沉淀测试用例到回归套件`
2. 读取 `deliverables/{REQ-ID}/te/testcases.md`
   - 如不存在（fast 模式 / test_strategy=manual|none）→ 跳过，标注原因
3. 调用 `parseTestcases(content, reqId)` 解析结构化用例
4. 读取 `output/tests/regression-suite.md`（不存在则从 `templates/regression-suite-template.md` 初始化）
5. 调用 `aggregateToSuite(existingContent, newCases, reqId)`
6. 写入更新后的 `output/tests/regression-suite.md`
7. `[PM] 回归套件已更新: +{added} 新增, {updated} 更新, 共 {total} 条`

---

## Step ARC-6: 执行指标

从 .state.md 填写 `templates/metrics-template.md` → 保存为 `output/docs/metrics.md`。

## Step ARC-7: 经验沉淀（人机交互）

1. 读取 `deliverables/{REQ-ID}/lessons.md`（自动采集的 CP-N 条目）
2. 向用户呈现，询问补充经验
3. 归档到 `output/docs/lessons-learned.md`（EXP-{N} 全局编号）

---

## Step ARC-8: 分层知识库生成（自动提取 + 人工补充）

**目的：** 为产出项目生成三层分层知识库，使后续 AI 维护/迭代时能渐进式获取信息，无需通读全部源码。

**产出结构：**
```
output/docs/kb/
├── system-map.md       ← Layer 0: 全景入口（≤150行）
├── domains/            ← Layer 1: 域指南（每份≤400行）
├── recipes/            ← Layer 2: 操作食谱（每份≤80行）
└── kb-verify.sh        ← 新鲜度检查脚本
```

**调用 `knowledge-base.js` 的 `buildKnowledgeBase()` + `mergeKnowledgeBase()`：**

1. `[PM] 构建分层知识库`
2. 收集提取源：
   - `deliverables/{REQ-ID}/ba/requirement-spec.md`（项目定位）
   - `deliverables/{REQ-ID}/sa/design.md`（架构、模块、接口、Tasks）
   - `deliverables/{REQ-ID}/de/code-report*.md`（文件清单、实现细节）
   - `deliverables/{REQ-ID}/te/code-review.md`（约定确认、不变量）
   - `.state.md` 中的 `repair_history[]`（已知陷阱）
   - `.state.md` 中的 `tech_stack`（技术栈）
   - `deliverables/{REQ-ID}/output/` 目录树扫描
3. 调用 `splitIntoDomains(designContent)` 确定域拆分方案
4. 调用 `buildKnowledgeBase(sources, reqId, date, meta)` 生成分层结构
5. 向用户呈现结果，重点询问补充：
   - **操作食谱**（"添加新 X 还需要做什么步骤？"）
   - **约束与陷阱**（"有什么隐藏的坑或不变量？"）
   - **域拆分合理性**（"这样分模块对吗？"）
6. 行数校验：system-map ≤150行，域指南 ≤400行，食谱 ≤80行
   - 超出则精简（细节下沉到下一层）
7. 检测 `output/docs/kb/` 是否已存在：
   - 不存在（first 模式）: 写入全部文件
   - 已存在（change 模式）: 调用 `mergeKnowledgeBase()` 更新
8. 写入 `output/docs/kb/` 目录
9. `[PM] 知识库已生成: Layer 0 ({N}行) + {M}份域指南 + {K}份食谱 + kb-verify.sh`

**跳过条件：**
- fast 模式 且 无 design.md 且 无 code-report → 跳过，标注原因
- 用户在交互中选择"全部跳过" → 跳过，记录到 metrics

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

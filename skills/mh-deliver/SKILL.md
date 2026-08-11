---
name: mh-deliver
description: This skill should be used when in the archive phase, during deliverable archiving, lessons learned collection, or knowledge base generation. Product archiving, test case sedimentation, execution metrics, experience collection, and project closure.
---

# Skill: mh-deliver

产物归档 + 结项。Orchestrator 执行，支持首次归档和变更归档两种场景。

**日志规则：** 见 `templates/logging-standard.md`

---

## 前置检查

验证 SR3=approved 且 `deliverables/{REQ-ID}/output/` 非空。不满足则阻塞。

## 归档模式检测

**调用 `detectArchiveMode()`**（`workflows/lib/detect-archive-mode.js`）：
- 输出: `{ archiveMode, existingFiles, nextBaselineVersion, extraArchive }`

---

## Step ARC-1~4: 文件归档（Orchestrator 机械执行）

| 步骤 | 动作 | first 模式 | change 模式 |
|------|------|-----------|-------------|
| ARC-1 | 需求归档 | 复制 proposal.md → output/docs/spec/ | `archiveMerge()` merge |
| ARC-2 | 设计归档 | 复制 thinker/design.md → output/docs/spec/ | `archiveMerge()` merge |
| ARC-3 | 产出物归档 | 按分流规则复制 output/ → 项目根 output/{src,tests,deploy,assets}/ | 覆盖同名，保留已有 |
| ARC-4 | 参考资料归档 | 复制 reference/ → output/reference/ | 覆盖同名 |

- 归档排除: .venv/, node_modules/, __pycache__/, .git/, .DS_Store, *.pyc, .env
- change 模式归档前自动备份 output/docs/spec/ 到 `baselines/` (v{nextBaselineVersion})
- **ARC-3 分流规则**见 `templates/output-structure.md`

### 变更合并

**调用 `archiveMerge()`**（`workflows/lib/archive-merge.js`）：
- append: 新增内容用 `<!-- REQ-{ID} START/END -->` 包裹追加
- replace: 定位已有标签段替换
- deprecate: 添加 `[DEPRECATED by REQ-{ID}]` 保留原文

---

## Step ARC-5: 测试用例沉淀

**调用 `regression-suite.js` 的 `aggregateToSuite()`：**

1. `[Orchestrator] 沉淀测试用例到回归套件`
2. 读取 `deliverables/{REQ-ID}/thinker/requirement-spec.md`
   - 如不存在或 test_strategy=manual|none → 跳过，标注原因
3. 调用 `aggregateToSuite(existingContent, newCases, reqId)`
4. 写入 `output/tests/regression-suite.md`
5. `[Orchestrator] 回归套件已更新: +{added} 新增, 共 {total} 条`

---

## Step ARC-6: 执行指标

从 .state.md 填写 `templates/metrics-template.md` → 保存为 `output/docs/metrics.md`。

---

## 经验采集规则

> 以下内容从 agents/orchestrator.md 下沉。Orchestrator 在关键节点实时记录经验。

Orchestrator 在以下时机自动采集经验并追加到 `deliverables/{REQ-ID}/lessons.md`：

| 采集点 | 触发时机 | 记录内容 |
|--------|---------|---------|
| CP-1 | SR 审批被用户驳回 | 驳回原因 + 用户的修正方向 |
| CP-2 | 用户主动纠正 Agent 行为 | 纠正内容 + 原因 |
| CP-3 | 修复循环 ≥2 轮 | 系统性根因分析（非个案 bug） |

记录格式：
```markdown
### CP-{N} [{时间}] {采集点类型}
- 触发: {什么情况触发了这条经验}
- 内容: {具体经验内容}
- 建议: {对后续执行或框架改进的建议}
```

---

## Step ARC-7: 经验沉淀（人机交互）

1. 读取 `deliverables/{REQ-ID}/lessons.md`（自动采集的条目）
2. 向用户呈现，询问补充经验
3. 归档到 `output/docs/lessons-learned.md`

---

## Step ARC-8: 分层知识库生成（用户请求时执行）

> **Tip:** 如需为项目生成 AI 友好的分层知识库（system-map + 域指南 + 操作食谱），请在归档交互时告知 Orchestrator "生成知识库"。适合中大型项目的后续维护。

**默认跳过。** 仅当用户在归档阶段明确要求"生成知识库"时执行。

**调用 `knowledge-base.js` 的 `buildKnowledgeBase()` + `mergeKnowledgeBase()`：**

1. `[Orchestrator] 构建分层知识库`
2. 收集提取源（design.md + code-report + code-review + tech_stack + 目录树）
3. 调用 `buildKnowledgeBase()` 生成分层结构
4. 向用户呈现，询问补充（操作食谱、约束与陷阱、域拆分）
5. 行数校验：system-map ≤150行，域指南 ≤400行，食谱 ≤80行
6. 写入 `output/docs/kb/` 目录
7. `[Orchestrator] 知识库已生成`

---

## 结项

1. 执行 `scripts/verify-archive.sh` 校验归档质量
2. 向用户呈现归档概况
3. phase=done，流程结束

## 异常处理

- 目标目录不存在: 自动创建
- merge 冲突: 呈现冲突内容，请求人工决策

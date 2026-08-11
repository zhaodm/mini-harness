# CR-006 技术设计：TE Code Review 强化 + 测试用例沉淀机制

> CR: CR-006-te-code-review-and-regression
> 作者: PM + SA
> 日期: 2026-06-10
> 状态: 设计中
> 设计原则: **脚本硬约束优先于自然语言软约束**

---

## 0. 已有基础设施分析

在设计新功能前，逐项对照已有模块，确定复用/扩展/新建策略：

| 需求 | 已有模块 | 决策 |
|------|---------|------|
| 回归套件追加/去重 | `archive-merge.js` (REQ-ID 标签 append/replace) | **复用** — 用例追加 = append 策略 |
| Code Review 维度路由 | `recommend-type-mode.js` (output_type/tech_stack 路由) | **扩展** — 增加 `deriveReviewScope()` 函数 |
| 报告格式硬校验 | `verify-qa.sh` (QA-1~11 框架) | **扩展** — 新增 QA-12/13 |
| SubAgent 结果判定 | `result-parser.js` (提取 PASS/FAIL) | **扩展** — 增加 Code Review 结论提取 |
| TE 审计 Workflow | `apply-batch-test.js` / `apply-final-audit.js` | **不变** — prompt 内容更丰富即可 |

**结论：新建 2 个 JS 模块 + 1 个 Shell 脚本，扩展 2 个已有模块，其余为文档更新。**

---

## 1. 架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│  脚本层（硬约束，退出码为准）                                      │
│                                                                   │
│  code-review-rules.js    → TE 评审维度/阈值/路由（纯函数）         │
│  regression-suite.js     → 用例解析/追加/去重/索引重建（纯函数）    │
│  verify-code-review.sh   → Code Review 报告格式硬校验              │
│  verify-qa.sh +QA-12/13  → 回归覆盖 + 用例沉淀完整性硬校验        │
│                                                                   │
├─────────────────────────────────────────────────────────────────┤
│  Agent 层（软约束，由脚本驱动行为）                                 │
│                                                                   │
│  agents/te.md            → 引用 code-review-rules.js 输出执行      │
│  agents/pm.md            → 质量门禁增加脚本检查项                   │
│  skills/mh-archive.md    → 调用 regression-suite.js 沉淀用例       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 新建模块设计

### 2.1 `workflows/lib/code-review-rules.js` — Code Review 规则引擎

**职责**：定义评审维度、严重程度阈值、模式/类型路由，供 TE 和校验脚本共同引用。

```javascript
/**
 * code-review-rules.js — Code Review 规则引擎（纯函数）
 *
 * 导出:
 * - REVIEW_DIMENSIONS: 7 个评审维度定义
 * - getReviewScope(): 根据 mode + output_type 返回应执行的维度子集
 * - classifySeverity(): 根据维度+发现类型返回严重程度
 * - shouldSkipReview(): 判断是否跳过 Code Review
 * - validateReviewReport(): 校验报告结构完整性（供 verify 脚本调用）
 */

// 7 个评审维度（结构化数据，非 NL 描述）
export const REVIEW_DIMENSIONS = [
  {
    id: 'naming',
    label: '命名规范',
    description: '变量/函数/文件命名一致性与语义明确性',
    criticalThreshold: '核心 API 命名误导性（如 delete 实际执行 archive）',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  },
  {
    id: 'error-handling',
    label: '错误处理',
    description: '异常捕获与传播、静默吞错检测',
    criticalThreshold: '未处理的致命异常路径（如数据库连接失败无 catch）',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  },
  {
    id: 'security',
    label: '安全模式',
    description: '输入校验、注入防护、认证/授权检查',
    criticalThreshold: 'SQL注入/XSS/认证绕过/敏感数据明文',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  },
  {
    id: 'complexity',
    label: '代码复杂度',
    description: '函数长度(>50行)、嵌套深度(>4层)、圈复杂度',
    criticalThreshold: '单函数>100行且无拆分理由',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library']
  },
  {
    id: 'dry',
    label: 'DRY 原则',
    description: '重复代码块(>10行相似)、可抽取的公共逻辑',
    criticalThreshold: '3处以上相同逻辑（>10行）未抽取',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library']
  },
  {
    id: 'api-consistency',
    label: 'API 一致性',
    description: '命名风格、响应格式、错误码规范',
    criticalThreshold: '同项目内 API 风格严重不一致（如混用 camelCase 和 snake_case）',
    applicableTo: ['web-app', 'backend-api', 'library']
  },
  {
    id: 'dependencies',
    label: '依赖合理性',
    description: '不必要重依赖、版本锁定、已知漏洞',
    criticalThreshold: '引入已知 CVE 漏洞依赖 或 未锁定版本的核心依赖',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  }
];

// 模式 → 维度子集映射
const MODE_SCOPE_MAP = {
  fast: ['security', 'error-handling'],           // 仅关键两项
  standard: null,                                  // null = 全量（按 output_type 过滤）
  full: null                                       // 全量 + Minor 也列出
};

// 跳过 Code Review 的 output_type
const SKIP_REVIEW_TYPES = ['documentation', 'ppt'];

/**
 * 根据 mode + output_type 返回应执行的评审维度列表
 */
export function getReviewScope(mode, outputType) {
  if (SKIP_REVIEW_TYPES.includes(outputType)) {
    return { skip: true, reason: `output_type=${outputType}, 非代码产出` };
  }

  const modeFilter = MODE_SCOPE_MAP[mode];
  const dimensions = REVIEW_DIMENSIONS.filter(d => d.applicableTo.includes(outputType));

  if (modeFilter) {
    return { skip: false, dimensions: dimensions.filter(d => modeFilter.includes(d.id)) };
  }
  return { skip: false, dimensions };
}

/**
 * 判断 Code Review 报告结构是否完整
 * 返回 { valid: boolean, errors: string[] }
 */
export function validateReviewReport(reportContent) {
  const errors = [];

  // 必须包含 "## Code Review" 章节
  if (!reportContent.includes('## Code Review')) {
    errors.push('缺少 "## Code Review" 章节');
  }

  // 必须包含结论行
  if (!/Code Review 判定:\s*(PASS|FAIL|SKIPPED)/i.test(reportContent)) {
    errors.push('缺少 "Code Review 判定: PASS/FAIL/SKIPPED" 结论');
  }

  // FAIL 时必须有发现表格
  if (/Code Review 判定:\s*FAIL/i.test(reportContent)) {
    if (!/Critical/i.test(reportContent)) {
      errors.push('Code Review FAIL 但未列出 Critical 发现');
    }
  }

  // SKIPPED 时必须有理由
  if (/Code Review 判定:\s*SKIPPED/i.test(reportContent)) {
    if (!/SKIPPED.*[-—]/.test(reportContent) && !/非代码产出|跳过/.test(reportContent)) {
      errors.push('Code Review SKIPPED 但未标注理由');
    }
  }

  return { valid: errors.length === 0, errors };
}
```

**单测文件**: `tests/test-code-review-rules.js`

---

### 2.2 `workflows/lib/regression-suite.js` — 回归套件管理引擎

**职责**：解析 testcases.md、追加到回归套件、去重、重建索引。复用 `archive-merge.js` 的 REQ-ID 标签模式。

```javascript
/**
 * regression-suite.js — 回归套件管理引擎（纯函数）
 *
 * 复用 archive-merge.js 的 REQ-ID 标签追加策略。
 *
 * 导出:
 * - parseTestcases(): 从 testcases.md 提取结构化用例列表
 * - aggregateToSuite(): 将新用例追加到回归套件（去重 + 索引重建）
 * - validateSuiteIntegrity(): 校验回归套件结构完整性
 * - getSuiteStats(): 提取回归套件统计信息
 */

import { archiveMerge } from './archive-merge.js';

/**
 * @typedef {Object} TestCase
 * @property {string} id - TC-{N}
 * @property {string} title - 用例标题
 * @property {string} sourceReq - 来源 REQ-ID
 * @property {string} requirement - 关联需求 FR-{N}
 * @property {string} type - E2E | Unit | Integration | Smoke | Manual
 * @property {string} priority - Critical | Major | Minor
 * @property {string} precondition - 前置条件
 * @property {string[]} steps - 执行步骤
 * @property {string} expected - 期望结果
 * @property {string[]} variants - 边界/异常变体
 */

/**
 * 从 testcases.md 内容中解析出结构化用例列表
 */
export function parseTestcases(content, sourceReqId) {
  const testcases = [];
  // 按 ## TC-{N} 或 ### TC-{N} 分割
  const sections = content.split(/^#{2,3}\s+TC-/m).slice(1);

  for (const section of sections) {
    const lines = section.split('\n');
    const headerMatch = lines[0].match(/^(\d+):\s*(.+)/);
    if (!headerMatch) continue;

    const tc = {
      id: `TC-${headerMatch[1]}`,
      title: headerMatch[2].trim(),
      sourceReq: sourceReqId,
      requirement: extractField(section, '关联需求'),
      type: extractField(section, '类型'),
      priority: extractField(section, '优先级'),
      precondition: extractField(section, '前置条件'),
      steps: extractListItems(section, '步骤'),
      expected: extractField(section, '期望结果'),
      variants: extractListItems(section, '边界/异常变体')
    };
    testcases.push(tc);
  }
  return testcases;
}

/**
 * 将新用例追加到回归套件
 * 复用 archive-merge.js 的 append 策略（REQ-ID 标签定位）
 *
 * @param {string} existingSuiteContent - 现有回归套件内容（空字符串表示首次创建）
 * @param {TestCase[]} newCases - 新用例列表
 * @param {string} reqId - 当前 REQ-ID
 * @returns {{ content: string, stats: { added: number, updated: number, total: number } }}
 */
export function aggregateToSuite(existingSuiteContent, newCases, reqId) {
  if (newCases.length === 0) {
    return { content: existingSuiteContent, stats: { added: 0, updated: 0, total: countCases(existingSuiteContent) } };
  }

  // 提取已有用例 ID 集合（用于去重）
  const existingIds = extractExistingIds(existingSuiteContent);

  // 分类: 新增 vs 更新
  let added = 0, updated = 0;
  for (const tc of newCases) {
    if (existingIds.has(tc.id)) { updated++; } else { added++; }
  }

  // 渲染新用例为 Markdown
  const newSection = renderCasesSection(newCases, reqId);

  // 使用 archive-merge 的 replace（已有 REQ 标签段）或 append（新 REQ）
  const hasExistingSection = existingSuiteContent.includes(`<!-- REQ-${reqId} START -->`);
  const mergeResult = archiveMerge({
    existingContent: existingSuiteContent,
    newContent: newSection,
    reqId: reqId,
    mergeType: hasExistingSection ? 'replace' : 'append'
  });

  // 重建索引
  const withIndex = rebuildIndex(mergeResult.mergedContent);
  const total = countCases(withIndex);

  // 更新元信息
  const final = updateMeta(withIndex, total);

  return { content: final, stats: { added, updated, total } };
}

/**
 * 校验回归套件结构完整性
 * 返回 { valid: boolean, errors: string[] }
 */
export function validateSuiteIntegrity(suiteContent) {
  const errors = [];

  if (!suiteContent.includes('# 回归测试套件')) {
    errors.push('缺少顶部标题 "# 回归测试套件"');
  }
  if (!suiteContent.includes('## 索引')) {
    errors.push('缺少索引章节');
  }
  if (!/用例总数:\s*\d+/.test(suiteContent)) {
    errors.push('缺少用例总数元信息');
  }
  // 每个 TC 必须有 priority 标注
  const tcHeaders = suiteContent.match(/^#{2,3}\s+TC-\d+/gm) || [];
  const priorities = suiteContent.match(/优先级:\s*(Critical|Major|Minor)/gi) || [];
  if (tcHeaders.length > priorities.length) {
    errors.push(`${tcHeaders.length - priorities.length} 个用例缺少优先级标注`);
  }

  return { valid: errors.length === 0, errors };
}

/**
 * 提取回归套件统计
 */
export function getSuiteStats(suiteContent) {
  const tcHeaders = suiteContent.match(/^#{2,3}\s+TC-\d+/gm) || [];
  const critical = (suiteContent.match(/优先级:\s*Critical/gi) || []).length;
  const major = (suiteContent.match(/优先级:\s*Major/gi) || []).length;
  const minor = (suiteContent.match(/优先级:\s*Minor/gi) || []).length;
  const reqs = (suiteContent.match(/<!-- REQ-\w+ START -->/g) || []).length;

  return { total: tcHeaders.length, critical, major, minor, reqCount: reqs };
}

// ─── 内部辅助函数 ───

function extractField(section, fieldName) {
  const match = section.match(new RegExp(`${fieldName}:\\s*(.+)`));
  return match ? match[1].trim() : '';
}

function extractListItems(section, fieldName) {
  const items = [];
  const fieldIdx = section.indexOf(fieldName);
  if (fieldIdx === -1) return items;
  const afterField = section.substring(fieldIdx);
  const lines = afterField.split('\n').slice(1);
  for (const line of lines) {
    if (/^\s+\d+\.\s/.test(line) || /^\s+-\s/.test(line)) {
      items.push(line.replace(/^\s+(\d+\.\s|-\s)/, '').trim());
    } else if (line.trim() && !line.startsWith(' ')) {
      break;
    }
  }
  return items;
}

function extractExistingIds(content) {
  const ids = new Set();
  const matches = content.match(/^#{2,3}\s+(TC-\d+)/gm) || [];
  for (const m of matches) {
    const id = m.match(/TC-\d+/);
    if (id) ids.add(id[0]);
  }
  return ids;
}

function countCases(content) {
  return (content.match(/^#{2,3}\s+TC-\d+/gm) || []).length;
}

function renderCasesSection(cases, reqId) {
  let md = `## ${reqId} 用例\n\n`;
  for (const tc of cases) {
    md += `### ${tc.id}: ${tc.title}\n`;
    md += `- 来源: ${tc.sourceReq}\n`;
    md += `- 沉淀时间: ${new Date().toISOString()}\n`;
    md += `- 关联需求: ${tc.requirement}\n`;
    md += `- 类型: ${tc.type}\n`;
    md += `- 优先级: ${tc.priority}\n`;
    md += `- 前置条件: ${tc.precondition}\n`;
    md += `- 步骤:\n`;
    tc.steps.forEach((s, i) => { md += `  ${i + 1}. ${s}\n`; });
    md += `- 期望结果: ${tc.expected}\n`;
    if (tc.variants.length > 0) {
      md += `- 边界/异常变体:\n`;
      tc.variants.forEach(v => { md += `  - ${v}\n`; });
    }
    md += '\n';
  }
  return md;
}

function rebuildIndex(content) {
  // 提取所有用例的 id + title + priority + sourceReq，重建索引区
  const cases = [];
  const regex = /^#{2,3}\s+(TC-\d+):\s*(.+)\n[\s\S]*?优先级:\s*(Critical|Major|Minor)/gm;
  let match;
  while ((match = regex.exec(content)) !== null) {
    const sourceMatch = content.substring(match.index).match(/来源:\s*(\w+)/);
    cases.push({ id: match[1], title: match[2], priority: match[3], source: sourceMatch ? sourceMatch[1] : '' });
  }

  const indexSection = buildIndexSection(cases);
  // 替换现有索引
  const indexStart = content.indexOf('## 索引');
  const indexEnd = content.indexOf('\n---', indexStart);
  if (indexStart !== -1 && indexEnd !== -1) {
    return content.substring(0, indexStart) + indexSection + content.substring(indexEnd);
  }
  return content;
}

function buildIndexSection(cases) {
  let md = '## 索引（按优先级）\n\n';
  for (const prio of ['Critical', 'Major', 'Minor']) {
    const filtered = cases.filter(c => c.priority === prio);
    if (filtered.length > 0) {
      md += `### ${prio}\n`;
      filtered.forEach(c => { md += `- [${c.id}] ${c.title} (来源: ${c.source})\n`; });
      md += '\n';
    }
  }
  return md;
}

function updateMeta(content, total) {
  const now = new Date().toISOString();
  let updated = content.replace(/最后更新:\s*.+/, `最后更新: ${now}`);
  updated = updated.replace(/用例总数:\s*\d+/, `用例总数: ${total}`);
  return updated;
}
```

**单测文件**: `tests/test-regression-suite.js`

---

### 2.3 `scripts/verify-code-review.sh` — Code Review 报告硬校验

**职责**：替代 PM 自然语言检查，用退出码强制 Code Review 报告格式合规。

```bash
#!/bin/bash
# verify-code-review.sh — Code Review 报告格式硬校验
# 退出码: 0=通过, 1=失败
# 用法: ./scripts/verify-code-review.sh [REQ-ID]
#
# 检查项:
# CR-1: 报告包含 "## Code Review" 章节
# CR-2: 报告包含 "Code Review 判定: PASS/FAIL/SKIPPED"
# CR-3: FAIL 时必须有 Critical 发现行
# CR-4: SKIPPED 时必须有理由（output_type 非代码类）
# CR-5: 非 SKIPPED 时发现表格至少包含维度列

set -euo pipefail

DELIVERABLES_DIR="deliverables"
ERRORS=0

req_id="${1:-}"
if [ -z "$req_id" ]; then
    req_id=$(grep "^req_id:" "$DELIVERABLES_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
fi
[ -z "$req_id" ] && echo "WARN: 无 REQ-ID，跳过" && exit 0

REQ_DIR="$DELIVERABLES_DIR/$req_id"
output_type=$(grep "^output_type:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")

# 非代码产出类型，Code Review 可跳过
if [[ "$output_type" == "documentation" || "$output_type" == "ppt" ]]; then
    echo "INFO: output_type=$output_type, Code Review 非必需"
    exit 0
fi

echo "=== Code Review 报告校验: $req_id ==="

# 查找 TE 报告
REPORT=""
for r in "$REQ_DIR"/te/final-test-report.md "$REQ_DIR"/te/temp-test-report.md; do
    [ -f "$r" ] && REPORT="$r" && break
done

if [ -z "$REPORT" ]; then
    echo "SKIP: 无 TE 报告文件"
    exit 0
fi

# CR-1: 必须包含 Code Review 章节
if ! grep -q "## Code Review" "$REPORT" 2>/dev/null; then
    echo "FAIL [CR-1]: 报告缺少 '## Code Review' 章节"
    ERRORS=$((ERRORS + 1))
fi

# CR-2: 必须包含结论
if ! grep -qiE "Code Review 判定:\s*(PASS|FAIL|SKIPPED)" "$REPORT" 2>/dev/null; then
    echo "FAIL [CR-2]: 缺少 'Code Review 判定: PASS/FAIL/SKIPPED'"
    ERRORS=$((ERRORS + 1))
fi

# CR-3: FAIL 时必须有 Critical
if grep -qi "Code Review 判定:.*FAIL" "$REPORT" 2>/dev/null; then
    if ! grep -qi "Critical" "$REPORT" 2>/dev/null; then
        echo "FAIL [CR-3]: Code Review FAIL 但未列出 Critical 发现"
        ERRORS=$((ERRORS + 1))
    fi
fi

# CR-4: SKIPPED 时必须有理由
if grep -qi "Code Review 判定:.*SKIPPED" "$REPORT" 2>/dev/null; then
    if ! grep -qiE "非代码产出|跳过.*理由|SKIPPED.*[-—]" "$REPORT" 2>/dev/null; then
        echo "FAIL [CR-4]: Code Review SKIPPED 但未标注理由"
        ERRORS=$((ERRORS + 1))
    fi
fi

# CR-5: 非 SKIPPED 时发现部分须有维度列（表格格式）
if grep -qi "Code Review 判定:.*\(PASS\|FAIL\)" "$REPORT" 2>/dev/null; then
    if ! grep -qE "维度.*严重程度|严重程度.*维度" "$REPORT" 2>/dev/null; then
        # 允许无发现时省略表格，但须有"无发现"标注
        if ! grep -qi "无.* Critical\|Critical: 0\|无发现\|未发现" "$REPORT" 2>/dev/null; then
            echo "WARN [CR-5]: Code Review 未包含发现表格或无发现声明"
        fi
    fi
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "=== Code Review 校验通过 ==="
    exit 0
else
    echo "=== Code Review 校验失败: $ERRORS 项 ==="
    exit 1
fi
```

---

### 2.4 扩展 `recommend-type-mode.js` — 增加 `deriveReviewScope()`

在已有模块底部追加导出函数，避免重复实现 output_type 路由逻辑：

```javascript
/**
 * 根据 mode + outputType 返回 Code Review 执行范围
 * 供 PM 生成 TE handoff 时注入，TE 据此决定评审深度
 *
 * @param {string} mode - fast | standard | full
 * @param {string} outputType - output_type 字段值
 * @returns {{ skip: boolean, dimensions: string[], depth: string, reason?: string }}
 */
export function deriveReviewScope(mode, outputType) {
  const SKIP_TYPES = ['documentation', 'ppt'];
  if (SKIP_TYPES.includes(outputType)) {
    return { skip: true, dimensions: [], depth: 'none', reason: `output_type=${outputType}` };
  }

  const FULL_DIMENSIONS = ['naming', 'error-handling', 'security', 'complexity', 'dry', 'api-consistency', 'dependencies'];
  const FAST_DIMENSIONS = ['security', 'error-handling'];
  const SIMPLE_TYPES = ['data-pipeline', 'infrastructure'];
  const SIMPLE_DIMENSIONS = ['security', 'dependencies', 'error-handling'];

  let dimensions;
  if (mode === 'fast') {
    dimensions = FAST_DIMENSIONS;
  } else if (SIMPLE_TYPES.includes(outputType)) {
    dimensions = SIMPLE_DIMENSIONS;
  } else {
    dimensions = FULL_DIMENSIONS;
  }

  const depth = mode === 'full' ? 'full' : (mode === 'fast' ? 'spot-check' : 'standard');
  return { skip: false, dimensions, depth };
}
```

---

### 2.5 扩展 `result-parser.js` — 增加 Code Review 结论提取

```javascript
/**
 * 从 TE SubAgent 输出中提取 Code Review 判定
 *
 * @param {string} rawOutput - SubAgent 原始输出
 * @returns {{ reviewVerdict: 'PASS'|'FAIL'|'SKIPPED'|'MISSING', criticalCount: number }}
 */
export function extractReviewVerdict(rawOutput) {
  const verdictMatch = rawOutput.match(/Code Review 判定:\s*(PASS|FAIL|SKIPPED)/i);
  if (!verdictMatch) {
    return { reviewVerdict: 'MISSING', criticalCount: 0 };
  }

  let criticalCount = 0;
  const criticalMatch = rawOutput.match(/Critical:\s*(\d+)/i);
  if (criticalMatch) {
    criticalCount = parseInt(criticalMatch[1], 10);
  }

  return { reviewVerdict: verdictMatch[1].toUpperCase(), criticalCount };
}
```

---

## 3. 扩展已有脚本

### 3.1 `scripts/verify-qa.sh` — 新增 QA-12 + QA-13

```bash
# ─────────────────────────────────────────────
# QA-12: 回归套件覆盖校验（TE 报告必须含回归结果）
# ─────────────────────────────────────────────
check_regression_coverage() {
    echo "--- QA-12: 回归套件覆盖校验 ---"

    local suite="output/tests/regression-suite.md"
    if [ ! -f "$suite" ]; then
        echo "INFO: regression-suite.md 不存在（首次开发），跳过"
        echo ""
        return
    fi

    local phase
    phase=$(grep "^phase:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
    # 仅在 apply/archive/done 阶段校验
    if [[ "$phase" != "apply" && "$phase" != "archive" && "$phase" != "done" ]]; then
        echo "INFO: phase=$phase, 回归校验在 apply+ 阶段执行"
        echo ""
        return
    fi

    local report=""
    for r in "$REQ_DIR"/te/final-test-report.md "$REQ_DIR"/te/temp-test-report.md; do
        [ -f "$r" ] && report="$r" && break
    done

    if [ -z "$report" ]; then
        echo "WARN: regression-suite.md 存在但无 TE 测试报告"
        WARNS=$((WARNS + 1))
    elif ! grep -qi "回归\|regression" "$report" 2>/dev/null; then
        echo "FAIL: regression-suite.md 存在但 TE 报告未包含回归测试结果"
        ERRORS=$((ERRORS + 1))
    else
        # 进一步检查: 回归结论必须明确
        if ! grep -qiE "回归判定:\s*(PASS|FAIL)" "$report" 2>/dev/null; then
            echo "WARN: 回归章节存在但缺少明确判定（回归判定: PASS/FAIL）"
            WARNS=$((WARNS + 1))
        else
            echo "PASS: TE 报告包含回归测试结果及判定"
        fi
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-13: 归档时测试用例沉淀完整性
# ─────────────────────────────────────────────
check_testcase_sedimentation() {
    echo "--- QA-13: 测试用例沉淀完整性 ---"

    local phase
    phase=$(grep "^phase:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
    if [[ "$phase" != "archive" && "$phase" != "done" ]]; then
        echo "INFO: phase=$phase, 沉淀校验在 archive/done 阶段执行"
        echo ""
        return
    fi

    local testcases="$REQ_DIR/te/testcases.md"
    local suite="output/tests/regression-suite.md"

    if [ ! -f "$testcases" ]; then
        echo "INFO: 无 testcases.md（可能为 fast 模式或 manual 策略），跳过"
        echo ""
        return
    fi

    if [ ! -f "$suite" ]; then
        echo "FAIL: testcases.md 存在但 regression-suite.md 未创建（归档沉淀未执行）"
        ERRORS=$((ERRORS + 1))
        echo ""
        return
    fi

    # 检查当前 REQ 的用例是否已沉淀（REQ-ID 标签存在）
    if ! grep -q "<!-- REQ-${req_id} START -->" "$suite" 2>/dev/null; then
        echo "FAIL: regression-suite.md 中缺少 REQ-${req_id} 标签段（沉淀不完整）"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS: REQ-${req_id} 用例已沉淀到回归套件"
    fi
    echo ""
}
```

---

## 4. Agent/Skill 文档变更（最小化 NL，引用脚本）

### 4.1 agents/te.md — Code Review 章节（引用脚本而非重复定义）

**设计策略**：TE 不再靠记忆 7 个维度的 NL 描述，而是：
1. 从 handoff 中读取 `review_scope`（由 PM 调用 `deriveReviewScope()` 生成并注入）
2. 按 `review_scope.dimensions` 列表逐项检查
3. 输出格式必须通过 `verify-code-review.sh` 校验

新增章节内容（精简 NL，指向脚本）：

```markdown
## Code Review 职责

TE 在审计时同步执行 Code Review。评审范围由 handoff 中 `review_scope` 字段指定
（PM 调用 `deriveReviewScope()` 自动生成，TE 不自行判断范围）。

### 执行规则

- `review_scope.skip = true` → 标注 `Code Review 判定: SKIPPED — {reason}`，不执行
- `review_scope.dimensions` 列出本次需检查的维度 ID，逐项评审
- 发现问题按 Critical / Major / Minor 分级（阈值定义见 `code-review-rules.js`）
- Critical > 0 → Code Review 判定: FAIL（触发整体 FAIL）

### 输出格式（硬约束，由 verify-code-review.sh 校验）

报告中必须包含 `## Code Review` 章节，结构：
- 评审范围（文件数、行数）
- 发现表格（维度 | 严重程度 | 文件:行号 | 描述 | 建议）
- 结论行: `Code Review 判定: {PASS | FAIL | SKIPPED}`

> 格式不合规时 verify-code-review.sh 返回 exit 1，PM 驳回。
```

### 4.2 agents/te.md — 回归测试章节

```markdown
## 回归测试执行

### 触发条件

- `output/tests/regression-suite.md` 存在 → 必须执行全量回归
- 不存在 → 标注 `[NO REGRESSION SUITE - 首次开发]`，仅验证当前 testcases

### 执行规则

- 读取回归套件全部用例
- 按 test_strategy 执行可自动化用例（Manual 类型生成检查清单）
- 回归用例失败 → 整体 FAIL（不降级，不跳过）
- fast 模式下回归不降级（仍执行全量）

### 输出格式（硬约束，由 verify-qa.sh QA-12 校验）

报告中必须包含 `## 回归测试` 章节，含：
- 结果表格（用例ID | 标题 | 来源 | 结果）
- 结论行: `回归判定: {PASS | FAIL}`

> 回归套件存在但报告无回归章节时 QA-12 返回 exit 1。
```

### 4.3 agents/pm.md — TE 质量门禁（增加脚本引用）

```markdown
### TE 产出验收

- [ ] 报告结论明确（PASS 或 FAIL），无模棱两可
- [ ] PASS 时无未解决的失败项
- [ ] FAIL 时每个失败项有：复现步骤 + 期望vs实际 + 严重程度
- [ ] 降级验证时标注了原因和未覆盖的风险
- [ ] **`verify-code-review.sh` 通过**（Code Review 格式合规）
- [ ] **`verify-qa.sh` QA-12 通过**（回归覆盖校验）
- [ ] **`verify-qa.sh` QA-13 通过**（归档阶段用例沉淀完整性）
```

### 4.4 skills/mh-apply-standard.md — 最终审计 handoff 生成

Step 3 handoff 生成要点补充：

```markdown
3. 生成全量审计 handoff:
   - **调用 `deriveReviewScope(mode, outputType)`** 获取 review_scope
   - 白名单追加: `output/tests/regression-suite.md`（如存在）
   - handoff 中注入字段:
     - review_scope: { skip, dimensions, depth }
     - regression_suite_exists: true/false
   - 期望输出: final-test-report.md（含 Code Review 章节 + 回归测试章节）
```

### 4.5 skills/mh-apply-fast.md — 轻量审计补充

```markdown
2. 写入 handoff:
   - **调用 `deriveReviewScope('fast', outputType)`** → 注入 review_scope
   - 如 `output/tests/regression-suite.md` 存在，白名单追加并标注 regression_suite_exists: true
   - 约束: 回归不降级（全量执行），Code Review 按 review_scope.dimensions 执行（仅 security + error-handling）
```

### 4.6 skills/mh-archive.md — 新增 ARC-5（测试用例沉淀）

插入在现有 ARC-4 之后、ARC-5(指标) 之前（原 ARC-5/6 顺延为 ARC-6/7）：

```markdown
## Step ARC-5: 测试用例沉淀

**调用 `regression-suite.js` 的 `aggregateToSuite()`：**

1. `[PM] 沉淀测试用例到回归套件`
2. 读取 `deliverables/{REQ-ID}/te/testcases.md`
   - 如不存在（fast 模式 / test_strategy=manual|none）→ 跳过，标注原因
3. 调用 `parseTestcases(content, reqId)` 解析结构化用例
4. 读取 `output/tests/regression-suite.md`（不存在则用模板初始化）
5. 调用 `aggregateToSuite(existingContent, newCases, reqId)`
6. 写入更新后的 `output/tests/regression-suite.md`
7. `[PM] 回归套件已更新: +{added} 新增, {updated} 更新, 共 {total} 条`
```

---

## 5. CLAUDE.md 规则追加

### §4 自检纪律新增条目

```markdown
- TE 审计报告格式由 `scripts/verify-code-review.sh` 硬校验，退出码为准
- 回归套件完整性由 `scripts/verify-qa.sh` QA-12/QA-13 硬校验
- 归档阶段调用 `regression-suite.js` 沉淀用例，不依赖 NL 描述
- Code Review 范围由 `deriveReviewScope()` 计算注入 handoff，TE 不自行判断
```

---

## 6. 模板文件

### `templates/regression-suite-template.md`

```markdown
# 回归测试套件

> 自动沉淀自各 REQ 的测试用例。TE 最终审计时必须执行全量回归。
> 最后更新: {timestamp}
> 用例总数: 0

---

## 索引（按优先级）

### Critical

### Major

### Minor

---
```

---

## 7. 新增测试套件

| 测试文件 | 测试目标 | 关键场景 |
|---------|---------|---------|
| `tests/test-code-review-rules.js` | code-review-rules.js | getReviewScope 路由正确性、validateReviewReport 检测完整性 |
| `tests/test-regression-suite.js` | regression-suite.js | parseTestcases 解析、aggregateToSuite 去重/追加/索引重建 |
| `tests/test-verify-code-review.sh` | verify-code-review.sh | CR-1~5 各检查项通过/失败场景 |

---

## 8. 完整文件变更清单

### 新建文件（4个）

| 文件 | 类型 | 职责 |
|------|------|------|
| `workflows/lib/code-review-rules.js` | JS 纯函数 | Code Review 维度/阈值/路由/格式校验 |
| `workflows/lib/regression-suite.js` | JS 纯函数 | 回归套件解析/追加/去重/统计 |
| `scripts/verify-code-review.sh` | Shell 脚本 | Code Review 报告格式硬校验 |
| `templates/regression-suite-template.md` | Markdown 模板 | 回归套件初始结构 |

### 扩展文件（2个）

| 文件 | 变更 |
|------|------|
| `workflows/lib/recommend-type-mode.js` | 追加 `deriveReviewScope()` 导出 |
| `workflows/lib/result-parser.js` | 追加 `extractReviewVerdict()` 导出 |

### 文档更新（6个）

| 文件 | 变更 |
|------|------|
| `agents/te.md` | 新增 Code Review 职责 + 回归测试执行（引用脚本，非 NL 规则） |
| `agents/pm.md` | TE 质量门禁新增 3 项脚本校验引用 |
| `skills/mh-apply-standard.md` | 最终审计 handoff 注入 review_scope + regression_suite_exists |
| `skills/mh-apply-fast.md` | 轻量审计注入 review_scope + 回归不降级 |
| `skills/mh-archive.md` | 新增 ARC-5 测试用例沉淀步骤 |
| `CLAUDE.md` §4 | 追加脚本硬约束条目 |

### 新增测试（3个）

| 文件 | 说明 |
|------|------|
| `tests/test-code-review-rules.js` | code-review-rules.js 单测 |
| `tests/test-regression-suite.js` | regression-suite.js 单测 |
| `tests/test-verify-code-review.sh` | verify-code-review.sh 集成测试 |

### 扩展测试

| 文件 | 说明 |
|------|------|
| `scripts/verify-qa.sh` | 追加 QA-12 + QA-13 检查函数 |

---

## 9. 实施顺序

```
Phase 1 — 核心脚本模块（可独立测试）:
  1. workflows/lib/code-review-rules.js + tests/test-code-review-rules.js
  2. workflows/lib/regression-suite.js + tests/test-regression-suite.js
  3. scripts/verify-code-review.sh + tests/test-verify-code-review.sh
  4. templates/regression-suite-template.md

Phase 2 — 已有模块扩展:
  5. workflows/lib/recommend-type-mode.js (+deriveReviewScope)
  6. workflows/lib/result-parser.js (+extractReviewVerdict)
  7. scripts/verify-qa.sh (+QA-12, +QA-13)

Phase 3 — 流程集成（文档更新）:
  8. agents/te.md
  9. agents/pm.md
  10. skills/mh-apply-standard.md
  11. skills/mh-apply-fast.md
  12. skills/mh-archive.md
  13. CLAUDE.md §4
```

---

## 10. 设计决策记录

| 决策 | 选项 | 选择 | 理由 |
|------|------|------|------|
| Code Review 规则载体 | A) NL 在 te.md B) JS 模块 | **B** | 脚本可测试、可被 verify 脚本引用、避免 NL 漂移 |
| 回归套件管理 | A) 新引擎 B) 复用 archive-merge.js | **B 复用** | REQ-ID 标签 append/replace 策略完全匹配需求 |
| Code Review 格式校验 | A) PM NL 检查 B) 独立 Shell 脚本 | **B** | 退出码为准，不依赖 PM 判断力 |
| deriveReviewScope 位置 | A) 新模块 B) 扩展 recommend-type-mode.js | **B 扩展** | 已有 output_type 路由逻辑，避免重复 |
| 回归套件位置 | A) deliverables/ 内 B) output/tests/ | **B** | 跨 REQ 持久化，归档产物的一部分 |
| fast 模式回归 | A) 降级 B) 不降级 | **B 不降级** | 回归保障兼容性是底线，不可妥协 |

// test-code-review-rules.js — code-review-rules 的单元测试
// 用法: node tests/test-code-review-rules.js
// 退出码: 0=全部通过, 1=有失败

import { REVIEW_DIMENSIONS, getReviewScope, shouldSkipReview, validateReviewReport, determineVerdict } from '../workflows/lib/code-review-rules.js';

let pass = 0;
let fail = 0;

function assert(desc, condition, detail = '') {
  if (condition) {
    console.log(`  \x1b[32mPASS\x1b[0m: ${desc}`);
    pass++;
  } else {
    console.log(`  \x1b[31mFAIL\x1b[0m: ${desc}${detail ? ' — ' + detail : ''}`);
    fail++;
  }
}

console.log('=== code-review-rules 单元测试 ===\n');

// --- 1. REVIEW_DIMENSIONS 结构 ---
console.log('--- 1. REVIEW_DIMENSIONS 结构完整性 ---');

assert('共 7 个维度', REVIEW_DIMENSIONS.length === 7);
assert('每个维度有 id', REVIEW_DIMENSIONS.every(d => d.id));
assert('每个维度有 label', REVIEW_DIMENSIONS.every(d => d.label));
assert('每个维度有 applicableTo', REVIEW_DIMENSIONS.every(d => Array.isArray(d.applicableTo)));
assert('每个维度有 criticalThreshold', REVIEW_DIMENSIONS.every(d => d.criticalThreshold));

// --- 2. getReviewScope 路由 ---
console.log('\n--- 2. getReviewScope 路由正确性 ---');

const fastWeb = getReviewScope('fast', 'web-app');
assert('fast+web-app: 不跳过', fastWeb.skip === false);
assert('fast+web-app: 仅 2 维度', fastWeb.dimensions.length === 2);
assert('fast+web-app: 含 security', fastWeb.dimensions.some(d => d.id === 'security'));
assert('fast+web-app: 含 error-handling', fastWeb.dimensions.some(d => d.id === 'error-handling'));
assert('fast+web-app: depth=spot-check', fastWeb.depth === 'spot-check');

const stdBackend = getReviewScope('standard', 'backend-api');
assert('standard+backend-api: 不跳过', stdBackend.skip === false);
assert('standard+backend-api: 7 维度全量', stdBackend.dimensions.length === 7);
assert('standard+backend-api: depth=standard', stdBackend.depth === 'standard');

const fullLib = getReviewScope('full', 'library');
assert('full+library: 不跳过', fullLib.skip === false);
assert('full+library: depth=full', fullLib.depth === 'full');

const docSkip = getReviewScope('standard', 'documentation');
assert('standard+documentation: 跳过', docSkip.skip === true);
assert('standard+documentation: dimensions 为空', docSkip.dimensions.length === 0);
assert('standard+documentation: depth=none', docSkip.depth === 'none');
assert('standard+documentation: 有 reason', docSkip.reason.includes('documentation'));

const pptSkip = getReviewScope('full', 'ppt');
assert('full+ppt: 跳过', pptSkip.skip === true);

const infra = getReviewScope('standard', 'infrastructure');
assert('standard+infrastructure: 不跳过', infra.skip === false);
assert('standard+infrastructure: 仅 3 维度（简化）', infra.dimensions.length === 3);
assert('standard+infrastructure: 含 security', infra.dimensions.some(d => d.id === 'security'));
assert('standard+infrastructure: 含 dependencies', infra.dimensions.some(d => d.id === 'dependencies'));
assert('standard+infrastructure: 含 error-handling', infra.dimensions.some(d => d.id === 'error-handling'));

const fastInfra = getReviewScope('fast', 'infrastructure');
assert('fast+infrastructure: 仅 2 维度（fast 过滤）', fastInfra.dimensions.length === 2);

// --- 3. shouldSkipReview ---
console.log('\n--- 3. shouldSkipReview ---');

assert('documentation → skip', shouldSkipReview('documentation') === true);
assert('ppt → skip', shouldSkipReview('ppt') === true);
assert('web-app → 不 skip', shouldSkipReview('web-app') === false);
assert('backend-api → 不 skip', shouldSkipReview('backend-api') === false);
assert('cli-tool → 不 skip', shouldSkipReview('cli-tool') === false);

// --- 4. validateReviewReport ---
console.log('\n--- 4. validateReviewReport 格式校验 ---');

const validPass = `
## Code Review

### 评审范围
- 文件数: 5

### 发现
无发现问题

### 结论
- Critical: 0 项
- Major: 0 项
- Minor: 0 项
- Code Review 判定: PASS
`;
const r1 = validateReviewReport(validPass);
assert('合规 PASS 报告 → valid', r1.valid === true);
assert('合规 PASS 报告 → 0 errors', r1.errors.length === 0);

const validFail = `
## Code Review

### 发现

| # | 维度 | 严重程度 | 文件:行号 | 描述 | 建议 |
|---|------|---------|----------|------|------|
| 1 | security | Critical | src/db.js:10 | SQL注入 | 参数化 |

### 结论
- Critical: 1 项
- Major: 0 项
- Code Review 判定: FAIL
`;
const r2 = validateReviewReport(validFail);
assert('合规 FAIL 报告 → valid', r2.valid === true);

const validSkipped = `
## Code Review

Code Review 判定: SKIPPED — output_type=documentation, 非代码产出
`;
const r3 = validateReviewReport(validSkipped);
assert('合规 SKIPPED 报告 → valid', r3.valid === true);

const missingChapter = `
## 测试报告
结论: PASS
`;
const r4 = validateReviewReport(missingChapter);
assert('缺少 Code Review 章节 → invalid', r4.valid === false);
assert('报告缺章节错误', r4.errors.some(e => e.includes('## Code Review')));

const failNoFinding = `
## Code Review

### 结论
- Code Review 判定: FAIL
`;
const r5 = validateReviewReport(failNoFinding);
assert('FAIL 无 Critical → invalid', r5.valid === false);
assert('报告缺 Critical 错误', r5.errors.some(e => e.includes('Critical')));

const skippedNoReason = `
## Code Review

Code Review 判定: SKIPPED
`;
const r6 = validateReviewReport(skippedNoReason);
assert('SKIPPED 无理由 → invalid', r6.valid === false);

// --- 5. determineVerdict ---
console.log('\n--- 5. determineVerdict ---');

assert('critical=0 → PASS', determineVerdict({ critical: 0, major: 3, minor: 5 }) === 'PASS');
assert('critical=1 → FAIL', determineVerdict({ critical: 1, major: 0, minor: 0 }) === 'FAIL');
assert('critical=5 → FAIL', determineVerdict({ critical: 5, major: 2, minor: 1 }) === 'FAIL');

// --- 汇总 ---
console.log(`\n=== 结果: ${pass} passed, ${fail} failed ===`);
process.exit(fail > 0 ? 1 : 0);

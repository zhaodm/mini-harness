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

const webApp = getReviewScope('web-app');
assert('web-app: 不跳过', webApp.skip === false);
assert('web-app: 7 维度全量', webApp.dimensions.length === 7);
assert('web-app: depth=standard', webApp.depth === 'standard');

const backendApi = getReviewScope('backend-api');
assert('backend-api: 不跳过', backendApi.skip === false);
assert('backend-api: 7 维度全量', backendApi.dimensions.length === 7);

const docSkip = getReviewScope('documentation');
assert('documentation: 跳过', docSkip.skip === true);
assert('documentation: dimensions 为空', docSkip.dimensions.length === 0);
assert('documentation: depth=none', docSkip.depth === 'none');
assert('documentation: 有 reason', docSkip.reason.includes('documentation'));

const pptSkip = getReviewScope('ppt');
assert('ppt: 跳过', pptSkip.skip === true);

const lib = getReviewScope('library');
assert('library: 不跳过', lib.skip === false);

const unknownType = getReviewScope('unknown-type');
assert('unknown-type: 不跳过，使用全量', unknownType.skip === false);
assert('unknown-type: 7 维度', unknownType.dimensions.length === 7);

// --- 3. shouldSkipReview ---
console.log('\n--- 3. shouldSkipReview ---');

assert('无源代码 → skip', shouldSkipReview(false) === true);
assert('有源代码 → 不 skip', shouldSkipReview(true) === false);

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

Code Review 判定: SKIPPED — 非代码产出
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

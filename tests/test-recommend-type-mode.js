// test-recommend-type-mode.js — recommend-test-strategy + deriveReviewScope 的单元测试
// 用法: node tests/test-recommend-type-mode.js
// 退出码: 0=全部通过, 1=有失败

import { recommendTestStrategy, detectTechStack, deriveReviewScope } from '../workflows/lib/recommend-type-mode.js';

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

console.log('=== recommend-test-strategy + deriveReviewScope 单元测试 ===\n');

// --- 1. React + browser → e2e ---
console.log('--- 1. React + browser → e2e ---');

const react = recommendTestStrategy({
  techStack: { language: 'javascript', packageManager: 'npm', testFramework: 'jest', buildTool: 'vite', lintTool: 'eslint' },
  frameworks: ['react'],
  browserAvailable: true,
  isPpt: false
});
assert('React + browser → e2e', react.testStrategy === 'e2e');

// --- 2. React 无 browser → integration ---
console.log('\n--- 2. React 无 browser → integration ---');

const reactNoBrowser = recommendTestStrategy({
  techStack: { language: 'javascript', packageManager: 'npm', testFramework: 'jest', buildTool: 'vite', lintTool: 'eslint' },
  frameworks: ['react'],
  browserAvailable: false,
  isPpt: false
});
assert('React 无 browser → integration', reactNoBrowser.testStrategy === 'integration');

// --- 3. Express → integration ---
console.log('\n--- 3. Express → integration ---');

const express = recommendTestStrategy({
  techStack: { language: 'javascript', packageManager: 'npm', testFramework: 'mocha', buildTool: '', lintTool: 'eslint' },
  frameworks: ['express'],
  browserAvailable: false,
  isPpt: false
});
assert('Express → integration', express.testStrategy === 'integration');

// --- 4. PPT → manual ---
console.log('\n--- 4. PPT → manual ---');

const ppt = recommendTestStrategy({
  techStack: { language: 'javascript', packageManager: 'npm' },
  frameworks: [],
  browserAvailable: true,
  isPpt: true
});
assert('PPT → manual', ppt.testStrategy === 'manual');

// --- 5. 未知技术栈 → manual ---
console.log('\n--- 5. 未知技术栈 → manual ---');

const unknown = recommendTestStrategy({
  techStack: { language: 'unknown', packageManager: '' },
  frameworks: [],
  browserAvailable: false,
  isPpt: false
});
assert('unknown → manual', unknown.testStrategy === 'manual');

// --- 6. detectTechStack ---
console.log('\n--- 6. detectTechStack ---');

const ts1 = detectTechStack(['package.json', 'yarn.lock', '.eslintrc.json']);
assert('package.json → javascript', ts1.language === 'javascript');
assert('yarn.lock → yarn', ts1.packageManager === 'yarn');
assert('.eslintrc.json → eslint', ts1.lintTool === 'eslint');

const ts2 = detectTechStack(['pyproject.toml', 'poetry.lock', 'ruff.toml']);
assert('pyproject.toml → python', ts2.language === 'python');
assert('poetry.lock → poetry', ts2.packageManager === 'poetry');
assert('ruff.toml → ruff', ts2.lintTool === 'ruff');

const ts3 = detectTechStack(['go.mod', 'go.sum', '.golangci.yml']);
assert('go.mod → go', ts3.language === 'go');
assert('go.sum → go modules', ts3.packageManager === 'go modules');
assert('.golangci.yml → golangci-lint', ts3.lintTool === 'golangci-lint');

// --- 7. deriveReviewScope — track-based ---
console.log('\n--- 7. deriveReviewScope (track-based) ---');

const codeScope = deriveReviewScope('web-app', 'code');
assert('code track → 不跳过', codeScope.skip === false);
assert('code track → 全量维度', codeScope.dimensions.length === 7);

const pptScope = deriveReviewScope('ppt', 'ppt');
assert('ppt track → 跳过', pptScope.skip === true);
assert('ppt track → 空维度', pptScope.dimensions.length === 0);

const codeScopeNoTrack = deriveReviewScope('web-app');
assert('无 track 参数 → 不跳过（兼容）', codeScopeNoTrack.skip === false);

// === 结果 ===
console.log('\n========================');
console.log(`总计: ${pass + fail} | \x1b[32m通过: ${pass}\x1b[0m | \x1b[31m失败: ${fail}\x1b[0m`);
if (fail === 0) {
  console.log('\x1b[32m全部通过 ✓\x1b[0m');
  process.exit(0);
} else {
  console.log(`\x1b[31m有 ${fail} 项失败\x1b[0m`);
  process.exit(1);
}

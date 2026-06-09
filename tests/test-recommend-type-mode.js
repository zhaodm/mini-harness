// test-recommend-type-mode.js — recommend-type-mode 的单元测试
// 用法: node tests/test-recommend-type-mode.js
// 退出码: 0=全部通过, 1=有失败

import { recommendTypeMode, detectTechStack } from '../workflows/lib/recommend-type-mode.js';

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

console.log('=== recommend-type-mode 单元测试 ===\n');

// --- 1. React 项目 → web-app ---
console.log('--- 1. React → web-app ---');

const react = recommendTypeMode({
  techStack: { language: 'javascript', packageManager: 'npm', testFramework: 'jest', buildTool: 'vite', lintTool: 'eslint' },
  frameworks: ['react'],
  referenceFileCount: 3,
  referenceLineCount: 200,
  browserAvailable: true,
  userHints: []
});
assert('React → web-app', react.recommendedType === 'web-app');
assert('browser可用 → 推荐 standard', react.recommendedMode === 'standard');

// --- 2. Express → backend-api ---
console.log('\n--- 2. Express → backend-api ---');

const express = recommendTypeMode({
  techStack: { language: 'javascript', packageManager: 'npm', testFramework: 'mocha', buildTool: '', lintTool: 'eslint' },
  frameworks: ['express'],
  referenceFileCount: 5,
  referenceLineCount: 500,
  browserAvailable: false,
  userHints: []
});
assert('Express → backend-api', express.recommendedType === 'backend-api');
assert('有 test 框架 + 多参考 → standard', express.recommendedMode === 'standard');

// --- 3. Terraform → infrastructure ---
console.log('\n--- 3. Terraform → infrastructure ---');

const terraform = recommendTypeMode({
  techStack: { language: 'hcl', packageManager: '', testFramework: '', buildTool: 'terraform', lintTool: '' },
  frameworks: ['terraform'],
  referenceFileCount: 1,
  referenceLineCount: 50,
  browserAvailable: false,
  userHints: []
});
assert('Terraform → infrastructure', terraform.recommendedType === 'infrastructure');

// --- 4. Commander → cli-tool ---
console.log('\n--- 4. Commander → cli-tool ---');

const cli = recommendTypeMode({
  techStack: { language: 'javascript', packageManager: 'npm', testFramework: 'jest', buildTool: '', lintTool: '' },
  frameworks: ['commander'],
  referenceFileCount: 2,
  referenceLineCount: 100,
  browserAvailable: false,
  userHints: []
});
assert('Commander → cli-tool', cli.recommendedType === 'cli-tool');

// --- 5. Python click → cli-tool ---
console.log('\n--- 5. Python click → cli-tool ---');

const pyClick = recommendTypeMode({
  techStack: { language: 'python', packageManager: 'poetry', testFramework: 'pytest', buildTool: '', lintTool: 'ruff' },
  frameworks: ['click'],
  referenceFileCount: 2,
  referenceLineCount: 100,
  browserAvailable: false,
  userHints: []
});
assert('Click → cli-tool', pyClick.recommendedType === 'cli-tool');

// --- 6. FastAPI → backend-api ---
console.log('\n--- 6. FastAPI → backend-api ---');

const fastapi = recommendTypeMode({
  techStack: { language: 'python', packageManager: 'uv', testFramework: 'pytest', buildTool: '', lintTool: 'ruff' },
  frameworks: ['fastapi'],
  referenceFileCount: 10,
  referenceLineCount: 2000,
  browserAvailable: false,
  userHints: []
});
assert('FastAPI → backend-api', fastapi.recommendedType === 'backend-api');
assert('大量参考(10文件/2000行) → full', fastapi.recommendedMode === 'full');

// --- 7. 无信号 → unknown ---
console.log('\n--- 7. 无信号 → unknown ---');

const unknown = recommendTypeMode({
  techStack: { language: 'unknown', packageManager: '', testFramework: '', buildTool: '', lintTool: '' },
  frameworks: [],
  referenceFileCount: 0,
  referenceLineCount: 0,
  browserAvailable: false,
  userHints: []
});
assert('无信号 → unknown', unknown.recommendedType === 'unknown');
assert('confidence 低', unknown.typeConfidence === 'low');

// --- 8. 纯文档 → documentation ---
console.log('\n--- 8. 纯文档 ---');

const docs = recommendTypeMode({
  techStack: { language: 'unknown', packageManager: '', testFramework: '', buildTool: '', lintTool: '' },
  frameworks: [],
  referenceFileCount: 5,
  referenceLineCount: 800,
  browserAvailable: false,
  userHints: ['documentation']
});
assert('userHints=documentation → documentation', docs.recommendedType === 'documentation');

// --- 9. PPT hint → ppt ---
console.log('\n--- 9. PPT hint ---');

const ppt = recommendTypeMode({
  techStack: { language: 'unknown', packageManager: '', testFramework: '', buildTool: '', lintTool: '' },
  frameworks: [],
  referenceFileCount: 2,
  referenceLineCount: 100,
  browserAvailable: true,
  userHints: ['ppt']
});
assert('userHints=ppt → ppt', ppt.recommendedType === 'ppt');

// --- 10. mode 推荐: 少量文件 → fast ---
console.log('\n--- 10. 模式推荐: 小规模 → fast ---');

const small = recommendTypeMode({
  techStack: { language: 'javascript', packageManager: 'npm', testFramework: 'jest', buildTool: '', lintTool: '' },
  frameworks: ['express'],
  referenceFileCount: 1,
  referenceLineCount: 30,
  browserAvailable: false,
  userHints: []
});
assert('少量参考(1文件/30行) → fast', small.recommendedMode === 'fast');

// --- 11. Vue → web-app ---
console.log('\n--- 11. Vue → web-app ---');

const vue = recommendTypeMode({
  techStack: { language: 'javascript', packageManager: 'pnpm', testFramework: 'vitest', buildTool: 'vite', lintTool: 'eslint' },
  frameworks: ['vue'],
  referenceFileCount: 4,
  referenceLineCount: 400,
  browserAvailable: true,
  userHints: []
});
assert('Vue → web-app', vue.recommendedType === 'web-app');

// --- 12. dbt → data-pipeline ---
console.log('\n--- 12. dbt → data-pipeline ---');

const dbt = recommendTypeMode({
  techStack: { language: 'sql', packageManager: '', testFramework: '', buildTool: '', lintTool: '' },
  frameworks: ['dbt'],
  referenceFileCount: 3,
  referenceLineCount: 300,
  browserAvailable: false,
  userHints: []
});
assert('dbt → data-pipeline', dbt.recommendedType === 'data-pipeline');

// --- 13. testStrategy: web-app + browser → e2e ---
console.log('\n--- 13. testStrategy 推导 ---');

assert('web-app + browser → e2e', react.testStrategy === 'e2e');
assert('web-app 无 browser → integration', small.testStrategy === 'integration');
assert('backend-api → integration', express.testStrategy === 'integration');
assert('infrastructure → smoke', terraform.testStrategy === 'smoke');
assert('data-pipeline → smoke', dbt.testStrategy === 'smoke');
assert('documentation → manual', docs.testStrategy === 'manual');

// --- 14. detectTechStack ---
console.log('\n--- 14. detectTechStack ---');

const ts1 = detectTechStack(['package.json', 'package-lock.json', '.eslintrc.json', 'tsconfig.json']);
assert('package.json → javascript', ts1.language === 'javascript');
assert('package-lock.json → npm', ts1.packageManager === 'npm');
assert('.eslintrc.json → eslint', ts1.lintTool === 'eslint');

const ts2 = detectTechStack(['pyproject.toml', 'poetry.lock', 'ruff.toml']);
assert('pyproject.toml → python', ts2.language === 'python');
assert('poetry.lock → poetry', ts2.packageManager === 'poetry');
assert('ruff.toml → ruff', ts2.lintTool === 'ruff');

const ts3 = detectTechStack(['README.md']);
assert('无配置文件 → unknown', ts3.language === 'unknown');

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

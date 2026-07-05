// test-detect-archive-mode.js — detect-archive-mode 的单元测试
// 用法: node tests/test-detect-archive-mode.js
// 退出码: 0=全部通过, 1=有失败

import { detectArchiveMode } from '../workflows/lib/detect-archive-mode.js';

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

console.log('=== detect-archive-mode 单元测试 ===\n');

// --- 1. 首次归档: output/spec 为空 ---
console.log('--- 1. 首次归档 ---');

const first1 = detectArchiveMode({
  outputSpecFiles: [],
  baselineFiles: [],
  reqId: 'REQ001'
});
assert('空 output/spec → first', first1.archiveMode === 'first');
assert('existingFiles 为空', first1.existingFiles.length === 0);
assert('nextBaselineVersion=1', first1.nextBaselineVersion === 1);

// --- 2. 变更归档: output/spec 有文件 ---
console.log('\n--- 2. 变更归档 ---');

const change1 = detectArchiveMode({
  outputSpecFiles: ['design.md', 'requirement-spec.md'],
  baselineFiles: [],
  reqId: 'REQ002'
});
assert('有文件 → change', change1.archiveMode === 'change');
assert('existingFiles 含 2 个文件', change1.existingFiles.length === 2);
assert('无 baseline → nextBaselineVersion=1', change1.nextBaselineVersion === 1);

// --- 3. 有 baseline 历史: 版本递增 ---
console.log('\n--- 3. Baseline 版本递增 ---');

const change2 = detectArchiveMode({
  outputSpecFiles: ['design.md'],
  baselineFiles: ['design.v1.md', 'design.v2.md', 'requirement-spec.v1.md'],
  reqId: 'REQ003'
});
assert('archiveMode=change', change2.archiveMode === 'change');
assert('最大版本 v2 → nextBaselineVersion=3', change2.nextBaselineVersion === 3);

// --- 4. Baseline 版本无序 ---
console.log('\n--- 4. Baseline 版本无序解析 ---');

const change3 = detectArchiveMode({
  outputSpecFiles: ['design.md'],
  baselineFiles: ['design.v5.md', 'design.v2.md', 'design.v10.md'],
  reqId: 'REQ004'
});
assert('最大版本 v10 → nextBaselineVersion=11', change3.nextBaselineVersion === 11);

// --- 5. 无 baseline 文件名中版本号 ---
console.log('\n--- 5. 无版本号的 baseline 文件 ---');

const nover = detectArchiveMode({
  outputSpecFiles: ['design.md'],
  baselineFiles: ['readme.md', 'notes.txt'],
  reqId: 'REQ007'
});
assert('无 .vN. 格式 → nextBaselineVersion=1', nover.nextBaselineVersion === 1);

// --- 6. extraArchive: PPT wireframes ---
console.log('\n--- 6. extraArchive 规则 ---');

const ppt = detectArchiveMode({
  outputSpecFiles: [],
  baselineFiles: [],
  reqId: 'REQ008',
  hasPptWireframes: true
});
assert('有 wireframes → extraArchive 规则', ppt.extraArchive.length === 1);
assert('extra 含 wireframes', ppt.extraArchive[0].source.includes('wireframes'));

const noPpt = detectArchiveMode({
  outputSpecFiles: [],
  baselineFiles: [],
  reqId: 'REQ009',
  hasPptWireframes: false
});
assert('无 wireframes → extraArchive 为空', noPpt.extraArchive.length === 0);

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

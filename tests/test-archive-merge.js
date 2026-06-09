// test-archive-merge.js — archive-merge 的单元测试
// 用法: node tests/test-archive-merge.js
// 退出码: 0=全部通过, 1=有失败

import { archiveMerge } from '../workflows/lib/archive-merge.js';

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

console.log('=== archive-merge 单元测试 ===\n');

// --- 1. 追加: 首次新增内容 ---
console.log('--- 1. 追加新增内容 ---');

const append1 = archiveMerge({
  existingContent: `# Design\n\n## 模块 A\n\n模块 A 的内容。\n`,
  newContent: `## 模块 B\n\n模块 B 的新内容。\n`,
  reqId: 'REQ002',
  mergeType: 'append'
});
assert('包含原有内容', append1.mergedContent.includes('模块 A 的内容'));
assert('包含新增内容', append1.mergedContent.includes('模块 B 的新内容'));
assert('新增内容有 REQ START 标签', append1.mergedContent.includes('<!-- REQ-REQ002 START -->'));
assert('新增内容有 REQ END 标签', append1.mergedContent.includes('<!-- REQ-REQ002 END -->'));
assert('operations 记录追加操作', append1.operations.length === 1 && append1.operations[0].type === 'append');

// --- 2. 替换: 已有标签段落 ---
console.log('\n--- 2. 替换已有标签段落 ---');

const existingWithTag = `# Design

## 模块 A

模块 A 的内容。

<!-- REQ-REQ001 START -->
## 模块 B

旧的模块 B 内容。
<!-- REQ-REQ001 END -->

## 模块 C

模块 C 的内容。
`;

const replace1 = archiveMerge({
  existingContent: existingWithTag,
  newContent: `## 模块 B\n\n更新后的模块 B 内容。\n`,
  reqId: 'REQ001',
  mergeType: 'replace'
});
assert('替换后包含新内容', replace1.mergedContent.includes('更新后的模块 B 内容'));
assert('替换后不含旧内容', !replace1.mergedContent.includes('旧的模块 B 内容'));
assert('保留模块 A', replace1.mergedContent.includes('模块 A 的内容'));
assert('保留模块 C', replace1.mergedContent.includes('模块 C 的内容'));
assert('标签更新为当前 REQ-ID', replace1.mergedContent.includes('<!-- REQ-REQ001 START -->'));
assert('operations 记录替换', replace1.operations[0].type === 'replace');

// --- 3. 废弃: 标记 DEPRECATED ---
console.log('\n--- 3. 废弃标记 ---');

const deprecate1 = archiveMerge({
  existingContent: existingWithTag,
  newContent: '功能已合并到模块 A 中',
  reqId: 'REQ003',
  mergeType: 'deprecate',
  targetReqId: 'REQ001'
});
assert('包含 DEPRECATED 标记', deprecate1.mergedContent.includes('[DEPRECATED by REQ-REQ003]'));
assert('保留原文供追溯', deprecate1.mergedContent.includes('旧的模块 B 内容'));
assert('包含废弃原因', deprecate1.mergedContent.includes('功能已合并到模块 A 中'));
assert('operations 记录废弃', deprecate1.operations[0].type === 'deprecate');

// --- 4. 追加到无标签的历史文档 ---
console.log('\n--- 4. 无标签历史文档追加 ---');

const noTag = `# Requirement Spec

## FR-1: 用户登录

用户可以通过邮箱密码登录。
`;

const append2 = archiveMerge({
  existingContent: noTag,
  newContent: `## FR-2: 用户注册\n\n用户可以通过邮箱注册新账号。\n`,
  reqId: 'REQ002',
  mergeType: 'append'
});
assert('历史内容完整保留', append2.mergedContent.includes('用户可以通过邮箱密码登录'));
assert('新内容追加到末尾', append2.mergedContent.indexOf('FR-2') > append2.mergedContent.indexOf('FR-1'));

// --- 5. 替换时目标标签不存在 → 降级为追加 ---
console.log('\n--- 5. 目标标签不存在降级为追加 ---');

const replaceFallback = archiveMerge({
  existingContent: noTag,
  newContent: `## FR-3: 密码重置\n\n用户可以重置密码。\n`,
  reqId: 'REQ005',
  mergeType: 'replace'
});
assert('标签不存在时降级为 append', replaceFallback.operations[0].type === 'append');
assert('内容仍被添加', replaceFallback.mergedContent.includes('密码重置'));

// --- 6. 多个 REQ 标签共存 ---
console.log('\n--- 6. 多标签共存 ---');

const multiTag = `# Design

<!-- REQ-REQ001 START -->
## 模块 A
内容 A
<!-- REQ-REQ001 END -->

<!-- REQ-REQ002 START -->
## 模块 B
内容 B
<!-- REQ-REQ002 END -->
`;

const appendMulti = archiveMerge({
  existingContent: multiTag,
  newContent: `## 模块 C\n\n内容 C\n`,
  reqId: 'REQ003',
  mergeType: 'append'
});
assert('保留 REQ001 标签段', appendMulti.mergedContent.includes('<!-- REQ-REQ001 START -->'));
assert('保留 REQ002 标签段', appendMulti.mergedContent.includes('<!-- REQ-REQ002 START -->'));
assert('新增 REQ003 标签段', appendMulti.mergedContent.includes('<!-- REQ-REQ003 START -->'));

// --- 7. 空文档追加 ---
console.log('\n--- 7. 空文档追加 ---');

const emptyDoc = archiveMerge({
  existingContent: '',
  newContent: `# 新文档\n\n全新内容。\n`,
  reqId: 'REQ001',
  mergeType: 'append'
});
assert('空文档 → 直接写入带标签', emptyDoc.mergedContent.includes('全新内容'));
assert('有标签包裹', emptyDoc.mergedContent.includes('<!-- REQ-REQ001 START -->'));

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

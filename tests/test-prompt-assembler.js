// test-prompt-assembler.js — prompt-assembler 的单元测试
// 用法: node tests/test-prompt-assembler.js
// 退出码: 0=全部通过, 1=有失败

import { assemblePrompt } from '../workflows/lib/prompt-assembler.js';

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

console.log('=== prompt-assembler 单元测试 ===\n');

// --- 1. 基本组装 ---
console.log('--- 1. 基本组装 ---');

const basic = assemblePrompt('# SA 契约\n职责: 架构设计', '## Handoff\nto: SA\ntask: 设计');
assert('包含角色契约标记', basic.includes('# 角色契约'));
assert('包含契约内容', basic.includes('# SA 契约'));
assert('包含 Handoff 标记', basic.includes('# 任务 Handoff'));
assert('包含 handoff 内容', basic.includes('to: SA'));
assert('角色契约在前，Handoff 在后', basic.indexOf('# 角色契约') < basic.indexOf('# 任务 Handoff'));

// --- 2. 带上下文文件 ---
console.log('\n--- 2. 带上下文文件 ---');

const withContext = assemblePrompt(
  '# DE 契约',
  '## Handoff\ntask: 编码',
  ['// file: utils.ts\nexport function add(a, b) { return a + b; }', '// file: config.ts\nexport const PORT = 3000;']
);
assert('包含上下文文件标记', withContext.includes('# 上下文文件'));
assert('包含第一个文件', withContext.includes('utils.ts'));
assert('包含第二个文件', withContext.includes('config.ts'));
assert('上下文文件在 Handoff 之后', withContext.indexOf('# 上下文文件') > withContext.indexOf('# 任务 Handoff'));

// --- 3. 无上下文文件 ---
console.log('\n--- 3. 无上下文文件时不添加标记 ---');

const noContext = assemblePrompt('# TE 契约', '## Handoff\ntask: 审计');
assert('无上下文文件标记', !noContext.includes('# 上下文文件'));

const emptyContext = assemblePrompt('# TE 契约', '## Handoff\ntask: 审计', []);
assert('空数组时也无上下文标记', !emptyContext.includes('# 上下文文件'));

// --- 4. 行数限制 ---
console.log('\n--- 4. 行数统计 ---');

const longContract = Array(100).fill('requirement line').join('\n');
const longHandoff = Array(100).fill('handoff line').join('\n');
const result = assemblePrompt(longContract, longHandoff);
const lineCount = result.split('\n').length;
assert(`组装结果行数合理 (got ${lineCount})`, lineCount > 200 && lineCount < 250);

// --- 5. 特殊字符处理 ---
console.log('\n--- 5. 特殊字符处理 ---');

const specialChars = assemblePrompt(
  '# 契约\n含有 `代码块` 和 $变量',
  '## Handoff\n路径: deliverables/${req}/sa/'
);
assert('保留反引号', specialChars.includes('`代码块`'));
assert('保留 $ 符号', specialChars.includes('$变量'));
assert('保留模板路径', specialChars.includes('${req}'));

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

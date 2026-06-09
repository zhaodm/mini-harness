// test-calculate-batches.js — calculate-batches 的单元测试
// 用法: node tests/test-calculate-batches.js
// 退出码: 0=全部通过, 1=有失败

import { calculateBatches } from '../workflows/lib/calculate-batches.js';

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

console.log('=== calculate-batches 单元测试 ===\n');

// --- 1. 无依赖: 全部可并行 ---
console.log('--- 1. 无依赖: 全部任务同一批 ---');

const noDeps = calculateBatches({
  tasks: [
    { id: '1', deps: [] },
    { id: '2', deps: [] },
    { id: '3', deps: [] }
  ],
  mergeThreshold: 3
});
assert('1 个批次', noDeps.batches.length === 1);
assert('批次包含全部 3 个任务', noDeps.batches[0].standard.length + (noDeps.batches[0].merged || []).reduce((s, g) => s + g.taskIds.length, 0) === 3);

// --- 2. 线性依赖: 串行执行 ---
console.log('\n--- 2. 线性依赖: 每批 1 个 ---');

const linear = calculateBatches({
  tasks: [
    { id: '1', deps: [] },
    { id: '2', deps: ['1'] },
    { id: '3', deps: ['2'] }
  ],
  mergeThreshold: 3
});
assert('3 个批次（串行）', linear.batches.length === 3);
assert('第 1 批含 task-1', linear.batches[0].standard.some(t => t.taskId === '1'));
assert('第 2 批含 task-2', linear.batches[1].standard.some(t => t.taskId === '2'));
assert('第 3 批含 task-3', linear.batches[2].standard.some(t => t.taskId === '3'));

// --- 3. 菱形依赖: A→B, A→C, B→D, C→D ---
console.log('\n--- 3. 菱形依赖 ---');

const diamond = calculateBatches({
  tasks: [
    { id: 'A', deps: [] },
    { id: 'B', deps: ['A'] },
    { id: 'C', deps: ['A'] },
    { id: 'D', deps: ['B', 'C'] }
  ],
  mergeThreshold: 3
});
assert('3 个批次（A → B,C → D）', diamond.batches.length === 3);
assert('第 1 批含 A', diamond.batches[0].standard.some(t => t.taskId === 'A'));
// B 和 C 在第 2 批（可合并或 standard）
const batch2Tasks = [
  ...diamond.batches[1].standard.map(t => t.taskId),
  ...(diamond.batches[1].merged || []).flatMap(g => g.taskIds)
];
assert('第 2 批含 B 和 C', batch2Tasks.includes('B') && batch2Tasks.includes('C'));
assert('第 3 批含 D', diamond.batches[2].standard.some(t => t.taskId === 'D'));

// --- 4. 合并模式: 同层 ≤threshold 合并 ---
console.log('\n--- 4. 合并模式 ---');

const mergeable = calculateBatches({
  tasks: [
    { id: '1', deps: [] },
    { id: '2', deps: [] },
    { id: '3', deps: [] }
  ],
  mergeThreshold: 3
});
// 3 个无依赖任务，threshold=3，应该合并
const hasMerged = mergeable.batches[0].merged && mergeable.batches[0].merged.length > 0;
const mergedTaskCount = hasMerged
  ? mergeable.batches[0].merged.reduce((s, g) => s + g.taskIds.length, 0)
  : 0;
assert('3 个无依赖任务合并为 1 组', hasMerged && mergedTaskCount === 3);

// --- 5. 超过 threshold 不合并 ---
console.log('\n--- 5. 超过 threshold ---');

const noMerge = calculateBatches({
  tasks: [
    { id: '1', deps: [] },
    { id: '2', deps: [] },
    { id: '3', deps: [] },
    { id: '4', deps: [] }
  ],
  mergeThreshold: 3
});
// 4 个任务，threshold=3，应拆分：一组 3 + 一个 standard，或其他合理组合
const batch1All = [
  ...noMerge.batches[0].standard.map(t => t.taskId),
  ...(noMerge.batches[0].merged || []).flatMap(g => g.taskIds)
];
assert('4 个任务仍在 1 批次', noMerge.batches.length === 1);
assert('全部 4 个任务被安排', batch1All.length === 4);

// --- 6. 单任务: 不合并 ---
console.log('\n--- 6. 单任务 ---');

const single = calculateBatches({
  tasks: [{ id: '1', deps: [] }],
  mergeThreshold: 3
});
assert('1 个批次', single.batches.length === 1);
assert('单任务在 standard 中', single.batches[0].standard.length === 1);
assert('无合并组', !single.batches[0].merged || single.batches[0].merged.length === 0);

// --- 7. 循环依赖检测 ---
console.log('\n--- 7. 循环依赖 ---');

const cyclic = calculateBatches({
  tasks: [
    { id: '1', deps: ['2'] },
    { id: '2', deps: ['1'] }
  ],
  mergeThreshold: 3
});
assert('循环依赖返回 error', cyclic.error !== undefined);
assert('error 包含循环信息', cyclic.error.includes('循环'));

// --- 8. 空任务列表 ---
console.log('\n--- 8. 空任务列表 ---');

const empty = calculateBatches({
  tasks: [],
  mergeThreshold: 3
});
assert('空列表返回 0 个批次', empty.batches.length === 0);

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

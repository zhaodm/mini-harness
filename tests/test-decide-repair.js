// test-decide-repair.js — decide-repair 的单元测试
// 用法: node tests/test-decide-repair.js
// 退出码: 0=全部通过, 1=有失败

import { decideRepair } from '../workflows/lib/decide-repair.js';

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

console.log('=== decide-repair 单元测试 ===\n');

// --- 1. 首轮: 总是 retry ---
console.log('--- 1. 首轮修复 ---');

const firstRound = decideRepair({
  repairRound: 1,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 3 }
  ],
  maxRounds: 5
});
assert('首轮 → retry', firstRound.action === 'retry');
assert('无升级类型', firstRound.escalationType === undefined);

// --- 2. 收敛中: retry ---
console.log('\n--- 2. 收敛中（failed_count 递减） ---');

const converging = decideRepair({
  repairRound: 3,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 5 },
    { round: 2, errorType: 'test_failure', failedCount: 3 },
    { round: 3, errorType: 'test_failure', failedCount: 2 }
  ],
  maxRounds: 5
});
assert('收敛中 → retry', converging.action === 'retry');

// --- 3. 发散: 连续 2 轮 failed_count 增加 ---
console.log('\n--- 3. 发散（failed_count 连续增加） ---');

const diverging = decideRepair({
  repairRound: 3,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 2 },
    { round: 2, errorType: 'test_failure', failedCount: 3 },
    { round: 3, errorType: 'test_failure', failedCount: 5 }
  ],
  maxRounds: 5
});
assert('发散 → escalate', diverging.action === 'escalate');
assert('escalationType=diverging', diverging.escalationType === 'diverging');

// --- 4. 抖动: 连续 2 轮 error_type 变化 ---
console.log('\n--- 4. 抖动（error_type 连续变化） ---');

const thrashing = decideRepair({
  repairRound: 3,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 3 },
    { round: 2, errorType: 'lint_error', failedCount: 2 },
    { round: 3, errorType: 'build_error', failedCount: 1 }
  ],
  maxRounds: 5
});
assert('抖动 → escalate', thrashing.action === 'escalate');
assert('escalationType=thrashing', thrashing.escalationType === 'thrashing');

// --- 5. 耗尽: 达到 maxRounds ---
console.log('\n--- 5. 耗尽（达到 maxRounds） ---');

const exhausted = decideRepair({
  repairRound: 5,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 3 },
    { round: 2, errorType: 'test_failure', failedCount: 3 },
    { round: 3, errorType: 'test_failure', failedCount: 2 },
    { round: 4, errorType: 'test_failure', failedCount: 2 },
    { round: 5, errorType: 'test_failure', failedCount: 1 }
  ],
  maxRounds: 5
});
assert('耗尽 → escalate', exhausted.action === 'escalate');
assert('escalationType=exhausted', exhausted.escalationType === 'exhausted');

// --- 6. 边界: round=4 但收敛 → retry ---
console.log('\n--- 6. 边界: 第 4 轮但收敛 ---');

const almostDone = decideRepair({
  repairRound: 4,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 10 },
    { round: 2, errorType: 'test_failure', failedCount: 5 },
    { round: 3, errorType: 'test_failure', failedCount: 3 },
    { round: 4, errorType: 'test_failure', failedCount: 1 }
  ],
  maxRounds: 5
});
assert('第 4 轮收敛 → retry', almostDone.action === 'retry');

// --- 7. 第 2 轮就发散 → 还不够（需连续 2 轮） ---
console.log('\n--- 7. 单轮增加不触发发散 ---');

const singleIncrease = decideRepair({
  repairRound: 2,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 2 },
    { round: 2, errorType: 'test_failure', failedCount: 4 }
  ],
  maxRounds: 5
});
assert('仅 1 轮增加 → retry（需连续 2 轮才判定发散）', singleIncrease.action === 'retry');

// --- 8. 第 3 轮同一错误无进展 → escalate ---
console.log('\n--- 8. 第 3 轮同错无进展 ---');

const stale = decideRepair({
  repairRound: 3,
  repairHistory: [
    { round: 1, errorType: 'test_failure', failedCount: 3 },
    { round: 2, errorType: 'test_failure', failedCount: 3 },
    { round: 3, errorType: 'test_failure', failedCount: 3 }
  ],
  maxRounds: 5
});
assert('3 轮同错同数 → escalate', stale.action === 'escalate');
assert('escalationType=stale', stale.escalationType === 'stale');

// --- 9. reason 始终非空 ---
console.log('\n--- 9. reason 字段 ---');

assert('首轮有 reason', firstRound.reason.length > 0);
assert('发散有 reason', diverging.reason.length > 0);
assert('耗尽有 reason', exhausted.reason.length > 0);

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

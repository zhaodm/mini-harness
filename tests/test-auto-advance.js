// test-auto-advance.js — auto-advance 的单元测试
// 用法: node tests/test-auto-advance.js
// 退出码: 0=全部通过, 1=有失败

import { autoAdvance } from '../workflows/lib/auto-advance.js';

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

console.log('=== auto-advance 单元测试 ===\n');

// --- 1. INIT-DONE → propose (standard) ---
console.log('--- 1. INIT-DONE → propose ---');

const initDone = autoAdvance({
  phase: 'init',
  currentStep: 'INIT-DONE',
  mode: 'standard',
  srStatus: { SR1: 'pending', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=advance', initDone.action === 'advance');
assert('nextPhase=propose', initDone.nextPhase === 'propose');

// --- 2. PROPOSE-DONE → apply (standard) ---
console.log('\n--- 2. PROPOSE-DONE → apply (standard) ---');

const proposeDone = autoAdvance({
  phase: 'propose',
  currentStep: 'PROPOSE-DONE',
  mode: 'standard',
  srStatus: { SR1: 'skipped', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=advance', proposeDone.action === 'advance');
assert('nextPhase=apply', proposeDone.nextPhase === 'apply');

// --- 3. SR1 审批 → pause (full) ---
console.log('\n--- 3. SR1 待审批 → pause ---');

const sr1Pending = autoAdvance({
  phase: 'propose',
  currentStep: 'SR1-PENDING',
  mode: 'full',
  srStatus: { SR1: 'pending', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=pause', sr1Pending.action === 'pause');
assert('reason 含审批', sr1Pending.reason.includes('SR1'));

// --- 4. SR1 通过 → apply (full) ---
console.log('\n--- 4. SR1 通过 → apply ---');

const sr1Approved = autoAdvance({
  phase: 'propose',
  currentStep: 'SR1-DONE',
  mode: 'full',
  srStatus: { SR1: 'approved', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=advance', sr1Approved.action === 'advance');
assert('nextPhase=apply', sr1Approved.nextPhase === 'apply');

// --- 5. SR3-DONE → archive ---
console.log('\n--- 5. SR3-DONE → archive ---');

const sr3Done = autoAdvance({
  phase: 'apply',
  currentStep: 'SR3-DONE',
  mode: 'standard',
  srStatus: { SR1: 'skipped', SR2: 'approved', SR3: 'approved', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=advance', sr3Done.action === 'advance');
assert('nextPhase=archive', sr3Done.nextPhase === 'archive');

// --- 6. phase=done → end ---
console.log('\n--- 6. phase=done → end ---');

const phaseDone = autoAdvance({
  phase: 'done',
  currentStep: 'SR4-DONE',
  mode: 'standard',
  srStatus: { SR1: 'skipped', SR2: 'approved', SR3: 'approved', SR4: 'approved' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=end', phaseDone.action === 'end');

// --- 7. fast 模式: PROPOSE-DONE 跳过 SR1 ---
console.log('\n--- 7. fast 模式跳过 SR1 ---');

const fastPropose = autoAdvance({
  phase: 'propose',
  currentStep: 'PROPOSE-DONE',
  mode: 'fast',
  srStatus: { SR1: 'skipped', SR2: 'pending', SR3: 'pending', SR4: 'skipped' },
  repairRound: 0,
  autoAdvance: true
});
assert('fast: PROPOSE-DONE → advance', fastPropose.action === 'advance');
assert('fast: nextPhase=apply', fastPropose.nextPhase === 'apply');

// --- 8. fast 模式: apply 完成直接到 archive ---
console.log('\n--- 8. fast 模式 apply→archive ---');

const fastApply = autoAdvance({
  phase: 'apply',
  currentStep: 'SR3-DONE',
  mode: 'fast',
  srStatus: { SR1: 'skipped', SR2: 'approved', SR3: 'approved', SR4: 'skipped' },
  repairRound: 0,
  autoAdvance: true
});
assert('fast: SR3-DONE → advance', fastApply.action === 'advance');
assert('fast: nextPhase=archive', fastApply.nextPhase === 'archive');

// --- 9. 修复循环中 → pause ---
console.log('\n--- 9. 修复循环中 ---');

const repairing = autoAdvance({
  phase: 'apply',
  currentStep: 'BATCH-DEV',
  mode: 'standard',
  srStatus: { SR1: 'skipped', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 3,
  autoAdvance: true
});
assert('修复中 → pause', repairing.action === 'pause');
assert('reason 含修复', repairing.reason.includes('修复'));

// --- 10. SR2 待审批 → pause ---
console.log('\n--- 10. SR2 待审批 ---');

const sr2Pending = autoAdvance({
  phase: 'apply',
  currentStep: 'SR2-PENDING',
  mode: 'standard',
  srStatus: { SR1: 'skipped', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('SR2 待审批 → pause', sr2Pending.action === 'pause');

// --- 11. SR4 待审批 (full) → pause ---
console.log('\n--- 11. SR4 待审批 ---');

const sr4Pending = autoAdvance({
  phase: 'archive',
  currentStep: 'SR4-PENDING',
  mode: 'full',
  srStatus: { SR1: 'approved', SR2: 'approved', SR3: 'approved', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('SR4 待审批 → pause', sr4Pending.action === 'pause');

// --- 12. SR4 fast 模式跳过 → end ---
console.log('\n--- 12. fast 模式跳过 SR4 ---');

const fastArchive = autoAdvance({
  phase: 'archive',
  currentStep: 'ARC-DONE',
  mode: 'fast',
  srStatus: { SR1: 'skipped', SR2: 'approved', SR3: 'approved', SR4: 'skipped' },
  repairRound: 0,
  autoAdvance: true
});
assert('fast: archive 完成 → end', fastArchive.action === 'end');

// --- 13. autoAdvance=false → pause ---
console.log('\n--- 13. autoAdvance=false ---');

const noAuto = autoAdvance({
  phase: 'init',
  currentStep: 'INIT-DONE',
  mode: 'standard',
  srStatus: { SR1: 'pending', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: false
});
assert('autoAdvance=false → pause', noAuto.action === 'pause');

// --- 14. Batch 人工确认 → pause ---
console.log('\n--- 14. Batch 确认 ---');

const batchConfirm = autoAdvance({
  phase: 'apply',
  currentStep: 'BATCH-CONFIRM',
  mode: 'standard',
  srStatus: { SR1: 'skipped', SR2: 'pending', SR3: 'pending', SR4: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('Batch 确认 → pause', batchConfirm.action === 'pause');

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

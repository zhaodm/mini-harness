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

// --- 1. INIT-DONE → propose ---
console.log('--- 1. INIT-DONE → propose ---');

const initDone = autoAdvance({
  phase: 'init',
  currentStep: 'INIT-DONE',
  srStatus: { SR1: 'pending', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=advance', initDone.action === 'advance');
assert('nextPhase=propose', initDone.nextPhase === 'propose');

// --- 2. SR1 待审批 → pause ---
console.log('\n--- 2. SR1 待审批 → pause ---');

const sr1Pending = autoAdvance({
  phase: 'propose',
  currentStep: 'SR1-PENDING',
  srStatus: { SR1: 'pending', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=pause', sr1Pending.action === 'pause');
assert('reason 含审批', sr1Pending.reason.includes('SR1'));

// --- 3. SR1 通过 → apply ---
console.log('\n--- 3. SR1 通过 → apply ---');

const sr1Approved = autoAdvance({
  phase: 'propose',
  currentStep: 'SR1-DONE',
  srStatus: { SR1: 'approved', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=advance', sr1Approved.action === 'advance');
assert('nextPhase=apply', sr1Approved.nextPhase === 'apply');

// --- 4. SR3-DONE → archive ---
console.log('\n--- 4. SR3-DONE → archive ---');

const sr3Done = autoAdvance({
  phase: 'apply',
  currentStep: 'SR3-DONE',
  srStatus: { SR1: 'approved', SR3: 'approved' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=advance', sr3Done.action === 'advance');
assert('nextPhase=archive', sr3Done.nextPhase === 'archive');

// --- 5. phase=done → end ---
console.log('\n--- 5. phase=done → end ---');

const phaseDone = autoAdvance({
  phase: 'done',
  currentStep: 'ARC-DONE',
  srStatus: { SR1: 'approved', SR3: 'approved' },
  repairRound: 0,
  autoAdvance: true
});
assert('action=end', phaseDone.action === 'end');

// --- 6. ARC-DONE → end ---
console.log('\n--- 6. ARC-DONE → end ---');

const arcDone = autoAdvance({
  phase: 'archive',
  currentStep: 'ARC-DONE',
  srStatus: { SR1: 'approved', SR3: 'approved' },
  repairRound: 0,
  autoAdvance: true
});
assert('archive ARC-DONE → end', arcDone.action === 'end');

// --- 7. 修复循环中 → pause ---
console.log('\n--- 7. 修复循环中 ---');

const repairing = autoAdvance({
  phase: 'apply',
  currentStep: 'BATCH-DEV',
  srStatus: { SR1: 'approved', SR3: 'pending' },
  repairRound: 3,
  autoAdvance: true
});
assert('修复中 → pause', repairing.action === 'pause');
assert('reason 含修复', repairing.reason.includes('修复'));

// --- 8. autoAdvance=false → pause ---
console.log('\n--- 8. autoAdvance=false ---');

const noAuto = autoAdvance({
  phase: 'init',
  currentStep: 'INIT-DONE',
  srStatus: { SR1: 'pending', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: false
});
assert('autoAdvance=false → pause', noAuto.action === 'pause');

// --- 9. Batch 人工确认 → pause ---
console.log('\n--- 9. Batch 确认 ---');

const batchConfirm = autoAdvance({
  phase: 'apply',
  currentStep: 'BATCH-CONFIRM',
  srStatus: { SR1: 'approved', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('Batch 确认 → pause', batchConfirm.action === 'pause');

// --- 10. SR3-DONE 返回 stateResets ---
console.log('\n--- 10. stateResets ---');

assert('SR3-DONE 返回 stateResets', sr3Done.stateResets !== undefined);
assert('stateResets 含 repair_round=0', sr3Done.stateResets.repair_round === 0);
assert('stateResets 含 repair_task=""', sr3Done.stateResets.repair_task === '');

// --- 11. SR3 待审批 → pause ---
console.log('\n--- 11. SR3 待审批 ---');

const sr3Pending = autoAdvance({
  phase: 'apply',
  currentStep: 'SR3-PENDING',
  srStatus: { SR1: 'approved', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('SR3 待审批 → pause', sr3Pending.action === 'pause');

// --- 12. WIREFRAME-PENDING → pause (AX-03) ---
console.log('\n--- 12. WIREFRAME-PENDING (ppt track) → pause ---');

const wireframePending = autoAdvance({
  phase: 'propose',
  currentStep: 'WIREFRAME-PENDING',
  srStatus: { SR1: 'pending', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('WIREFRAME-PENDING → pause', wireframePending.action === 'pause');
assert('reason 含 WIREFRAME', wireframePending.reason.includes('WIREFRAME'));

// --- 13. PROPOSAL-CONFIRM → pause ---
console.log('\n--- 13. PROPOSAL-CONFIRM → pause ---');

const proposalConfirm = autoAdvance({
  phase: 'init',
  currentStep: 'PROPOSAL-CONFIRM',
  srStatus: { SR1: 'pending', SR3: 'pending' },
  repairRound: 0,
  autoAdvance: true
});
assert('PROPOSAL-CONFIRM → pause', proposalConfirm.action === 'pause');

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

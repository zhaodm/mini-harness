// test-detect-scenario.js — detect-scenario 的单元测试
// 用法: node tests/test-detect-scenario.js
// 退出码: 0=全部通过, 1=有失败

import { detectScenario } from '../workflows/lib/detect-scenario.js';

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

console.log('=== detect-scenario 单元测试 ===\n');

// --- 1. NEW 场景: 无 state 文件，无 docs/spec ---
console.log('--- 1. NEW 场景 ---');

const newResult1 = detectScenario({
  globalStateExists: false,
  reqStatePhase: null,
  outputSpecFiles: []
});
assert('无全局 state → NEW', newResult1.scenario === 'NEW');
assert('reason 非空', newResult1.reason.length > 0);

const newResult2 = detectScenario({
  globalStateExists: true,
  reqStatePhase: null,
  outputSpecFiles: [],
  activeProject: null
});
assert('有全局 state 但无 project → NEW', newResult2.scenario === 'NEW');

// --- 2. RESUME 场景: 有未完成的流程 ---
console.log('\n--- 2. RESUME 场景 ---');

const resumeResult1 = detectScenario({
  globalStateExists: true,
  reqStatePhase: 'propose',
  outputSpecFiles: [],
  activeProject: 'auth-svc'
});
assert('phase=propose → RESUME', resumeResult1.scenario === 'RESUME');
assert('activeProject=auth-svc', resumeResult1.activeProject === 'auth-svc');

const resumeResult2 = detectScenario({
  globalStateExists: true,
  reqStatePhase: 'apply',
  outputSpecFiles: ['design.md'],
  activeProject: 'sync-job'
});
assert('phase=apply 且有 docs/spec → RESUME（优先级高于 CHANGE）', resumeResult2.scenario === 'RESUME');
assert('未完成流程优先于变更模式', resumeResult2.activeProject === 'sync-job');

// --- 3. CHANGE 场景: phase=done 且有归档产物 ---
console.log('\n--- 3. CHANGE 场景 ---');

const changeResult1 = detectScenario({
  globalStateExists: true,
  reqStatePhase: 'done',
  outputSpecFiles: ['requirement-spec.md', 'design.md'],
  activeProject: 'order-api'
});
assert('phase=done + docs/spec 有文件 → CHANGE', changeResult1.scenario === 'CHANGE');

const changeResult2 = detectScenario({
  globalStateExists: false,
  reqStatePhase: null,
  outputSpecFiles: ['design.md']
});
assert('无 state 但 docs/spec 有文件 → CHANGE', changeResult2.scenario === 'CHANGE');

// --- 4. 边界: phase=done 但无 docs/spec ---
console.log('\n--- 4. 边界情况 ---');

const edgeResult1 = detectScenario({
  globalStateExists: true,
  reqStatePhase: 'done',
  outputSpecFiles: [],
  activeProject: 'web-cli'
});
assert('phase=done 但 docs/spec 为空 → NEW（历史已清理）', edgeResult1.scenario === 'NEW');

// --- 5. init 阶段视为 RESUME ---
console.log('\n--- 5. init 阶段 ---');

const initResult = detectScenario({
  globalStateExists: true,
  reqStatePhase: 'init',
  outputSpecFiles: [],
  activeProject: 'data-etl'
});
assert('phase=init → RESUME（未完成的初始化）', initResult.scenario === 'RESUME');

// --- 6. archive 阶段视为 RESUME ---
console.log('\n--- 6. archive 阶段 ---');

const archiveResult = detectScenario({
  globalStateExists: true,
  reqStatePhase: 'archive',
  outputSpecFiles: ['design.md'],
  activeProject: 'chat-ui'
});
assert('phase=archive → RESUME', archiveResult.scenario === 'RESUME');
assert('不误判为 CHANGE', archiveResult.scenario !== 'CHANGE');

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

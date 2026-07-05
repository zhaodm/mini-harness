// test-retro-collect.js — retro-collect 的单元测试
// 用法: node tests/test-retro-collect.js
// 退出码: 0=全部通过, 1=有失败

import { retroCollect } from '../workflows/lib/retro-collect.js';

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

console.log('=== retro-collect 单元测试 ===\n');

// --- 1. 完整数据采集 ---
console.log('--- 1. 完整数据 ---');

const full = retroCollect({
  reqId: 'REQ001',
  stateData: {
    repair_round: 0,
    sr_status: { SR1: 'approved', SR3: 'approved' },
    repair_history: [
      { round: 1, errorType: 'test_failure', failedCount: 3, summary: 'API 500' },
      { round: 2, errorType: 'test_failure', failedCount: 1, summary: '断言失败' }
    ]
  },
  lessonsContent: `# Lessons

## CP-1: SR2 被驳回
- 现象: 测试覆盖率不足
- 根因: DE 未执行 dev-test
- 影响: 额外 1 轮修复

## CP-2: handoff 白名单遗漏
- 现象: DE 无法读取参考文件
- 根因: SA 未在 handoff 中列出 reference/
- 影响: DE 产出不完整
`,
  processLogContent: `[2026-06-01 10:00] [PM] 初始化完成
[2026-06-01 10:05] [PM] propose 完成
[2026-06-01 10:15] [PM] Task-1 审计失败（轮次 1/5）
[2026-06-01 10:20] [PM] Task-1 修复通过
[2026-06-01 10:30] [PM] SR3 通过
[2026-06-01 10:35] [PM] archive 完成
`,
  handoffFiles: ['REQ001-SA1-T0-R0.md', 'REQ001-DEV1-T1-R0.md', 'REQ001-DEV1-T1-R1.md', 'REQ001-TE1-T1-R0.md'],
  taskCount: 3,
  batchCount: 2
});

assert('metrics.repairRounds=2', full.metrics.repairRounds === 2);
assert('metrics.taskCount=3', full.metrics.taskCount === 3);
assert('metrics.batchCount=2', full.metrics.batchCount === 2);
assert('metrics.srRejections=0（全部 approved）', full.metrics.srRejections === 0);
assert('problems 提取 2 个 CP', full.problems.length === 2);
assert('第一个 problem cpId=CP-1', full.problems[0].cpId === 'CP-1');
assert('第一个 problem 有 title', full.problems[0].title === 'SR2 被驳回');
assert('dataSourcesCount=4', full.dataSourcesCount === 4);

// --- 2. 缺 lessons ---
console.log('\n--- 2. 缺 lessons ---');

const noLessons = retroCollect({
  reqId: 'REQ002',
  stateData: {
    repair_round: 0,
    sr_status: { SR1: 'approved', SR3: 'approved' },
    repair_history: []
  },
  lessonsContent: null,
  processLogContent: `[2026-06-02 09:00] [PM] 初始化完成\n[2026-06-02 09:10] [PM] archive 完成\n`,
  handoffFiles: [],
  taskCount: 1,
  batchCount: 1
});

assert('无 lessons → problems 为空', noLessons.problems.length === 0);
assert('dataSourcesCount=2（state + processLog）', noLessons.dataSourcesCount === 2);
assert('metrics.repairRounds=0', noLessons.metrics.repairRounds === 0);

// --- 3. 缺 processLog ---
console.log('\n--- 3. 缺 processLog ---');

const noLog = retroCollect({
  reqId: 'REQ003',
  stateData: {
    repair_round: 0,
    sr_status: { SR1: 'approved', SR3: 'rejected' },
    repair_history: []
  },
  lessonsContent: `# Lessons\n\n## CP-1: 接口设计不合理\n- 现象: SR2 驳回\n- 根因: SA 未考虑幂等性\n- 影响: 重新设计\n`,
  processLogContent: null,
  handoffFiles: [],
  taskCount: 5,
  batchCount: 2
});

assert('无 processLog → 仍可工作', noLog.metrics.taskCount === 5);
assert('SR3 rejected → srRejections=1', noLog.metrics.srRejections === 1);
assert('dataSourcesCount=2（state + lessons）', noLog.dataSourcesCount === 2);

// --- 4. 多轮修复 ---
console.log('\n--- 4. 多轮修复 ---');

const multiRepair = retroCollect({
  reqId: 'REQ004',
  stateData: {
    repair_round: 0,
    sr_status: { SR1: 'approved', SR3: 'approved' },
    repair_history: [
      { round: 1, errorType: 'build_error', failedCount: 1, summary: '编译失败' },
      { round: 2, errorType: 'build_error', failedCount: 1, summary: '依赖缺失' },
      { round: 3, errorType: 'test_failure', failedCount: 2, summary: '集成测试失败' },
      { round: 4, errorType: 'test_failure', failedCount: 1, summary: '最后 1 个断言' }
    ]
  },
  lessonsContent: `# Lessons\n\n## CP-1: 修复循环过长\n- 现象: 4 轮修复\n- 根因: DE handoff 缺少构建环境说明\n- 影响: Token 浪费\n`,
  processLogContent: null,
  handoffFiles: ['REQ004-DEV1-T1-R0.md', 'REQ004-DEV1-T1-R1.md', 'REQ004-DEV1-T1-R2.md', 'REQ004-DEV1-T1-R3.md', 'REQ004-DEV1-T1-R4.md'],
  taskCount: 2,
  batchCount: 1
});

assert('修复 4 轮', multiRepair.metrics.repairRounds === 4);
assert('result=通过（最终 repair_round=0）', multiRepair.metrics.result === '通过');

// --- 5. 空 handoffs ---
console.log('\n--- 5. 空 handoffs ---');

const noHandoffs = retroCollect({
  reqId: 'REQ005',
  stateData: {
    repair_round: 0,
    sr_status: { SR1: 'approved', SR3: 'approved' },
    repair_history: []
  },
  lessonsContent: null,
  processLogContent: null,
  handoffFiles: [],
  taskCount: 1,
  batchCount: 1
});

assert('无数据 → dataSourcesCount=1（仅 state）', noHandoffs.dataSourcesCount === 1);
assert('metrics 仍完整', noHandoffs.metrics.taskCount === 1);

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

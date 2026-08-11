// test-result-parser.js — result-parser 的单元测试
// 用法: node tests/test-result-parser.js
// 退出码: 0=全部通过, 1=有失败

import { parseReport, isAuditPassed } from '../workflows/lib/result-parser.js';

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

console.log('=== result-parser 单元测试 ===\n');

// --- 1. parseReport: 正常完成回报 ---
console.log('--- 1. parseReport: 正常完成回报 ---');

const doneReport = `
## 完成回报
- status: done
- output_files:
  - deliverables/TEST001/THINKER-propose-design.md
  - deliverables/TEST001/.archiveignore
- summary: 架构设计完成，包含 3 个 Task
- issues: N/A
`;

const parsed = parseReport(doneReport);
assert('status=done', parsed.status === 'done');
assert('解析出 2 个输出文件', parsed.outputFiles.length === 2);
assert('第一个文件路径正确', parsed.outputFiles[0] === 'deliverables/TEST001/THINKER-propose-design.md');
assert('第二个文件路径正确', parsed.outputFiles[1] === 'deliverables/TEST001/.archiveignore');
assert('保留原始输出', parsed.raw === doneReport);

// --- 2. parseReport: 失败回报 ---
console.log('\n--- 2. parseReport: 失败回报 ---');

const failedReport = `
## 完成回报
- status: failed
- output_files:
  - deliverables/TEST001/WORKER-apply-code-report-t1.md
- summary: 编译失败，缺少依赖
- issues: ModuleNotFoundError: No module named 'fastapi'
`;

const parsedFail = parseReport(failedReport);
assert('status=failed', parsedFail.status === 'failed');
assert('解析出 1 个输出文件', parsedFail.outputFiles.length === 1);

// --- 3. parseReport: 无回报（SubAgent 未填写） ---
console.log('\n--- 3. parseReport: 无回报/格式异常 ---');

const emptyReport = `
我已完成了架构设计，文件保存在 sa/design.md 中。
包含以下模块: 用户管理、权限控制、日志系统。
`;

const parsedEmpty = parseReport(emptyReport);
assert('status=unknown（无明确状态）', parsedEmpty.status === 'unknown');
assert('outputFiles 为空数组', parsedEmpty.outputFiles.length === 0);
assert('raw 保留原文', parsedEmpty.raw === emptyReport);

// --- 4. parseReport: 混合内容中提取状态 ---
console.log('\n--- 4. parseReport: 混合内容 ---');

const mixedReport = `
执行过程中遇到了一些问题，但最终解决了。

## 完成回报
- status: done
- output_files:
  - deliverables/TEST001/src/app.ts
  - deliverables/TEST001/src/routes/index.ts
  - deliverables/TEST001/package.json
- summary: Task-1 完成
- issues: N/A

以上是本次开发的全部产出。
`;

const parsedMixed = parseReport(mixedReport);
assert('混合内容中正确提取 status=done', parsedMixed.status === 'done');
assert('混合内容中提取 3 个文件', parsedMixed.outputFiles.length === 3);

// --- 5. isAuditPassed: 明确 PASS ---
console.log('\n--- 5. isAuditPassed: 明确结论 ---');

assert('结论: PASS → true', isAuditPassed('结论: PASS\n所有测试通过'));
assert('conclusion: PASS → true', isAuditPassed('conclusion: PASS'));
assert('结论: FAIL → false', isAuditPassed('结论: FAIL\n3 个用例失败') === false);
assert('conclusion: FAIL → false', isAuditPassed('conclusion: FAIL') === false);

// --- 6. isAuditPassed: 无明确结论 ---
console.log('\n--- 6. isAuditPassed: 模糊判断 ---');

assert('含 FAIL 关键字 → false', isAuditPassed('测试结果: 2 FAIL, 5 PASS') === false);
assert('不含 FAIL → true（兜底）', isAuditPassed('所有检查项均通过，代码质量达标'));
assert('空字符串 → true（兜底）', isAuditPassed(''));

// --- 7. isAuditPassed: 边界情况 ---
console.log('\n--- 7. isAuditPassed: 边界情况 ---');

assert('"FAIL" 在代码引用中仍触发', isAuditPassed('错误: assert.equal FAIL at line 42') === false);
assert('"failure" 不触发（仅精确 FAIL）', isAuditPassed('Previous failure has been resolved'));
assert('结论优先于内容中的 FAIL', isAuditPassed('之前有 FAIL 但修复了\n结论: PASS') === true);

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

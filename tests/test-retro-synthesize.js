// test-retro-synthesize.js — retro-synthesize 的单元测试
// 用法: node tests/test-retro-synthesize.js
// 退出码: 0=全部通过, 1=有失败

import { retroSynthesize } from '../workflows/lib/retro-synthesize.js';

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

console.log('=== retro-synthesize 单元测试 ===\n');

// --- 1. P0 问题 → 脚本层 ---
console.log('--- 1. P0 → 脚本层 ---');

const p0 = retroSynthesize({
  problems: [
    { cpId: 'CP-1', title: 'repair_round 未更新', severity: 'P0', domain: 'state-management', isSystemic: true }
  ]
});
assert('1 个推荐', p0.recommendations.length === 1);
assert('层级=script', p0.recommendations[0].layer === 'script');
assert('problemDomain 保留', p0.recommendations[0].problemDomain === 'state-management');
assert('rationale 非空', p0.recommendations[0].rationale.length > 0);

// --- 2. P1 问题 → 模板层 ---
console.log('\n--- 2. P1 → 模板层 ---');

const p1 = retroSynthesize({
  problems: [
    { cpId: 'CP-2', title: 'handoff 缺少白名单', severity: 'P1', domain: 'handoff-quality', isSystemic: true }
  ]
});
assert('层级=template', p1.recommendations[0].layer === 'template');

// --- 3. P2 问题 → Skill 层 ---
console.log('\n--- 3. P2 → skill 层 ---');

const p2 = retroSynthesize({
  problems: [
    { cpId: 'CP-3', title: '归档顺序不当', severity: 'P2', domain: 'archive-flow', isSystemic: true }
  ]
});
assert('层级=skill', p2.recommendations[0].layer === 'skill');

// --- 4. 非系统性问题被过滤 ---
console.log('\n--- 4. 非系统性问题过滤 ---');

const nonSystemic = retroSynthesize({
  problems: [
    { cpId: 'CP-1', title: '个案操作失误', severity: 'P1', domain: 'misc', isSystemic: false },
    { cpId: 'CP-2', title: '系统缺陷', severity: 'P1', domain: 'validation', isSystemic: true }
  ]
});
assert('过滤非系统性，仅 1 个推荐', nonSystemic.recommendations.length === 1);
assert('保留的是系统性问题', nonSystemic.recommendations[0].problemDomain === 'validation');

// --- 5. 同域问题合并 ---
console.log('\n--- 5. 同域合并 ---');

const sameDomain = retroSynthesize({
  problems: [
    { cpId: 'CP-1', title: '问题 A', severity: 'P0', domain: 'role-guard', isSystemic: true },
    { cpId: 'CP-2', title: '问题 B', severity: 'P1', domain: 'role-guard', isSystemic: true },
    { cpId: 'CP-3', title: '问题 C', severity: 'P1', domain: 'handoff', isSystemic: true }
  ]
});
assert('同域合并为 2 个推荐', sameDomain.recommendations.length === 2);
// 合并后取最高严重度
const roleGuardRec = sameDomain.recommendations.find(r => r.problemDomain === 'role-guard');
assert('同域取最高严重度 P0 → script', roleGuardRec.layer === 'script');
assert('合并后包含所有 cpIds', roleGuardRec.cpIds.includes('CP-1') && roleGuardRec.cpIds.includes('CP-2'));

// --- 6. 空问题列表 ---
console.log('\n--- 6. 空问题列表 ---');

const empty = retroSynthesize({ problems: [] });
assert('空列表 → 0 个推荐', empty.recommendations.length === 0);

// --- 7. deliverables 字段 ---
console.log('\n--- 7. deliverables 字段 ---');

const withDeliverables = retroSynthesize({
  problems: [
    { cpId: 'CP-1', title: '验证脚本遗漏', severity: 'P0', domain: 'verification', isSystemic: true }
  ]
});
assert('deliverables 非空数组', withDeliverables.recommendations[0].deliverables.length > 0);

// --- 8. crSlug 生成 ---
console.log('\n--- 8. crSlug ---');

assert('crSlug 非空', p0.crSlug.length > 0);
assert('crSlug 为 kebab-case', /^[a-z0-9-]+$/.test(p0.crSlug));

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

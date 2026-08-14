// test-regression-suite.js — regression-suite 的单元测试
// 用法: node tests/test-regression-suite.js
// 退出码: 0=全部通过, 1=有失败

import { parseTestcases, aggregateToSuite, validateSuiteIntegrity, getSuiteStats } from '../workflows/lib/regression-suite.js';
import { readFileSync } from 'fs';

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

console.log('=== regression-suite 单元测试 ===\n');

// --- 1. parseTestcases ---
console.log('--- 1. parseTestcases 解析 ---');

const sampleTestcases = `# 测试用例

## TC-1: 用户注册正常流

- 关联需求: FR-1
- 类型: Integration
- 优先级: Critical
- 前置条件: 数据库已启动
- 步骤:
  1. 发送 POST /api/register
  2. 验证响应 201
- 期望结果: 返回 201 且用户已入库
- 边界/异常变体:
  - 重复邮箱: 期望 409

## TC-2: 密码长度校验

- 关联需求: FR-1
- 类型: Unit
- 优先级: Major
- 前置条件: 无
- 步骤:
  1. 调用 validatePassword("abc")
- 期望结果: 返回 false
- 边界/异常变体:
  - 空密码: 期望 false
  - 64字符: 期望 true

## TC-3: 邮箱格式提示

- 关联需求: FR-1
- 类型: Unit
- 优先级: Minor
- 前置条件: 无
- 步骤:
  1. 输入无效邮箱格式
- 期望结果: 显示格式错误提示
`;

const parsed = parseTestcases(sampleTestcases, 'web-cli');
assert('解析出 3 个用例', parsed.length === 3);
assert('TC-1 id 正确', parsed[0].id === 'TC-1');
assert('TC-1 title 正确', parsed[0].title === '用户注册正常流');
assert('TC-1 sourceReq', parsed[0].sourceReq === 'web-cli');
assert('TC-1 requirement', parsed[0].requirement === 'FR-1');
assert('TC-1 type', parsed[0].type === 'Integration');
assert('TC-1 priority', parsed[0].priority === 'Critical');
assert('TC-1 precondition', parsed[0].precondition === '数据库已启动');
assert('TC-1 steps 有 2 步', parsed[0].steps.length === 2);
assert('TC-1 expected 非空', parsed[0].expected.length > 0);
assert('TC-1 variants 有 1 条', parsed[0].variants.length === 1);
assert('TC-2 priority=Major', parsed[1].priority === 'Major');
assert('TC-2 variants 有 2 条', parsed[1].variants.length === 2);
assert('TC-3 priority=Minor', parsed[2].priority === 'Minor');

// --- 2. aggregateToSuite 首次创建 ---
console.log('\n--- 2. aggregateToSuite 首次创建 ---');

const template = readFileSync('templates/regression-suite-template.md', 'utf8');
const result1 = aggregateToSuite(template, parsed, 'web-cli');

assert('首次: added=3', result1.stats.added === 3);
assert('首次: updated=0', result1.stats.updated === 0);
assert('首次: total=3', result1.stats.total === 3);
assert('首次: 包含 PROJECT-web-cli START 标签', result1.content.includes('<!-- PROJECT-web-cli START -->'));
assert('首次: 包含 PROJECT-web-cli END 标签', result1.content.includes('<!-- PROJECT-web-cli END -->'));
assert('首次: 包含 TC-1', result1.content.includes('TC-1'));
assert('首次: 包含 TC-2', result1.content.includes('TC-2'));
assert('首次: 包含 TC-3', result1.content.includes('TC-3'));
assert('首次: 索引含 Critical', result1.content.includes('### Critical'));
assert('首次: 索引含 TC-1 在 Critical', /### Critical[\s\S]*?\[TC-1\]/.test(result1.content));

// --- 3. aggregateToSuite 追加第二个 REQ ---
console.log('\n--- 3. aggregateToSuite 追加 order-api ---');

const proj2Cases = `# 测试用例

## TC-4: 登录成功

- 关联需求: FR-2
- 类型: Integration
- 优先级: Critical
- 前置条件: 用户已注册
- 步骤:
  1. 发送 POST /api/login
- 期望结果: 返回 200 + token

## TC-5: 登录密码错误

- 关联需求: FR-2
- 类型: Integration
- 优先级: Major
- 前置条件: 用户已注册
- 步骤:
  1. 发送错误密码
- 期望结果: 返回 401
`;

const parsed2 = parseTestcases(proj2Cases, 'order-api');
assert('order-api 解析出 2 个用例', parsed2.length === 2);

const result2 = aggregateToSuite(result1.content, parsed2, 'order-api');
assert('追加: added=2', result2.stats.added === 2);
assert('追加: total=5', result2.stats.total === 5);
assert('追加: 包含 PROJECT-web-cli START', result2.content.includes('<!-- PROJECT-web-cli START -->'));
assert('追加: 包含 PROJECT-order-api START', result2.content.includes('<!-- PROJECT-order-api START -->'));
assert('追加: 索引含 TC-4 在 Critical', /### Critical[\s\S]*?\[TC-4\]/.test(result2.content));

// --- 4. aggregateToSuite 去重（同 REQ 再次沉淀）---
console.log('\n--- 4. aggregateToSuite 去重 ---');

const result3 = aggregateToSuite(result2.content, parsed2, 'order-api');
assert('去重: updated=2', result3.stats.updated === 2);
assert('去重: added=0', result3.stats.added === 0);
assert('去重: total=5（不增长）', result3.stats.total === 5);
// 确认只有一个 PROJECT-order-api 标签段
const proj2Starts = (result3.content.match(/<!-- PROJECT-order-api START -->/g) || []).length;
assert('去重: order-api 标签段仅 1 个', proj2Starts === 1);

// --- 5. aggregateToSuite 空用例 ---
console.log('\n--- 5. aggregateToSuite 空用例 ---');

const result4 = aggregateToSuite(result2.content, [], 'auth-svc');
assert('空用例: total 不变', result4.stats.total === 5);
assert('空用例: added=0', result4.stats.added === 0);

// --- 6. validateSuiteIntegrity ---
console.log('\n--- 6. validateSuiteIntegrity ---');

const v1 = validateSuiteIntegrity(result2.content);
assert('完整套件 → valid', v1.valid === true, v1.errors.join('; '));

const v2 = validateSuiteIntegrity('# 随便的文件\n没有结构');
assert('无结构文件 → invalid', v2.valid === false);
assert('缺少标题错误', v2.errors.some(e => e.includes('回归测试套件')));

const v3 = validateSuiteIntegrity('# 回归测试套件\n## 索引\n用例总数: 1\n### TC-1: foo\n没有优先级');
assert('缺少优先级标注 → 报错', v3.valid === false);

// --- 7. getSuiteStats ---
console.log('\n--- 7. getSuiteStats ---');

const stats = getSuiteStats(result2.content);
assert('total=5', stats.total === 5);
assert('critical=2', stats.critical === 2);
assert('major=2', stats.major === 2);
assert('minor=1', stats.minor === 1);
assert('reqCount=2', stats.reqCount === 2);

// --- 汇总 ---
console.log(`\n=== 结果: ${pass} passed, ${fail} failed ===`);
process.exit(fail > 0 ? 1 : 0);

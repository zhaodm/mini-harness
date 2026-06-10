/**
 * regression-suite.js — 回归套件管理引擎（纯函数）
 *
 * 解析 testcases.md、追加到回归套件、去重、重建索引。
 * 复用 archive-merge.js 的 REQ-ID 标签模式。
 *
 * @module workflows/lib/regression-suite
 */

import { archiveMerge } from './archive-merge.js';

/**
 * @typedef {Object} TestCase
 * @property {string} id - TC-{N}
 * @property {string} title - 用例标题
 * @property {string} sourceReq - 来源 REQ-ID
 * @property {string} requirement - 关联需求 FR-{N}
 * @property {string} type - E2E | Unit | Integration | Smoke | Manual
 * @property {string} priority - Critical | Major | Minor
 * @property {string} precondition - 前置条件
 * @property {string[]} steps - 执行步骤
 * @property {string} expected - 期望结果
 * @property {string[]} variants - 边界/异常变体
 */

/**
 * 从 testcases.md 内容中解析出结构化用例列表
 *
 * @param {string} content - testcases.md 文件内容
 * @param {string} sourceReqId - 来源 REQ-ID
 * @returns {TestCase[]}
 */
export function parseTestcases(content, sourceReqId) {
  const testcases = [];
  // 按 ## TC-{N} 或 ### TC-{N} 分割
  const sections = content.split(/^#{2,3}\s+TC-/m).slice(1);

  for (const section of sections) {
    const lines = section.split('\n');
    const headerMatch = lines[0].match(/^(\d+):\s*(.+)/);
    if (!headerMatch) continue;

    const tc = {
      id: `TC-${headerMatch[1]}`,
      title: headerMatch[2].trim(),
      sourceReq: sourceReqId,
      requirement: extractField(section, '关联需求'),
      type: extractField(section, '类型'),
      priority: extractField(section, '优先级'),
      precondition: extractField(section, '前置条件'),
      steps: extractListItems(section, '步骤'),
      expected: extractField(section, '期望结果'),
      variants: extractListItems(section, '边界/异常变体')
    };
    testcases.push(tc);
  }
  return testcases;
}

/**
 * 将新用例追加到回归套件
 * 复用 archive-merge.js 的 append/replace 策略（REQ-ID 标签定位）
 *
 * @param {string} existingSuiteContent - 现有回归套件内容（空字符串表示首次创建）
 * @param {TestCase[]} newCases - 新用例列表
 * @param {string} reqId - 当前 REQ-ID
 * @returns {{ content: string, stats: { added: number, updated: number, total: number } }}
 */
export function aggregateToSuite(existingSuiteContent, newCases, reqId) {
  if (newCases.length === 0) {
    return {
      content: existingSuiteContent,
      stats: { added: 0, updated: 0, total: countCases(existingSuiteContent) }
    };
  }

  // 提取已有用例 ID 集合（用于统计新增 vs 更新）
  const existingIds = extractExistingIds(existingSuiteContent);

  let added = 0, updated = 0;
  for (const tc of newCases) {
    if (existingIds.has(tc.id)) { updated++; } else { added++; }
  }

  // 渲染新用例为 Markdown
  const newSection = renderCasesSection(newCases, reqId);

  // 使用 archive-merge: replace（已有 REQ 标签段）或 append（新 REQ）
  const hasExistingSection = existingSuiteContent.includes(`<!-- REQ-${reqId} START -->`);
  const mergeResult = archiveMerge({
    existingContent: existingSuiteContent,
    newContent: newSection,
    reqId: reqId,
    mergeType: hasExistingSection ? 'replace' : 'append'
  });

  // 重建索引
  const withIndex = rebuildIndex(mergeResult.mergedContent);
  const total = countCases(withIndex);

  // 更新元信息
  const final = updateMeta(withIndex, total);

  return { content: final, stats: { added, updated, total } };
}

/**
 * 校验回归套件结构完整性
 *
 * @param {string} suiteContent
 * @returns {{ valid: boolean, errors: string[] }}
 */
export function validateSuiteIntegrity(suiteContent) {
  const errors = [];

  if (!suiteContent.includes('# 回归测试套件')) {
    errors.push('缺少顶部标题 "# 回归测试套件"');
  }
  if (!suiteContent.includes('## 索引')) {
    errors.push('缺少索引章节');
  }
  if (!/用例总数:\s*\d+/.test(suiteContent)) {
    errors.push('缺少用例总数元信息');
  }

  // 每个 TC 必须有 priority 标注
  const tcHeaders = suiteContent.match(/^#{2,3}\s+TC-\d+/gm) || [];
  const priorities = suiteContent.match(/优先级:\s*(Critical|Major|Minor)/gi) || [];
  if (tcHeaders.length > priorities.length) {
    errors.push(`${tcHeaders.length - priorities.length} 个用例缺少优先级标注`);
  }

  return { valid: errors.length === 0, errors };
}

/**
 * 提取回归套件统计信息
 *
 * @param {string} suiteContent
 * @returns {{ total: number, critical: number, major: number, minor: number, reqCount: number }}
 */
export function getSuiteStats(suiteContent) {
  const tcHeaders = suiteContent.match(/^#{2,3}\s+TC-\d+/gm) || [];
  const critical = (suiteContent.match(/优先级:\s*Critical/gi) || []).length;
  const major = (suiteContent.match(/优先级:\s*Major/gi) || []).length;
  const minor = (suiteContent.match(/优先级:\s*Minor/gi) || []).length;
  const reqs = (suiteContent.match(/<!-- REQ-\w+ START -->/g) || []).length;

  return { total: tcHeaders.length, critical, major, minor, reqCount: reqs };
}

// ─── 内部辅助函数 ───

/**
 * 从用例 section 中提取指定字段值
 */
function extractField(section, fieldName) {
  const match = section.match(new RegExp(`${fieldName}[：:]\\s*(.+)`));
  return match ? match[1].trim() : '';
}

/**
 * 从用例 section 中提取列表项（步骤、变体等）
 */
function extractListItems(section, fieldName) {
  const items = [];
  const fieldIdx = section.indexOf(fieldName);
  if (fieldIdx === -1) return items;
  const afterField = section.substring(fieldIdx);
  const lines = afterField.split('\n').slice(1);
  for (const line of lines) {
    if (/^\s+\d+\.\s/.test(line) || /^\s+-\s/.test(line)) {
      items.push(line.replace(/^\s+(\d+\.\s|-\s)/, '').trim());
    } else if (line.trim() && !line.startsWith(' ') && !line.startsWith('\t')) {
      break;
    }
  }
  return items;
}

/**
 * 从回归套件内容中提取所有已有用例 ID
 */
function extractExistingIds(content) {
  const ids = new Set();
  const matches = content.match(/^#{2,3}\s+(TC-\d+)/gm) || [];
  for (const m of matches) {
    const id = m.match(/TC-\d+/);
    if (id) ids.add(id[0]);
  }
  return ids;
}

/**
 * 统计回归套件中的用例数
 */
function countCases(content) {
  return (content.match(/^#{2,3}\s+TC-\d+/gm) || []).length;
}

/**
 * 渲染用例列表为 Markdown 章节
 */
function renderCasesSection(cases, reqId) {
  let md = `## ${reqId} 用例\n\n`;
  for (const tc of cases) {
    md += `### ${tc.id}: ${tc.title}\n`;
    md += `- 来源: ${tc.sourceReq}\n`;
    md += `- 沉淀时间: ${new Date().toISOString()}\n`;
    md += `- 关联需求: ${tc.requirement}\n`;
    md += `- 类型: ${tc.type}\n`;
    md += `- 优先级: ${tc.priority}\n`;
    md += `- 前置条件: ${tc.precondition}\n`;
    if (tc.steps.length > 0) {
      md += `- 步骤:\n`;
      tc.steps.forEach((s, i) => { md += `  ${i + 1}. ${s}\n`; });
    }
    md += `- 期望结果: ${tc.expected}\n`;
    if (tc.variants.length > 0) {
      md += `- 边界/异常变体:\n`;
      tc.variants.forEach(v => { md += `  - ${v}\n`; });
    }
    md += '\n';
  }
  return md.trimEnd();
}

/**
 * 重建索引区（按优先级分组）
 */
function rebuildIndex(content) {
  // 提取所有用例的 id + title + priority + sourceReq
  const cases = [];
  const lines = content.split('\n');

  let currentId = '', currentTitle = '', currentPriority = '', currentSource = '';
  for (const line of lines) {
    const tcMatch = line.match(/^#{2,3}\s+(TC-\d+):\s*(.+)/);
    if (tcMatch) {
      if (currentId) {
        cases.push({ id: currentId, title: currentTitle, priority: currentPriority, source: currentSource });
      }
      currentId = tcMatch[1];
      currentTitle = tcMatch[2].trim();
      currentPriority = '';
      currentSource = '';
    }
    const prioMatch = line.match(/优先级[：:]\s*(Critical|Major|Minor)/i);
    if (prioMatch && currentId) {
      currentPriority = prioMatch[1];
    }
    const srcMatch = line.match(/来源[：:]\s*(\S+)/);
    if (srcMatch && currentId) {
      currentSource = srcMatch[1];
    }
  }
  if (currentId) {
    cases.push({ id: currentId, title: currentTitle, priority: currentPriority, source: currentSource });
  }

  const indexSection = buildIndexSection(cases);

  // 替换现有索引区
  const indexStart = content.indexOf('## 索引');
  if (indexStart === -1) return content;

  // 找到索引区结束位置（下一个 --- 分隔线）
  const afterIndex = content.substring(indexStart);
  const separatorIdx = afterIndex.indexOf('\n---');
  if (separatorIdx === -1) return content;

  return content.substring(0, indexStart) + indexSection + content.substring(indexStart + separatorIdx);
}

/**
 * 构建索引章节 Markdown
 */
function buildIndexSection(cases) {
  let md = '## 索引（按优先级）\n\n';
  for (const prio of ['Critical', 'Major', 'Minor']) {
    const filtered = cases.filter(c => c.priority === prio);
    md += `### ${prio}\n`;
    if (filtered.length > 0) {
      filtered.forEach(c => { md += `- [${c.id}] ${c.title} (来源: ${c.source})\n`; });
    }
    md += '\n';
  }
  return md;
}

/**
 * 更新回归套件元信息（最后更新时间 + 用例总数）
 */
function updateMeta(content, total) {
  const now = new Date().toISOString();
  let updated = content.replace(/最后更新:\s*.+/, `最后更新: ${now}`);
  updated = updated.replace(/用例总数:\s*\d+/, `用例总数: ${total}`);
  return updated;
}

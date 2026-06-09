/**
 * retro-collect.js — 复盘数据采集引擎
 *
 * 从 .state.md、lessons.md、process.log、handoffs 中聚合结构化指标和问题列表。
 * 纯函数，不做 I/O（调用方负责读取文件后传入内容）。
 *
 * @module workflows/lib/retro-collect
 */

/**
 * @typedef {Object} StateData
 * @property {string} mode - 执行模式
 * @property {string} output_type - 产出类型
 * @property {number} repair_round - 当前修复轮次（完成后应为 0）
 * @property {Object} sr_status - SR1-SR4 状态
 * @property {Array} repair_history - 修复历史
 */

/**
 * @typedef {Object} RetroCollectInput
 * @property {string} reqId - 需求编号
 * @property {StateData} stateData - .state.md 解析后的数据
 * @property {string|null} lessonsContent - lessons.md 文件内容（可为 null）
 * @property {string|null} processLogContent - process.log 文件内容（可为 null）
 * @property {string[]} handoffFiles - handoffs/ 下的文件名列表
 * @property {number} taskCount - 任务总数
 * @property {number} batchCount - 批次总数
 */

/**
 * @typedef {Object} Problem
 * @property {string} cpId - CP 编号
 * @property {string} title - 问题标题
 * @property {string} symptom - 现象
 * @property {string} rootCause - 根因
 * @property {string} impact - 影响
 */

/**
 * @typedef {Object} Metrics
 * @property {string} mode - 执行模式
 * @property {string} outputType - 产出类型
 * @property {number} taskCount - 任务总数
 * @property {number} batchCount - 批次总数
 * @property {number} repairRounds - 修复轮次数
 * @property {number} srRejections - SR 驳回次数
 * @property {string} result - 最终结果
 */

/**
 * @typedef {Object} RetroCollectResult
 * @property {Metrics} metrics - 结构化指标
 * @property {Problem[]} problems - 问题列表
 * @property {number} dataSourcesCount - 有效数据源数量
 */

/**
 * 采集复盘数据
 *
 * @param {RetroCollectInput} input
 * @returns {RetroCollectResult}
 */
export function retroCollect(input) {
  const { reqId, stateData, lessonsContent, processLogContent, handoffFiles, taskCount, batchCount } = input;

  // 统计有效数据源
  let dataSourcesCount = 1; // stateData 始终存在
  if (lessonsContent) dataSourcesCount++;
  if (processLogContent) dataSourcesCount++;
  if (handoffFiles && handoffFiles.length > 0) dataSourcesCount++;

  // 从 stateData 提取指标
  const repairRounds = stateData.repair_history ? stateData.repair_history.length : 0;
  const srRejections = countSrRejections(stateData.sr_status);
  const result = determineResult(stateData);

  const metrics = {
    mode: stateData.mode,
    outputType: stateData.output_type,
    taskCount: taskCount || 0,
    batchCount: batchCount || 0,
    repairRounds,
    srRejections,
    result
  };

  // 从 lessons 中提取问题
  const problems = lessonsContent ? parseLessons(lessonsContent) : [];

  return {
    metrics,
    problems,
    dataSourcesCount
  };
}

/**
 * 统计 SR 驳回次数
 */
function countSrRejections(srStatus) {
  if (!srStatus) return 0;
  let count = 0;
  for (const key of Object.keys(srStatus)) {
    if (srStatus[key] === 'rejected') {
      count++;
    }
  }
  return count;
}

/**
 * 判定最终结果
 */
function determineResult(stateData) {
  // repair_round=0 表示完成（修复通过或无需修复）
  if (stateData.repair_round === 0) {
    return '通过';
  }
  if (stateData.repair_round >= 5) {
    return '升级';
  }
  return '进行中';
}

/**
 * 解析 lessons.md 中的 CP-N 条目
 */
function parseLessons(content) {
  const problems = [];
  // 匹配 ## CP-N: 标题 格式
  const cpRegex = /## (CP-\d+):\s*(.+)/g;
  let match;

  while ((match = cpRegex.exec(content)) !== null) {
    const cpId = match[1];
    const title = match[2].trim();

    // 提取该 CP 下的字段
    const startIdx = match.index + match[0].length;
    const nextCpIdx = content.indexOf('\n## CP-', startIdx);
    const section = nextCpIdx === -1
      ? content.substring(startIdx)
      : content.substring(startIdx, nextCpIdx);

    const symptom = extractField(section, '现象');
    const rootCause = extractField(section, '根因');
    const impact = extractField(section, '影响');

    problems.push({ cpId, title, symptom, rootCause, impact });
  }

  return problems;
}

/**
 * 从段落中提取字段值
 */
function extractField(section, fieldName) {
  const regex = new RegExp(`-\\s*\\*\\*${fieldName}:\\*\\*\\s*(.+)`);
  const match = section.match(regex);
  return match ? match[1].trim() : '';
}

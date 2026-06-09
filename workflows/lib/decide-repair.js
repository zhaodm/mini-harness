/**
 * decide-repair.js — 修复循环决策引擎
 *
 * 根据 repair_history 判断是继续重试还是升级人工。
 * 提前升级条件: 发散(failed_count连续增加) / 抖动(error_type连续变化) / 停滞(同错同数≥3轮) / 耗尽(≥maxRounds)
 *
 * @module workflows/lib/decide-repair
 */

/**
 * @typedef {Object} RepairHistoryEntry
 * @property {number} round - 轮次编号
 * @property {string} errorType - 错误类型 (test_failure/lint_error/build_error/logic_error)
 * @property {number} failedCount - 失败数量
 */

/**
 * @typedef {Object} DecideRepairInput
 * @property {number} repairRound - 当前轮次
 * @property {RepairHistoryEntry[]} repairHistory - 修复历史（按轮次排序）
 * @property {number} maxRounds - 最大轮次（默认 5）
 */

/**
 * @typedef {Object} DecideRepairResult
 * @property {'retry'|'escalate'} action - 决策动作
 * @property {string} reason - 决策依据
 * @property {'diverging'|'thrashing'|'exhausted'|'stale'} [escalationType] - 升级类型
 */

/**
 * 修复循环决策
 *
 * 判断逻辑（按优先级）:
 * 1. 耗尽: repairRound >= maxRounds → escalate
 * 2. 发散: 连续 2 轮 failed_count 递增 → escalate
 * 3. 抖动: 连续 2 轮 error_type 变化（即最近 3 轮各不相同） → escalate
 * 4. 停滞: 连续 3 轮 error_type 和 failed_count 完全相同 → escalate
 * 5. 其他: retry
 *
 * @param {DecideRepairInput} input
 * @returns {DecideRepairResult}
 */
export function decideRepair(input) {
  const { repairRound, repairHistory, maxRounds = 5 } = input;

  // 条件 1: 耗尽
  if (repairRound >= maxRounds) {
    return {
      action: 'escalate',
      reason: `修复轮次已达上限 (${repairRound}/${maxRounds})`,
      escalationType: 'exhausted'
    };
  }

  const len = repairHistory.length;

  // 需要至少 3 条记录才能判定发散/抖动/停滞
  if (len >= 3) {
    const last3 = repairHistory.slice(-3);

    // 条件 2: 发散 — 连续 2 轮 failed_count 增加（即 last3 中后两次递增）
    if (last3[1].failedCount > last3[0].failedCount &&
        last3[2].failedCount > last3[1].failedCount) {
      return {
        action: 'escalate',
        reason: `failed_count 连续 2 轮增加 (${last3[0].failedCount}→${last3[1].failedCount}→${last3[2].failedCount})`,
        escalationType: 'diverging'
      };
    }

    // 条件 3: 抖动 — 连续 2 轮 error_type 变化（3 轮各不相同）
    if (last3[0].errorType !== last3[1].errorType &&
        last3[1].errorType !== last3[2].errorType) {
      return {
        action: 'escalate',
        reason: `error_type 连续变化 (${last3[0].errorType}→${last3[1].errorType}→${last3[2].errorType})`,
        escalationType: 'thrashing'
      };
    }

    // 条件 4: 停滞 — 连续 3 轮同一错误且 failed_count 不变
    if (last3[0].errorType === last3[1].errorType &&
        last3[1].errorType === last3[2].errorType &&
        last3[0].failedCount === last3[1].failedCount &&
        last3[1].failedCount === last3[2].failedCount) {
      return {
        action: 'escalate',
        reason: `连续 3 轮同一错误且无进展 (${last3[0].errorType}, failedCount=${last3[0].failedCount})`,
        escalationType: 'stale'
      };
    }
  }

  // 默认: retry
  return {
    action: 'retry',
    reason: repairRound === 1
      ? '首轮修复，继续尝试'
      : `第 ${repairRound} 轮，尚未触发升级条件`
  };
}

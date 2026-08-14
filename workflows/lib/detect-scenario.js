/**
 * detect-scenario.js — 场景检测引擎
 *
 * 根据全局状态、需求阶段、归档产物判断当前场景。
 * 优先级: RESUME > CHANGE > NEW
 *
 * @module workflows/lib/detect-scenario
 */

/**
 * @typedef {Object} DetectScenarioInput
 * @property {boolean} globalStateExists - deliverables/.state.md 是否存在
 * @property {string|null} reqStatePhase - 当前 REQ 的 phase 字段 (init/propose/apply/archive/done/null)
 * @property {string[]} outputSpecFiles - deliverables/{project}/docs/spec/ 下的文件名列表
 * @property {string} [activeProject] - 当前活跃的项目标识符
 */

/**
 * @typedef {Object} DetectScenarioResult
 * @property {'NEW'|'RESUME'|'CHANGE'} scenario - 检测到的场景
 * @property {string} reason - 判断依据
 * @property {string} [activeProject] - RESUME 场景下的活跃项目标识符
 */

/**
 * 检测当前项目场景
 *
 * 判断优先级（从高到低）:
 * 1. RESUME: 有未完成流程（phase 非空且 ≠ done）
 * 2. CHANGE: deliverables/{project}/docs/spec/ 有已归档文件
 * 3. NEW: 以上均不满足
 *
 * @param {DetectScenarioInput} input
 * @returns {DetectScenarioResult}
 */
export function detectScenario(input) {
  const { globalStateExists, reqStatePhase, outputSpecFiles, activeProject } = input;

  // 优先级 1: RESUME — 有未完成的流程
  // phase 非空、非 null、非 done → 流程进行中
  if (reqStatePhase && reqStatePhase !== 'done') {
    return {
      scenario: 'RESUME',
      reason: `存在未完成的流程 (phase=${reqStatePhase})`,
      activeProject: activeProject || undefined
    };
  }

  // 优先级 2: CHANGE — docs/spec/ 有已归档文件
  if (outputSpecFiles && outputSpecFiles.length > 0) {
    return {
      scenario: 'CHANGE',
      reason: `docs/spec/ 存在 ${outputSpecFiles.length} 个已归档文件，进入变更模式`
    };
  }

  // 优先级 3: NEW — 全新项目
  return {
    scenario: 'NEW',
    reason: globalStateExists
      ? '无未完成流程且无归档产物'
      : '项目未初始化（无全局状态文件）'
  };
}

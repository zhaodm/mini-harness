/**
 * auto-advance.js — 状态机推进引擎
 *
 * 根据当前 phase/step/track 判断下一步动作: advance(自动推进) / pause(等待人工) / end(结束)。
 * 将 mh-run.md / mh-ppt.md 中的状态转移表编码为确定性逻辑。
 *
 * 不变量：auto-advance.js 不写 if(track) 分支。track 通过 clarify 阶段写入不同的
 * 步骤序列来分流，状态机本身按 current_step 决策。WIREFRAME-PENDING 只出现在 ppt track
 * 的 .state.md 中，状态机只需识别该步骤 ID。
 *
 * @module workflows/lib/auto-advance
 */

/**
 * @typedef {Object} AutoAdvanceInput
 * @property {string} phase - 当前阶段 (init/propose/apply/archive/done)
 * @property {string} currentStep - 当前步骤标识
 * @property {Object} srStatus - SR1/SR3 审批状态
 * @property {number} repairRound - 当前修复轮次（>0 表示修复中）
 * @property {boolean} autoAdvance - 是否启用自动推进
 */

/**
 * @typedef {Object} AutoAdvanceResult
 * @property {'advance'|'pause'|'end'} action - 动作
 * @property {string} [nextPhase] - advance 时的目标阶段
 * @property {string} [nextStep] - advance 时的目标步骤
 * @property {string} reason - 决策理由
 * @property {Object} [stateResets] - advance 时需要重置的 .state.md 字段
 */

// 需要人工暂停的步骤
const PAUSE_STEPS = new Set([
  'SR1-PENDING',
  'SR3-PENDING',
  'BATCH-CONFIRM',
  'PROPOSAL-CONFIRM',
  'WIREFRAME-PENDING'  // PPT track wireframe 审批
]);

/**
 * 状态机推进决策
 *
 * 优先级:
 * 1. autoAdvance=false → 一律 pause
 * 2. phase=done → end
 * 3. repairRound > 0 → pause（修复循环内部处理）
 * 4. 人工审批步骤 → pause
 * 5. 阶段完成标记 → advance 到下一阶段
 * 6. 其他 → pause（未识别的步骤保守处理）
 *
 * @param {AutoAdvanceInput} input
 * @returns {AutoAdvanceResult}
 */
export function autoAdvance(input) {
  const { phase, currentStep, srStatus, repairRound, autoAdvance: autoMode } = input;

  // 规则 1: 未启用自动推进
  if (!autoMode) {
    return {
      action: 'pause',
      reason: 'auto_advance 未启用，等待用户手动触发下一阶段'
    };
  }

  // 规则 2: 已完成
  if (phase === 'done') {
    return {
      action: 'end',
      reason: '流程已完成 (phase=done)'
    };
  }

  // 规则 3: 修复循环中
  if (repairRound > 0) {
    return {
      action: 'pause',
      reason: `修复循环进行中 (round=${repairRound})，阶段内处理`
    };
  }

  // 规则 4: 人工审批步骤
  if (PAUSE_STEPS.has(currentStep)) {
    return {
      action: 'pause',
      reason: `等待人工审批: ${currentStep}`
    };
  }

  // 规则 5: 阶段完成标记 → 推进
  const transition = resolveTransition(phase, currentStep);
  if (transition) {
    return transition;
  }

  // 规则 6: 未识别步骤，保守 pause
  return {
    action: 'pause',
    reason: `未识别的步骤状态: ${phase}/${currentStep}`
  };
}

/**
 * 根据阶段完成标记解析转移目标
 */
function resolveTransition(phase, currentStep) {
  // init → propose
  if (phase === 'init' && currentStep === 'INIT-DONE') {
    return {
      action: 'advance',
      nextPhase: 'propose',
      nextStep: 'PROPOSE-START',
      reason: 'clarify 完成，自动推进 → propose'
    };
  }

  // propose → apply (SR1 通过后推进)
  if (phase === 'propose' && currentStep === 'SR1-DONE') {
    return {
      action: 'advance',
      nextPhase: 'apply',
      nextStep: 'APPLY-START',
      reason: 'SR1 通过，自动推进 → apply'
    };
  }

  // apply → archive (SR3 通过后推进)
  if (phase === 'apply' && currentStep === 'SR3-DONE') {
    return {
      action: 'advance',
      nextPhase: 'archive',
      nextStep: 'ARC-START',
      reason: 'SR3 通过，自动推进 → archive',
      stateResets: { repair_round: 0, repair_task: '' }
    };
  }

  // archive → done
  if (phase === 'archive' && currentStep === 'ARC-DONE') {
    return {
      action: 'end',
      reason: '归档完成，流程结束'
    };
  }

  return null;
}

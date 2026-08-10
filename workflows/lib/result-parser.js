/**
 * result-parser.js — 解析 SubAgent 返回结果，提取结构化信息
 *
 * 用于 Workflow 返回后，Orchestrator 会话层解析 SubAgent 输出进行质量门禁判断。
 */

/**
 * 从 SubAgent 输出中提取完成回报
 * @param {string} agentOutput - SubAgent 的原始输出
 * @returns {{ status: string, outputFiles: string[], raw: string }}
 */
export function parseReport(agentOutput) {
  // 提取 status
  let status = 'unknown';
  if (agentOutput.includes('status: failed')) {
    status = 'failed';
  } else if (agentOutput.includes('status: done')) {
    status = 'done';
  }

  // 提取 output_files 列表（仅匹配缩进的行，避免误匹配同级字段）
  const outputFiles = [];
  const filePattern = /output_files:\s*\n((?:[ \t]+-\s*.+\n?)+)/;
  const match = agentOutput.match(filePattern);
  if (match) {
    const lines = match[1].split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('-')) {
        outputFiles.push(trimmed.replace(/^-\s*/, ''));
      }
    }
  }

  return { status, outputFiles, raw: agentOutput };
}

/**
 * 判断 Verifier 审计是否通过
 * @param {string} verifierOutput - Verifier SubAgent 输出
 * @returns {boolean}
 */
export function isAuditPassed(verifierOutput) {
  // 优先看明确结论（结论行权威性最高）
  const conclusionPattern = /(?:结论|conclusion):\s*(PASS|FAIL)/;
  const conclusionMatch = verifierOutput.match(conclusionPattern);
  if (conclusionMatch) {
    return conclusionMatch[1] === 'PASS';
  }

  // 兜底：无明确结论时，检查是否包含 FAIL 关键字
  return !verifierOutput.includes('FAIL');
}

/**
 * 从 Verifier SubAgent 输出中提取 Code Review 判定
 * CR-006: 供 Orchestrator 质量门禁和 Workflow 结果判定使用
 *
 * @param {string} rawOutput - SubAgent 原始输出
 * @returns {{ reviewVerdict: 'PASS'|'FAIL'|'SKIPPED'|'MISSING', criticalCount: number, majorCount: number, minorCount: number }}
 */
export function extractReviewVerdict(rawOutput) {
  const verdictMatch = rawOutput.match(/Code Review 判定:\s*(PASS|FAIL|SKIPPED)/i);
  if (!verdictMatch) {
    return { reviewVerdict: 'MISSING', criticalCount: 0, majorCount: 0, minorCount: 0 };
  }

  const reviewVerdict = verdictMatch[1].toUpperCase();

  let criticalCount = 0, majorCount = 0, minorCount = 0;
  const criticalMatch = rawOutput.match(/Critical:\s*(\d+)/i);
  const majorMatch = rawOutput.match(/Major:\s*(\d+)/i);
  const minorMatch = rawOutput.match(/Minor:\s*(\d+)/i);

  if (criticalMatch) criticalCount = parseInt(criticalMatch[1], 10);
  if (majorMatch) majorCount = parseInt(majorMatch[1], 10);
  if (minorMatch) minorCount = parseInt(minorMatch[1], 10);

  return { reviewVerdict, criticalCount, majorCount, minorCount };
}

/**
 * 从 Verifier SubAgent 输出中提取回归测试判定
 * CR-006: 供 Orchestrator 质量门禁和 Workflow 结果判定使用
 *
 * @param {string} rawOutput - SubAgent 原始输出
 * @returns {{ regressionVerdict: 'PASS'|'FAIL'|'MISSING'|'NO_SUITE', totalCases: number, failedCases: number }}
 */
export function extractRegressionVerdict(rawOutput) {
  // 检查是否标注无回归套件
  if (/NO REGRESSION SUITE|无回归套件/i.test(rawOutput)) {
    return { regressionVerdict: 'NO_SUITE', totalCases: 0, failedCases: 0 };
  }

  const verdictMatch = rawOutput.match(/回归判定:\s*(PASS|FAIL)/i);
  if (!verdictMatch) {
    return { regressionVerdict: 'MISSING', totalCases: 0, failedCases: 0 };
  }

  let totalCases = 0, failedCases = 0;
  const totalMatch = rawOutput.match(/总用例数:\s*(\d+)/);
  const failMatch = rawOutput.match(/失败:\s*(\d+)/);

  if (totalMatch) totalCases = parseInt(totalMatch[1], 10);
  if (failMatch) failedCases = parseInt(failMatch[1], 10);

  return { regressionVerdict: verdictMatch[1].toUpperCase(), totalCases, failedCases };
}

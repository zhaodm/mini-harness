/**
 * result-parser.js — 解析 SubAgent 返回结果，提取结构化信息
 *
 * 用于 Workflow 返回后，PM 会话层解析 SubAgent 输出进行质量门禁判断。
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
 * 判断 TE 审计是否通过
 * @param {string} teOutput - TE SubAgent 输出
 * @returns {boolean}
 */
export function isAuditPassed(teOutput) {
  // 优先看明确结论（结论行权威性最高）
  const conclusionPattern = /(?:结论|conclusion):\s*(PASS|FAIL)/;
  const conclusionMatch = teOutput.match(conclusionPattern);
  if (conclusionMatch) {
    return conclusionMatch[1] === 'PASS';
  }

  // 兜底：无明确结论时，检查是否包含 FAIL 关键字
  return !teOutput.includes('FAIL');
}

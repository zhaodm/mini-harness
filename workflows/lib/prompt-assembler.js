/**
 * prompt-assembler.js — 将 agent 契约 + handoff 内容组装为 SubAgent 的完整 prompt
 *
 * 用于 Workflow 脚本中 agent() 调用前，将角色契约和任务 handoff 拼装为结构化 prompt。
 */

/**
 * 组装 SubAgent prompt
 * @param {string} agentContract - agents/*.md 文件内容（角色契约）
 * @param {string} handoffContent - handoff 内容（任务描述、白名单、约束等）
 * @param {string[]} [contextFiles=[]] - 额外上下文文件内容（白名单中的参考文件摘要）
 * @returns {string} 完整 prompt
 */
export function assemblePrompt(agentContract, handoffContent, contextFiles = []) {
  const parts = [
    '# 角色契约\n',
    agentContract,
    '\n\n---\n\n# 任务 Handoff\n',
    handoffContent
  ];

  if (contextFiles && contextFiles.length > 0) {
    parts.push('\n\n---\n\n# 上下文文件\n');
    contextFiles.forEach(f => {
      parts.push(f);
      parts.push('\n\n---\n');
    });
  }

  return parts.join('');
}

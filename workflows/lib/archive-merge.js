/**
 * archive-merge.js — 归档合并引擎
 *
 * 实现 REQ-ID 标签定位 + 追加/替换/废弃 三种合并策略。
 * 确保 deliverables/{REQ-ID}/docs/spec/ 文档始终是全量文档。
 *
 * @module workflows/lib/archive-merge
 */

/**
 * @typedef {Object} ArchiveMergeInput
 * @property {string} existingContent - 已有文档内容
 * @property {string} newContent - 新增/替换内容
 * @property {string} reqId - 当前需求编号
 * @property {'append'|'replace'|'deprecate'} mergeType - 合并类型
 * @property {string} [targetReqId] - deprecate 模式下要废弃的目标 REQ-ID
 */

/**
 * @typedef {Object} MergeOperation
 * @property {'append'|'replace'|'deprecate'} type - 操作类型
 * @property {string} location - 操作位置描述
 * @property {string} description - 操作描述
 */

/**
 * @typedef {Object} ArchiveMergeResult
 * @property {string} mergedContent - 合并后的完整内容
 * @property {MergeOperation[]} operations - 执行的操作列表
 */

/**
 * 执行归档合并
 *
 * 策略:
 * - append: 在文档末尾追加新内容，用 REQ-ID 标签包裹
 * - replace: 定位目标 REQ-ID 标签段并替换内容
 * - deprecate: 在目标 REQ-ID 标签段前插入 DEPRECATED 标记
 *
 * @param {ArchiveMergeInput} input
 * @returns {ArchiveMergeResult}
 */
export function archiveMerge(input) {
  const { existingContent, newContent, reqId, mergeType, targetReqId } = input;

  const operations = [];

  if (mergeType === 'append') {
    return doAppend(existingContent, newContent, reqId, operations);
  }

  if (mergeType === 'replace') {
    return doReplace(existingContent, newContent, reqId, operations);
  }

  if (mergeType === 'deprecate') {
    return doDeprecate(existingContent, newContent, reqId, targetReqId || reqId, operations);
  }

  // fallback
  return { mergedContent: existingContent, operations: [] };
}

/**
 * 追加新内容到文档末尾，用 REQ-ID 标签包裹
 */
function doAppend(existingContent, newContent, reqId, operations) {
  const tagged = wrapWithTag(newContent, reqId);
  const separator = existingContent && !existingContent.endsWith('\n') ? '\n\n' : '\n';
  const mergedContent = existingContent
    ? existingContent.trimEnd() + separator + tagged + '\n'
    : tagged + '\n';

  operations.push({
    type: 'append',
    location: '文档末尾',
    description: `追加 REQ-${reqId} 标签段`
  });

  return { mergedContent, operations };
}

/**
 * 替换已有 REQ-ID 标签段，如标签不存在则降级为追加
 */
function doReplace(existingContent, newContent, reqId, operations) {
  const startTag = `<!-- REQ-${reqId} START -->`;
  const endTag = `<!-- REQ-${reqId} END -->`;

  const startIdx = existingContent.indexOf(startTag);
  const endIdx = existingContent.indexOf(endTag);

  if (startIdx === -1 || endIdx === -1) {
    // 标签不存在，降级为追加
    return doAppend(existingContent, newContent, reqId, operations);
  }

  // 替换标签段内容
  const before = existingContent.substring(0, startIdx);
  const after = existingContent.substring(endIdx + endTag.length);
  const tagged = wrapWithTag(newContent, reqId);
  const mergedContent = before + tagged + after;

  operations.push({
    type: 'replace',
    location: `REQ-${reqId} 标签段`,
    description: `替换 REQ-${reqId} 标签段内容`
  });

  return { mergedContent, operations };
}

/**
 * 废弃目标 REQ-ID 标签段，添加 DEPRECATED 标记但保留原文
 */
function doDeprecate(existingContent, reason, reqId, targetReqId, operations) {
  const startTag = `<!-- REQ-${targetReqId} START -->`;
  const endTag = `<!-- REQ-${targetReqId} END -->`;

  const startIdx = existingContent.indexOf(startTag);
  const endIdx = existingContent.indexOf(endTag);

  if (startIdx === -1 || endIdx === -1) {
    // 目标标签不存在，无法废弃
    operations.push({
      type: 'deprecate',
      location: `REQ-${targetReqId} (未找到)`,
      description: `目标标签 REQ-${targetReqId} 不存在，跳过`
    });
    return { mergedContent: existingContent, operations };
  }

  // 在标签段开始标签后插入 DEPRECATED 标记
  const deprecatedMark = `\n[DEPRECATED by REQ-${reqId}] — ${reason}\n`;
  const insertPos = startIdx + startTag.length;
  const mergedContent = existingContent.substring(0, insertPos) +
    deprecatedMark +
    existingContent.substring(insertPos);

  operations.push({
    type: 'deprecate',
    location: `REQ-${targetReqId} 标签段`,
    description: `标记废弃 by REQ-${reqId}: ${reason}`
  });

  return { mergedContent, operations };
}

/**
 * 用 REQ-ID 标签包裹内容
 */
function wrapWithTag(content, reqId) {
  const trimmed = content.trimEnd();
  return `<!-- REQ-${reqId} START -->\n${trimmed}\n<!-- REQ-${reqId} END -->`;
}

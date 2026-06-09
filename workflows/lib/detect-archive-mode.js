/**
 * detect-archive-mode.js — 归档模式检测引擎
 *
 * 根据 output/spec/ 文件状态和 baselines/ 历史判断归档模式。
 *
 * @module workflows/lib/detect-archive-mode
 */

/**
 * @typedef {Object} DetectArchiveModeInput
 * @property {string[]} outputSpecFiles - output/spec/ 目录下的文件名列表
 * @property {string[]} baselineFiles - deliverables/{REQ-ID}/baselines/ 下的文件名列表
 * @property {string} reqId - 需求编号
 * @property {string} mode - 执行模式 (fast/standard/full)
 */

/**
 * @typedef {Object} DetectArchiveModeResult
 * @property {'first'|'change'} archiveMode - 归档模式
 * @property {string[]} existingFiles - output/spec/ 中已有的文件
 * @property {number} nextBaselineVersion - 下一个 baseline 版本号
 * @property {boolean} [skipSpec] - fast 模式下跳过 spec 归档
 */

/**
 * 检测归档模式
 *
 * 逻辑:
 * - output/spec/ 非空 → change 模式（需 merge）
 * - output/spec/ 为空 → first 模式（直接复制）
 * - baseline 版本号从文件名 .v{N}. 中提取最大值 + 1
 * - fast 模式标记 skipSpec=true（无 requirement-spec/design 归档）
 *
 * @param {DetectArchiveModeInput} input
 * @returns {DetectArchiveModeResult}
 */
export function detectArchiveMode(input) {
  const { outputSpecFiles, baselineFiles, reqId, mode } = input;

  // 判断归档模式
  const hasExistingSpec = outputSpecFiles && outputSpecFiles.length > 0;
  const archiveMode = hasExistingSpec ? 'change' : 'first';

  // 从 baseline 文件名中提取最大版本号
  let maxVersion = 0;
  if (baselineFiles && baselineFiles.length > 0) {
    for (const file of baselineFiles) {
      const match = file.match(/\.v(\d+)\./);
      if (match) {
        const ver = parseInt(match[1], 10);
        if (ver > maxVersion) {
          maxVersion = ver;
        }
      }
    }
  }

  const result = {
    archiveMode,
    existingFiles: hasExistingSpec ? [...outputSpecFiles] : [],
    nextBaselineVersion: maxVersion + 1
  };

  // fast 模式标记
  if (mode === 'fast') {
    result.skipSpec = true;
  }

  return result;
}

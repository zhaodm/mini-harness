/**
 * detect-archive-mode.js — 归档模式检测引擎
 *
 * 根据 deliverables/{REQ-ID}/docs/spec/ 文件状态和 baselines/ 历史判断归档模式。
 *
 * @module workflows/lib/detect-archive-mode
 */

/**
 * @typedef {Object} DetectArchiveModeInput
 * @property {string[]} outputSpecFiles - deliverables/{REQ-ID}/docs/spec/ 目录下的文件名列表
 * @property {string[]} baselineFiles - deliverables/{REQ-ID}/.engine/baselines/ 下的文件名列表
 * @property {string} reqId - 需求编号
 * @property {boolean} hasPptWireframes - 是否存在 THINKER-propose-wireframes/ 目录
 */

/**
 * @typedef {Object} DetectArchiveModeResult
 * @property {'first'|'change'} archiveMode - 归档模式
 * @property {string[]} existingFiles - docs/spec/ 中已有的文件
 * @property {number} nextBaselineVersion - 下一个 baseline 版本号
 * @property {{source: string, target: string, description: string}[]} extraArchive - 额外归档规则
 */

/**
 * 检测归档模式
 *
 * 逻辑:
 * - deliverables/{REQ-ID}/docs/spec/ 非空 → change 模式（需 merge）
 * - deliverables/{REQ-ID}/docs/spec/ 为空 → first 模式（直接复制）
 * - baseline 版本号从文件名 .v{N}. 中提取最大值 + 1
 *
 * @param {DetectArchiveModeInput} input
 * @returns {DetectArchiveModeResult}
 */
export function detectArchiveMode(input) {
  const { outputSpecFiles, baselineFiles, reqId, hasPptWireframes } = input;

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

  // 额外归档规则（基于文件检测）
  const extraArchive = [];
  if (hasPptWireframes) {
    extraArchive.push({ source: 'THINKER-propose-wireframes/', target: 'assets/wireframes/', description: 'Thinker wireframe 归档' });
  }

  return {
    archiveMode,
    existingFiles: hasExistingSpec ? [...outputSpecFiles] : [],
    nextBaselineVersion: maxVersion + 1,
    extraArchive
  };
}

// 归档排除规则
export const ARCHIVE_EXCLUDES = [
  '.venv/', 'node_modules/', '__pycache__/', '.pytest_cache/', '.ruff_cache/',
  '.git/', '.DS_Store', '*.pyc', '*.pyo', '.env'
];

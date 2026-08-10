/**
 * code-review-rules.js — Code Review 规则引擎（纯函数）
 *
 * 定义评审维度、严重程度阈值、类型路由。
 * 供 Verifier SubAgent prompt 注入 + verify-code-review.sh 格式校验共同引用。
 *
 * @module workflows/lib/code-review-rules
 */

/**
 * 7 个评审维度（结构化数据）
 */
export const REVIEW_DIMENSIONS = [
  {
    id: 'naming',
    label: '命名规范',
    description: '变量/函数/文件命名一致性与语义明确性',
    criticalThreshold: '核心 API 命名误导性（如 delete 实际执行 archive）',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  },
  {
    id: 'error-handling',
    label: '错误处理',
    description: '异常捕获与传播、静默吞错检测',
    criticalThreshold: '未处理的致命异常路径（如数据库连接失败无 catch）',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  },
  {
    id: 'security',
    label: '安全模式',
    description: '输入校验、注入防护、认证/授权检查',
    criticalThreshold: 'SQL注入/XSS/认证绕过/敏感数据明文',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  },
  {
    id: 'complexity',
    label: '代码复杂度',
    description: '函数长度(>50行)、嵌套深度(>4层)、圈复杂度',
    criticalThreshold: '单函数>100行且无拆分理由',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library']
  },
  {
    id: 'dry',
    label: 'DRY 原则',
    description: '重复代码块(>10行相似)、可抽取的公共逻辑',
    criticalThreshold: '3处以上相同逻辑（>10行）未抽取',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library']
  },
  {
    id: 'api-consistency',
    label: 'API 一致性',
    description: '命名风格、响应格式、错误码规范',
    criticalThreshold: '同项目内 API 风格严重不一致（如混用 camelCase 和 snake_case）',
    applicableTo: ['web-app', 'backend-api', 'library']
  },
  {
    id: 'dependencies',
    label: '依赖合理性',
    description: '不必要重依赖、版本锁定、已知漏洞',
    criticalThreshold: '引入已知 CVE 漏洞依赖 或 未锁定版本的核心依赖',
    applicableTo: ['web-app', 'backend-api', 'cli-tool', 'library', 'data-pipeline', 'infrastructure']
  }
];

/**
 * 严重程度定义
 */
export const SEVERITY_LEVELS = {
  Critical: '安全漏洞、数据损坏风险、架构级设计缺陷 → 触发 FAIL',
  Major: '可维护性严重退化、性能隐患、违反项目约定 → 记录但不触发 FAIL',
  Minor: '风格偏差、命名建议、微小优化空间 → 仅建议'
};

// 跳过 Code Review 的产出类型（基于文件检测，这里保留标识供外部判断）
const SKIP_REVIEW_INDICATORS = ['documentation', 'ppt'];

/**
 * 根据产出类型返回应执行的评审维度列表
 * 始终执行全量审查（原 standard 行为）
 *
 * @param {string} outputType - 产出类型标识（从 tech_stack 或文件检测推断）
 * @returns {{ skip: boolean, dimensions: Object[], depth: string, reason?: string }}
 */
export function getReviewScope(outputType) {
  if (SKIP_REVIEW_INDICATORS.includes(outputType)) {
    return { skip: true, dimensions: [], depth: 'none', reason: `${outputType}, 非代码产出` };
  }

  // 按产出类型过滤适用维度
  let dimensions = REVIEW_DIMENSIONS.filter(d => d.applicableTo.includes(outputType));

  // 如果无法匹配任何类型，使用全量维度
  if (dimensions.length === 0) {
    dimensions = [...REVIEW_DIMENSIONS];
  }

  return { skip: false, dimensions, depth: 'standard' };
}

/**
 * 判断是否应跳过 Code Review（基于文件检测）
 *
 * @param {boolean} hasSourceCode - output/ 下是否存在源代码文件
 * @returns {boolean}
 */
export function shouldSkipReview(hasSourceCode) {
  return !hasSourceCode;
}

/**
 * 校验 Code Review 报告结构完整性
 * 供 verify-code-review.sh 的 JS 等价逻辑 或 result-parser 使用
 *
 * @param {string} reportContent - Verifier 报告全文
 * @returns {{ valid: boolean, errors: string[] }}
 */
export function validateReviewReport(reportContent) {
  const errors = [];

  // CR-1: 必须包含 "## Code Review" 章节
  if (!reportContent.includes('## Code Review')) {
    errors.push('缺少 "## Code Review" 章节');
  }

  // CR-2: 必须包含结论行
  if (!/Code Review 判定:\s*(PASS|FAIL|SKIPPED)/i.test(reportContent)) {
    errors.push('缺少 "Code Review 判定: PASS/FAIL/SKIPPED" 结论');
  }

  // CR-3: FAIL 时必须有 Critical 发现
  if (/Code Review 判定:\s*FAIL/i.test(reportContent)) {
    if (!/Critical/i.test(reportContent)) {
      errors.push('Code Review FAIL 但未列出 Critical 发现');
    }
  }

  // CR-4: SKIPPED 时必须有理由
  if (/Code Review 判定:\s*SKIPPED/i.test(reportContent)) {
    if (!/非代码产出|跳过/i.test(reportContent)) {
      errors.push('Code Review SKIPPED 但未标注理由');
    }
  }

  // CR-5: 非 SKIPPED 且有发现时必须有表格格式（维度列）
  const isPassOrFail = /Code Review 判定:\s*(PASS|FAIL)/i.test(reportContent);
  if (isPassOrFail) {
    const hasFindingsTable = /维度.*严重程度|严重程度.*维度/i.test(reportContent);
    const hasNoFindings = /无.*Critical|Critical:\s*0|无发现|未发现问题/i.test(reportContent);
    if (!hasFindingsTable && !hasNoFindings) {
      errors.push('Code Review PASS/FAIL 但未包含发现表格或无发现声明');
    }
  }

  return { valid: errors.length === 0, errors };
}

/**
 * 根据 Code Review 发现统计判定结论
 *
 * @param {{ critical: number, major: number, minor: number }} counts
 * @returns {'PASS' | 'FAIL'}
 */
export function determineVerdict(counts) {
  return counts.critical > 0 ? 'FAIL' : 'PASS';
}

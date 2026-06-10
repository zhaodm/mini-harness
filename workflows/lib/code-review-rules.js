/**
 * code-review-rules.js — Code Review 规则引擎（纯函数）
 *
 * 定义评审维度、严重程度阈值、模式/类型路由。
 * 供 TE SubAgent prompt 注入 + verify-code-review.sh 格式校验共同引用。
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

// 模式 → 维度子集映射
const MODE_SCOPE_MAP = {
  fast: ['security', 'error-handling'],
  standard: null,  // null = 全量（按 output_type 过滤）
  full: null        // 全量 + Minor 也列出
};

// 跳过 Code Review 的 output_type
const SKIP_REVIEW_TYPES = ['documentation', 'ppt'];

// 简化评审的 output_type（仅安全 + 依赖 + 错误处理）
const SIMPLE_REVIEW_TYPES = ['data-pipeline', 'infrastructure'];
const SIMPLE_DIMENSIONS = ['security', 'dependencies', 'error-handling'];

/**
 * 根据 mode + output_type 返回应执行的评审维度列表
 *
 * @param {string} mode - fast | standard | full
 * @param {string} outputType - output_type 字段值
 * @returns {{ skip: boolean, dimensions: Object[], depth: string, reason?: string }}
 */
export function getReviewScope(mode, outputType) {
  if (SKIP_REVIEW_TYPES.includes(outputType)) {
    return { skip: true, dimensions: [], depth: 'none', reason: `output_type=${outputType}, 非代码产出` };
  }

  // 按 output_type 过滤适用维度
  let dimensions = REVIEW_DIMENSIONS.filter(d => d.applicableTo.includes(outputType));

  // 简化类型进一步收窄
  if (SIMPLE_REVIEW_TYPES.includes(outputType)) {
    dimensions = dimensions.filter(d => SIMPLE_DIMENSIONS.includes(d.id));
  }

  // 按 mode 过滤
  const modeFilter = MODE_SCOPE_MAP[mode];
  if (modeFilter) {
    dimensions = dimensions.filter(d => modeFilter.includes(d.id));
  }

  const depth = mode === 'full' ? 'full' : (mode === 'fast' ? 'spot-check' : 'standard');
  return { skip: false, dimensions, depth };
}

/**
 * 判断是否应跳过 Code Review
 *
 * @param {string} outputType
 * @returns {boolean}
 */
export function shouldSkipReview(outputType) {
  return SKIP_REVIEW_TYPES.includes(outputType);
}

/**
 * 校验 Code Review 报告结构完整性
 * 供 verify-code-review.sh 的 JS 等价逻辑 或 result-parser 使用
 *
 * @param {string} reportContent - TE 报告全文
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
    if (!/非代码产出|output_type=|跳过/i.test(reportContent)) {
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

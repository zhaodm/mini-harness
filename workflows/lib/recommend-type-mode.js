/**
 * recommend-type-mode.js — 产品类型/模式推荐引擎
 *
 * 根据 tech_stack、框架检测、参考资料规模推荐 output_type 和 mode。
 *
 * @module workflows/lib/recommend-type-mode
 */

/**
 * @typedef {Object} TechStack
 * @property {string} language
 * @property {string} packageManager
 * @property {string} testFramework
 * @property {string} buildTool
 * @property {string} lintTool
 */

/**
 * @typedef {Object} RecommendTypeModeInput
 * @property {TechStack} techStack - 检测到的技术栈
 * @property {string[]} frameworks - 检测到的框架列表
 * @property {number} referenceFileCount - reference/ 中文件数
 * @property {number} referenceLineCount - reference/ 中总行数
 * @property {boolean} browserAvailable - 浏览器是否可用
 * @property {string[]} userHints - 用户提供的关键词提示
 */

/**
 * @typedef {Object} RecommendTypeModeResult
 * @property {string} recommendedType - 推荐的 output_type
 * @property {'high'|'medium'|'low'} typeConfidence - 类型推荐置信度
 * @property {string} recommendedMode - 推荐的 mode (fast/standard/full)
 * @property {'high'|'medium'|'low'} modeConfidence - 模式推荐置信度
 * @property {string} reasoning - 推荐理由
 */

// 框架 → 类型映射（优先级从高到低）
const FRAMEWORK_TYPE_MAP = {
  // Web 前端框架
  react: 'web-app',
  vue: 'web-app',
  angular: 'web-app',
  svelte: 'web-app',
  nextjs: 'web-app',
  nuxt: 'web-app',
  // 后端框架
  express: 'backend-api',
  fastapi: 'backend-api',
  flask: 'backend-api',
  django: 'backend-api',
  gin: 'backend-api',
  spring: 'backend-api',
  nestjs: 'backend-api',
  koa: 'backend-api',
  hono: 'backend-api',
  // CLI 框架
  commander: 'cli-tool',
  click: 'cli-tool',
  cobra: 'cli-tool',
  clap: 'cli-tool',
  argparse: 'cli-tool',
  yargs: 'cli-tool',
  // 基础设施
  terraform: 'infrastructure',
  pulumi: 'infrastructure',
  cdk: 'infrastructure',
  ansible: 'infrastructure',
  // 数据管道
  dbt: 'data-pipeline',
  airflow: 'data-pipeline',
  spark: 'data-pipeline',
  dagster: 'data-pipeline',
  prefect: 'data-pipeline'
};

// 用户提示 → 类型映射
const HINT_TYPE_MAP = {
  ppt: 'ppt',
  slides: 'ppt',
  演示: 'ppt',
  presentation: 'ppt',
  documentation: 'documentation',
  文档: 'documentation',
  docs: 'documentation',
  library: 'library',
  sdk: 'library',
  lib: 'library'
};

/**
 * 推荐产品类型和执行模式
 *
 * 决策链:
 * 1. userHints 优先（用户明确说了什么类型）
 * 2. 框架匹配（检测到的框架映射到类型）
 * 3. 语言/工具推断
 * 4. 无信号 → unknown
 *
 * 模式推荐:
 * - referenceLineCount ≤ 50 且 fileCount ≤ 1 → fast
 * - referenceLineCount ≤ 1000 且 fileCount ≤ 8 → standard
 * - 其他 → full
 *
 * @param {RecommendTypeModeInput} input
 * @returns {RecommendTypeModeResult}
 */
export function recommendTypeMode(input) {
  const { techStack, frameworks = [], referenceFileCount = 0, referenceLineCount = 0, browserAvailable = false, userHints = [] } = input;

  let recommendedType = null;
  let typeConfidence = 'low';
  let reasoning = '';

  // 决策链 1: userHints
  for (const hint of userHints) {
    const normalizedHint = hint.toLowerCase();
    if (HINT_TYPE_MAP[normalizedHint]) {
      recommendedType = HINT_TYPE_MAP[normalizedHint];
      typeConfidence = 'high';
      reasoning = `用户明确提示: "${hint}"`;
      break;
    }
  }

  // 决策链 2: 框架匹配
  if (!recommendedType) {
    for (const fw of frameworks) {
      const normalizedFw = fw.toLowerCase();
      if (FRAMEWORK_TYPE_MAP[normalizedFw]) {
        recommendedType = FRAMEWORK_TYPE_MAP[normalizedFw];
        typeConfidence = 'high';
        reasoning = `检测到框架: ${fw}`;
        break;
      }
    }
  }

  // 决策链 3: 构建工具推断
  if (!recommendedType && techStack.buildTool) {
    const bt = techStack.buildTool.toLowerCase();
    if (bt === 'terraform' || bt === 'pulumi') {
      recommendedType = 'infrastructure';
      typeConfidence = 'medium';
      reasoning = `构建工具: ${techStack.buildTool}`;
    }
  }

  // 决策链 4: 无信号
  if (!recommendedType) {
    // 纯文档场景: language=unknown + 有参考资料
    if (techStack.language === 'unknown' && referenceFileCount > 0 && !browserAvailable) {
      recommendedType = 'documentation';
      typeConfidence = 'low';
      reasoning = '无技术栈信号，有参考资料，推测为文档类型';
    } else {
      recommendedType = 'unknown';
      typeConfidence = 'low';
      reasoning = '无法自动判定，需用户选择';
    }
  }

  // 模式推荐
  let recommendedMode;
  let modeConfidence;

  if (referenceLineCount <= 50 && referenceFileCount <= 1) {
    recommendedMode = 'fast';
    modeConfidence = 'medium';
  } else if (referenceLineCount <= 1000 && referenceFileCount <= 8) {
    recommendedMode = 'standard';
    modeConfidence = 'medium';
  } else {
    recommendedMode = 'full';
    modeConfidence = 'medium';
  }

  // test_strategy 推导
  const testStrategy = deriveTestStrategy(recommendedType, browserAvailable);

  return {
    recommendedType,
    typeConfidence,
    recommendedMode,
    modeConfidence,
    testStrategy,
    reasoning
  };
}

// test_strategy 映射表
const TEST_STRATEGY_MAP = {
  'web-app': 'e2e',       // 降级: browser 不可用时 → integration
  'backend-api': 'integration',
  'cli-tool': 'integration',
  'data-pipeline': 'smoke',
  'infrastructure': 'smoke',
  'documentation': 'manual',
  'ppt': 'manual',
  'library': 'unit',
  'custom': 'manual'
};

/**
 * 根据 output_type 和浏览器可用性推导 test_strategy
 *
 * @param {string} outputType
 * @param {boolean} browserAvailable
 * @returns {string} test_strategy
 */
function deriveTestStrategy(outputType, browserAvailable) {
  const base = TEST_STRATEGY_MAP[outputType] || 'manual';
  // web-app 特殊处理: 浏览器不可用时降级为 integration
  if (outputType === 'web-app' && !browserAvailable) {
    return 'integration';
  }
  return base;
}

// 技术栈检测映射（供调用方使用）
const TECH_DETECT_MAP = {
  language: {
    'pyproject.toml': 'python', 'setup.py': 'python', 'requirements.txt': 'python',
    'package.json': 'javascript', 'tsconfig.json': 'typescript',
    'go.mod': 'go',
    'Cargo.toml': 'rust',
    'pom.xml': 'java', 'build.gradle': 'java', 'build.gradle.kts': 'kotlin',
    'mix.exs': 'elixir', 'Gemfile': 'ruby'
  },
  packageManager: {
    'poetry.lock': 'poetry', 'uv.lock': 'uv', 'Pipfile.lock': 'pipenv',
    'package-lock.json': 'npm', 'yarn.lock': 'yarn', 'pnpm-lock.yaml': 'pnpm', 'bun.lockb': 'bun',
    'go.sum': 'go modules', 'Cargo.lock': 'cargo'
  },
  lintTool: {
    '.eslintrc': 'eslint', '.eslintrc.js': 'eslint', '.eslintrc.json': 'eslint', 'eslint.config.js': 'eslint',
    'ruff.toml': 'ruff', '.flake8': 'flake8', 'pyproject.toml[tool.ruff]': 'ruff',
    '.golangci.yml': 'golangci-lint', 'clippy.toml': 'clippy'
  }
};

/**
 * 根据项目文件列表检测技术栈
 *
 * @param {string[]} projectFiles - 项目根目录文件名列表
 * @returns {{language: string, packageManager: string, lintTool: string}}
 */
export function detectTechStack(projectFiles) {
  const result = { language: 'unknown', packageManager: '', lintTool: '' };

  for (const file of projectFiles) {
    if (!result.language || result.language === 'unknown') {
      if (TECH_DETECT_MAP.language[file]) {
        result.language = TECH_DETECT_MAP.language[file];
      }
    }
    if (!result.packageManager) {
      if (TECH_DETECT_MAP.packageManager[file]) {
        result.packageManager = TECH_DETECT_MAP.packageManager[file];
      }
    }
    if (!result.lintTool) {
      if (TECH_DETECT_MAP.lintTool[file]) {
        result.lintTool = TECH_DETECT_MAP.lintTool[file];
      }
    }
  }

  return result;
}

// ─── CR-006: Code Review 范围路由 ───

// 跳过 Code Review 的 output_type
const SKIP_REVIEW_TYPES = ['documentation', 'ppt'];

// 简化评审的 output_type（仅安全 + 依赖 + 错误处理）
const SIMPLE_REVIEW_TYPES = ['data-pipeline', 'infrastructure'];
const SIMPLE_DIMENSIONS = ['security', 'dependencies', 'error-handling'];

// 全量评审维度 ID 列表
const FULL_DIMENSIONS = ['naming', 'error-handling', 'security', 'complexity', 'dry', 'api-consistency', 'dependencies'];

// 模式 → 维度子集（null = 全量）
const MODE_REVIEW_SCOPE = {
  fast: ['security', 'error-handling'],
  standard: null,
  full: null
};

/**
 * 根据 mode + outputType 返回 Code Review 执行范围
 * 供 PM 生成 TE handoff 时注入，TE 据此决定评审深度
 *
 * @param {string} mode - fast | standard | full
 * @param {string} outputType - output_type 字段值
 * @returns {{ skip: boolean, dimensions: string[], depth: string, reason?: string }}
 */
export function deriveReviewScope(mode, outputType) {
  if (SKIP_REVIEW_TYPES.includes(outputType)) {
    return { skip: true, dimensions: [], depth: 'none', reason: `output_type=${outputType}, 非代码产出` };
  }

  let dimensions;

  // 简化类型
  if (SIMPLE_REVIEW_TYPES.includes(outputType)) {
    dimensions = SIMPLE_DIMENSIONS;
  } else {
    dimensions = FULL_DIMENSIONS;
  }

  // 按 mode 过滤
  const modeFilter = MODE_REVIEW_SCOPE[mode];
  if (modeFilter) {
    dimensions = dimensions.filter(d => modeFilter.includes(d));
  }

  const depth = mode === 'full' ? 'full' : (mode === 'fast' ? 'spot-check' : 'standard');
  return { skip: false, dimensions, depth };
}

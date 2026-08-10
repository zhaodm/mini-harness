/**
 * recommend-test-strategy.js — 验证策略推荐引擎
 *
 * 根据 tech_stack、框架检测推荐 test_strategy。
 * 同时提供 detectTechStack 和 deriveReviewScope 工具函数。
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
 * @typedef {Object} RecommendTestStrategyInput
 * @property {TechStack} techStack - 检测到的技术栈
 * @property {string[]} frameworks - 检测到的框架列表
 * @property {boolean} browserAvailable - 浏览器是否可用
 * @property {boolean} isPpt - 是否为 PPT 类需求
 */

/**
 * @typedef {Object} RecommendTestStrategyResult
 * @property {string} testStrategy - 推荐的 test_strategy
 * @property {string} reasoning - 推荐理由
 */

// 框架 → 产出类型推断（用于 test_strategy 决策）
const FRAMEWORK_TYPE_MAP = {
  // Web 前端框架 → e2e/integration
  react: 'web-app', vue: 'web-app', angular: 'web-app',
  svelte: 'web-app', nextjs: 'web-app', nuxt: 'web-app',
  // 后端框架 → integration
  express: 'backend-api', fastapi: 'backend-api', flask: 'backend-api',
  django: 'backend-api', gin: 'backend-api', spring: 'backend-api',
  nestjs: 'backend-api', koa: 'backend-api', hono: 'backend-api',
  // CLI 框架 → integration
  commander: 'cli-tool', click: 'cli-tool', cobra: 'cli-tool', clap: 'cli-tool',
};

// 推断产出类型 → test_strategy 映射
const TYPE_STRATEGY_MAP = {
  'web-app': 'e2e',
  'backend-api': 'integration',
  'cli-tool': 'integration',
  'library': 'unit',
};

/**
 * 根据技术栈和框架推荐 test_strategy
 *
 * @param {RecommendTestStrategyInput} input
 * @returns {RecommendTestStrategyResult}
 */
export function recommendTestStrategy(input) {
  const { techStack, frameworks = [], browserAvailable = false, isPpt = false } = input;

  // PPT → manual
  if (isPpt) {
    return { testStrategy: 'manual', reasoning: 'PPT 类需求，使用人工验证' };
  }

  // 无技术栈检测结果 → manual
  if (!techStack || techStack.language === 'unknown') {
    return { testStrategy: 'manual', reasoning: '未检测到技术栈，默认人工验证' };
  }

  // 从框架推断产出类型
  let inferredType = '';
  for (const fw of frameworks) {
    const normalized = fw.toLowerCase().replace(/[^a-z]/g, '');
    if (FRAMEWORK_TYPE_MAP[normalized]) {
      inferredType = FRAMEWORK_TYPE_MAP[normalized];
      break;
    }
  }

  // 如果框架未匹配，从语言推断
  if (!inferredType) {
    if (['javascript', 'typescript'].includes(techStack.language)) {
      inferredType = 'web-app'; // 默认假设，可能被浏览器可用性降级
    } else {
      inferredType = 'backend-api'; // 通用后端
    }
  }

  // 映射到 test_strategy
  let testStrategy = TYPE_STRATEGY_MAP[inferredType] || 'integration';

  // web-app 降级：浏览器不可用时 → integration
  if (inferredType === 'web-app' && !browserAvailable) {
    testStrategy = 'integration';
    return {
      testStrategy,
      reasoning: `检测到 Web 应用框架，但浏览器不可用，降级为 integration`
    };
  }

  return {
    testStrategy,
    reasoning: `基于技术栈(${techStack.language})和框架检测推断`
  };
}

// ─── 技术栈检测 ───

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
    'ruff.toml': 'ruff', '.flake8': 'flake8',
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

// ─── Code Review 范围路由 ───

// 全量评审维度 ID 列表
const FULL_DIMENSIONS = ['naming', 'error-handling', 'security', 'complexity', 'dry', 'api-consistency', 'dependencies'];

/**
 * 返回 Code Review 执行范围（始终全量审查）
 *
 * @param {string} outputType - 从文件检测推断的产出类型标识（保留兼容）
 * @param {string} [track] - 轨道: code | ppt（用于判断是否跳过 Code Review）
 * @returns {{ skip: boolean, dimensions: string[], depth: string, reason?: string }}
 */
export function deriveReviewScope(outputType, track) {
  // ppt track → 跳过 Code Review
  if (track === 'ppt') {
    return { skip: true, dimensions: [], depth: 'none', reason: 'track=ppt, 非代码产出' };
  }

  return { skip: false, dimensions: FULL_DIMENSIONS, depth: 'standard' };
}

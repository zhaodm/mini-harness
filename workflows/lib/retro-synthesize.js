/**
 * retro-synthesize.js — 复盘约束层决策引擎
 *
 * 将系统性问题分类，按决策树推荐约束层级（脚本 > 模板 > Skill > NL）。
 * 同域问题合并，取最高严重度决定层级。
 *
 * @module workflows/lib/retro-synthesize
 */

/**
 * @typedef {Object} ProblemInput
 * @property {string} cpId - CP 编号
 * @property {string} title - 问题标题
 * @property {'P0'|'P1'|'P2'} severity - 严重度
 * @property {string} domain - 问题域标识
 * @property {boolean} isSystemic - 是否为系统性问题
 */

/**
 * @typedef {Object} RetroSynthesizeInput
 * @property {ProblemInput[]} problems - 问题列表（含非系统性）
 */

/**
 * @typedef {Object} Recommendation
 * @property {string} problemDomain - 问题域标识
 * @property {string[]} cpIds - 关联的 CP 编号
 * @property {'script'|'template'|'skill'|'natural-language'} layer - 推荐约束层级
 * @property {string} rationale - 推荐理由
 * @property {string[]} deliverables - 预期交付物
 */

/**
 * @typedef {Object} RetroSynthesizeResult
 * @property {Recommendation[]} recommendations - 推荐列表
 * @property {string} crSlug - CR 文档 slug（kebab-case）
 */

// 严重度 → 层级映射
const SEVERITY_LAYER_MAP = {
  P0: 'script',
  P1: 'template',
  P2: 'skill'
};

// 层级 → 交付物模板
const LAYER_DELIVERABLES = {
  script: ['scripts/*.sh 或 Hook 脚本'],
  template: ['templates/*.md 模板文件'],
  skill: ['skills/*.md 流程约束'],
  'natural-language': ['CLAUDE.md 或 agents/*.md 软约束']
};

// 层级 → 推荐理由模板
const LAYER_RATIONALE = {
  script: '可机械判定的违规，应通过脚本硬约束阻止',
  template: '需引导正确行为，通过模板结构约束实现',
  skill: '需流程步骤保障，在 Skill 中增加检查点',
  'natural-language': '无法脚本化的行为判断，通过文档约束'
};

/**
 * 综合分析问题并推荐约束层
 *
 * 算法:
 * 1. 过滤：仅保留 isSystemic=true 的问题
 * 2. 合并：同 domain 的问题合并，取最高严重度
 * 3. 映射：严重度 → 约束层（P0→脚本, P1→模板, P2→Skill）
 * 4. 生成 crSlug
 *
 * @param {RetroSynthesizeInput} input
 * @returns {RetroSynthesizeResult}
 */
export function retroSynthesize(input) {
  const { problems } = input;

  // Step 1: 过滤非系统性问题
  const systemic = problems.filter(p => p.isSystemic);

  if (systemic.length === 0) {
    return { recommendations: [], crSlug: 'no-systemic-issues' };
  }

  // Step 2: 按 domain 分组合并
  const domainMap = new Map();
  for (const problem of systemic) {
    if (!domainMap.has(problem.domain)) {
      domainMap.set(problem.domain, {
        domain: problem.domain,
        cpIds: [],
        highestSeverity: problem.severity,
        titles: []
      });
    }
    const group = domainMap.get(problem.domain);
    group.cpIds.push(problem.cpId);
    group.titles.push(problem.title);
    // 取最高严重度（P0 > P1 > P2）
    if (compareSeverity(problem.severity, group.highestSeverity) > 0) {
      group.highestSeverity = problem.severity;
    }
  }

  // Step 3: 映射层级并生成推荐
  const recommendations = [];
  for (const [domain, group] of domainMap) {
    const layer = SEVERITY_LAYER_MAP[group.highestSeverity] || 'natural-language';
    recommendations.push({
      problemDomain: domain,
      cpIds: group.cpIds,
      layer,
      rationale: LAYER_RATIONALE[layer],
      deliverables: [...LAYER_DELIVERABLES[layer]]
    });
  }

  // 按严重度排序（P0 优先）
  recommendations.sort((a, b) => {
    const order = { script: 0, template: 1, skill: 2, 'natural-language': 3 };
    return (order[a.layer] || 3) - (order[b.layer] || 3);
  });

  // Step 4: 生成 crSlug
  const primaryDomain = recommendations[0].problemDomain;
  const crSlug = generateSlug(primaryDomain, recommendations.length);

  return { recommendations, crSlug };
}

/**
 * 比较严重度（返回正数表示 a 更严重）
 */
function compareSeverity(a, b) {
  const order = { P0: 3, P1: 2, P2: 1 };
  return (order[a] || 0) - (order[b] || 0);
}

/**
 * 生成 kebab-case slug
 */
function generateSlug(primaryDomain, totalDomains) {
  const base = primaryDomain.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  if (totalDomains > 1) {
    return `${base}-and-${totalDomains - 1}-more`;
  }
  return base;
}

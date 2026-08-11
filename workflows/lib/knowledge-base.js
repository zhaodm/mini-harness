/**
 * knowledge-base.js — 分层知识库生成引擎（纯函数）
 *
 * 从开发产物中自动生成三层知识库结构：
 * - Layer 0: system-map.md（全景入口，≤150行）
 * - Layer 1: domains/*.md（域指南，每份≤400行）
 * - Layer 2: recipes/*.md（操作食谱，每份≤80行）
 * - kb-verify.sh（新鲜度检查脚本）
 *
 * @module workflows/lib/knowledge-base
 */

import { archiveMerge } from './archive-merge.js';

// === 类型定义 ===

/**
 * @typedef {Object} KBSources
 * @property {string} [requirementSpec] - THINKER-propose-requirement-spec.md
 * @property {string} [designContent] - THINKER-propose-design.md
 * @property {string[]} [codeReports] - WORKER-apply-code-report*.md 数组
 * @property {string} [codeReviewContent] - Verifier code-review 内容
 * @property {Object[]} [repairHistory] - .engine/.state.md repair_history[]
 * @property {string[]} [outputFiles] - deliverables/{REQ-ID}/ 文件路径列表
 * @property {Object} [techStack] - .engine/.state.md tech_stack
 * @property {string} [outputType] - 产出类型（可选，用于推断）
 */

/**
 * @typedef {Object} DomainInfo
 * @property {string} name - 域名（kebab-case，用作文件名）
 * @property {string} title - 域标题（中文）
 * @property {string} content - 域指南完整内容
 * @property {string} sourcePaths - 对应源码路径
 */

/**
 * @typedef {Object} RecipeInfo
 * @property {string} name - 食谱名（kebab-case）
 * @property {string} title - 食谱标题
 * @property {string} content - 食谱完整内容
 */

/**
 * @typedef {Object} KnowledgeBase
 * @property {string} systemMap - Layer 0 内容
 * @property {DomainInfo[]} domains - Layer 1 域指南列表
 * @property {RecipeInfo[]} recipes - Layer 2 食谱列表
 * @property {string} kbVerify - kb-verify.sh 内容
 */

// === 主导出函数 ===

/**
 * 构建分层知识库
 *
 * @param {KBSources} sources - 各来源内容
 * @param {string} reqId - 当前 REQ-ID
 * @param {string} date - 当前日期 YYYY-MM-DD
 * @param {Object} meta - { projectName, techStack }
 * @returns {KnowledgeBase}
 */
export function buildKnowledgeBase(sources, reqId, date, meta) {
  const { requirementSpec, designContent, codeReports, codeReviewContent,
          repairHistory, outputFiles, techStack, outputType } = sources;
  const { projectName = '未命名项目' } = meta || {};

  // Step 1: 确定域拆分
  const domains = splitIntoDomains(designContent, codeReports);

  // Step 2: 推断食谱
  const recipes = inferRecipes(designContent, codeReports);

  // Step 3: 生成 system-map
  const systemMap = buildSystemMap({
    projectName, reqId, date, techStack, outputType,
    requirementSpec, designContent, outputFiles, domains, recipes,
    codeReviewContent, repairHistory,
  });

  // Step 4: 生成域指南内容
  const domainGuides = domains.map(d => ({
    ...d,
    content: buildDomainGuide(d, designContent, codeReports, codeReviewContent, repairHistory),
  }));

  // Step 5: 生成食谱内容
  const recipeGuides = recipes.map(r => ({
    ...r,
    content: buildRecipeContent(r, designContent, codeReports),
  }));

  // Step 6: 生成 kb-verify.sh
  const kbVerify = generateKBVerify(domainGuides);

  return {
    systemMap,
    domains: domainGuides,
    recipes: recipeGuides,
    kbVerify,
  };
}

/**
 * 合并知识库（change 模式）
 *
 * @param {Object} existingKB - 已有知识库文件内容 { systemMap, domains: {name: content}, recipes: {name: content} }
 * @param {KnowledgeBase} newKB - 本次生成的知识库
 * @param {string} reqId - 当前 REQ-ID
 * @param {string} date - 当前日期
 * @returns {{ files: {path: string, content: string}[], stats: Object }}
 */
export function mergeKnowledgeBase(existingKB, newKB, reqId, date) {
  const files = [];

  // system-map: 全量替换（始终反映最新全景）
  files.push({ path: 'docs/kb/system-map.md', content: newKB.systemMap });

  // 域指南: 新增或替换对应域
  for (const domain of newKB.domains) {
    const existing = existingKB.domains && existingKB.domains[domain.name];
    if (existing) {
      // 合并：保留已有约束/陷阱段，更新其他段
      const merged = mergeDomainGuide(existing, domain.content, reqId);
      files.push({ path: `docs/kb/domains/${domain.name}.md`, content: merged });
    } else {
      files.push({ path: `docs/kb/domains/${domain.name}.md`, content: domain.content });
    }
  }

  // 食谱: 仅新增，不覆盖已有（已有的可能被人工完善过）
  for (const recipe of newKB.recipes) {
    const existing = existingKB.recipes && existingKB.recipes[recipe.name];
    if (!existing) {
      files.push({ path: `docs/kb/recipes/${recipe.name}.md`, content: recipe.content });
    }
  }

  // kb-verify.sh: 全量替换
  files.push({ path: 'docs/kb/kb-verify.sh', content: newKB.kbVerify });

  const stats = {
    systemMap: countLines(newKB.systemMap),
    domains: newKB.domains.length,
    recipes: newKB.recipes.length,
    totalFiles: files.length,
  };

  return { files, stats };
}

/**
 * 从 design.md 中识别模块/域拆分
 *
 * @param {string} [designContent]
 * @param {string[]} [codeReports]
 * @returns {DomainInfo[]}
 */
export function splitIntoDomains(designContent, codeReports) {
  const domains = [];

  if (!designContent) {
    // 无设计文档时生成单一 core 域
    return [{ name: 'core', title: '核心模块', content: '', sourcePaths: 'src/' }];
  }

  // 从设计文档中识别模块级二级/三级标题
  const modulePattern = /^#{2,3}\s+.*(?:模块|组件|服务|层|Module|Service|Component|Layer)/im;
  const sections = splitByHeadings(designContent, 2);

  for (const section of sections) {
    if (!modulePattern.test(section.heading)) continue;

    const title = section.heading.replace(/^#+\s+/, '').trim();
    const name = toKebabCase(title);

    // 从内容中推断源码路径
    const srcPaths = section.body.match(/src\/[\w/.-]+/g) || [];
    const sourcePaths = [...new Set(srcPaths.map(p => p.split('/').slice(0, 2).join('/')))].join(', ') || 'src/';

    domains.push({ name, title, content: '', sourcePaths });
  }

  // 如果没识别到模块段落，从 Tasks 中推断
  if (domains.length === 0 && designContent) {
    const taskSections = extractTaskFilePatterns(designContent);
    const dirs = [...new Set(taskSections.map(t => t.dir).filter(Boolean))];

    if (dirs.length > 1) {
      for (const dir of dirs) {
        domains.push({
          name: toKebabCase(dir),
          title: dir,
          content: '',
          sourcePaths: `src/${dir}/`,
        });
      }
    }
  }

  // 兜底：至少一个 core 域
  if (domains.length === 0) {
    domains.push({ name: 'core', title: '核心模块', content: '', sourcePaths: 'src/' });
  }

  return domains;
}

/**
 * 从 design.md 的 Tasks 结构推断操作食谱
 *
 * @param {string} [designContent]
 * @param {string[]} [codeReports]
 * @returns {RecipeInfo[]}
 */
export function inferRecipes(designContent, codeReports) {
  const recipes = [];
  if (!designContent) return recipes;

  // 从 Tasks 表格中提取文件创建模式
  const taskPatterns = extractTaskFilePatterns(designContent);

  // 归纳模式：哪些 Tasks 创建了类似结构的文件
  const patternGroups = groupByFilePattern(taskPatterns);

  for (const [patternName, group] of Object.entries(patternGroups)) {
    if (group.files.length < 2) continue; // 至少涉及 2 个文件才值得做食谱

    recipes.push({
      name: `add-${patternName}`,
      title: `添加新${group.label}`,
      content: '',
      files: group.files,
      reference: group.referenceTask,
    });
  }

  // 如果没推断出食谱，从常见模式生成通用食谱
  if (recipes.length === 0 && codeReports && codeReports.length > 0) {
    const allFiles = extractAllFilesFromReports(codeReports);
    if (allFiles.some(f => /route|controller|endpoint/i.test(f))) {
      recipes.push({ name: 'add-endpoint', title: '添加新接口', content: '', files: [], reference: '' });
    }
    if (allFiles.some(f => /component|page/i.test(f))) {
      recipes.push({ name: 'add-component', title: '添加新组件', content: '', files: [], reference: '' });
    }
    if (allFiles.some(f => /service|worker|queue/i.test(f))) {
      recipes.push({ name: 'add-service', title: '添加新服务', content: '', files: [], reference: '' });
    }
  }

  return recipes;
}

/**
 * 生成 Layer 0: system-map.md
 */
function buildSystemMap(ctx) {
  const { projectName, reqId, date, techStack, outputType,
          requirementSpec, designContent, outputFiles, domains, recipes,
          codeReviewContent, repairHistory } = ctx;

  const techSummary = techStack
    ? [techStack.language, techStack.build_tool, techStack.test_framework].filter(Boolean).join(' + ')
    : '未指定';

  const lines = [];
  lines.push(`# ${projectName} — 系统全景`);
  lines.push('');
  lines.push(`> 自动生成，供 AI 快速定位任务涉及的模块并跳转到域指南。`);
  lines.push(`> 生成自: ${reqId} | 日期: ${date} | 技术栈: ${techSummary}`);
  lines.push('');

  // 项目定位
  lines.push('## 项目定位');
  lines.push('');
  lines.push(extractProjectPurpose(requirementSpec, designContent));
  lines.push('');

  // 技术栈
  lines.push('## 技术栈');
  lines.push('');
  if (techStack) {
    if (techStack.language) lines.push(`- 语言: ${techStack.language}`);
    if (techStack.build_tool) lines.push(`- 构建: ${techStack.build_tool}`);
    if (techStack.test_framework) lines.push(`- 测试: ${techStack.test_framework}`);
    if (techStack.package_manager) lines.push(`- 包管理: ${techStack.package_manager}`);
  } else {
    lines.push('- （待补充）');
  }
  lines.push('');

  // 架构概览
  lines.push('## 架构概览');
  lines.push('');
  lines.push(extractArchOverview(designContent));
  lines.push('');

  // 目录结构
  lines.push('## 目录结构');
  lines.push('');
  if (outputFiles && outputFiles.length > 0) {
    lines.push('```');
    lines.push(buildCompactTree(outputFiles));
    lines.push('```');
  } else {
    lines.push('（归档后自动填充）');
  }
  lines.push('');

  // 模块速查表
  lines.push('## 模块速查表');
  lines.push('');
  lines.push('| 模块 | 职责 | 核心文件 | 域指南 |');
  lines.push('|------|------|---------|--------|');
  for (const d of domains) {
    lines.push(`| ${d.title} | — | ${d.sourcePaths} | → [domains/${d.name}.md](domains/${d.name}.md) |`);
  }
  lines.push('');

  // 跨模块约束
  lines.push('## 跨模块约束');
  lines.push('');
  const constraints = extractConstraints(codeReviewContent, repairHistory);
  lines.push(constraints || '（待补充：系统级不变量）');
  lines.push('');

  // 扩展场景导航
  lines.push('## 扩展场景导航');
  lines.push('');
  if (recipes.length > 0) {
    lines.push('| 常见任务 | 食谱 |');
    lines.push('|---------|------|');
    for (const r of recipes) {
      lines.push(`| ${r.title} | → [recipes/${r.name}.md](recipes/${r.name}.md) |`);
    }
  } else {
    lines.push('（无自动推断的食谱，建议人工补充）');
  }

  return lines.join('\n');
}

/**
 * 生成 Layer 1: 单个域指南
 */
function buildDomainGuide(domain, designContent, codeReports, codeReviewContent, repairHistory) {
  const lines = [];
  lines.push(`# ${domain.title}`);
  lines.push('');
  lines.push(`> 本域指南描述 ${domain.title} 的内部机制。修改本域代码前请先阅读。`);
  lines.push(`> 对应源码: \`${domain.sourcePaths}\``);
  lines.push('');

  // 职责与边界
  lines.push('## 职责与边界');
  lines.push('');
  const responsibilities = extractDomainResponsibilities(domain, designContent);
  lines.push(responsibilities);
  lines.push('');

  // 内部结构
  lines.push('## 内部结构');
  lines.push('');
  const structure = extractDomainStructure(domain, codeReports);
  lines.push(structure);
  lines.push('');

  // 核心数据结构
  lines.push('## 核心数据结构');
  lines.push('');
  const dataStructures = extractDomainDataStructures(domain, designContent);
  lines.push(dataStructures);
  lines.push('');

  // 关键流程
  lines.push('## 关键流程');
  lines.push('');
  const flows = extractDomainFlows(domain, designContent);
  lines.push(flows);
  lines.push('');

  // 对外接口
  lines.push('## 对外接口');
  lines.push('');
  const interfaces = extractDomainInterfaces(domain, designContent, codeReports);
  lines.push(interfaces);
  lines.push('');

  // 文件清单与影响范围
  lines.push('## 文件清单与影响范围');
  lines.push('');
  const fileList = extractDomainFiles(domain, codeReports);
  lines.push(fileList);
  lines.push('');

  // 约束与陷阱
  lines.push('## 约束与陷阱');
  lines.push('');
  const pitfalls = extractDomainPitfalls(domain, codeReviewContent, repairHistory);
  lines.push(pitfalls);

  return lines.join('\n');
}

/**
 * 生成 Layer 2: 单个操作食谱
 */
function buildRecipeContent(recipe, designContent, codeReports) {
  const lines = [];
  lines.push(`# ${recipe.title}`);
  lines.push('');
  lines.push(`> 场景: 需要${recipe.title.replace('添加新', '新增一个')}时使用`);
  lines.push('');

  // 涉及文件
  lines.push('## 涉及文件');
  lines.push('');
  lines.push('| 文件 | 操作 | 说明 |');
  lines.push('|------|------|------|');
  if (recipe.files && recipe.files.length > 0) {
    for (const f of recipe.files) {
      const op = f.isTest ? '新建' : '新建';
      lines.push(`| \`${f.path}\` | ${op} | ${f.desc || '—'} |`);
    }
  } else {
    lines.push('| （待补充） | — | — |');
  }
  lines.push('');

  // 前置条件
  lines.push('## 前置条件');
  lines.push('');
  lines.push('- 项目已完成初始化并可正常构建');
  lines.push('');

  // 步骤
  lines.push('## 步骤');
  lines.push('');
  if (recipe.files && recipe.files.length > 0) {
    recipe.files.forEach((f, i) => {
      const ref = recipe.reference ? `参考: \`${recipe.reference}\`` : '';
      lines.push(`${i + 1}. 创建 \`${f.path}\` ${ref}`);
    });
    lines.push(`${recipe.files.length + 1}. ⚠️ 确认相关注册/导入已添加`);
  } else {
    lines.push('1. （待补充具体操作步骤）');
  }
  lines.push('');

  // 验证
  lines.push('## 验证');
  lines.push('');
  lines.push('```bash');
  lines.push('# 运行测试确认新增功能正常');
  lines.push('npm test  # 或对应的测试命令');
  lines.push('```');

  return lines.join('\n');
}

/**
 * 生成 kb-verify.sh（基于实际域指南内容定制）
 */
export function generateKBVerify(domains) {
  // 生成域→源码路径映射
  const mappings = domains.map(d =>
    `    "${d.name}:${d.sourcePaths}"`
  ).join('\n');

  return `#!/bin/bash
# kb-verify.sh — 知识库新鲜度与覆盖检查
# 随项目交付，供后续维护时检测知识库是否需要同步更新
# 用法: bash docs/kb/kb-verify.sh [--strict]
# 退出码: 0=全部通过, 1=有问题需处理

set -uo pipefail

STRICT=false
[ "\${1:-}" = "--strict" ] && STRICT=true

KB_DIR="docs/kb"
ERRORS=0
WARNS=0

echo "=== 知识库新鲜度检查 ==="
echo ""

# 域→源码路径映射
DOMAIN_MAP=(
${mappings}
)

# 1. 结构完整性
echo "--- 结构完整性 ---"
[ ! -f "$KB_DIR/system-map.md" ] && echo "FAIL: system-map.md 缺失" && ERRORS=$((ERRORS+1))
[ ! -d "$KB_DIR/domains" ] && echo "FAIL: domains/ 缺失" && ERRORS=$((ERRORS+1))
echo ""

# 2. 行数约束
echo "--- 行数约束 ---"
for f in "$KB_DIR/system-map.md"; do
    [ -f "$f" ] || continue
    lines=$(wc -l < "$f" | tr -d ' ')
    [ "$lines" -gt 150 ] && echo "WARN: system-map.md 超限 ($lines/150)" && WARNS=$((WARNS+1))
done
for f in "$KB_DIR/domains"/*.md; do
    [ -f "$f" ] || continue
    lines=$(wc -l < "$f" | tr -d ' ')
    [ "$lines" -gt 400 ] && echo "WARN: $(basename "$f") 超限 ($lines/400)" && WARNS=$((WARNS+1))
done
for f in "$KB_DIR/recipes"/*.md; do
    [ -f "$f" ] || continue
    lines=$(wc -l < "$f" | tr -d ' ')
    [ "$lines" -gt 80 ] && echo "WARN: $(basename "$f") 超限 ($lines/80)" && WARNS=$((WARNS+1))
done
echo ""

# 3. 新鲜度检测
echo "--- 新鲜度检测 ---"
for mapping in "\${DOMAIN_MAP[@]}"; do
    domain="\${mapping%%:*}"
    src_path="\${mapping#*:}"
    guide="$KB_DIR/domains/$domain.md"
    [ ! -f "$guide" ] && continue
    [ ! -e "$src_path" ] && continue
    if [ "$src_path" -nt "$guide" ]; then
        echo "WARN: $domain.md 可能过时（$src_path 更新）"
        WARNS=$((WARNS+1))
    fi
done
echo ""

# 汇总
echo "════════════════════════════════════"
[ "$STRICT" = true ] && [ "$WARNS" -gt 0 ] && ERRORS=$((ERRORS+WARNS))
if [ $ERRORS -gt 0 ]; then
    echo "=== 知识库检查: $ERRORS 项需处理 ==="
    exit 1
else
    echo "=== 知识库检查: 通过 (WARN: $WARNS) ==="
    exit 0
fi
`;
}

/**
 * 校验分层知识库完整性
 *
 * @param {Object} kbFiles - { systemMap, domains: string[], recipes: string[] } 文件路径列表
 * @param {Object} [contents] - { systemMap: string, domains: {name: string}[], recipes: {name: string}[] }
 * @param {Object} [options] - { hasSourceCode: boolean }
 * @returns {{ valid: boolean, errors: string[] }}
 */
export function validateKBIntegrity(kbFiles, contents, options) {
  const errors = [];

  // system-map 存在
  if (!kbFiles.systemMap) {
    errors.push('缺少 system-map.md');
  }

  // 至少一个域指南
  if (!kbFiles.domains || kbFiles.domains.length === 0) {
    errors.push('缺少域指南（domains/ 为空）');
  }

  // 有源代码产出时必须有食谱
  const hasSourceCode = options && options.hasSourceCode;
  if (hasSourceCode && (!kbFiles.recipes || kbFiles.recipes.length === 0)) {
    errors.push('有代码产出但缺少操作食谱（recipes/ 为空）');
  }

  // 行数校验
  if (contents) {
    if (contents.systemMap && countLines(contents.systemMap) > 150) {
      errors.push(`system-map.md 超出 150 行限制 (${countLines(contents.systemMap)} 行)`);
    }
    if (contents.domains) {
      for (const d of contents.domains) {
        if (d.content && countLines(d.content) > 400) {
          errors.push(`域指南 ${d.name}.md 超出 400 行限制 (${countLines(d.content)} 行)`);
        }
      }
    }
    if (contents.recipes) {
      for (const r of contents.recipes) {
        if (r.content && countLines(r.content) > 80) {
          errors.push(`食谱 ${r.name}.md 超出 80 行限制 (${countLines(r.content)} 行)`);
        }
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

/**
 * 获取知识库统计信息
 *
 * @param {KnowledgeBase} kb
 * @returns {{ systemMapLines: number, domainCount: number, recipeCount: number, totalLines: number }}
 */
export function getKBStats(kb) {
  const systemMapLines = countLines(kb.systemMap);
  const domainLines = kb.domains.reduce((sum, d) => sum + countLines(d.content), 0);
  const recipeLines = kb.recipes.reduce((sum, r) => sum + countLines(r.content), 0);

  return {
    systemMapLines,
    domainCount: kb.domains.length,
    recipeCount: kb.recipes.length,
    totalLines: systemMapLines + domainLines + recipeLines,
  };
}

// === 内部辅助函数 ===

/** 按标题分割 markdown */
function splitByHeadings(content, level) {
  const prefix = '#'.repeat(level);
  const regex = new RegExp(`^${prefix}\\s+.+`, 'gm');
  const headings = [];
  let match;
  while ((match = regex.exec(content)) !== null) {
    headings.push({ index: match.index, heading: match[0] });
  }
  return headings.map((h, i) => {
    const start = h.index + h.heading.length;
    const end = i < headings.length - 1 ? headings[i + 1].index : content.length;
    return { heading: h.heading, body: content.slice(start, end).trim() };
  });
}

/** 中文/英文标题转 kebab-case */
function toKebabCase(str) {
  return str
    .replace(/[\s/\\]+/g, '-')
    .replace(/[^a-zA-Z0-9一-鿿-]/g, '')
    .replace(/([A-Z])/g, '-$1')
    .toLowerCase()
    .replace(/^-+|-+$/g, '')
    .replace(/-{2,}/g, '-')
    .slice(0, 40) || 'unnamed';
}

/** 计算行数 */
function countLines(content) {
  if (!content) return 0;
  return content.split('\n').length;
}

/** 从需求规格提取项目定位 */
function extractProjectPurpose(requirementSpec, designContent) {
  if (requirementSpec) {
    const bgMatch = requirementSpec.match(/(?:项目背景|概述|Background)[\s\S]*?\n([\s\S]*?)(?=\n##|\n---)/i);
    if (bgMatch) return bgMatch[1].trim().split('\n').slice(0, 4).join('\n');
  }
  if (designContent) {
    const first = designContent.split(/\n##/)[0].replace(/^#.*\n/, '').trim();
    if (first.length > 20) return first.split('\n').slice(0, 4).join('\n');
  }
  return '（待补充：项目做什么、服务谁、核心价值）';
}

/** 从 design.md 提取架构概览 */
function extractArchOverview(designContent) {
  if (!designContent) return '（待补充）';
  const sections = splitByHeadings(designContent, 2);
  const archSection = sections.find(s => /架构|Architecture/i.test(s.heading));
  if (archSection) {
    // 取前30行
    return archSection.body.split('\n').slice(0, 30).join('\n');
  }
  return '（待补充：系统分层与数据流）';
}

/** 构建紧凑目录树（仅前两层 + 关键深层文件） */
function buildCompactTree(files) {
  const topDirs = new Map();
  for (const f of files) {
    const parts = f.split('/');
    const top = parts[0];
    if (!topDirs.has(top)) topDirs.set(top, []);
    if (parts.length > 1) topDirs.get(top).push(parts.slice(1).join('/'));
  }

  const lines = [];
  for (const [dir, children] of topDirs) {
    if (children.length === 0) {
      lines.push(dir);
    } else {
      lines.push(`${dir}/`);
      const subDirs = new Set(children.map(c => c.split('/')[0]));
      const shown = [...subDirs].slice(0, 8);
      for (const sub of shown) {
        const isDir = children.some(c => c.startsWith(sub + '/'));
        lines.push(`  ${isDir ? sub + '/' : sub}`);
      }
      if (subDirs.size > 8) lines.push(`  ... (${subDirs.size - 8} more)`);
    }
  }
  return lines.join('\n');
}

/** 从 code-review 和 repair-history 提取跨模块约束 */
function extractConstraints(codeReviewContent, repairHistory) {
  const items = [];
  if (codeReviewContent) {
    const musts = codeReviewContent.match(/.*(?:必须|不得|禁止|务必|always|never|must).*/gi) || [];
    for (const m of musts.slice(0, 5)) {
      const clean = m.replace(/^[-*|]\s*/, '').trim();
      if (clean.length > 10 && clean.length < 150) items.push(`- ${clean}`);
    }
  }
  if (repairHistory && repairHistory.length > 0) {
    for (const r of repairHistory.slice(0, 3)) {
      if (r.rootCause || r.root_cause_hypothesis) {
        items.push(`- ⚠️ ${r.rootCause || r.root_cause_hypothesis}（已修复）`);
      }
    }
  }
  return items.length > 0 ? items.join('\n') : null;
}

/** 从 design.md 提取域的职责描述 */
function extractDomainResponsibilities(domain, designContent) {
  if (!designContent) return '（待补充）';
  const sections = splitByHeadings(designContent, 2);
  for (const s of sections) {
    if (s.heading.includes(domain.title) || toKebabCase(s.heading).includes(domain.name)) {
      const firstPara = s.body.split('\n\n')[0];
      if (firstPara && firstPara.length > 10) return firstPara;
    }
  }
  return `${domain.title} 模块的核心职责（待补充）`;
}

/** 从 code reports 提取域的内部结构 */
function extractDomainStructure(domain, codeReports) {
  if (!codeReports || codeReports.length === 0) return '（待补充）';
  const files = [];
  for (const report of codeReports) {
    const matches = report.match(/\|\s*([^\|]*\.\w+)\s*\|/g) || [];
    for (const m of matches) {
      const path = m.replace(/\|/g, '').trim();
      if (path.includes(domain.name) || path.includes(domain.sourcePaths.replace('src/', ''))) {
        files.push(path);
      }
    }
  }
  if (files.length > 0) {
    return '| 文件 | 说明 |\n|------|------|\n' + files.slice(0, 10).map(f => `| \`${f}\` | — |`).join('\n');
  }
  return '（待补充：子模块列表）';
}

/** 从 design.md 提取域相关的数据结构 */
function extractDomainDataStructures(domain, designContent) {
  if (!designContent) return '（待补充）';
  // 查找域相关段落中的代码块或类型定义
  const sections = splitByHeadings(designContent, 3);
  for (const s of sections) {
    if (/数据|模型|类型|Schema|Entity/i.test(s.heading) &&
        (s.body.includes(domain.title) || s.body.includes(domain.name))) {
      return s.body.slice(0, 600);
    }
  }
  return '（待补充：核心类型定义）';
}

/** 从 design.md 提取域的关键流程 */
function extractDomainFlows(domain, designContent) {
  if (!designContent) return '（待补充）';
  const sections = splitByHeadings(designContent, 2);
  for (const s of sections) {
    if ((s.heading.includes(domain.title) || toKebabCase(s.heading).includes(domain.name))) {
      // 查找代码块（流程图/时序图）
      const diagrams = s.body.match(/```[\s\S]*?```/g) || [];
      if (diagrams.length > 0) return diagrams[0];
      // 查找有序步骤
      const steps = s.body.match(/^\d+\..+$/gm) || [];
      if (steps.length > 0) return steps.slice(0, 8).join('\n');
    }
  }
  return '（待补充：正常/异常路径流程）';
}

/** 从 design.md 和 code reports 提取域的对外接口 */
function extractDomainInterfaces(domain, designContent, codeReports) {
  const interfaces = [];
  if (designContent) {
    const apis = designContent.match(/(?:GET|POST|PUT|DELETE|PATCH)\s+\/[\w/:.-]+/gi) || [];
    for (const api of apis) {
      if (interfaces.length < 10) interfaces.push(api);
    }
  }
  if (interfaces.length > 0) {
    return '| 接口 | 方法 |\n|------|------|\n' + interfaces.map(api => {
      const [method, path] = api.split(/\s+/);
      return `| ${path} | ${method} |`;
    }).join('\n');
  }
  return '（待补充：对外暴露的接口签名）';
}

/** 从 code reports 提取域的文件清单 */
function extractDomainFiles(domain, codeReports) {
  if (!codeReports || codeReports.length === 0) return '（待补充）';
  const files = extractAllFilesFromReports(codeReports);
  const domainFiles = files.filter(f =>
    f.includes(domain.name) || f.includes(domain.sourcePaths.replace('src/', '').replace('/', ''))
  );
  if (domainFiles.length > 0) {
    return '| 文件 | 职责 | 改动时需同步检查 |\n|------|------|----------------|\n' +
      domainFiles.slice(0, 15).map(f => `| \`${f}\` | — | — |`).join('\n');
  }
  return '| 文件 | 职责 | 改动时需同步检查 |\n|------|------|----------------|\n| （待补充） | — | — |';
}

/** 从 code review 和 repair history 提取域的约束 */
function extractDomainPitfalls(domain, codeReviewContent, repairHistory) {
  const items = [];
  if (repairHistory && repairHistory.length > 0) {
    for (const r of repairHistory) {
      if (r.rootCause || r.root_cause_hypothesis) {
        items.push(`- ⚠️ ${r.rootCause || r.root_cause_hypothesis}`);
      }
    }
  }
  if (items.length > 0) {
    return '**已知陷阱（来自修复历史）:**\n' + items.slice(0, 5).join('\n');
  }
  return '（待补充：不变量和常见误区）';
}

/** 合并已有域指南和新内容 */
function mergeDomainGuide(existing, newContent, reqId) {
  // 保留已有的"约束与陷阱"段（可能被人工完善），替换其他段
  const existingPitfalls = extractSectionContent(existing, '## 约束与陷阱');
  if (existingPitfalls && existingPitfalls.length > 30) {
    // 用已有的约束段替换新生成的
    const pitfallSection = extractSectionContent(newContent, '## 约束与陷阱');
    if (pitfallSection) {
      return newContent.replace(pitfallSection, existingPitfalls);
    }
  }
  return newContent;
}

/** 提取指定标题到下一个同级标题之间的内容 */
function extractSectionContent(content, heading) {
  const idx = content.indexOf(heading);
  if (idx === -1) return null;
  const afterHeading = idx + heading.length;
  const nextHeading = content.indexOf('\n## ', afterHeading);
  return nextHeading > -1
    ? content.slice(afterHeading, nextHeading).trim()
    : content.slice(afterHeading).trim();
}

/** 从 design.md 的 Tasks 表提取文件模式 */
function extractTaskFilePatterns(designContent) {
  const patterns = [];
  const taskRows = designContent.match(/\|\s*Task-\d+\s*\|[\s\S]*?\|/g) || [];
  for (const row of taskRows) {
    const paths = row.match(/src\/[\w/.-]+/g) || [];
    const testPaths = row.match(/tests?\/[\w/.-]+/g) || [];
    const allPaths = [...paths, ...testPaths];
    if (allPaths.length > 0) {
      const dirs = [...new Set(allPaths.map(p => p.split('/')[1]))];
      patterns.push({ files: allPaths, dir: dirs[0] || '' });
    }
  }
  return patterns;
}

/** 按文件路径模式归组，推断食谱类型 */
function groupByFilePattern(taskPatterns) {
  const groups = {};
  const labelMap = {
    routes: { label: '接口', pattern: /route|controller|endpoint/i },
    components: { label: '组件', pattern: /component|page|view/i },
    services: { label: '服务', pattern: /service|worker|queue|job/i },
    models: { label: '模型', pattern: /model|entity|schema/i },
    middleware: { label: '中间件', pattern: /middleware|plugin|hook/i },
  };

  for (const task of taskPatterns) {
    for (const [key, { label, pattern }] of Object.entries(labelMap)) {
      if (task.files.some(f => pattern.test(f))) {
        if (!groups[key]) groups[key] = { label, files: [], referenceTask: '' };
        for (const f of task.files) {
          if (!groups[key].files.some(existing => existing.path === f)) {
            groups[key].files.push({ path: f, desc: '', isTest: /test/i.test(f) });
          }
        }
        break;
      }
    }
  }
  return groups;
}

/** 从 code reports 提取所有文件路径 */
function extractAllFilesFromReports(codeReports) {
  const files = [];
  for (const report of codeReports) {
    const matches = report.match(/(?:src|tests?|lib)\/[\w/.-]+/gi) || [];
    files.push(...matches);
  }
  return [...new Set(files)];
}

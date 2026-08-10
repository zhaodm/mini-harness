#!/bin/bash
# scope-scan.sh — 全仓库关键词影响搜索
# 用法: bash tools/mh-dev/scripts/scope-scan.sh "关键词1" "关键词2" ...
# 输出: stdout 匹配文件列表 + 行号 + 上下文；同时写入 .mh-dev/scope-result.md
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
cd "$ROOT_DIR"

[[ $# -gt 0 ]] || { echo "Usage: $0 <keyword1> [keyword2...]" >&2; exit 2; }

OUTPUT="$RUNTIME/scope-result.md"
mkdir -p "$RUNTIME"

# 搜索范围：排除 .mh-dev 运行态、node_modules、.git、deliverables
SEARCH_DIRS="agents skills scripts workflows templates .claude docs tests tools/mh-dev/agents tools/mh-dev/scripts tools/mh-dev/templates tools/mh-dev/tests"
EXCLUDE_DIR="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=deliverables --exclude-dir=.mh-dev"

# 构建关键词正则
PATTERN=""
for kw in "$@"; do
  if [[ -n "$PATTERN" ]]; then PATTERN="${PATTERN}\|${kw}"; else PATTERN="${kw}"; fi
done

echo "# 影响范围扫描结果" > "$OUTPUT"
echo "" >> "$OUTPUT"
echo "**关键词:** $*" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "## 匹配文件" >> "$OUTPUT"
echo "" >> "$OUTPUT"

total_matches=0
for dir in $SEARCH_DIRS; do
  [[ -d "$dir" ]] || continue
  matches=$(grep -rn $EXCLUDE_DIR --include='*.md' --include='*.sh' --include='*.js' --include='*.json' --include='*.py' "$PATTERN" "$dir" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "### $dir/" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    echo "$matches" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    count=$(echo "$matches" | wc -l | tr -d ' ')
    total_matches=$((total_matches + count))
    echo "$matches"
  fi
done

echo "" >> "$OUTPUT"
echo "## 汇总" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "- 总匹配数: $total_matches" >> "$OUTPUT"
echo "- 搜索目录: $SEARCH_DIRS" >> "$OUTPUT"

echo "PASS: scope-scan found $total_matches match(es); report at ${OUTPUT#$ROOT_DIR/}"

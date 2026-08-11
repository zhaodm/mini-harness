#!/bin/bash
# kb-verify.sh — 框架知识库新鲜度与覆盖检查
# 供后续维护时检测知识库是否需要同步更新
# 用法: bash docs/kb/kb-verify.sh [--strict]
# 退出码: 0=全部通过, 1=有问题需处理

set -uo pipefail

STRICT=false
[ "${1:-}" = "--strict" ] && STRICT=true

KB_DIR="docs/kb"
ERRORS=0
WARNS=0

echo "=== 框架知识库新鲜度检查 ==="
echo ""

# ─────────────────────────────────────────────
# 1. 结构完整性：必要文件存在
# ─────────────────────────────────────────────
echo "--- 结构完整性 ---"

if [ ! -f "$KB_DIR/system-map.md" ]; then
    echo "FAIL: system-map.md 不存在"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: system-map.md 存在"
fi

if [ ! -d "$KB_DIR/domains" ] || [ -z "$(ls -A "$KB_DIR/domains" 2>/dev/null)" ]; then
    echo "FAIL: domains/ 目录为空或不存在"
    ERRORS=$((ERRORS + 1))
else
    domain_count=$(find "$KB_DIR/domains" -name "*.md" | wc -l | tr -d ' ')
    echo "PASS: domains/ 含 $domain_count 份域指南"
fi

# 检查 6 个必需的域指南
required_domains="roles skills workflow guards templates mh-dev"
for domain in $required_domains; do
    if [ ! -f "$KB_DIR/domains/${domain}.md" ]; then
        echo "FAIL: domains/${domain}.md 不存在"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ ! -f "$KB_DIR/README.md" ]; then
    echo "FAIL: README.md 不存在"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: README.md 存在"
fi

if [ ! -f "$KB_DIR/kb-verify.sh" ]; then
    echo "FAIL: kb-verify.sh 不存在"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: kb-verify.sh 存在"
fi

echo ""

# ─────────────────────────────────────────────
# 2. 行数约束检查
# ─────────────────────────────────────────────
echo "--- 行数约束 ---"

check_line_limit() {
    local file="$1"
    local limit="$2"
    local label="$3"
    if [ -f "$file" ]; then
        local lines
        lines=$(wc -l < "$file" | tr -d ' ')
        if [ "$lines" -gt "$limit" ]; then
            echo "WARN: $label ($file) 超出行数限制: $lines/$limit 行"
            WARNS=$((WARNS + 1))
        fi
    fi
}

check_line_limit "$KB_DIR/system-map.md" 150 "Layer 0"

for domain_file in "$KB_DIR/domains"/*.md; do
    [ -f "$domain_file" ] || continue
    check_line_limit "$domain_file" 400 "域指南 $(basename "$domain_file")"
done

for recipe_file in "$KB_DIR/recipes"/*.md; do
    [ -f "$recipe_file" ] || continue
    check_line_limit "$recipe_file" 80 "食谱 $(basename "$recipe_file")"
done

echo ""

# ─────────────────────────────────────────────
# 3. 文件路径有效性：域指南中引用的源码路径是否存在
# ─────────────────────────────────────────────
echo "--- 路径有效性 ---"

path_errors=0
for domain_file in "$KB_DIR/domains"/*.md; do
    [ -f "$domain_file" ] || continue
    # 提取反引号包裹的文件路径
    while IFS= read -r ref_path; do
        ref_path=$(echo "$ref_path" | sed 's/^[| ]*//' | sed 's/[| ]*$//' | tr -d '`')
        [ -z "$ref_path" ] && continue
        # 跳过占位符和模式
        [[ "$ref_path" == *"{"* ]] && continue
        [[ "$ref_path" == *"*"* ]] && continue
        # 跳过非文件路径（以 # 或 > 开头的注释）
        [[ "$ref_path" == \#* ]] && continue
        [[ "$ref_path" == \>* ]] && continue
        # 检查文件是否存在（相对于项目根）
        if [ ! -e "$ref_path" ] && [ ! -e "src/$ref_path" ]; then
            echo "WARN: $(basename "$domain_file") 引用的路径不存在: $ref_path"
            path_errors=$((path_errors + 1))
        fi
    done < <(grep -oE '`[a-zA-Z][a-zA-Z0-9_./-]+\.[a-z]+`' "$domain_file" 2>/dev/null | tr -d '`' || true)
done

if [ "$path_errors" -eq 0 ]; then
    echo "PASS: 所有引用路径有效"
else
    WARNS=$((WARNS + path_errors))
fi

echo ""

# ─────────────────────────────────────────────
# 4. 新鲜度检测：域指南是否比对应源码更旧
# ─────────────────────────────────────────────
echo "--- 新鲜度检测 ---"

# 域→源码路径映射
get_source_path() {
    case "$1" in
        roles.md)     echo "agents/" ;;
        skills.md)    echo "skills/" ;;
        workflow.md)  echo "workflows/" ;;
        guards.md)    echo "scripts/" ;;
        templates.md) echo "templates/" ;;
        mh-dev.md)    echo "tools/mh-dev/" ;;
        *)            echo "" ;;
    esac
}

stale_count=0
for domain_file in "$KB_DIR/domains"/*.md; do
    [ -f "$domain_file" ] || continue
    domain_name=$(basename "$domain_file")
    source_path=$(get_source_path "$domain_name")

    [ -z "$source_path" ] && continue

    if [ -e "$source_path" ]; then
        # 比较域指南与源码目录的最新修改时间
        # 如果源码目录中有比域指南更新的文件，则 WARN
        # 排除运行态目录（.mh-dev/、.mh-dev-archive/）和测试目录（tests/）：
        # 运行态文件在开发流程中被频繁更新，测试文件是验证产物而非被描述的模块源码，
        # 它们的时间戳不代表源码语义变化
        newest_source=$(find "$source_path" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.js' -o -name '*.json' -o -name '*.css' -o -name '*.html' \) -not -path '*/.mh-dev/*' -not -path '*/.mh-dev-archive/*' -not -path '*/tests/*' -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1)
        if [ -n "$newest_source" ]; then
            source_mtime=$(echo "$newest_source" | awk '{print $1}')
            guide_mtime=$(stat -f '%m' "$domain_file" 2>/dev/null || echo 0)
            if [ "$source_mtime" -gt "$guide_mtime" ]; then
                echo "WARN: $domain_name 可能过时（源码 $source_path 更新）"
                stale_count=$((stale_count + 1))
            fi
        fi
    fi
done

if [ "$stale_count" -eq 0 ]; then
    echo "PASS: 域指南新鲜度正常"
else
    WARNS=$((WARNS + stale_count))
fi

echo ""

# ─────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────
echo "════════════════════════════════════"

# --strict 模式下 WARN 升级为 ERROR
if [ "$STRICT" = true ] && [ "$WARNS" -gt 0 ]; then
    ERRORS=$((ERRORS + WARNS))
    echo "=== [strict] WARN 升级为 ERROR ==="
fi

if [ $ERRORS -gt 0 ]; then
    echo "=== 知识库检查: $ERRORS 项需处理 ==="
    exit 1
elif [ $WARNS -gt 0 ]; then
    echo "=== 知识库检查: 通过, $WARNS 项建议更新 ==="
    exit 0
else
    echo "=== 知识库检查: 全部通过 ==="
    exit 0
fi

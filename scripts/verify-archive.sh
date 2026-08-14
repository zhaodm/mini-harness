#!/bin/bash
# verify-archive.sh - 归档质量硬校验脚本
# 通用检查 + 项目专属检查（从 .archiveignore 读取）
# 退出码: 0=全部通过, 1=存在失败项
# 用法: ./scripts/verify-archive.sh [project]
#
# CR-010: 取消 ARC-2（重复检测）、ARC-3（更新方向检测）、ARC-5（REQ-ID 隔离）
# 产出即归档：无根 output/ 二份存放

set -euo pipefail

DELIVERABLES_DIR="deliverables"
ERRORS=0
WARNS=0

project="${1:-}"

# 自动从全局指针读取项目标识符（CR-018: req_id → project）
if [ -z "$project" ]; then
    project=$(grep "^project:" "$DELIVERABLES_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
fi

if [ -z "$project" ]; then
    echo "WARN: 未指定项目标识符且无法从 .state.md 读取，跳过归档检查"
    exit 0
fi

REQ_DIR="$DELIVERABLES_DIR/$project"
IGNORE_FILE="$REQ_DIR/.archiveignore"

echo "=== 归档质量检查: $project ==="
echo ""

# ─────────────────────────────────────────────
# ARC-1: 项目专属禁止项检查（从 .archiveignore 读取）
# 检查 deliverables/{project}/ 产品区
# ─────────────────────────────────────────────
check_archiveignore() {
    echo "--- ARC-1: 项目专属禁止项 ---"

    if [ ! -f "$IGNORE_FILE" ]; then
        echo "FAIL: .archiveignore 不存在（clarify 阶段应已生成）"
        echo "      路径: $IGNORE_FILE"
        ERRORS=$((ERRORS + 1))
        echo ""
        return
    fi

    local violations=0
    while IFS= read -r pattern; do
        # 跳过注释和空行
        [[ "$pattern" =~ ^[[:space:]]*#.*$ || -z "${pattern// }" ]] && continue

        # 支持目录模式（以 / 结尾）和文件模式
        local matches=""
        if [[ "$pattern" == */ ]]; then
            # 目录模式：用 -path 匹配
            matches=$(find "$REQ_DIR" -type d -path "*/${pattern%/}" -not -path "*/.engine/*" 2>/dev/null | head -5)
        else
            # 文件/通配模式：同时用 -name 和 -path
            matches=$(find "$REQ_DIR" -name "$pattern" -not -path "*/.engine/*" -not -path "*/node_modules/*" 2>/dev/null | head -5)
            if [ -z "$matches" ]; then
                matches=$(find "$REQ_DIR" -path "*/$pattern" -not -path "*/.engine/*" -not -path "*/node_modules/*" 2>/dev/null | head -5)
            fi
        fi

        if [ -n "$matches" ]; then
            echo "FAIL: 产品区包含禁止项: $pattern"
            echo "$matches" | head -3 | while read -r f; do
                echo "  - $f"
            done
            violations=$((violations + 1))
        fi
    done < "$IGNORE_FILE"

    if [ "$violations" -eq 0 ]; then
        echo "PASS: 无 .archiveignore 中的禁止项"
    else
        ERRORS=$((ERRORS + violations))
    fi
    echo ""
}

# ─────────────────────────────────────────────
# ARC-4: 归档非空检查（产品区，排除 .engine/）
# ─────────────────────────────────────────────
check_output_nonempty() {
    echo "--- ARC-4: 归档目录非空 ---"

    if [ ! -d "$REQ_DIR" ]; then
        echo "FAIL: deliverables/$project/ 目录不存在"
        ERRORS=$((ERRORS + 1))
    else
        local file_count
        file_count=$(find "$REQ_DIR" -type f -not -path "*/.engine/*" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$file_count" -eq 0 ]; then
            echo "FAIL: 产品区为空（排除 .engine/）"
            ERRORS=$((ERRORS + 1))
        else
            echo "PASS: 产品区含 $file_count 个文件"
        fi
    fi
    echo ""
}

# ─────────────────────────────────────────────
# ARC-6: 分层知识库校验
# 仅当 deliverables/{project}/docs/kb/ 已存在时校验（用户主动请求生成才会存在）
# ─────────────────────────────────────────────
check_knowledge_base() {
    echo "--- ARC-6: 分层知识库校验 ---"

    local kb_dir="$REQ_DIR/docs/kb"

    # 用户未请求生成知识库 → 跳过
    if [ ! -d "$kb_dir" ]; then
        echo "INFO: docs/kb/ 不存在（用户未请求生成知识库），跳过"
        echo ""
        return
    fi

    # 目录存在性
    if [ ! -d "$kb_dir" ]; then
        echo "FAIL: docs/kb/ 目录不存在"
        ERRORS=$((ERRORS + 1))
        echo ""
        return
    fi

    # Layer 0: system-map.md 存在且非占位符
    if [ ! -f "$kb_dir/system-map.md" ]; then
        echo "FAIL: system-map.md 不存在"
        ERRORS=$((ERRORS + 1))
    elif grep -q "{一句话定义" "$kb_dir/system-map.md" 2>/dev/null; then
        echo "FAIL: system-map.md 仍为模板占位符"
        ERRORS=$((ERRORS + 1))
    else
        local sm_lines
        sm_lines=$(wc -l < "$kb_dir/system-map.md" | tr -d ' ')
        if [ "$sm_lines" -gt 150 ]; then
            echo "WARN: system-map.md 超出 150 行限制 ($sm_lines 行)"
            WARNS=$((WARNS + 1))
        else
            echo "PASS: system-map.md ($sm_lines 行)"
        fi
    fi

    # Layer 1: domains/ 至少一个域指南
    if [ ! -d "$kb_dir/domains" ] || [ -z "$(ls -A "$kb_dir/domains" 2>/dev/null)" ]; then
        echo "FAIL: domains/ 目录为空或不存在"
        ERRORS=$((ERRORS + 1))
    else
        local domain_count
        domain_count=$(find "$kb_dir/domains" -name "*.md" | wc -l | tr -d ' ')
        echo "PASS: domains/ 含 $domain_count 份域指南"

        # 行数检查
        for df in "$kb_dir/domains"/*.md; do
            [ -f "$df" ] || continue
            local dl
            dl=$(wc -l < "$df" | tr -d ' ')
            if [ "$dl" -gt 400 ]; then
                echo "WARN: $(basename "$df") 超出 400 行限制 ($dl 行)"
                WARNS=$((WARNS + 1))
            fi
        done
    fi

    # Layer 2: recipes/（有源代码产出时建议提供）
    if [ -d "$REQ_DIR/src" ]; then
        if [ ! -d "$kb_dir/recipes" ] || [ -z "$(ls -A "$kb_dir/recipes" 2>/dev/null)" ]; then
            echo "WARN: recipes/ 为空（有代码产出建议提供操作食谱）"
            WARNS=$((WARNS + 1))
        else
            local recipe_count
            recipe_count=$(find "$kb_dir/recipes" -name "*.md" | wc -l | tr -d ' ')
            echo "PASS: recipes/ 含 $recipe_count 份食谱"
        fi
    fi

    # kb-verify.sh 存在
    if [ ! -f "$kb_dir/kb-verify.sh" ]; then
        echo "WARN: kb-verify.sh 不存在（建议交付新鲜度检查脚本）"
        WARNS=$((WARNS + 1))
    else
        echo "PASS: kb-verify.sh 已交付"
    fi

    echo ""
}

# ─────────────────────────────────────────────
# ARC-7: 目录结构合规性检查
# 产品区顶层只允许规范目录和根文件
# ─────────────────────────────────────────────
check_output_structure() {
    echo "--- ARC-7: 目录结构合规性 ---"

    if [ ! -d "$REQ_DIR" ]; then
        echo "INFO: $REQ_DIR/ 不存在，跳过结构检查"
        echo ""
        return
    fi

    # 允许的顶层目录（排除 .engine/）
    local allowed_dirs="docs src tests deploy assets reference"
    local violations=0

    # 检查顶层目录
    for entry in "$REQ_DIR"/*/; do
        [ -d "$entry" ] || continue
        local dirname
        dirname=$(basename "$entry")

        # 跳过隐藏目录（.engine/ 等）
        [[ "$dirname" == .* ]] && continue

        local found=false
        for allowed in $allowed_dirs; do
            if [ "$dirname" = "$allowed" ]; then
                found=true
                break
            fi
        done

        if [ "$found" = false ]; then
            echo "WARN: 产品区下存在非规范目录: $dirname/（应归入 docs/src/tests/deploy/assets/reference）"
            violations=$((violations + 1))
        fi
    done

    # 检查顶层散落的 .md 文件（仅 README.md 合法）
    # CR-018 R8：角色前缀（THINKER-/WORKER-/VERIFIER-/ORCHESTRATOR-）不再是豁免理由——
    # 产品区已不含角色名，它现在是违规特征。原判据把 ROLE-*.md 显式列入白名单，
    # 是「散落在根」成为框架保证结果的三处成因之一。
    for entry in "$REQ_DIR"/*.md; do
        [ -f "$entry" ] || continue
        local filename
        filename=$(basename "$entry")
        if [ "$filename" != "README.md" ]; then
            # ${filename} 必须加花括号：变量名紧邻全角字符时 bash 会把全角字符并入变量名，
            # `set -u` 下即 unbound variable 而整个检查函数中断（guards.md 已记录该陷阱）。
            # 基线同样缺花括号，但根 ROLE-*.md 被豁免使该分支在常见输入下不可达；
            # 本 CR 收紧判据后它变为主路径，故一并修正。
            echo "WARN: 产品区根目录存在散落文档: ${filename}（应移入 docs/；含角色名或相位名者属 CR-018 R3 违规）"
            violations=$((violations + 1))
        fi
    done

    if [ "$violations" -eq 0 ]; then
        echo "PASS: 产品区目录结构合规"
    else
        WARNS=$((WARNS + violations))
    fi
    echo ""
}

# ─────────────────────────────────────────────
# 执行所有检查
# ─────────────────────────────────────────────
check_archiveignore
check_output_nonempty
check_knowledge_base
check_output_structure

# ─────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────
echo "════════════════════════════════════"
if [ $ERRORS -gt 0 ]; then
    echo "=== 归档检查: $ERRORS 项 FAIL, $WARNS 项 WARN ==="
    exit 1
elif [ $WARNS -gt 0 ]; then
    echo "=== 归档检查: 全部通过, $WARNS 项 WARN ==="
    exit 0
else
    echo "=== 归档检查: 全部通过 ==="
    exit 0
fi

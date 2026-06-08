#!/bin/bash
# verify-archive.sh - 归档质量硬校验脚本
# 通用检查 + 项目专属检查（从 .archiveignore 读取）
# 退出码: 0=全部通过, 1=存在失败项
# 用法: ./scripts/verify-archive.sh [REQ-ID]

set -euo pipefail

DELIVERABLES_DIR="deliverables"
OUTPUT_DIR="output"
ERRORS=0
WARNS=0

req_id="${1:-}"

# 自动从 .state.md 读取 REQ-ID
if [ -z "$req_id" ]; then
    req_id=$(grep "^req_id:" "$DELIVERABLES_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
fi

if [ -z "$req_id" ]; then
    echo "WARN: 未指定 REQ-ID 且无法从 .state.md 读取，跳过归档检查"
    exit 0
fi

REQ_DIR="$DELIVERABLES_DIR/$req_id"
IGNORE_FILE="$REQ_DIR/.archiveignore"

echo "=== 归档质量检查: $req_id ==="
echo ""

# ─────────────────────────────────────────────
# ARC-1: 项目专属禁止项检查（从 .archiveignore 读取）
# ─────────────────────────────────────────────
check_archiveignore() {
    echo "--- ARC-1: 项目专属禁止项 ---"

    if [ ! -f "$IGNORE_FILE" ]; then
        echo "INFO: .archiveignore 不存在，跳过项目专属检查"
        echo "      （建议 propose 阶段由 SA 生成此文件）"
        echo ""
        return
    fi

    local violations=0
    while IFS= read -r pattern; do
        # 跳过注释和空行
        [[ "$pattern" =~ ^[[:space:]]*#.*$ || -z "${pattern// }" ]] && continue

        if find "$OUTPUT_DIR" -name "$pattern" 2>/dev/null | grep -q .; then
            echo "FAIL: output/ 包含禁止项: $pattern"
            find "$OUTPUT_DIR" -name "$pattern" 2>/dev/null | head -3 | while read -r f; do
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
# ARC-2: 文件重复检测（通用）
# 同名文件不应同时存在于 deliverables 顶层和 output/
# ─────────────────────────────────────────────
check_file_duplication() {
    echo "--- ARC-2: 文件重复检测（单一真相源） ---"

    local duplicates=0
    # 检查 deliverables/{REQ-ID}/ 顶层的 .md 文件是否与 output/ 下重复
    for f in "$REQ_DIR"/*.md; do
        [ -f "$f" ] || continue
        local basename
        basename=$(basename "$f")

        # 排除流程管控文件（这些只在 deliverables 顶层，不会在 output）
        case "$basename" in
            .state.md|proposal.md|plan-action.md|SR*-record.md|comparison-report.md)
                continue
                ;;
        esac

        # 检查 output/ 下是否存在同名文件
        if find "$OUTPUT_DIR" -name "$basename" -not -path "*/node_modules/*" 2>/dev/null | grep -q .; then
            echo "FAIL: $basename 同时存在于 $REQ_DIR/ 和 output/（应只保留一处）"
            duplicates=$((duplicates + 1))
        fi
    done

    if [ "$duplicates" -eq 0 ]; then
        echo "PASS: 无文件重复"
    else
        ERRORS=$((ERRORS + duplicates))
    fi
    echo ""
}

# ─────────────────────────────────────────────
# ARC-3: 更新方向检测（通用）
# output/ 文件不应比 deliverables/output/ 源文件更新
# （如果 output 更新说明直接编辑了归档目录）
# ─────────────────────────────────────────────
check_update_direction() {
    echo "--- ARC-3: 更新方向检测 ---"

    if [ ! -d "$OUTPUT_DIR" ] || [ ! -d "$REQ_DIR/output" ]; then
        echo "INFO: output/ 或 $REQ_DIR/output/ 不存在，跳过方向检测"
        echo ""
        return
    fi

    local reversed=0
    # 抽样检查（避免大项目耗时过长）
    while IFS= read -r out_file; do
        local rel_path="${out_file#$OUTPUT_DIR/}"
        local src_file="$REQ_DIR/output/$rel_path"

        if [ -f "$src_file" ] && [ "$out_file" -nt "$src_file" ]; then
            echo "WARN: $out_file 比源文件更新（可能直接编辑了归档目录）"
            reversed=$((reversed + 1))
            [ "$reversed" -ge 5 ] && echo "  ... (仅显示前 5 项)" && break
        fi
    done < <(find "$OUTPUT_DIR" -type f -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -200)

    if [ "$reversed" -eq 0 ]; then
        echo "PASS: 更新方向正确（deliverables → output）"
    else
        WARNS=$((WARNS + 1))
    fi
    echo ""
}

# ─────────────────────────────────────────────
# ARC-4: 归档非空检查（通用）
# ─────────────────────────────────────────────
check_output_nonempty() {
    echo "--- ARC-4: 归档目录非空 ---"

    if [ ! -d "$OUTPUT_DIR" ]; then
        echo "FAIL: output/ 目录不存在"
        ERRORS=$((ERRORS + 1))
    elif [ -z "$(ls -A "$OUTPUT_DIR" 2>/dev/null)" ]; then
        echo "FAIL: output/ 目录为空"
        ERRORS=$((ERRORS + 1))
    else
        local file_count
        file_count=$(find "$OUTPUT_DIR" -type f -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l | tr -d ' ')
        echo "PASS: output/ 含 $file_count 个文件"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# 执行所有检查
# ─────────────────────────────────────────────
check_archiveignore
check_file_duplication
check_update_direction
check_output_nonempty

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

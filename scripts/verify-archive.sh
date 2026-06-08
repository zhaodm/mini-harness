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
            matches=$(find "$OUTPUT_DIR" -type d -path "*/${pattern%/}" 2>/dev/null | head -5)
        else
            # 文件/通配模式：同时用 -name 和 -path
            matches=$(find "$OUTPUT_DIR" -name "$pattern" 2>/dev/null | head -5)
            if [ -z "$matches" ]; then
                matches=$(find "$OUTPUT_DIR" -path "*/$pattern" 2>/dev/null | head -5)
            fi
        fi

        if [ -n "$matches" ]; then
            echo "FAIL: output/ 包含禁止项: $pattern"
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
# ARC-5: 文档产出按 REQ-ID 目录隔离检查
# 归档的 .md 文件必须落在 {req-id}/ 子目录下
# ─────────────────────────────────────────────
check_reqid_isolation() {
    echo "--- ARC-5: REQ-ID 目录隔离 ---"

    local req_lower
    req_lower=$(echo "$req_id" | tr '[:upper:]' '[:lower:]')

    # 检查 output/docs/ 下是否存在本次归档的文件未落在 req-id 子目录
    if [ ! -d "$OUTPUT_DIR/docs" ]; then
        echo "INFO: output/docs/ 不存在，跳过 REQ-ID 隔离检查"
        echo ""
        return
    fi

    # 查找 .state.md 的修改时间作为本次归档的时间基准
    local state_mtime=""
    if [ -f "$REQ_DIR/.state.md" ]; then
        state_mtime="$REQ_DIR/.state.md"
    fi

    # 检查 output/docs/ 下的 .md 文件是否在 req-id 子目录中
    local stray_docs=0
    while IFS= read -r doc_file; do
        [ -f "$doc_file" ] || continue
        # 跳过顶层通用文件（如 CHANGELOG.md, deployment-guide.md）
        local rel_path="${doc_file#$OUTPUT_DIR/docs/}"
        # 如果路径中不包含 req-id 子目录，且文件比 .state.md 新（本次归档产出）
        if [[ ! "$rel_path" =~ ${req_lower}/ ]]; then
            if [ -n "$state_mtime" ] && [ "$doc_file" -nt "$state_mtime" ]; then
                echo "FAIL: 文档未归入 ${req_lower}/ 子目录: $doc_file"
                stray_docs=$((stray_docs + 1))
            fi
        fi
    done < <(find "$OUTPUT_DIR/docs" -name "*.md" -not -path "*/node_modules/*" 2>/dev/null)

    # 检查测试报告目录
    local test_report_dirs
    test_report_dirs=$(find "$OUTPUT_DIR" -type d -name "reports" 2>/dev/null)
    for report_dir in $test_report_dirs; do
        while IFS= read -r report_file; do
            [ -f "$report_file" ] || continue
            local rel_path="${report_file#$report_dir/}"
            if [[ ! "$rel_path" =~ ${req_lower}/ ]]; then
                if [ -n "$state_mtime" ] && [ "$report_file" -nt "$state_mtime" ]; then
                    echo "FAIL: 测试报告未归入 ${req_lower}/ 子目录: $report_file"
                    stray_docs=$((stray_docs + 1))
                fi
            fi
        done < <(find "$report_dir" -name "*.md" 2>/dev/null)
    done

    if [ "$stray_docs" -eq 0 ]; then
        echo "PASS: 文档产出已按 REQ-ID 目录隔离"
    else
        ERRORS=$((ERRORS + stray_docs))
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
check_reqid_isolation

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

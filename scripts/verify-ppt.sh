#!/bin/bash
# verify-ppt.sh - PPT HTML 产出物校验脚本
# 退出码: 0=全部通过, 1=存在失败项
# 用法: ./scripts/verify-ppt.sh [A|B|C|all] [REQ-ID]

set -euo pipefail

DELIVERABLES_DIR="deliverables"
TEMPLATES_DIR="templates"
ERRORS=0

check_type="${1:-all}"
req_id="${2:-}"

if [ -z "$req_id" ]; then
    req_id=$(grep "^req_id:" "$DELIVERABLES_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
fi

if [ -z "$req_id" ]; then
    echo "WARN: 未指定 REQ-ID 且无法从 .state.md 读取"
fi

REQ_DIR="$DELIVERABLES_DIR/$req_id"

# A类检查: 文件存在性
check_a() {
    echo "=== A类检查: PPT 文件存在性 ==="

    if [ -z "$req_id" ]; then
        echo "SKIP: 无 REQ-ID"
        return
    fi

    # slide-spec.md
    if [ ! -s "$REQ_DIR/thinker/slide-spec.md" ]; then
        echo "FAIL: $REQ_DIR/thinker/slide-spec.md 缺失或为空"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS: $REQ_DIR/thinker/slide-spec.md"
    fi

    # wireframes 目录
    if [ ! -d "$REQ_DIR/thinker/wireframes" ]; then
        echo "FAIL: $REQ_DIR/thinker/wireframes/ 目录不存在"
        ERRORS=$((ERRORS + 1))
    else
        local wf_count
        wf_count=$(find "$REQ_DIR/thinker/wireframes" -name "*.html" | wc -l | tr -d ' ')
        if [ "$wf_count" -eq 0 ]; then
            echo "FAIL: $REQ_DIR/thinker/wireframes/ 无 HTML 文件"
            ERRORS=$((ERRORS + 1))
        else
            echo "PASS: $REQ_DIR/thinker/wireframes/ ($wf_count 个文件)"
        fi
    fi

    # output 目录
    if [ -d "$REQ_DIR/output" ]; then
        local out_count
        out_count=$(find "$REQ_DIR/output" -name "*.html" | wc -l | tr -d ' ')
        if [ "$out_count" -eq 0 ]; then
            echo "INFO: $REQ_DIR/output/ 无 HTML 文件（Worker 尚未实现）"
        else
            echo "PASS: $REQ_DIR/output/ ($out_count 个文件)"
        fi
    fi
}

# B类检查: HTML 合规性
check_b() {
    echo "=== B类检查: HTML 合规性 ==="

    local target_dir=""

    # 优先检查 output（最终产出），其次 wireframes，最后 templates
    if [ -n "$req_id" ] && [ -d "$REQ_DIR/output" ]; then
        local out_count
        out_count=$(find "$REQ_DIR/output" -name "*.html" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$out_count" -gt 0 ]; then
            target_dir="$REQ_DIR/output"
        fi
    fi

    if [ -z "$target_dir" ] && [ -n "$req_id" ] && [ -d "$REQ_DIR/thinker/wireframes" ]; then
        local wf_count
        wf_count=$(find "$REQ_DIR/thinker/wireframes" -name "*.html" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$wf_count" -gt 0 ]; then
            target_dir="$REQ_DIR/thinker/wireframes"
        fi
    fi

    if [ -z "$target_dir" ]; then
        target_dir="$TEMPLATES_DIR/ppt-templates/layouts"
    fi

    echo "INFO: 检查目录 $target_dir"

    local html_files
    html_files=$(find "$target_dir" -name "*.html" -not -name ".*")

    if [ -z "$html_files" ]; then
        echo "SKIP: 无 HTML 文件可检查"
        return
    fi

    while IFS= read -r f; do
        local fname
        fname=$(basename "$f")
        local file_errors=0

        # 检查 viewport meta
        if ! grep -q 'width=1920' "$f"; then
            echo "FAIL: $fname - 缺少 viewport width=1920"
            file_errors=$((file_errors + 1))
        fi

        # 检查 .slide 容器
        if ! grep -q 'class="slide' "$f"; then
            echo "FAIL: $fname - 缺少 .slide 容器"
            file_errors=$((file_errors + 1))
        fi

        # 检查 ppt-base.css 引用（仅 system 模式强制）
        local design_mode=""
        if [ -n "$req_id" ] && [ -f "$REQ_DIR/.state.md" ]; then
            design_mode=$(grep "^ppt_design_mode:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "system")
        fi
        if [ "$design_mode" != "creative" ]; then
            if ! grep -q 'ppt-base.css' "$f"; then
                echo "FAIL: $fname - 未引用 ppt-base.css"
                file_errors=$((file_errors + 1))
            fi
        fi

        # 检查字号底线（< 18px 的 font-size 视为违规）
        local small_fonts
        small_fonts=$(grep -oP 'font-size:\s*\K\d+(?=px)' "$f" 2>/dev/null | awk '$1 < 18' || true)
        if [ -n "$small_fonts" ]; then
            echo "FAIL: $fname - 存在小于18px的字号: $(echo $small_fonts | tr '\n' ' ')"
            file_errors=$((file_errors + 1))
        fi

        # 检查方向键导航
        if ! grep -q 'ArrowRight\|ArrowLeft\|navigator' "$f"; then
            echo "FAIL: $fname - 缺少方向键导航"
            file_errors=$((file_errors + 1))
        fi

        if [ $file_errors -eq 0 ]; then
            echo "PASS: $fname"
        else
            ERRORS=$((ERRORS + file_errors))
        fi
    done <<< "$html_files"
}

# C类检查: 内容完整性
check_c() {
    echo "=== C类检查: 内容完整性 ==="

    if [ -z "$req_id" ]; then
        echo "SKIP: 无 REQ-ID"
        return
    fi

    local target_dir="$REQ_DIR/output"
    if [ ! -d "$target_dir" ]; then
        target_dir="$REQ_DIR/thinker/wireframes"
    fi

    if [ ! -d "$target_dir" ]; then
        echo "SKIP: 无可检查目录"
        return
    fi

    local html_files
    html_files=$(find "$target_dir" -name "*.html" -not -name ".*" 2>/dev/null)

    if [ -z "$html_files" ]; then
        echo "SKIP: 无 HTML 文件"
        return
    fi

    # 检查占位符残留
    local placeholder_patterns="Lorem\|placeholder\|TODO\|FIXME\|TBD\|待填充\|占位符"

    while IFS= read -r f; do
        local fname
        fname=$(basename "$f")

        if grep -qi "$placeholder_patterns" "$f" 2>/dev/null; then
            echo "WARN: $fname - 检测到可能的占位符残留"
            grep -n -i "$placeholder_patterns" "$f" | head -3 | while read -r line; do
                echo "      $line"
            done
        else
            echo "PASS: $fname - 无占位符残留"
        fi
    done <<< "$html_files"

    # 页数一致性检查
    if [ -f "$REQ_DIR/thinker/slide-spec.md" ]; then
        local spec_pages
        spec_pages=$(grep -c "^## Slide" "$REQ_DIR/thinker/slide-spec.md" 2>/dev/null || echo "0")
        local html_pages
        html_pages=$(find "$target_dir" -name "*.html" | wc -l | tr -d ' ')

        if [ "$spec_pages" -gt 0 ] && [ "$spec_pages" -ne "$html_pages" ]; then
            echo "FAIL: 页数不一致 - slide-spec 定义 $spec_pages 页，实际 $html_pages 页"
            ERRORS=$((ERRORS + 1))
        elif [ "$spec_pages" -gt 0 ]; then
            echo "PASS: 页数一致 ($spec_pages 页)"
        fi
    fi
}

# 执行检查
case "$check_type" in
    A|a) check_a ;;
    B|b) check_b ;;
    C|c) check_c ;;
    all)
        check_a
        echo ""
        check_b
        echo ""
        check_c
        ;;
    *)
        echo "用法: $0 [A|B|C|all] [REQ-ID]"
        exit 2
        ;;
esac

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "=== PPT 校验通过 ==="
    exit 0
else
    echo "=== PPT 校验失败: $ERRORS 项错误 ==="
    exit 1
fi

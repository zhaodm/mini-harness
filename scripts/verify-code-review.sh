#!/bin/bash
# verify-code-review.sh — Code Review 报告格式硬校验
# 退出码: 0=通过, 1=失败
# 用法: ./scripts/verify-code-review.sh [REQ-ID]
#
# 检查项:
# CR-1: 报告包含 "## Code Review" 章节
# CR-2: 报告包含 "Code Review 判定: PASS/FAIL/SKIPPED"
# CR-3: FAIL 时必须有 Critical 发现行
# CR-4: SKIPPED 时必须有理由（output_type 非代码类）
# CR-5: 非 SKIPPED 时须有发现表格或无发现声明

set -euo pipefail

DELIVERABLES_DIR="deliverables"
ERRORS=0

req_id="${1:-}"
if [ -z "$req_id" ]; then
    req_id=$(grep "^req_id:" "$DELIVERABLES_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
fi

if [ -z "$req_id" ]; then
    echo "WARN: 无 REQ-ID，跳过"
    exit 0
fi

REQ_DIR="$DELIVERABLES_DIR/$req_id"

if [ ! -f "$REQ_DIR/.state.md" ]; then
    echo "WARN: $REQ_DIR/.state.md 不存在，跳过"
    exit 0
fi

output_type=$(grep "^output_type:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")

# 非代码产出类型，Code Review 可跳过
if [[ "$output_type" == "documentation" || "$output_type" == "ppt" ]]; then
    echo "INFO: output_type=$output_type, Code Review 非必需"
    exit 0
fi

echo "=== Code Review 报告校验: $req_id ==="

# 查找 TE 报告
REPORT=""
for r in "$REQ_DIR"/te/final-test-report.md "$REQ_DIR"/te/temp-test-report.md; do
    [ -f "$r" ] && REPORT="$r" && break
done

if [ -z "$REPORT" ]; then
    echo "SKIP: 无 TE 报告文件"
    exit 0
fi

# CR-1: 必须包含 Code Review 章节
if ! grep -q "## Code Review" "$REPORT" 2>/dev/null; then
    echo "FAIL [CR-1]: 报告缺少 '## Code Review' 章节"
    ERRORS=$((ERRORS + 1))
fi

# CR-2: 必须包含结论
if ! grep -qiE "Code Review 判定:[[:space:]]*(PASS|FAIL|SKIPPED)" "$REPORT" 2>/dev/null; then
    echo "FAIL [CR-2]: 缺少 'Code Review 判定: PASS/FAIL/SKIPPED'"
    ERRORS=$((ERRORS + 1))
fi

# CR-3: FAIL 时必须有 Critical
if grep -qi "Code Review 判定:.*FAIL" "$REPORT" 2>/dev/null; then
    if ! grep -qi "Critical" "$REPORT" 2>/dev/null; then
        echo "FAIL [CR-3]: Code Review FAIL 但未列出 Critical 发现"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS [CR-3]: FAIL 时有 Critical 发现"
    fi
fi

# CR-4: SKIPPED 时必须有理由
if grep -qi "Code Review 判定:.*SKIPPED" "$REPORT" 2>/dev/null; then
    if ! grep -qiE "非代码产出|output_type=|跳过.*理由" "$REPORT" 2>/dev/null; then
        echo "FAIL [CR-4]: Code Review SKIPPED 但未标注理由"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS [CR-4]: SKIPPED 有理由"
    fi
fi

# CR-5: 非 SKIPPED 时须有发现表格或无发现声明
if grep -qiE "Code Review 判定:[[:space:]]*(PASS|FAIL)" "$REPORT" 2>/dev/null; then
    has_table=false
    has_no_findings=false

    grep -qE "维度.*严重程度|严重程度.*维度|\| *# *\|.*维度" "$REPORT" 2>/dev/null && has_table=true
    grep -qiE "无.*Critical|Critical:[[:space:]]*0|无发现|未发现问题|发现: 0" "$REPORT" 2>/dev/null && has_no_findings=true

    if [ "$has_table" = false ] && [ "$has_no_findings" = false ]; then
        echo "WARN [CR-5]: Code Review 未包含发现表格或无发现声明"
    else
        echo "PASS [CR-5]: 发现部分格式合规"
    fi
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "=== Code Review 校验通过 ==="
    exit 0
else
    echo "=== Code Review 校验失败: $ERRORS 项 ==="
    exit 1
fi

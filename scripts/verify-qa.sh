#!/bin/bash
# verify-qa.sh - 内容质量硬校验脚本
# 补充 verify.sh（文件存在性）和 verify-ppt.sh（PPT结构），专注于内容质量
# 退出码: 0=全部通过, 1=存在失败项
# 用法: ./scripts/verify-qa.sh [REQ-ID]

set -euo pipefail

DELIVERABLES_DIR="deliverables"
ERRORS=0
WARNS=0

req_id="${1:-}"

# 自动从 .state.md 读取 REQ-ID
if [ -z "$req_id" ]; then
    req_id=$(grep "^req_id:" "$DELIVERABLES_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
fi

if [ -z "$req_id" ]; then
    echo "WARN: 未指定 REQ-ID 且无法从 .state.md 读取，跳过质量检查"
    exit 0
fi

REQ_DIR="$DELIVERABLES_DIR/$req_id"

# 读取字段
get_field() {
    local field="$1"
    grep "^${field}:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo ""
}

echo "=== 内容质量检查: $req_id ==="
echo ""

# ─────────────────────────────────────────────
# QA-1: Thinker 需求文档 — 禁止模糊词
# ─────────────────────────────────────────────
check_thinker_ambiguity() {
    local file="$REQ_DIR/thinker/requirement-spec.md"
    if [ ! -f "$file" ]; then return; fi

    echo "--- QA-1: 需求文档模糊词检查 ---"
    local ambiguous
    ambiguous=$(grep -n -i "适当\|合理\|尽量\|较快\|较好\|一般来说\|大概\|可能需要" "$file" 2>/dev/null || true)

    if [ -n "$ambiguous" ]; then
        echo "FAIL: requirement-spec.md 含模糊词（需求不可测试）:"
        echo "$ambiguous" | head -5
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS: 无模糊词"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-2: Worker code-report — 必须含测试结果
# ─────────────────────────────────────────────
check_worker_report() {
    local file="$REQ_DIR/worker/code-report.md"
    if [ ! -f "$file" ]; then return; fi

    echo "--- QA-2: Worker code-report 测试结果检查 ---"
    if ! grep -qi "dev-test.*PASS\|测试.*通过\|tests.*pass" "$file" 2>/dev/null; then
        echo "FAIL: code-report.md 未包含 dev-test PASS 记录"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS: 含测试通过记录"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-3: Verifier 报告 — 必须有明确结论
# ─────────────────────────────────────────────
check_verifier_conclusion() {
    echo "--- QA-3: Verifier 测试报告结论检查 ---"
    local found=0

    for report in "$REQ_DIR"/verifier/*test-report*.md "$REQ_DIR"/verifier/*report*.md; do
        [ -f "$report" ] || continue
        if grep -qi "结论.*PASS\|结论.*FAIL\|PASS\|FAIL\|通过\|不通过" "$report" 2>/dev/null; then
            echo "PASS: $(basename "$report") 含明确结论"
            found=1
        else
            echo "FAIL: $(basename "$report") 无明确结论（PASS/FAIL）"
            ERRORS=$((ERRORS + 1))
            found=1
        fi
    done

    if [ $found -eq 0 ]; then
        echo "INFO: 无测试报告，跳过"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-4: Handoff 完成报告 — 4字段非空
# ─────────────────────────────────────────────
check_handoff_completion() {
    echo "--- QA-4: Handoff 完成报告完整性 ---"
    local checked=0

    for hf in "$REQ_DIR"/handoffs/*.md; do
        [ -f "$hf" ] || continue
        # 只检查已完成的 handoff（含 status: done/completed）
        if ! grep -qi "status:.*done\|status:.*completed" "$hf" 2>/dev/null; then
            continue
        fi
        checked=$((checked + 1))

        local missing=""
        grep -qi "output_files:" "$hf" 2>/dev/null || missing="$missing output_files"
        grep -qi "summary:" "$hf" 2>/dev/null || missing="$missing summary"

        if [ -n "$missing" ]; then
            echo "WARN: $(basename "$hf") 缺少字段:$missing"
            WARNS=$((WARNS + 1))
        fi
    done

    if [ $checked -eq 0 ]; then
        echo "INFO: 无已完成的 handoff，跳过"
    else
        echo "PASS: 检查了 $checked 个完成报告"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-5: PPT slide-spec — 每页须含情绪+布局类型
# ─────────────────────────────────────────────
check_slidespec_quality() {
    if ! is_ppt_project; then return; fi
    local file="$REQ_DIR/thinker/slide-spec.md"
    if [ ! -f "$file" ]; then return; fi

    echo "--- QA-5: slide-spec 视觉设计完整性 ---"

    # 统计 Slide 条目数
    local slide_count
    slide_count=$(grep -c "^## Slide-\|^### Slide-" "$file" 2>/dev/null || echo "0")

    # 检查情绪标注
    local emotion_count
    emotion_count=$(grep -ci "情绪:\|情绪：" "$file" 2>/dev/null || echo "0")

    # 检查布局类型标注
    local layout_count
    layout_count=$(grep -ci "布局类型:\|布局类型：" "$file" 2>/dev/null || echo "0")

    if [ "$slide_count" -gt 0 ]; then
        if [ "$emotion_count" -lt "$slide_count" ]; then
            echo "FAIL: slide-spec 有 $slide_count 页但仅 $emotion_count 页标注了情绪"
            ERRORS=$((ERRORS + 1))
        else
            echo "PASS: 所有页面已标注情绪"
        fi

        if [ "$layout_count" -lt "$slide_count" ]; then
            echo "FAIL: slide-spec 有 $slide_count 页但仅 $layout_count 页标注了布局类型"
            ERRORS=$((ERRORS + 1))
        else
            echo "PASS: 所有页面已标注布局类型"
        fi
    else
        echo "INFO: slide-spec 中未检测到 Slide 条目"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-6: PPT HTML — 禁止过度内联样式
# ─────────────────────────────────────────────
check_ppt_inline_styles() {
    if ! is_ppt_project; then return; fi
    if [ ! -d "$REQ_DIR/output" ]; then return; fi

    echo "--- QA-6: PPT HTML 内联样式检查 ---"
    local bad_files=0

    for html in "$REQ_DIR"/output/*.html; do
        [ -f "$html" ] || continue
        # 统计含 3+ 属性的 style="" 行数
        local inline_count
        inline_count=$(grep -c 'style="[^"]*;[^"]*;[^"]*;' "$html" 2>/dev/null || echo "0")

        if [ "$inline_count" -gt 5 ]; then
            echo "WARN: $(basename "$html") 有 $inline_count 处重度内联样式（建议抽取CSS class）"
            bad_files=$((bad_files + 1))
        fi
    done

    if [ $bad_files -gt 0 ]; then
        echo "WARN: $bad_files 个文件内联样式过多"
        WARNS=$((WARNS + 1))
    else
        echo "PASS: 内联样式控制合理"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-7: 经验采集 — SR驳回后 lessons.md 应有记录
# ─────────────────────────────────────────────
check_lessons_after_rejection() {
    echo "--- QA-7: SR驳回后经验采集检查 ---"

    # 检查是否有 SR 驳回记录
    local has_rejection=false
    for sr in SR1 SR3; do
        local sr_status
        sr_status=$(grep -i "${sr}:" "$REQ_DIR/.state.md" 2>/dev/null | grep -i "rejected" || true)
        if [ -n "$sr_status" ]; then
            has_rejection=true
            break
        fi
    done

    if [ "$has_rejection" = true ]; then
        if [ -f "$REQ_DIR/lessons.md" ] && [ -s "$REQ_DIR/lessons.md" ]; then
            echo "PASS: 存在 SR 驳回且 lessons.md 已记录"
        else
            echo "WARN: 存在 SR 驳回但 lessons.md 为空或不存在（经验可能丢失）"
            WARNS=$((WARNS + 1))
        fi
    else
        echo "INFO: 无 SR 驳回，跳过"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-8: 返工轮次 handoff 须含用户反馈
# ─────────────────────────────────────────────
check_handoff_feedback() {
    echo "--- QA-8: 返工 handoff 用户反馈检查 ---"
    local checked=0
    local missing=0

    for hf in "$REQ_DIR"/handoffs/*-R[2-9]*.md "$REQ_DIR"/handoffs/*-R1[0-9]*.md; do
        [ -f "$hf" ] || continue
        checked=$((checked + 1))
        if ! grep -qi "用户反馈\|用户原文\|user_feedback\|反馈原文" "$hf" 2>/dev/null; then
            echo "WARN: $(basename "$hf") 为返工轮次但无用户反馈原文"
            missing=$((missing + 1))
        fi
    done

    if [ $checked -eq 0 ]; then
        echo "INFO: 无返工轮次 handoff，跳过"
    elif [ $missing -eq 0 ]; then
        echo "PASS: 所有返工 handoff 含用户反馈"
    else
        WARNS=$((WARNS + missing))
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-9: 修复轮次须有对应 code-report
# ─────────────────────────────────────────────
check_repair_reports() {
    echo "--- QA-9: 修复轮次 code-report 存在性 ---"

    if [ ! -f "$REQ_DIR/.state.md" ]; then
        echo "INFO: 无 .state.md，跳过"
        echo ""
        return
    fi

    local repair_round
    repair_round=$(grep "^repair_round:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "0")

    if [ "$repair_round" -eq 0 ] 2>/dev/null; then
        echo "INFO: repair_round=0，无修复轮次"
        echo ""
        return
    fi

    local missing=0
    for i in $(seq 2 $((repair_round + 1))); do
        if ! ls "$REQ_DIR"/worker/code-report-r${i}*.md >/dev/null 2>&1; then
            echo "FAIL: repair_round=$repair_round 但缺少 worker/code-report-r${i}*.md"
            missing=$((missing + 1))
        fi
    done

    if [ $missing -eq 0 ]; then
        echo "PASS: 所有修复轮次有对应 code-report"
    else
        ERRORS=$((ERRORS + missing))
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-10: (已废弃 — audit-dimensions.md 由 CR-007 废弃，覆盖度由 deriveReviewScope + testcases.md 保障)
# ─────────────────────────────────────────────

# ─────────────────────────────────────────────
# QA-11: Handoff 行数检查（防止上下文膨胀）
# ─────────────────────────────────────────────
check_handoff_linecount() {
    echo "--- QA-11: Handoff 行数检查 ---"
    local handoff_dir="$REQ_DIR/handoffs"
    if [ ! -d "$handoff_dir" ]; then
        echo "SKIP: handoffs/ 目录不存在"
        echo ""
        return
    fi

    local oversized=0
    local warned=0
    for f in "$handoff_dir"/*.md; do
        [ -f "$f" ] || continue
        local lines
        lines=$(wc -l < "$f" | tr -d ' ')
        local fname
        fname=$(basename "$f")
        if [ "$lines" -gt 300 ]; then
            echo "FAIL: $fname = $lines 行（超过 300 行硬上限）"
            oversized=$((oversized + 1))
        elif [ "$lines" -gt 200 ]; then
            echo "WARN: $fname = $lines 行（超过 200 行建议上限）"
            warned=$((warned + 1))
        fi
    done

    if [ $oversized -gt 0 ]; then
        echo "FAIL: $oversized 个 handoff 超过 300 行"
        ERRORS=$((ERRORS + 1))
    elif [ $warned -gt 0 ]; then
        echo "WARN: $warned 个 handoff 超过 200 行（建议精简）"
        WARNS=$((WARNS + 1))
    else
        echo "PASS: 所有 handoff 行数在合理范围"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-12: 回归套件覆盖校验（Verifier 报告必须含回归结果）
# ─────────────────────────────────────────────
check_regression_coverage() {
    echo "--- QA-12: 回归套件覆盖校验 ---"

    local suite="output/tests/regression-suite.md"
    if [ ! -f "$suite" ]; then
        echo "INFO: regression-suite.md 不存在（首次开发），跳过"
        echo ""
        return
    fi

    local phase
    phase=$(grep "^phase:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
    # 仅在 apply/archive/done 阶段校验
    if [[ "$phase" != "apply" && "$phase" != "archive" && "$phase" != "done" ]]; then
        echo "INFO: phase=$phase, 回归校验在 apply+ 阶段执行"
        echo ""
        return
    fi

    local report=""
    for r in "$REQ_DIR"/verifier/final-test-report.md "$REQ_DIR"/verifier/temp-test-report.md; do
        [ -f "$r" ] && report="$r" && break
    done

    if [ -z "$report" ]; then
        echo "WARN: regression-suite.md 存在但无 Verifier 测试报告"
        WARNS=$((WARNS + 1))
    elif ! grep -qi "回归\|regression" "$report" 2>/dev/null; then
        echo "FAIL: regression-suite.md 存在但 Verifier 报告未包含回归测试结果"
        ERRORS=$((ERRORS + 1))
    else
        # 进一步检查: 回归结论必须明确
        if ! grep -qiE "回归判定:[[:space:]]*(PASS|FAIL)" "$report" 2>/dev/null; then
            echo "WARN: 回归章节存在但缺少明确判定（回归判定: PASS/FAIL）"
            WARNS=$((WARNS + 1))
        else
            echo "PASS: Verifier 报告包含回归测试结果及判定"
        fi
    fi
    echo ""
}

# ─────────────────────────────────────────────
# QA-13: 归档时测试用例沉淀完整性
# ─────────────────────────────────────────────
check_testcase_sedimentation() {
    echo "--- QA-13: 测试用例沉淀完整性 ---"

    local phase
    phase=$(grep "^phase:" "$REQ_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
    if [[ "$phase" != "archive" && "$phase" != "done" ]]; then
        echo "INFO: phase=$phase, 沉淀校验在 archive/done 阶段执行"
        echo ""
        return
    fi

    local testcases="$REQ_DIR/thinker/requirement-spec.md"
    local suite="output/tests/regression-suite.md"

    if [ ! -f "$testcases" ]; then
        echo "INFO: 无 testcases.md（可能为 manual 策略），跳过"
        echo ""
        return
    fi

    if [ ! -f "$suite" ]; then
        echo "FAIL: testcases.md 存在但 regression-suite.md 未创建（归档沉淀未执行）"
        ERRORS=$((ERRORS + 1))
        echo ""
        return
    fi

    # 检查当前 REQ 的用例是否已沉淀（REQ-ID 标签存在）
    if ! grep -q "<!-- REQ-${req_id} START -->" "$suite" 2>/dev/null; then
        echo "FAIL: regression-suite.md 中缺少 REQ-${req_id} 标签段（沉淀不完整）"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS: REQ-${req_id} 用例已沉淀到回归套件"
    fi
    echo ""
}

# ─────────────────────────────────────────────
# 执行所有检查
# ─────────────────────────────────────────────
check_thinker_ambiguity
check_worker_report
check_verifier_conclusion
check_handoff_completion
check_lessons_after_rejection
check_handoff_feedback
check_repair_reports
check_handoff_linecount
check_regression_coverage
check_testcase_sedimentation

# ─────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────
echo "════════════════════════════════════"
if [ $ERRORS -gt 0 ]; then
    echo "=== 质量检查: $ERRORS 项 FAIL, $WARNS 项 WARN ==="
    exit 1
elif [ $WARNS -gt 0 ]; then
    echo "=== 质量检查: 全部通过, $WARNS 项 WARN ==="
    exit 0
else
    echo "=== 质量检查: 全部通过 ==="
    exit 0
fi

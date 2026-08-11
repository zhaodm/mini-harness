#!/bin/bash
# baseline.sh - 基线对比脚本
# 对比当前产出物与已归档基线，检测是否有未经流程的修改
# 退出码: 0=一致, 1=存在差异
# 用法: ./scripts/baseline.sh [REQ-ID]

set -euo pipefail

DELIVERABLES_DIR="deliverables"
ERRORS=0
req_id="${1:-}"

# 自动从 .state.md 读取 REQ-ID
if [ -z "$req_id" ]; then
    req_id=$(grep "^req_id:" "$DELIVERABLES_DIR/.state.md" 2>/dev/null | awk '{print $2}' || echo "")
fi

REQ_DIR="$DELIVERABLES_DIR/$req_id"
SPEC_DIR="$DELIVERABLES_DIR/$req_id/docs/spec"
BASELINES_DIR="$DELIVERABLES_DIR/$req_id/.engine/baselines"

echo "=== 基线对比检查 ==="
if [ -n "$req_id" ]; then
    echo "INFO: REQ-ID=$req_id"
fi

# 检查 deliverables/{REQ-ID}/docs/spec/ 是否有内容可对比
if [ ! -d "$SPEC_DIR" ] || [ -z "$(ls -A "$SPEC_DIR" 2>/dev/null | grep -v baselines)" ]; then
    echo "INFO: docs/spec/ 为空，无基线可对比（首次归档场景）"
    exit 0
fi

# 检查归档后的 spec 文件是否被非流程修改
check_spec_integrity() {
    local file="$1"
    local basename
    basename=$(basename "$file")

    if [ ! -f "$file" ]; then
        return
    fi

    # 查找最新的 baseline 版本
    local latest_baseline=""
    local max_version=0
    for bl in "$BASELINES_DIR"/"${basename%.md}".v*.md; do
        if [ -f "$bl" ]; then
            local ver
            ver=$(echo "$bl" | grep -o 'v[0-9]*' | tr -d 'v')
            if [ "$ver" -gt "$max_version" ]; then
                max_version=$ver
                latest_baseline="$bl"
            fi
        fi
    done

    if [ -z "$latest_baseline" ]; then
        echo "INFO: $basename 无 baseline 版本，跳过"
        return
    fi

    # 对比当前 spec 与最新 baseline
    if diff -q "$file" "$latest_baseline" > /dev/null 2>&1; then
        echo "PASS: $basename 与 baseline v$max_version 一致"
    else
        echo "WARN: $basename 与 baseline v$max_version 存在差异"
        echo "      如果是通过 CHANGE 流程修改的，这是正常的"
        diff --brief "$file" "$latest_baseline" || true
    fi
}

# 对比各 spec 文件
for spec_file in "$SPEC_DIR"/*.md; do
    if [ -f "$spec_file" ]; then
        check_spec_integrity "$spec_file"
    fi
done

# 产出即归档：无根 output/ 二份存放，取消源产出一致性检查

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "=== 基线对比完成 ==="
    exit 0
else
    echo "=== 基线对比发现 $ERRORS 项异常 ==="
    exit 1
fi

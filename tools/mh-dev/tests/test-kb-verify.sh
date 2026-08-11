#!/bin/bash
# test-kb-verify.sh — kb-verify.sh 测试用例
# 覆盖: 正常退出码、strict 模式、缺失检测、行数约束

set -uo pipefail

PASS=0
FAIL=0

pass() { echo "  [PASS]: $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL]: $1"; FAIL=$((FAIL + 1)); }

KB_VERIFY="docs/kb/kb-verify.sh"

# 前置: 确认 kb-verify.sh 存在且可执行
if [ ! -f "$KB_VERIFY" ]; then
    echo "FATAL: $KB_VERIFY 不存在"
    exit 99
fi

echo "=== kb-verify.sh 测试套件 ==="
echo ""

# ─────────────────────────────────────────────
# 1. 正常退出码: 无 ERROR 时普通模式 exit 0
# ─────────────────────────────────────────────
echo "--- 1. 正常退出码 ---"
bash "$KB_VERIFY" > /dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    pass "普通模式 exit 0"
else
    fail "普通模式应 exit 0, 实际 exit $rc"
fi

# ─────────────────────────────────────────────
# 2. strict 模式: 有 WARN 时 exit 1, 无 WARN 时 exit 0
# ─────────────────────────────────────────────
echo "--- 2. strict 模式 ---"
bash "$KB_VERIFY" --strict > /tmp/kb-verify-strict.out 2>&1
strict_rc=$?
warn_count=$(grep -c 'WARN' /tmp/kb-verify-strict.out 2>/dev/null || true)
warn_count=${warn_count:-0}

if [ "$warn_count" -gt 0 ]; then
    if [ "$strict_rc" -eq 1 ]; then
        pass "strict 模式有 WARN 时 exit 1"
    else
        fail "strict 模式有 WARN 应 exit 1, 实际 exit $strict_rc"
    fi
else
    if [ "$strict_rc" -eq 0 ]; then
        pass "strict 模式无 WARN 时 exit 0"
    else
        fail "strict 模式无 WARN 应 exit 0, 实际 exit $strict_rc"
    fi
fi

# ─────────────────────────────────────────────
# 3. 缺失检测: 临时移除一个 domains 文件后 FAIL 且 exit 1
# ─────────────────────────────────────────────
echo "--- 3. 缺失检测 ---"
if [ -f docs/kb/domains/guards.md ]; then
    mv docs/kb/domains/guards.md /tmp/kb-guards-bak.md
    bash "$KB_VERIFY" > /tmp/kb-verify-missing.out 2>&1
    missing_rc=$?
    if [ "$missing_rc" -eq 1 ] && grep -q 'FAIL.*guards.md' /tmp/kb-verify-missing.out; then
        pass "缺失文件时 FAIL 且 exit 1"
    else
        fail "缺失文件时应 FAIL 且 exit 1, 实际 exit $missing_rc"
    fi
    # 恢复
    mv /tmp/kb-guards-bak.md docs/kb/domains/guards.md

    # 恢复后验证
    bash "$KB_VERIFY" > /dev/null 2>&1
    restore_rc=$?
    if [ "$restore_rc" -eq 0 ]; then
        pass "恢复后 exit 0"
    else
        fail "恢复后应 exit 0, 实际 exit $restore_rc"
    fi
else
    fail "前置条件不满足: docs/kb/domains/guards.md 不存在"
fi

# ─────────────────────────────────────────────
# 4. 行数约束: 超限文件触发 WARN
# ─────────────────────────────────────────────
echo "--- 4. 行数约束 ---"
TMP_OVERFLOW="/tmp/kb-verify-test-overflow.md"
for i in $(seq 1 160); do echo "line $i" >> "$TMP_OVERFLOW"; done

cp docs/kb/system-map.md /tmp/kb-sysmap-bak.md
cp "$TMP_OVERFLOW" docs/kb/system-map.md

bash "$KB_VERIFY" > /tmp/kb-verify-overflow.out 2>&1
if grep -q 'WARN.*Layer 0.*超出行数限制' /tmp/kb-verify-overflow.out; then
    pass "超限文件触发 WARN"
else
    fail "超限文件应触发 WARN"
fi

# strict 模式下应 exit 1
bash "$KB_VERIFY" --strict > /tmp/kb-verify-overflow-strict.out 2>&1
overflow_strict_rc=$?
if [ "$overflow_strict_rc" -eq 1 ]; then
    pass "超限文件 strict 模式 exit 1"
else
    fail "超限文件 strict 模式应 exit 1, 实际 exit $overflow_strict_rc"
fi

# 恢复
mv /tmp/kb-sysmap-bak.md docs/kb/system-map.md
rm -f "$TMP_OVERFLOW"

# ─────────────────────────────────────────────
# 5. KB_DIR 配置正确
# ─────────────────────────────────────────────
echo "--- 5. KB_DIR 配置 ---"
kb_dir=$(grep '^KB_DIR=' "$KB_VERIFY" | head -1 | sed 's/KB_DIR=//' | tr -d '"')
if [ "$kb_dir" = "docs/kb" ]; then
    pass "KB_DIR=docs/kb"
else
    fail "KB_DIR 应为 docs/kb, 实际为 $kb_dir"
fi

# ─────────────────────────────────────────────
# 6. 六域新鲜度映射完整性
# ─────────────────────────────────────────────
echo "--- 6. 六域新鲜度映射 ---"
required_mappings="roles.md:agents/ skills.md:skills/ workflow.md:workflows/ guards.md:scripts/ templates.md:templates/ mh-dev.md:tools/mh-dev/"
for mapping in $required_mappings; do
    domain=$(echo "$mapping" | cut -d: -f1)
    expected_path=$(echo "$mapping" | cut -d: -f2)
    actual_path=$(grep -A1 "$domain)" "$KB_VERIFY" | grep 'echo' | head -1 | sed 's/.*echo "//' | sed 's/".*//')
    if [ "$actual_path" = "$expected_path" ]; then
        pass "$domain -> $expected_path"
    else
        fail "$domain 应映射到 $expected_path, 实际为 $actual_path"
    fi
done

# ─────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────
echo ""
echo "========================"
echo "总计: $((PASS + FAIL)) | 通过: $PASS | 失败: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "全部通过"
    exit 0
else
    echo "存在失败"
    exit 1
fi

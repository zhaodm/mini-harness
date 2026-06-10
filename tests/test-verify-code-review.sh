#!/bin/bash
# test-verify-code-review.sh — verify-code-review.sh 集成测试
# 用法: bash tests/test-verify-code-review.sh
# 退出码: 0=全部通过, 1=有失败

set -u

PASS=0
FAIL=0
SCRIPT="scripts/verify-code-review.sh"
TMPDIR=$(mktemp -d)

# 清理函数
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

assert() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  [PASS]: $desc"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL]: $desc (expected=$expected, actual=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

# 搭建临时 deliverables 结构
setup_env() {
  local req_id="$1" output_type="$2" report_content="$3"
  rm -rf "$TMPDIR/deliverables"
  mkdir -p "$TMPDIR/deliverables/$req_id/te"
  echo "req_id: $req_id" > "$TMPDIR/deliverables/.state.md"
  cat > "$TMPDIR/deliverables/$req_id/.state.md" <<EOF
req_id: $req_id
mode: standard
phase: apply
output_type: $output_type
current_step: TEST-2
current_role: TE
last_updated: "2026-06-10T10:00:00Z"
EOF
  if [ -n "$report_content" ]; then
    echo "$report_content" > "$TMPDIR/deliverables/$req_id/te/final-test-report.md"
  fi
}

# 在 tmpdir 中运行脚本
run_verify() {
  local req_id="$1"
  cd "$TMPDIR"
  bash "$OLDPWD/$SCRIPT" "$req_id" >/dev/null 2>&1
  echo $?
}

OLDPWD=$(pwd)

echo "=== verify-code-review.sh 集成测试 ==="
echo ""

# --- 1. documentation 类型跳过 ---
echo "--- 1. documentation 类型自动跳过 ---"
setup_env "REQ001" "documentation" ""
result=$(run_verify "REQ001")
assert "documentation → exit 0" "0" "$result"

# --- 2. ppt 类型跳过 ---
echo "--- 2. ppt 类型自动跳过 ---"
setup_env "REQ002" "ppt" ""
result=$(run_verify "REQ002")
assert "ppt → exit 0" "0" "$result"

# --- 3. 无 TE 报告 → 跳过 ---
echo "--- 3. 无报告文件 → exit 0 ---"
setup_env "REQ003" "web-app" ""
rm -f "$TMPDIR/deliverables/REQ003/te/final-test-report.md"
result=$(run_verify "REQ003")
assert "无报告 → exit 0" "0" "$result"

# --- 4. 合规 PASS 报告 ---
echo "--- 4. 合规 PASS 报告 → exit 0 ---"
VALID_PASS='## Code Review

### 评审范围
- 文件数: 5

### 发现
无发现问题

### 结论
- Critical: 0 项
- Major: 0 项
- Minor: 0 项
- Code Review 判定: PASS'
setup_env "REQ004" "backend-api" "$VALID_PASS"
result=$(run_verify "REQ004")
assert "合规 PASS → exit 0" "0" "$result"

# --- 5. 合规 FAIL 报告 ---
echo "--- 5. 合规 FAIL 报告 → exit 0 ---"
VALID_FAIL='## Code Review

### 发现

| # | 维度 | 严重程度 | 文件:行号 | 描述 | 建议 |
|---|------|---------|----------|------|------|
| 1 | security | Critical | src/db.js:10 | SQL注入 | 参数化 |

### 结论
- Critical: 1 项
- Code Review 判定: FAIL'
setup_env "REQ005" "web-app" "$VALID_FAIL"
result=$(run_verify "REQ005")
assert "合规 FAIL → exit 0" "0" "$result"

# --- 6. 合规 SKIPPED 报告 ---
echo "--- 6. 合规 SKIPPED 报告 → exit 0 ---"
VALID_SKIPPED='## Code Review

Code Review 判定: SKIPPED — output_type=documentation, 非代码产出'
setup_env "REQ006" "cli-tool" "$VALID_SKIPPED"
result=$(run_verify "REQ006")
assert "合规 SKIPPED → exit 0" "0" "$result"

# --- 7. 缺少 Code Review 章节 → FAIL ---
echo "--- 7. 缺少 Code Review 章节 → exit 1 ---"
NO_CHAPTER='## 测试报告

结论: PASS
所有测试通过'
setup_env "REQ007" "web-app" "$NO_CHAPTER"
result=$(run_verify "REQ007")
assert "缺章节 → exit 1" "1" "$result"

# --- 8. 缺少结论行 → FAIL ---
echo "--- 8. 缺少判定结论 → exit 1 ---"
NO_VERDICT='## Code Review

### 评审范围
- 文件数: 3

### 发现
无发现'
setup_env "REQ008" "backend-api" "$NO_VERDICT"
result=$(run_verify "REQ008")
assert "缺结论 → exit 1" "1" "$result"

# --- 9. FAIL 但无 Critical → FAIL ---
echo "--- 9. FAIL 无 Critical → exit 1 ---"
FAIL_NO_CRITICAL='## Code Review

### 结论
- Major: 2 项
- Code Review 判定: FAIL'
setup_env "REQ009" "web-app" "$FAIL_NO_CRITICAL"
result=$(run_verify "REQ009")
assert "FAIL无Critical → exit 1" "1" "$result"

# --- 10. SKIPPED 无理由 → FAIL ---
echo "--- 10. SKIPPED 无理由 → exit 1 ---"
SKIPPED_NO_REASON='## Code Review

Code Review 判定: SKIPPED'
setup_env "REQ010" "web-app" "$SKIPPED_NO_REASON"
result=$(run_verify "REQ010")
assert "SKIPPED无理由 → exit 1" "1" "$result"

# --- 汇总 ---
echo ""
echo "=== 结果: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1

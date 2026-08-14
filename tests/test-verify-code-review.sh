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
  local project="$1" track="$2" report_content="$3"
  rm -rf "$TMPDIR/deliverables"
  mkdir -p "$TMPDIR/deliverables/$project/.engine"
  echo "project: $project" > "$TMPDIR/deliverables/.state.md"
  cat > "$TMPDIR/deliverables/$project/.engine/.state.md" <<EOF
project: $project
phase: apply
current_step: VERIFY-2
current_role: VERIFIER
track: $track
last_updated: "2026-08-10T10:00:00Z"
EOF
  if [ -n "$report_content" ]; then
    echo "$report_content" > "$TMPDIR/deliverables/$project/.engine/final-test-report.md"
  fi
}

# 在 tmpdir 中运行脚本
run_verify() {
  local project="$1"
  cd "$TMPDIR"
  bash "$OLDPWD/$SCRIPT" "$project" >/dev/null 2>&1
  echo $?
}

OLDPWD=$(pwd)

echo "=== verify-code-review.sh 集成测试 ==="
echo ""

# --- 1. ppt track 跳过 ---
echo "--- 1. ppt track 自动跳过 ---"
setup_env "web-cli" "ppt" ""
result=$(run_verify "web-cli")
assert "ppt track → exit 0" "0" "$result"

# --- 2. 无 Verifier 报告 → 跳过 ---
echo "--- 2. 无报告文件 → exit 0 ---"
setup_env "auth-svc" "code" ""
rm -f "$TMPDIR/deliverables/auth-svc/.engine/final-test-report.md"
result=$(run_verify "auth-svc")
assert "无报告 → exit 0" "0" "$result"

# --- 3. 合规 PASS 报告 ---
echo "--- 3. 合规 PASS 报告 → exit 0 ---"
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
setup_env "data-etl" "code" "$VALID_PASS"
result=$(run_verify "data-etl")
assert "合规 PASS → exit 0" "0" "$result"

# --- 4. 合规 FAIL 报告 ---
echo "--- 4. 合规 FAIL 报告 → exit 0 ---"
VALID_FAIL='## Code Review

### 发现

| # | 维度 | 严重程度 | 文件:行号 | 描述 | 建议 |
|---|------|---------|----------|------|------|
| 1 | security | Critical | src/db.js:10 | SQL注入 | 参数化 |

### 结论
- Critical: 1 项
- Code Review 判定: FAIL'
setup_env "sync-job" "code" "$VALID_FAIL"
result=$(run_verify "sync-job")
assert "合规 FAIL → exit 0" "0" "$result"

# --- 5. 合规 SKIPPED 报告 ---
echo "--- 5. 合规 SKIPPED 报告 → exit 0 ---"
VALID_SKIPPED='## Code Review

Code Review 判定: SKIPPED — 非代码产出'
setup_env "chat-ui" "code" "$VALID_SKIPPED"
result=$(run_verify "chat-ui")
assert "合规 SKIPPED → exit 0" "0" "$result"

# --- 6. 缺少 Code Review 章节 → FAIL ---
echo "--- 6. 缺少 Code Review 章节 → exit 1 ---"
NO_CHAPTER='## 测试报告

结论: PASS
所有测试通过'
setup_env "log-agg" "code" "$NO_CHAPTER"
result=$(run_verify "log-agg")
assert "缺章节 → exit 1" "1" "$result"

# --- 7. 缺少结论行 → FAIL ---
echo "--- 7. 缺少判定结论 → exit 1 ---"
NO_VERDICT='## Code Review

### 评审范围
- 文件数: 3

### 发现
无发现'
setup_env "pay-gw" "code" "$NO_VERDICT"
result=$(run_verify "pay-gw")
assert "缺结论 → exit 1" "1" "$result"

# --- 8. FAIL 但无 Critical → FAIL ---
echo "--- 8. FAIL 无 Critical → exit 1 ---"
FAIL_NO_CRITICAL='## Code Review

### 结论
- Major: 2 项
- Code Review 判定: FAIL'
setup_env "mail-svc" "code" "$FAIL_NO_CRITICAL"
result=$(run_verify "mail-svc")
assert "FAIL无Critical → exit 1" "1" "$result"

# --- 9. SKIPPED 无理由 → FAIL ---
echo "--- 9. SKIPPED 无理由 → exit 1 ---"
SKIPPED_NO_REASON='## Code Review

Code Review 判定: SKIPPED'
setup_env "push-svc" "code" "$SKIPPED_NO_REASON"
result=$(run_verify "push-svc")
assert "SKIPPED无理由 → exit 1" "1" "$result"

# --- 汇总 ---
echo ""
echo "=== 结果: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1

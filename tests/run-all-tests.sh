#!/bin/bash
# run-all-tests.sh — 运行所有测试
# 用法: bash tests/run-all-tests.sh
# 退出码: 0=全部通过, 1=有失败

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

TOTAL_SUITES=0
FAILED_SUITES=0

run_suite() {
  local name=$1 cmd=$2
  TOTAL_SUITES=$((TOTAL_SUITES + 1))
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ $name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if eval "$cmd"; then
    echo ""
  else
    FAILED_SUITES=$((FAILED_SUITES + 1))
    echo ""
  fi
}

run_suite "role-guard.sh 回归测试" "bash tests/test-role-guard.sh"
run_suite "prompt-assembler 单元测试" "node tests/test-prompt-assembler.js"
run_suite "result-parser 单元测试" "node tests/test-result-parser.js"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [ $FAILED_SUITES -eq 0 ]; then
  echo "✅ 全部 $TOTAL_SUITES 个测试套件通过"
  exit 0
else
  echo "❌ $FAILED_SUITES/$TOTAL_SUITES 个测试套件失败"
  exit 1
fi

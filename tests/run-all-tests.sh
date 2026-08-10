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
run_suite "框架自检回归测试" "bash tests/test-check-harness.sh"
run_suite "mh-dev 治理集成测试" "bash tools/mh-dev/tests/test-governance.sh"
run_suite "prompt-assembler 单元测试" "node tests/test-prompt-assembler.js"
run_suite "result-parser 单元测试" "node tests/test-result-parser.js"
run_suite "detect-scenario 单元测试" "node tests/test-detect-scenario.js"
run_suite "calculate-batches 单元测试" "node tests/test-calculate-batches.js"
run_suite "decide-repair 单元测试" "node tests/test-decide-repair.js"
run_suite "detect-archive-mode 单元测试" "node tests/test-detect-archive-mode.js"
run_suite "recommend-type-mode 单元测试" "node tests/test-recommend-type-mode.js"
run_suite "archive-merge 单元测试" "node tests/test-archive-merge.js"
run_suite "auto-advance 单元测试" "node tests/test-auto-advance.js"
run_suite "code-review-rules 单元测试" "node tests/test-code-review-rules.js"
run_suite "regression-suite 单元测试" "node tests/test-regression-suite.js"
run_suite "verify-code-review 集成测试" "bash tests/test-verify-code-review.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [ $FAILED_SUITES -eq 0 ]; then
  echo "✅ 全部 $TOTAL_SUITES 个测试套件通过"
  exit 0
else
  echo "❌ $FAILED_SUITES/$TOTAL_SUITES 个测试套件失败"
  exit 1
fi

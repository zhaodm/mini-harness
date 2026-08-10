#!/bin/bash
# verify.sh — mh-dev 工具内总门禁
# 6 节验证：预检、框架自检、shell 语法、测试覆盖、全量回归、结构化报告
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
REPORT="$RUNTIME/evidence/verify-result.md"
cd "$ROOT_DIR"

mkdir -p "$(dirname "$REPORT")"
FAILURES=0
section() { mkdir -p "$(dirname "$REPORT")"; echo ""; echo "── $1 ──"; echo "" >> "$REPORT"; echo "## $1" >> "$REPORT"; echo "" >> "$REPORT"; }
record() { mkdir -p "$(dirname "$REPORT")"; echo "- $1" >> "$REPORT"; }

# 1. 机械预检
section "1. 机械预检"
if bash tools/mh-dev/scripts/audit-preflight.sh; then
  record "audit-preflight: PASS ✓"
else
  record "audit-preflight: FAIL ✗"; FAILURES=$((FAILURES+1))
fi

# 2. 框架自检
section "2. 框架自检"
if bash scripts/check-harness.sh; then
  record "check-harness: PASS ✓"
else
  record "check-harness: FAIL ✗"; FAILURES=$((FAILURES+1))
fi

# 3. shell 语法检查
section "3. Shell 语法检查"
scripts_failed=0
for f in scripts/*.sh tools/mh-dev/scripts/*.sh tools/mh-dev/tests/*.sh tests/*.sh; do
  [[ -f "$f" ]] || continue
  if ! bash -n "$f" 2>/dev/null; then
    record "syntax error: $f"; scripts_failed=$((scripts_failed+1))
  fi
done
if [[ $scripts_failed -eq 0 ]]; then record "shell syntax: PASS ✓"; else record "shell syntax: $scripts_failed file(s) FAIL ✗"; FAILURES=$((FAILURES+1)); fi

# 4. 残留关键词检查（如果 state.json 存在且有 scope-result）
section "4. 残留关键词检查"
if [[ -f "$RUNTIME/scope-result.md" ]] && grep -q '关键词:' "$RUNTIME/scope-result.md" 2>/dev/null; then
  record "scope-result.md exists; review for residual references"
else
  record "no scope-result.md; skip residual check"
fi

# 5. 全量回归测试
section "5. 全量回归测试"
if bash tests/run-all-tests.sh; then
  record "run-all-tests: PASS ✓"
else
  record "run-all-tests: FAIL ✗"; FAILURES=$((FAILURES+1))
fi

# 6. 禁止外发操作扫描
section "6. 禁止外发操作扫描"
if grep -REn --include='*.sh' '(git[[:space:]]+(commit|tag|push)|npm[[:space:]]+publish|gh[[:space:]]+release[[:space:]]+create)' tools/mh-dev/scripts/ 2>/dev/null; then
  record "forbidden outbound action: FAIL ✗"; FAILURES=$((FAILURES+1))
else
  record "no outbound release action: PASS ✓"
fi

# 汇总
echo "" >> "$REPORT"
echo "## 汇总" >> "$REPORT"
echo "" >> "$REPORT"
if [[ $FAILURES -eq 0 ]]; then
  echo "ALL PASS" >> "$REPORT"
  echo "PASS: mh-dev verification suite completed"
  exit 0
else
  echo "FAIL: $FAILURES section(s) failed" >> "$REPORT"
  echo "FAIL: $FAILURES section(s) failed" >&2
  exit 1
fi

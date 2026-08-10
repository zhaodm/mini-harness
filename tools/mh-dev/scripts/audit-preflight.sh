#!/bin/bash
# audit-preflight.sh — mh-dev 机械预检
# 检查：文件存在性、脚本可执行性、命令注册一致性、文档引用、shell 语法、陈旧引用
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

FAILURES=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES+1)); }

# 1. 关键文件存在性
echo "--- 1. 关键文件 ---"
for f in .claude/commands/mh-dev.md skills/mh-dev.md tools/mh-dev/CLAUDE.md \
         tools/mh-dev/templates/semantic-verdict.json tools/mh-dev/templates/acceptance-criteria.json \
         tools/mh-dev/templates/dispatch-prompts.md tools/mh-dev/templates/audit-report.md; do
  [[ -s "$f" ]] && pass "$f" || fail "$f 缺失或为空"
done

# 2. 脚本可执行性
echo "--- 2. 脚本可执行性 ---"
for s in tools/mh-dev/start.sh tools/mh-dev/scripts/*.sh; do
  [[ -x "$s" ]] && pass "$s" || fail "$s 不可执行"
done

# 3. 命令注册一致性
echo "--- 3. 命令注册一致性 ---"
grep -q 'mh-dev' README.md && pass "README.md 含 mh-dev" || fail "README.md 不含 mh-dev"
grep -q 'mh-dev' CLAUDE.md && pass "CLAUDE.md 含 mh-dev" || fail "CLAUDE.md 不含 mh-dev"
grep -q 'mh-dev' docs/workflow.md && pass "docs/workflow.md 含 mh-dev" || fail "docs/workflow.md 不含 mh-dev"
grep -q 'mh-dev' docs/source-of-truth.md && pass "docs/source-of-truth.md 含 mh-dev" || fail "docs/source-of-truth.md 不含 mh-dev"

# 4. shell 语法
echo "--- 4. Shell 语法 ---"
syntax_fail=0
for f in tools/mh-dev/scripts/*.sh; do
  bash -n "$f" 2>/dev/null || { fail "$f 语法错误"; syntax_fail=$((syntax_fail+1)); }
done
[[ $syntax_fail -eq 0 ]] && pass "所有 mh-dev 脚本语法正确" || fail "$syntax_fail 个脚本语法错误"

# 5. 文档引用一致性（dispatch-prompts 引用的角色文件存在）
echo "--- 5. 文档引用一致性 ---"
for agent in developer tester auditor; do
  [[ -s "tools/mh-dev/agents/$agent.md" ]] && pass "agents/$agent.md" || fail "agents/$agent.md 缺失"
done

# 6. 禁止外发操作
echo "--- 6. 禁止外发操作 ---"
if grep -REn --include='*.sh' '(git[[:space:]]+(commit|tag|push)|npm[[:space:]]+publish|gh[[:space:]]+release[[:space:]]+create)' tools/mh-dev/scripts/ 2>/dev/null; then
  fail "发现禁止的外发操作"
else
  pass "无外发操作"
fi

# 7. 陈旧引用扫描（检查已废弃的 pdt-* 引用）
echo "--- 7. 陈旧引用扫描 ---"
stale=$(grep -rn 'pdt-init\|pdt-propose\|pdt-apply\|pdt-archive' .claude/commands/ skills/ 2>/dev/null | grep -v 'mh-' || true)
if [[ -z "$stale" ]]; then
  pass "无陈旧 pdt-* 引用"
else
  fail "发现陈旧 pdt-* 引用: $stale"
fi

# 8. CLAUDE.md 引用的脚本存在
echo "--- 8. CLAUDE.md 引用脚本存在性 ---"
for script in reset-session.sh scope-scan.sh capture-snapshot.sh validate-changes.sh \
  validate-dev-completion.sh check-transition.sh transition-state.sh precondition-check.sh \
  validate-outputs.sh audit-preflight.sh verify.sh release-candidate.sh; do
  [[ -f "tools/mh-dev/scripts/$script" ]] && pass "scripts/$script" || fail "scripts/$script 缺失"
done

# 结果
echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS: mh-dev mechanical preflight passed"
  exit 0
else
  echo "FAIL: mh-dev mechanical preflight failed: $FAILURES issue(s)" >&2
  exit 1
fi

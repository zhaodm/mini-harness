#!/bin/bash
# check-harness.sh - Mini-Harness 已发布框架文件完整性自检
# 验证受版本控制的命令面、角色、技能、脚本、模板与测试入口。
# 退出码: 0=框架完整, 1=框架损坏

set -euo pipefail

ERRORS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
require_file() { [[ -s "$1" ]] && pass "$1" || fail "$1 缺失或为空"; }
require_exec() {
  require_file "$1"
  [[ -x "$1" ]] && pass "$1 可执行" || fail "$1 不可执行"
}

printf '%s\n' "=== Mini-Harness 框架自检 ==="
printf '\n--- 核心配置 ---\n'
for file in CLAUDE.md .clinerules .mcp.json README.md CHANGELOG.md package.json; do
  require_file "$file"
done

printf '\n--- Agent 定义 ---\n'
for role in thinker worker verifier orchestrator; do
  require_file "agents/$role.md"
done

printf '\n--- Skill 与命令面 ---\n'
for skill in mh-codeflow mh-slideflow mh-intake mh-design mh-build mh-deliver mh-repair mh-self-test mh-verify; do
  require_file "skills/$skill/SKILL.md"
done
require_file "tools/mh-dev/skills/mh-dev/SKILL.md"
require_file "tools/mh-dev/skills/mh-dev-develop/SKILL.md"
require_file "tools/mh-dev/skills/mh-dev-test/SKILL.md"
require_file "tools/mh-dev/skills/mh-dev-audit/SKILL.md"
for command in mh-run mh-ppt mh-dev; do
  require_file ".claude/commands/$command.md"
done

printf '\n--- 校验脚本 ---\n'
for script in verify.sh baseline.sh check-harness.sh verify-ppt.sh verify-archive.sh verify-code-review.sh verify-qa.sh role-guard.sh; do
  require_exec "scripts/$script"
done

printf '\n--- 框架目录与模板 ---\n'
for dir in agents skills scripts templates workflows workflows/lib tests docs docs/designs docs/requirements docs/retrospectives templates/ppt-templates/layouts templates/examples templates/output-guides tools/mh-dev; do
  [[ -d "$dir" ]] && pass "$dir/" || fail "$dir/ 不存在"
done
for file in templates/handoff-template.md templates/logging-standard.md templates/state-template.md templates/output-structure.md templates/ppt-base.css templates/ppt-base.html \
           templates/orchestrator-quality-gate.md templates/needs-spec-template.md templates/design-spec-template.md templates/ppt-slide-spec-template.md templates/ppt-quality-rules.md templates/code-report-template.md templates/test-report-template.md; do
  require_file "$file"
done

if [[ $(find templates/examples -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ') -ge 4 ]]; then
  pass "templates/examples/ 至少四个示例"
else
  fail "templates/examples/ 不完整（需至少四个示例）"
fi
if [[ $(find templates/output-guides -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ') -ge 3 ]]; then
  pass "templates/output-guides/ 至少三个指南"
else
  fail "templates/output-guides/ 不完整（需至少三个指南）"
fi

printf '\n--- 工作流与测试入口 ---\n'
for file in workflows/thinker-design.js workflows/apply-batch-dev.js workflows/apply-batch-test.js workflows/apply-final-audit.js tests/run-all-tests.sh tools/mh-dev/CLAUDE.md tools/mh-dev/start.sh tools/mh-dev/scripts/verify.sh tools/mh-dev/templates/dispatch-prompts.md tools/mh-dev/templates/audit-report.md; do
  require_file "$file"
done
require_file tests/run-all-tests.sh
require_exec tools/mh-dev/start.sh
require_exec tools/mh-dev/scripts/verify.sh

printf '\n========================\n'
if (( ERRORS == 0 )); then
  echo "框架自检通过 ✓"
  exit 0
fi

echo "框架自检失败: $ERRORS 项错误"
exit 1

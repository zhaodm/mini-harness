#!/bin/bash
# test-role-guard.sh — role-guard.sh 的自动化回归测试
# 用法: bash tests/test-role-guard.sh
# 退出码: 0=全部通过, 1=有失败

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# Use temp dir for all mh-dev state to avoid wiping real .mh-dev/
MH_DEV_RUNTIME="$(mktemp -d)"
export MH_DEV_RUNTIME
trap 'rm -rf "$MH_DEV_RUNTIME"' EXIT

PASS=0
FAIL=0
TOTAL=0

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# --- 辅助函数 ---

setup_state() {
  local role=$1 phase=${2:-propose}
  mkdir -p deliverables/TEST001/.engine/handoffs
  cat > deliverables/TEST001/.engine/.state.md << EOF
req_id: TEST001
phase: ${phase}
current_step: THINK-DESIGN
current_role: ${role}
repair_round: 0
repair_task: ""
last_updated: "2026-06-09T10:00:00Z"
EOF
  cat > deliverables/.state.md << EOF
req_id: TEST001
EOF
}

cleanup_state() {
  rm -rf deliverables/TEST001 deliverables/.state.md
}

run_hook() {
  local tool=$1 file=$2
  echo "{\"tool_name\":\"${tool}\",\"tool_input\":{\"file_path\":\"${file}\"}}" | bash scripts/role-guard.sh 2>&1
  return $?
}

assert_allow() {
  local desc=$1 tool=$2 file=$3
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$tool" "$file")
  local code=$?
  if [ $code -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (expected allow, got exit=$code)"
    echo "        output: $output"
    FAIL=$((FAIL + 1))
  fi
}

assert_block() {
  local desc=$1 tool=$2 file=$3
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$tool" "$file")
  local code=$?
  if [ $code -eq 2 ]; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (expected block/exit=2, got exit=$code)"
    echo "        output: $output"
    FAIL=$((FAIL + 1))
  fi
}

# === 测试套件 ===

echo "=== role-guard.sh 回归测试 ==="
echo ""

# --- 1. 单角色权限 ---
echo "--- 1. 单角色权限测试 ---"

setup_state "THINKER"
assert_allow "THINKER 写 THINKER-propose-design.md" "Write" "deliverables/TEST001/THINKER-propose-design.md"
assert_allow "THINKER 写 .archiveignore" "Write" "deliverables/TEST001/.archiveignore"
assert_block "THINKER 写 VERIFIER-" "Write" "deliverables/TEST001/VERIFIER-apply-report.md"
assert_block "THINKER 写 WORKER-" "Write" "deliverables/TEST001/WORKER-apply-code-report-t1.md"
assert_block "THINKER 写 .engine/.state.md" "Write" "deliverables/TEST001/.engine/.state.md"
assert_block "THINKER 写 .engine/handoffs/" "Write" "deliverables/TEST001/.engine/handoffs/h.md"
cleanup_state

echo ""
setup_state "WORKER"
assert_allow "WORKER 写 WORKER-apply-" "Write" "deliverables/TEST001/WORKER-apply-code-report-t1.md"
assert_allow "WORKER 写 src/ 项目代码" "Write" "deliverables/TEST001/src/app.js"
assert_allow "WORKER 写 WORKER-apply-quality-gate" "Write" "deliverables/TEST001/WORKER-apply-quality-gate-report-b1.md"
assert_block "WORKER 写 THINKER-" "Write" "deliverables/TEST001/THINKER-propose-design.md"
assert_block "WORKER 写 VERIFIER-" "Write" "deliverables/TEST001/VERIFIER-apply-report.md"
cleanup_state

echo ""
setup_state "VERIFIER"
assert_allow "VERIFIER 写 VERIFIER-apply-" "Write" "deliverables/TEST001/VERIFIER-apply-temp-test-report.md"
assert_allow "VERIFIER 写 VERIFIER-apply-final" "Write" "deliverables/TEST001/VERIFIER-apply-final-test-report.md"
assert_block "VERIFIER 写 WORKER-" "Write" "deliverables/TEST001/WORKER-apply-code-report-t1.md"
assert_block "VERIFIER 写 THINKER-" "Write" "deliverables/TEST001/THINKER-propose-design.md"
assert_block "VERIFIER 写 src/" "Write" "deliverables/TEST001/src/fix.js"
cleanup_state

echo ""
setup_state "ORCHESTRATOR"
assert_allow "ORCHESTRATOR 写 .engine/.state.md" "Write" "deliverables/TEST001/.engine/.state.md"
assert_allow "ORCHESTRATOR 写 .engine/handoffs/" "Write" "deliverables/TEST001/.engine/handoffs/REQ001-REQ1-R1.md"
assert_allow "ORCHESTRATOR 写 .engine/plan-action.md" "Write" "deliverables/TEST001/.engine/plan-action.md"
assert_allow "ORCHESTRATOR 写 .engine/SR-record" "Write" "deliverables/TEST001/.engine/SR1-record.md"
assert_allow "ORCHESTRATOR 写 .engine/lessons.md" "Write" "deliverables/TEST001/.engine/lessons.md"
assert_allow "ORCHESTRATOR 写 .engine/process.log" "Write" "deliverables/TEST001/.engine/process.log"
assert_allow "ORCHESTRATOR 写 全局 .state.md" "Write" "deliverables/.state.md"
assert_allow "ORCHESTRATOR 写 WORKER-apply-quality-gate-report" "Write" "deliverables/TEST001/WORKER-apply-quality-gate-report-b1.md"
assert_block "ORCHESTRATOR 写 src/app.js" "Write" "deliverables/TEST001/src/app.js"
assert_block "ORCHESTRATOR 写 THINKER-" "Write" "deliverables/TEST001/THINKER-propose-design.md"
assert_block "ORCHESTRATOR 写 VERIFIER-" "Write" "deliverables/TEST001/VERIFIER-apply-report.md"
cleanup_state

# --- 2. 多角色并行 ---
echo ""
echo "--- 2. 多角色并行测试 ---"

setup_state "THINKER,VERIFIER"
assert_allow "THINKER,VERIFIER 并行: THINKER 写 THINKER-" "Write" "deliverables/TEST001/THINKER-propose-design.md"
assert_allow "THINKER,VERIFIER 并行: VERIFIER 写 VERIFIER-" "Write" "deliverables/TEST001/VERIFIER-apply-report.md"
assert_allow "THINKER,VERIFIER 并行: THINKER 写 .archiveignore" "Write" "deliverables/TEST001/.archiveignore"
assert_block "THINKER,VERIFIER 并行: WORKER 写 WORKER-" "Write" "deliverables/TEST001/WORKER-apply-code-report-t1.md"
assert_block "THINKER,VERIFIER 并行: ORCHESTRATOR 写 .engine/handoffs/" "Write" "deliverables/TEST001/.engine/handoffs/h.md"
cleanup_state

echo ""
setup_state "WORKER,VERIFIER"
assert_allow "WORKER,VERIFIER 并行: WORKER 写 src/" "Write" "deliverables/TEST001/src/app.js"
assert_allow "WORKER,VERIFIER 并行: VERIFIER 写 VERIFIER-" "Write" "deliverables/TEST001/VERIFIER-apply-report.md"
assert_allow "WORKER,VERIFIER 并行: WORKER 写 WORKER-" "Write" "deliverables/TEST001/WORKER-apply-code-report-t1.md"
assert_block "WORKER,VERIFIER 并行: THINKER 写 THINKER-" "Write" "deliverables/TEST001/THINKER-propose-design.md"
assert_block "WORKER,VERIFIER 并行: ORCHESTRATOR 写 .engine/.state.md" "Write" "deliverables/TEST001/.engine/.state.md"
cleanup_state

# --- 3. 边界条件 ---
echo ""
echo "--- 3. 边界条件测试 ---"

# 无活跃需求（应放行所有）
rm -rf deliverables/TEST001 deliverables/.state.md
mkdir -p deliverables
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"any/file.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: 无活跃需求时放行"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: 无活跃需求时应放行 (got exit=$code)"
  FAIL=$((FAIL + 1))
fi

# current_role 为空（应放行）
setup_state ""
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"deliverables/TEST001/THINKER-propose-design.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: current_role 为空时放行"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: current_role 为空时应放行 (got exit=$code)"
  FAIL=$((FAIL + 1))
fi
cleanup_state

# 非 Write/Edit 工具（应放行）
setup_state "THINKER"
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"deliverables/TEST001/VERIFIER-apply-report.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: Read 工具不拦截"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Read 工具不应拦截 (got exit=$code)"
  FAIL=$((FAIL + 1))
fi

# Edit 工具也应拦截
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"deliverables/TEST001/VERIFIER-apply-report.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC}: Edit 工具同样拦截越权"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Edit 工具应拦截越权 (got exit=$code)"
  FAIL=$((FAIL + 1))
fi
cleanup_state

# --- 4. ORCHESTRATOR 归档阶段特权 ---
echo ""
echo "--- 4. ORCHESTRATOR 归档阶段特权测试 ---"

# CR-010: 取消根 output/ 目录，ORCHESTRATOR 不再有 archive 阶段 output/docs/ 特权
setup_state "ORCHESTRATOR" "archive"
assert_block "ORCHESTRATOR archive 阶段写 src/app.js (非白名单)" "Write" "deliverables/TEST001/src/app.js"
assert_allow "ORCHESTRATOR archive 阶段写 ORCHESTRATOR-" "Write" "deliverables/TEST001/ORCHESTRATOR-init-proposal.md"
assert_allow "ORCHESTRATOR archive 阶段写 .engine/.state.md" "Write" "deliverables/TEST001/.engine/.state.md"
cleanup_state

setup_state "ORCHESTRATOR" "apply"
assert_allow "ORCHESTRATOR apply 阶段写 ORCHESTRATOR-" "Write" "deliverables/TEST001/ORCHESTRATOR-init-proposal.md"
assert_block "ORCHESTRATOR apply 阶段写 src/ (非白名单)" "Write" "deliverables/TEST001/src/app.js"
cleanup_state

# --- 5. 旧角色值容错（AX-02） ---
echo ""
echo "--- 5. 旧角色值容错测试 (AX-02) ---"

setup_state "SA"
assert_block "旧角色 SA → BLOCKED" "Write" "deliverables/TEST001/THINKER-propose-design.md"
cleanup_state

setup_state "DE"
assert_block "旧角色 DE → BLOCKED" "Write" "deliverables/TEST001/WORKER-apply-code-report-t1.md"
cleanup_state

setup_state "TE"
assert_block "旧角色 TE → BLOCKED" "Write" "deliverables/TEST001/VERIFIER-apply-report.md"
cleanup_state

setup_state "BA"
assert_block "旧角色 BA → BLOCKED" "Write" "deliverables/TEST001/THINKER-propose-spec.md"
cleanup_state

setup_state "UX"
assert_block "旧角色 UX → BLOCKED" "Write" "deliverables/TEST001/THINKER-propose-wireframes/page1.html"
cleanup_state

setup_state "PM"
assert_block "旧角色 PM → BLOCKED" "Write" "deliverables/TEST001/.engine/.state.md"
cleanup_state

# --- 6. mh-dev 状态隔离 ---
echo ""
echo "--- 6. mh-dev 状态隔离测试 ---"

setup_mhdev_state() {
  local phase=$1
  mkdir -p "$MH_DEV_RUNTIME"
  cat > "$MH_DEV_RUNTIME/state.json" << EOF
{"workflow":"mh-dev","phase":"$phase","approved_scope":["README.md"],"track":"formal"}
EOF
}
cleanup_mhdev_state() {
  rm -rf "$MH_DEV_RUNTIME"
  mkdir -p "$MH_DEV_RUNTIME"
}

# mh-dev 活跃 phase、无外部 deliverable
rm -rf deliverables/TEST001 deliverables/.state.md
setup_mhdev_state "develop"
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"README.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then echo -e "  ${GREEN}PASS${NC}: mh-dev 活跃时批准路径放行"; PASS=$((PASS + 1)); else echo -e "  ${RED}FAIL${NC}: mh-dev 活跃时批准路径应放行 (got exit=$code)"; FAIL=$((FAIL + 1)); fi
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"scripts/foo.sh"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 2 ]; then echo -e "  ${GREEN}PASS${NC}: mh-dev 活跃时未批准路径阻断"; PASS=$((PASS + 1)); else echo -e "  ${RED}FAIL${NC}: mh-dev 活跃时未批准路径应阻断 (got exit=$code)"; FAIL=$((FAIL + 1)); fi
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"tools/mh-dev/.mh-dev/foo"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then echo -e "  ${GREEN}PASS${NC}: mh-dev 活跃时运行态文件放行"; PASS=$((PASS + 1)); else echo -e "  ${RED}FAIL${NC}: mh-dev 活跃时运行态文件应放行 (got exit=$code)"; FAIL=$((FAIL + 1)); fi

# mh-dev 终态残留不污染 /mh-run 无活跃需求行为
setup_mhdev_state "done"
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"any/file.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then echo -e "  ${GREEN}PASS${NC}: mh-dev 终态残留时无活跃需求放行"; PASS=$((PASS + 1)); else echo -e "  ${RED}FAIL${NC}: mh-dev 终态残留时应放行 (got exit=$code)"; FAIL=$((FAIL + 1)); fi

# mh-dev 活跃但外部 deliverable 存在：按 deliverable 角色判定
setup_mhdev_state "develop"
setup_state "THINKER"
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"deliverables/TEST001/THINKER-propose-design.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then echo -e "  ${GREEN}PASS${NC}: 外部 deliverable 存在时按角色白名单放行"; PASS=$((PASS + 1)); else echo -e "  ${RED}FAIL${NC}: 外部 deliverable 存在时应按角色放行 (got exit=$code)"; FAIL=$((FAIL + 1)); fi
cleanup_state
cleanup_mhdev_state

# --- 7. mh-dev 绝对路径归一化（CR-011 验收） ---
echo ""
echo "--- 7. mh-dev 绝对路径归一化测试 (CR-011) ---"

# 扩展辅助函数：支持自定义 scope 和 track
setup_mhdev_state_full() {
  local phase=$1 scope=$2 track=${3:-formal}
  mkdir -p "$MH_DEV_RUNTIME"
  cat > "$MH_DEV_RUNTIME/state.json" << EOF
{"workflow":"mh-dev","phase":"$phase","approved_scope":$scope,"track":"$track"}
EOF
}

# 带消息匹配的断言拦截
assert_block_msg() {
  local desc=$1 tool=$2 file=$3 pattern=$4
  TOTAL=$((TOTAL + 1))
  local output
  output=$(run_hook "$tool" "$file")
  local code=$?
  if [ $code -eq 2 ] && echo "$output" | grep -qF "$pattern"; then
    echo -e "  ${GREEN}PASS${NC}: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $desc (expected exit=2 and message containing '$pattern', got exit=$code)"
    echo "        output: $output"
    FAIL=$((FAIL + 1))
  fi
}

ROOT_PREFIX="$(pwd)"

# 确保无 deliverable 状态干扰 mh-dev 测试
rm -rf deliverables/TEST001 deliverables/.state.md

# AC-01: formal 轨，scope 含相对路径 scripts/role-guard.sh，Write 传绝对路径 → 放行
setup_mhdev_state_full "develop" '["scripts/role-guard.sh"]' "formal"
assert_allow "AC-01: formal 轨绝对路径在 scope 内放行" "Write" "${ROOT_PREFIX}/scripts/role-guard.sh"
cleanup_mhdev_state

# AC-02: formal 轨，scope 不含目标，Write 传绝对路径 → 拦截
setup_mhdev_state_full "develop" '["README.md"]' "formal"
assert_block "AC-02: formal 轨绝对路径不在 scope 内拦截" "Write" "${ROOT_PREFIX}/scripts/foo.sh"
cleanup_mhdev_state

# AC-03: formal 轨，scope 含 scripts/role-guard.sh (sensitive)，Write 传绝对路径 → 放行
setup_mhdev_state_full "develop" '["scripts/role-guard.sh"]' "formal"
assert_allow "AC-03: formal 轨 sensitive 路径放行" "Write" "${ROOT_PREFIX}/scripts/role-guard.sh"
cleanup_mhdev_state

# AC-04: light 轨，scope 含 scripts/role-guard.sh (sensitive)，Write 传绝对路径 → 拦截 formal required
setup_mhdev_state_full "develop" '["scripts/role-guard.sh"]' "light"
assert_block_msg "AC-04: light 轨 sensitive 路径拦截 (formal required)" "Write" "${ROOT_PREFIX}/scripts/role-guard.sh" "formal"
cleanup_mhdev_state

# AC-05: Write 传相对路径，scope 含同名相对路径 → 放行（不回归）
setup_mhdev_state_full "develop" '["README.md"]' "formal"
assert_allow "AC-05: 相对路径场景不回归" "Write" "README.md"
cleanup_mhdev_state

# AX-01: Write 传含 .. 的绝对路径 → 穿越检测先行拦截
setup_mhdev_state_full "develop" '["scripts/role-guard.sh"]' "formal"
assert_block_msg "AX-01: 含 .. 的绝对路径穿越检测先行拦截" "Write" "${ROOT_PREFIX}/../evil.sh" "穿越"
cleanup_mhdev_state

# AX-02: Write 传仓库外绝对路径 /tmp/evil.sh → 拦截
setup_mhdev_state_full "develop" '["README.md"]' "formal"
assert_block "AX-02: 仓库外绝对路径拦截" "Write" "/tmp/evil.sh"
cleanup_mhdev_state

# AX-04: Write 传前缀伪造路径 → 拦截（精确匹配）
setup_mhdev_state_full "develop" '["scripts/role-guard.sh"]' "formal"
assert_block "AX-04: 前缀伪造路径精确匹配拦截" "Write" "${ROOT_PREFIX}/scripts/role-guard.sh.evil"
cleanup_mhdev_state

# AX-03: deliverables 分支无回归：WORKER 写绝对路径到 deliverables/TEST001/WORKER-foo.md → 放行
cleanup_mhdev_state
setup_state "WORKER"
assert_allow "AX-03: deliverables 分支绝对路径正则命中放行" "Write" "${ROOT_PREFIX}/deliverables/TEST001/WORKER-foo.md"
cleanup_state

# --- 8. R4/R5 round 口径与门禁回填测试 (CR-011) ---
echo ""
echo "--- 8. R4/R5 round 口径与门禁回填测试 (CR-011) ---"

# 辅助函数：创建带 repair.round 的 mock state
setup_mhdev_state_r45() {
  local round=$1 phase=${2:-verify}
  rm -rf "$MH_DEV_RUNTIME"
  mkdir -p "$MH_DEV_RUNTIME/evidence" "$MH_DEV_RUNTIME/snapshots"
  cat > "$MH_DEV_RUNTIME/state.json" << EOF
{"workflow":"mh-dev","phase":"$phase","revision":1,"approved_scope":["scripts/role-guard.sh"],"track":"formal","testcase_adding_required":false,"mechanical_preflight":"pending","test_verdict":"pending","repair":{"round":$round,"max_rounds":3,"status":"active","reason":"","source_verdict":""},"snapshots":{},"change_ownership":{},"approvals":{"intake":"approved","design":"approved","delivery":"pending"}}
EOF
}

# 确保无 deliverable 状态干扰
rm -rf deliverables/TEST001 deliverables/.state.md

# AC-06: round 口径统一 — capture-snapshot.sh --round 与 repair.round 不一致 → BLOCKED
setup_mhdev_state_r45 1
TOTAL=$((TOTAL + 1))
output=$(bash tools/mh-dev/scripts/capture-snapshot.sh --role tester --round 0 --kind before 2>&1)
code=$?
if [ $code -ne 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: AC-06: capture-snapshot --round 0 vs repair.round=1 → BLOCKED"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: AC-06: capture-snapshot --round 0 vs repair.round=1 应 BLOCKED (got exit=$code)"
  FAIL=$((FAIL + 1))
fi

setup_mhdev_state_r45 1
TOTAL=$((TOTAL + 1))
output=$(bash tools/mh-dev/scripts/capture-snapshot.sh --role tester --round 2 --kind before 2>&1)
code=$?
if [ $code -ne 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: AC-06: capture-snapshot --round 2 vs repair.round=1 → BLOCKED"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: AC-06: capture-snapshot --round 2 vs repair.round=1 应 BLOCKED (got exit=$code)"
  FAIL=$((FAIL + 1))
fi

# AC-06: validate-changes.sh --round 与 repair.round 不一致 → BLOCKED
setup_mhdev_state_r45 1
echo '{"schema_version":1,"role":"tester","round":1,"point":"before","entries":[]}' > "$MH_DEV_RUNTIME/snapshots/mock.before.json"
echo '{"schema_version":1,"role":"tester","round":1,"point":"after","entries":[]}' > "$MH_DEV_RUNTIME/snapshots/mock.after.json"
TOTAL=$((TOTAL + 1))
output=$(bash tools/mh-dev/scripts/validate-changes.sh --role tester --round 0 --before "$MH_DEV_RUNTIME/snapshots/mock.before.json" --after "$MH_DEV_RUNTIME/snapshots/mock.after.json" 2>&1)
code=$?
if [ $code -ne 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: AC-06: validate-changes --round 0 vs repair.round=1 → BLOCKED"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: AC-06: validate-changes --round 0 vs repair.round=1 应 BLOCKED (got exit=$code)"
  FAIL=$((FAIL + 1))
fi

setup_mhdev_state_r45 1
echo '{"schema_version":1,"role":"tester","round":1,"point":"before","entries":[]}' > "$MH_DEV_RUNTIME/snapshots/mock.before.json"
echo '{"schema_version":1,"role":"tester","round":1,"point":"after","entries":[]}' > "$MH_DEV_RUNTIME/snapshots/mock.after.json"
TOTAL=$((TOTAL + 1))
output=$(bash tools/mh-dev/scripts/validate-changes.sh --role tester --round 2 --before "$MH_DEV_RUNTIME/snapshots/mock.before.json" --after "$MH_DEV_RUNTIME/snapshots/mock.after.json" 2>&1)
code=$?
if [ $code -ne 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: AC-06: validate-changes --round 2 vs repair.round=1 → BLOCKED"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: AC-06: validate-changes --round 2 vs repair.round=1 应 BLOCKED (got exit=$code)"
  FAIL=$((FAIL + 1))
fi

# AC-08: validate-outputs.sh verify 在 tester verdict PASS 后回填 state.json
setup_mhdev_state_r45 1
cat > "$MH_DEV_RUNTIME/acceptance-criteria.json" << 'CRITEOF'
{"schema_version":1,"cr_id":"CR-011","items":[{"id":"AC-01","kind":"AC","statement":"test","required_evidence":"test"},{"id":"AX-01","kind":"AX","statement":"boundary","required_evidence":"test"}]}
CRITEOF
cat > "$MH_DEV_RUNTIME/evidence/test-verdict.json" << 'TVEOF'
{"schema_version":1,"role":"tester","round":1,"verdict":"PASS","generated_at":"2026-08-11T00:00:00Z","delta_ref":"snapshots/developer.r1.after.json","commands":[{"id":"cmd-01","command":"bash tests/run-all-tests.sh","cwd":"/tmp","started_at":"2026-08-11T00:00:00Z","ended_at":"2026-08-11T00:00:01Z","exit_code":0,"summary":"passed"}],"acceptance":[{"id":"AC-01","status":"PASS","evidence":["cmd-01"],"summary":"passed"},{"id":"AX-01","status":"PASS","evidence":["cmd-01"],"summary":"passed"}],"failures":[],"summary":"passed"}
TVEOF
cat > "$MH_DEV_RUNTIME/evidence/change-attribution.tester.1.json" << 'ATTEOF'
{"schema_version":1,"role":"tester","round":1,"before_snapshot":"snapshots/tester.r1.before.json","after_snapshot":"snapshots/tester.r1.after.json","changed":[],"violations":[],"result":"PASS","validated_at":"2026-08-11T00:00:00Z"}
ATTEOF
python3 -c "
import json
s=json.load(open('$MH_DEV_RUNTIME/state.json'))
s['snapshots']={'tester.1':{'before':'snapshots/tester.r1.before.json','after':'snapshots/tester.r1.after.json','attribution':'evidence/change-attribution.tester.1.json'}}
json.dump(s,open('$MH_DEV_RUNTIME/state.json','w'),indent=2)
"
TOTAL=$((TOTAL + 1))
output=$(bash tools/mh-dev/scripts/validate-outputs.sh verify 2>&1)
code=$?
if [ $code -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: AC-08: validate-outputs.sh verify → PASS"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: AC-08: validate-outputs.sh verify 应 PASS (got exit=$code)"
  echo "        output: $output"
  FAIL=$((FAIL + 1))
fi

# 验证 state.json 已回填 test_verdict=PASS, mechanical_preflight=pass
TOTAL=$((TOTAL + 1))
test_verdict=$(python3 -c "import json;s=json.load(open('$MH_DEV_RUNTIME/state.json'));print(s.get('test_verdict',''))")
mech_preflight=$(python3 -c "import json;s=json.load(open('$MH_DEV_RUNTIME/state.json'));print(s.get('mechanical_preflight',''))")
if [ "$test_verdict" = "PASS" ] && [ "$mech_preflight" = "pass" ]; then
  echo -e "  ${GREEN}PASS${NC}: AC-08: state.json 回填 test_verdict=PASS, mechanical_preflight=pass"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: AC-08: state.json 回填失败 (test_verdict=$test_verdict, mechanical_preflight=$mech_preflight)"
  FAIL=$((FAIL + 1))
fi

# AC-07: check-transition.sh done 在 R5 回填后 → PASS（不执行 transition-state.sh done）
TOTAL=$((TOTAL + 1))
output=$(bash tools/mh-dev/scripts/check-transition.sh done 2>&1)
code=$?
if [ $code -eq 0 ]; then
  echo -e "  ${GREEN}PASS${NC}: AC-07: check-transition.sh done → PASS (门禁通过)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: AC-07: check-transition.sh done 应 PASS (got exit=$code)"
  echo "        output: $output"
  FAIL=$((FAIL + 1))
fi

# AX-05: transition-state.sh repair 后 repair.round+1
setup_mhdev_state_r45 0 verify
TOTAL=$((TOTAL + 1))
output=$(bash tools/mh-dev/scripts/transition-state.sh repair --actor planner --expected-revision 1 2>&1)
code=$?
if [ $code -eq 0 ]; then
  new_round=$(python3 -c "import json;s=json.load(open('$MH_DEV_RUNTIME/state.json'));print(s.get('repair',{}).get('round',0))")
  if [ "$new_round" = "1" ]; then
    echo -e "  ${GREEN}PASS${NC}: AX-05: transition-state.sh repair → repair.round=0→1"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: AX-05: repair.round 应为 1 (got $new_round)"
    FAIL=$((FAIL + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC}: AX-05: transition-state.sh repair 应 PASS (got exit=$code)"
  echo "        output: $output"
  FAIL=$((FAIL + 1))
fi
# === 结果汇总 ===
echo ""
echo "========================"
echo -e "总计: $TOTAL | ${GREEN}通过: $PASS${NC} | ${RED}失败: $FAIL${NC}"

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}全部通过 ✓${NC}"
  exit 0
else
  echo -e "${RED}有 $FAIL 项失败${NC}"
  exit 1
fi


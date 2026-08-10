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
  mkdir -p deliverables/TEST001/{thinker,worker,verifier,output,handoffs}
  cat > deliverables/TEST001/.state.md << EOF
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
assert_allow "THINKER 写 thinker/design.md" "Write" "deliverables/TEST001/thinker/design.md"
assert_allow "THINKER 写 .archiveignore" "Write" "deliverables/TEST001/.archiveignore"
assert_block "THINKER 写 verifier/" "Write" "deliverables/TEST001/verifier/report.md"
assert_block "THINKER 写 worker/" "Write" "deliverables/TEST001/worker/code-report.md"
assert_block "THINKER 写 output/" "Write" "deliverables/TEST001/output/index.js"
assert_block "THINKER 写 handoffs/" "Write" "deliverables/TEST001/handoffs/h.md"
cleanup_state

echo ""
setup_state "WORKER"
assert_allow "WORKER 写 output/" "Write" "deliverables/TEST001/output/app.js"
assert_allow "WORKER 写 output/ 子目录" "Write" "deliverables/TEST001/output/src/utils.ts"
assert_allow "WORKER 写 code-report" "Write" "deliverables/TEST001/worker/code-report-t1.md"
assert_block "WORKER 写 thinker/" "Write" "deliverables/TEST001/thinker/design.md"
assert_block "WORKER 写 verifier/" "Write" "deliverables/TEST001/verifier/report.md"
cleanup_state

echo ""
setup_state "VERIFIER"
assert_allow "VERIFIER 写 verifier/" "Write" "deliverables/TEST001/verifier/testcases.md"
assert_allow "VERIFIER 写 verifier/ 子文件" "Write" "deliverables/TEST001/verifier/final-test-report.md"
assert_block "VERIFIER 写 output/" "Write" "deliverables/TEST001/output/fix.js"
assert_block "VERIFIER 写 thinker/" "Write" "deliverables/TEST001/thinker/design.md"
assert_block "VERIFIER 写 worker/" "Write" "deliverables/TEST001/worker/code-report.md"
cleanup_state

echo ""
setup_state "ORCHESTRATOR"
assert_allow "ORCHESTRATOR 写 .state.md" "Write" "deliverables/TEST001/.state.md"
assert_allow "ORCHESTRATOR 写 handoffs/" "Write" "deliverables/TEST001/handoffs/REQ001-REQ1-R1.md"
assert_allow "ORCHESTRATOR 写 plan-action.md" "Write" "deliverables/TEST001/plan-action.md"
assert_allow "ORCHESTRATOR 写 SR-record" "Write" "deliverables/TEST001/SR1-record.md"
assert_allow "ORCHESTRATOR 写 lessons.md" "Write" "deliverables/TEST001/lessons.md"
assert_allow "ORCHESTRATOR 写 process.log" "Write" "deliverables/TEST001/process.log"
assert_allow "ORCHESTRATOR 写 全局 .state.md" "Write" "deliverables/.state.md"
assert_allow "ORCHESTRATOR 写 quality-gate-report" "Write" "deliverables/TEST001/worker/quality-gate-report.md"
assert_block "ORCHESTRATOR 写 output/app.js" "Write" "deliverables/TEST001/output/app.js"
assert_block "ORCHESTRATOR 写 thinker/" "Write" "deliverables/TEST001/thinker/design.md"
assert_block "ORCHESTRATOR 写 verifier/" "Write" "deliverables/TEST001/verifier/report.md"
cleanup_state

# --- 2. 多角色并行 ---
echo ""
echo "--- 2. 多角色并行测试 ---"

setup_state "THINKER,VERIFIER"
assert_allow "THINKER,VERIFIER 并行: THINKER 写 thinker/" "Write" "deliverables/TEST001/thinker/design.md"
assert_allow "THINKER,VERIFIER 并行: VERIFIER 写 verifier/" "Write" "deliverables/TEST001/verifier/report.md"
assert_allow "THINKER,VERIFIER 并行: THINKER 写 .archiveignore" "Write" "deliverables/TEST001/.archiveignore"
assert_block "THINKER,VERIFIER 并行: WORKER 写 output/" "Write" "deliverables/TEST001/output/index.js"
assert_block "THINKER,VERIFIER 并行: ORCHESTRATOR 写 handoffs/" "Write" "deliverables/TEST001/handoffs/h.md"
cleanup_state

echo ""
setup_state "WORKER,VERIFIER"
assert_allow "WORKER,VERIFIER 并行: WORKER 写 output/" "Write" "deliverables/TEST001/output/app.js"
assert_allow "WORKER,VERIFIER 并行: VERIFIER 写 verifier/" "Write" "deliverables/TEST001/verifier/report.md"
assert_allow "WORKER,VERIFIER 并行: WORKER 写 code-report" "Write" "deliverables/TEST001/worker/code-report-t1.md"
assert_block "WORKER,VERIFIER 并行: THINKER 写 thinker/" "Write" "deliverables/TEST001/thinker/design.md"
assert_block "WORKER,VERIFIER 并行: ORCHESTRATOR 写 state" "Write" "deliverables/TEST001/.state.md"
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
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"deliverables/TEST001/thinker/design.md"}}' | bash scripts/role-guard.sh 2>&1)
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
output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"deliverables/TEST001/verifier/report.md"}}' | bash scripts/role-guard.sh 2>&1)
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
output=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"deliverables/TEST001/verifier/report.md"}}' | bash scripts/role-guard.sh 2>&1)
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

setup_state "ORCHESTRATOR" "archive"
assert_allow "ORCHESTRATOR archive 阶段写 output/docs/" "Write" "output/docs/spec.md"
assert_block "ORCHESTRATOR archive 阶段写 output/app.js (非 docs)" "Write" "deliverables/TEST001/output/app.js"
cleanup_state

setup_state "ORCHESTRATOR" "apply"
assert_block "ORCHESTRATOR apply 阶段写 output/docs/ (非 archive)" "Write" "output/docs/spec.md"
cleanup_state

# --- 5. 旧角色值容错（AX-02） ---
echo ""
echo "--- 5. 旧角色值容错测试 (AX-02) ---"

setup_state "SA"
assert_block "旧角色 SA → BLOCKED" "Write" "deliverables/TEST001/thinker/design.md"
cleanup_state

setup_state "DE"
assert_block "旧角色 DE → BLOCKED" "Write" "deliverables/TEST001/output/app.js"
cleanup_state

setup_state "TE"
assert_block "旧角色 TE → BLOCKED" "Write" "deliverables/TEST001/verifier/report.md"
cleanup_state

setup_state "BA"
assert_block "旧角色 BA → BLOCKED" "Write" "deliverables/TEST001/thinker/spec.md"
cleanup_state

setup_state "UX"
assert_block "旧角色 UX → BLOCKED" "Write" "deliverables/TEST001/thinker/wireframes/page1.html"
cleanup_state

setup_state "PM"
assert_block "旧角色 PM → BLOCKED" "Write" "deliverables/TEST001/.state.md"
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
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"deliverables/TEST001/thinker/design.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 0 ]; then echo -e "  ${GREEN}PASS${NC}: 外部 deliverable 存在时按角色白名单放行"; PASS=$((PASS + 1)); else echo -e "  ${RED}FAIL${NC}: 外部 deliverable 存在时应按角色放行 (got exit=$code)"; FAIL=$((FAIL + 1)); fi
cleanup_state
cleanup_mhdev_state

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

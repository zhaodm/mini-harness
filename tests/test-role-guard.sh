#!/bin/bash
# test-role-guard.sh — role-guard.sh 的自动化回归测试
# 用法: bash tests/test-role-guard.sh
# 退出码: 0=全部通过, 1=有失败

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

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
  mkdir -p deliverables/TEST001/{sa,te,de,ba,ux,output,handoffs}
  cat > deliverables/TEST001/.state.md << EOF
req_id: TEST001
mode: standard
phase: ${phase}
current_step: REQ-2+REQ-3
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

setup_state "SA"
assert_allow "SA 写 sa/design.md" "Write" "deliverables/TEST001/sa/design.md"
assert_allow "SA 写 .archiveignore" "Write" "deliverables/TEST001/.archiveignore"
assert_block "SA 写 te/" "Write" "deliverables/TEST001/te/testcases.md"
assert_block "SA 写 de/" "Write" "deliverables/TEST001/de/code-report.md"
assert_block "SA 写 output/" "Write" "deliverables/TEST001/output/index.js"
assert_block "SA 写 handoffs/" "Write" "deliverables/TEST001/handoffs/h.md"
cleanup_state

echo ""
setup_state "DE"
assert_allow "DE 写 output/" "Write" "deliverables/TEST001/output/app.js"
assert_allow "DE 写 output/ 子目录" "Write" "deliverables/TEST001/output/src/utils.ts"
assert_allow "DE 写 code-report" "Write" "deliverables/TEST001/de/code-report-t1.md"
assert_block "DE 写 sa/" "Write" "deliverables/TEST001/sa/design.md"
assert_block "DE 写 te/" "Write" "deliverables/TEST001/te/report.md"
assert_block "DE 写 ba/" "Write" "deliverables/TEST001/ba/spec.md"
cleanup_state

echo ""
setup_state "TE"
assert_allow "TE 写 te/" "Write" "deliverables/TEST001/te/testcases.md"
assert_allow "TE 写 te/ 子文件" "Write" "deliverables/TEST001/te/final-test-report.md"
assert_block "TE 写 output/" "Write" "deliverables/TEST001/output/fix.js"
assert_block "TE 写 sa/" "Write" "deliverables/TEST001/sa/design.md"
cleanup_state

echo ""
setup_state "BA"
assert_allow "BA 写 ba/" "Write" "deliverables/TEST001/ba/requirement-spec.md"
assert_block "BA 写 sa/" "Write" "deliverables/TEST001/sa/design.md"
assert_block "BA 写 output/" "Write" "deliverables/TEST001/output/x.js"
cleanup_state

echo ""
setup_state "UX"
assert_allow "UX 写 ux/" "Write" "deliverables/TEST001/ux/wireframes/page1.html"
assert_block "UX 写 output/" "Write" "deliverables/TEST001/output/styles.css"
assert_block "UX 写 sa/" "Write" "deliverables/TEST001/sa/design.md"
cleanup_state

echo ""
setup_state "PM"
assert_allow "PM 写 .state.md" "Write" "deliverables/TEST001/.state.md"
assert_allow "PM 写 handoffs/" "Write" "deliverables/TEST001/handoffs/REQ001-REQ1-R1.md"
assert_allow "PM 写 plan-action.md" "Write" "deliverables/TEST001/plan-action.md"
assert_allow "PM 写 SR-record" "Write" "deliverables/TEST001/SR1-record.md"
assert_allow "PM 写 lessons.md" "Write" "deliverables/TEST001/lessons.md"
assert_allow "PM 写 process.log" "Write" "deliverables/TEST001/process.log"
assert_allow "PM 写 全局 .state.md" "Write" "deliverables/.state.md"
assert_block "PM 写 output/app.js" "Write" "deliverables/TEST001/output/app.js"
assert_block "PM 写 sa/" "Write" "deliverables/TEST001/sa/design.md"
assert_block "PM 写 de/" "Write" "deliverables/TEST001/de/code-report.md"
cleanup_state

# --- 2. 多角色并行（CR-004 新增） ---
echo ""
echo "--- 2. 多角色并行测试 (CR-004) ---"

setup_state "SA,TE"
assert_allow "SA,TE 并行: SA 写 sa/" "Write" "deliverables/TEST001/sa/design.md"
assert_allow "SA,TE 并行: TE 写 te/" "Write" "deliverables/TEST001/te/testcases.md"
assert_allow "SA,TE 并行: SA 写 .archiveignore" "Write" "deliverables/TEST001/.archiveignore"
assert_block "SA,TE 并行: DE 写 output/" "Write" "deliverables/TEST001/output/index.js"
assert_block "SA,TE 并行: PM 写 handoffs/" "Write" "deliverables/TEST001/handoffs/h.md"
assert_block "SA,TE 并行: BA 写 ba/" "Write" "deliverables/TEST001/ba/spec.md"
cleanup_state

echo ""
setup_state "DE,TE"
assert_allow "DE,TE 并行: DE 写 output/" "Write" "deliverables/TEST001/output/app.js"
assert_allow "DE,TE 并行: TE 写 te/" "Write" "deliverables/TEST001/te/report.md"
assert_allow "DE,TE 并行: DE 写 code-report" "Write" "deliverables/TEST001/de/code-report-t1.md"
assert_block "DE,TE 并行: SA 写 sa/" "Write" "deliverables/TEST001/sa/design.md"
assert_block "DE,TE 并行: PM 写 state" "Write" "deliverables/TEST001/.state.md"
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
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"deliverables/TEST001/sa/design.md"}}' | bash scripts/role-guard.sh 2>&1)
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
setup_state "SA"
TOTAL=$((TOTAL + 1))
output=$(echo '{"tool_name":"Read","tool_input":{"file_path":"deliverables/TEST001/te/testcases.md"}}' | bash scripts/role-guard.sh 2>&1)
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
output=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"deliverables/TEST001/te/testcases.md"}}' | bash scripts/role-guard.sh 2>&1)
code=$?
if [ $code -eq 2 ]; then
  echo -e "  ${GREEN}PASS${NC}: Edit 工具同样拦截越权"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Edit 工具应拦截越权 (got exit=$code)"
  FAIL=$((FAIL + 1))
fi
cleanup_state

# --- 4. PM 归档阶段特权 ---
echo ""
echo "--- 4. PM 归档阶段特权测试 ---"

setup_state "PM" "archive"
assert_allow "PM archive 阶段写 output/docs/" "Write" "output/docs/spec.md"
assert_block "PM archive 阶段写 output/app.js (非 docs)" "Write" "deliverables/TEST001/output/app.js"
cleanup_state

setup_state "PM" "apply"
assert_block "PM apply 阶段写 output/docs/ (非 archive)" "Write" "output/docs/spec.md"
cleanup_state

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

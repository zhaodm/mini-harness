#!/bin/bash
# role-guard.sh — PreToolUse hook，拦截角色越权文件写入
# Claude Code hook 协议：stdin 接收 JSON，非零退出码 = 拒绝操作
#
# 工作原理：
# 1. 从 stdin 读取 tool call JSON
# 2. 从 .state.md 读取 current_role
# 3. 检查目标文件是否在当前角色的写入白名单内
# 4. 不在白名单 → exit 2（拒绝）

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# 仅拦截文件写入操作
[[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]] && exit 0
[[ -z "$FILE_PATH" ]] && exit 0

# 定位活跃需求的 .state.md
STATE_FILE=$(find deliverables -maxdepth 2 -name ".state.md" -not -path "deliverables/.state.md" 2>/dev/null | head -1)
[[ -z "$STATE_FILE" ]] && exit 0  # 无活跃需求时不拦截

CURRENT_ROLE=$(grep "^current_role:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
REQ_ID=$(grep "^req_id:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
[[ -z "$CURRENT_ROLE" || -z "$REQ_ID" ]] && exit 0

# 角色权限检查
check_permission() {
  local role=$1 file=$2 req=$3

  case "$role" in
    PM)
      [[ "$file" =~ deliverables/${req}/\.state\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/handoffs/.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/plan-action\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/SR.*-record\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/lessons\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/de/quality-gate-report.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/archive-manifest\.md ]] && return 0
      [[ "$file" =~ deliverables/\.state\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/process\.log ]] && return 0
      # ARC 阶段 PM 可写归档目标（通过 archive-manifest 约束具体路径）
      local phase
      phase=$(grep "^phase:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
      [[ "$phase" == "archive" && "$file" =~ ^output/docs/ ]] && return 0
      ;;
    DE)
      [[ "$file" =~ deliverables/${req}/output/ ]] && return 0
      [[ "$file" =~ deliverables/${req}/de/code-report.*\.md ]] && return 0
      ;;
    SA)
      [[ "$file" =~ deliverables/${req}/sa/ ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.archiveignore ]] && return 0
      ;;
    BA)
      [[ "$file" =~ deliverables/${req}/ba/ ]] && return 0
      ;;
    TE)
      [[ "$file" =~ deliverables/${req}/te/ ]] && return 0
      ;;
    UX)
      [[ "$file" =~ deliverables/${req}/ux/ ]] && return 0
      ;;
  esac
  return 1
}

if ! check_permission "$CURRENT_ROLE" "$FILE_PATH" "$REQ_ID"; then
  echo "BLOCKED: ${CURRENT_ROLE} 无权写入 ${FILE_PATH}"
  echo "请通过 handoff 派发给有权限的角色处理。"
  exit 2
fi

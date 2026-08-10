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

# mh-dev 仅在没有外部项目流程时治理框架根目录写入。运行态文件始终允许；
# phase 正则仅匹配活跃开发阶段；done/blocked 为终态，不激活治理（避免残留状态污染 /mh-run）：
# 框架文件必须被 approved_scope 精确列出，且治理关键路径只允许 formal 轨道。
MH_DEV_STATE="${MH_DEV_RUNTIME:-tools/mh-dev/.mh-dev}/state.json"
if [[ -z "$STATE_FILE" && -f "$MH_DEV_STATE" ]] && jq -e '.workflow == "mh-dev" and (.phase | test("^(intake|propose|develop|verify|repair)$"))' "$MH_DEV_STATE" >/dev/null 2>&1; then
  [[ "$FILE_PATH" =~ tools/mh-dev/\.mh-dev/ ]] && exit 0

  MH_TRACK=$(jq -r '.track // empty' "$MH_DEV_STATE")
  if jq -e --arg path "$FILE_PATH" '.approved_scope | index($path) != null' "$MH_DEV_STATE" >/dev/null 2>&1; then
    case "$FILE_PATH" in
      CLAUDE.md|.claude/settings.json|scripts/role-guard.sh|templates/state-template.md)
        [[ "$MH_TRACK" == "formal" ]] || { echo "BLOCKED: mh-dev 治理关键路径要求 formal 轨道: $FILE_PATH"; exit 2; }
        ;;
    esac
    exit 0
  fi

  echo "BLOCKED: mh-dev 未批准写入路径 $FILE_PATH"
  exit 2
fi

[[ -z "$STATE_FILE" ]] && exit 0  # 无活跃需求时不拦截

CURRENT_ROLES=$(grep "^current_role:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
REQ_ID=$(grep "^req_id:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
[[ -z "$CURRENT_ROLES" || -z "$REQ_ID" ]] && exit 0

# 角色权限检查（单角色）
check_permission() {
  local role=$1 file=$2 req=$3

  case "$role" in
    ORCHESTRATOR)
      [[ "$file" =~ deliverables/${req}/\.state\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/handoffs/.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/plan-action\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/SR.*-record\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/lessons\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/worker/quality-gate-report.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/archive-manifest\.md ]] && return 0
      [[ "$file" =~ deliverables/\.state\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/process\.log ]] && return 0
      # ARC 阶段 Orchestrator 可写归档目标（通过 archive-manifest 约束具体路径）
      local phase
      phase=$(grep "^phase:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
      [[ "$phase" == "archive" && "$file" =~ ^output/docs/ ]] && return 0
      ;;
    THINKER)
      [[ "$file" =~ deliverables/${req}/thinker/ ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.archiveignore ]] && return 0
      ;;
    WORKER)
      [[ "$file" =~ deliverables/${req}/output/ ]] && return 0
      [[ "$file" =~ deliverables/${req}/worker/code-report.*\.md ]] && return 0
      ;;
    VERIFIER)
      [[ "$file" =~ deliverables/${req}/verifier/ ]] && return 0
      ;;
    *)
      echo "BLOCKED: 未知角色 ${role}，请检查 .state.md schema 版本" >&2
      return 1
      ;;
  esac
  return 1
}

# 支持逗号分隔多角色并行（如 current_role: THINKER,VERIFIER）
IFS=',' read -ra ROLES <<< "$CURRENT_ROLES"
ALLOWED=false
for ROLE in "${ROLES[@]}"; do
  if check_permission "$ROLE" "$FILE_PATH" "$REQ_ID"; then
    ALLOWED=true
    break
  fi
done

if [[ "$ALLOWED" == "false" ]]; then
  echo "BLOCKED: ${CURRENT_ROLES} 无权写入 ${FILE_PATH}"
  echo "请通过 handoff 派发给有权限的角色处理。"
  exit 2
fi

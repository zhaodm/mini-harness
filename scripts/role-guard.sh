#!/bin/bash
# role-guard.sh — PreToolUse hook，拦截角色越权文件写入
# Claude Code hook 协议：stdin 接收 JSON，非零退出码 = 拒绝操作
#
# 工作原理：
# 1. 从 stdin 读取 tool call JSON
# 2. 从 .engine/.state.md 读取 current_role
# 3. 检查目标文件是否在当前角色的写入白名单内
# 4. 不在白名单 → exit 2（拒绝）

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# 仅拦截文件写入操作
[[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" ]] && exit 0
[[ -z "$FILE_PATH" ]] && exit 0

# 全局路径穿越检测：拒绝包含 .. 组件的路径（防止逃出 deliverables/ 沙箱）
if [[ "$FILE_PATH" =~ \.\.[/] ]]; then
  echo "BLOCKED: 路径包含 .. 组件，疑似路径穿越: $FILE_PATH"
  exit 2
fi

# 定位活跃需求的 .engine/.state.md
STATE_FILE=$(find deliverables -maxdepth 3 -name ".state.md" -path "*/.engine/.state.md" 2>/dev/null | head -1)

# mh-dev 仅在没有外部项目流程时治理框架根目录写入。运行态文件始终允许；
# phase 正则仅匹配活跃开发阶段；done/blocked 为终态，不激活治理（避免残留状态污染 /mh-run）：
# 框架文件必须被 approved_scope 精确列出，且治理关键路径只允许 formal 轨道。
MH_DEV_STATE="${MH_DEV_RUNTIME:-tools/mh-dev/.mh-dev}/state.json"
if [[ -z "$STATE_FILE" && -f "$MH_DEV_STATE" ]] && jq -e '.workflow == "mh-dev" and (.phase | test("^(intake|propose|develop|verify|repair)$"))' "$MH_DEV_STATE" >/dev/null 2>&1; then
  [[ "$FILE_PATH" =~ tools/mh-dev/\.mh-dev/ ]] && exit 0

  # 路径归一化：绝对路径剥离仓库根前缀，转为相对路径再与 approved_scope 精确匹配。
  # 与 validate-changes.sh 的归一化口径对齐（见该脚本第 30 行注释）。
  ROOT="$(pwd)"
  if [[ "$FILE_PATH" == "$ROOT"/* ]]; then
    NORM_PATH="${FILE_PATH#$ROOT/}"
  else
    NORM_PATH="$FILE_PATH"
  fi

  MH_TRACK=$(jq -r '.track // empty' "$MH_DEV_STATE")
  if jq -e --arg path "$NORM_PATH" '.approved_scope | index($path) != null' "$MH_DEV_STATE" >/dev/null 2>&1; then
    case "$NORM_PATH" in
      CLAUDE.md|.claude/settings.json|scripts/role-guard.sh|templates/state-template.md)
        [[ "$MH_TRACK" == "formal" ]] || { echo "BLOCKED: mh-dev 治理关键路径要求 formal 轨道: $NORM_PATH"; exit 2; }
        ;;
    esac
    exit 0
  fi

  echo "BLOCKED: mh-dev 未批准写入路径 $NORM_PATH"
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
      [[ "$file" =~ deliverables/${req}/\.engine/\.state\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/handoffs/.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/plan-action\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/SR.*-record\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/lessons\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/WORKER-apply-quality-gate-report.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/ORCHESTRATOR-.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/archive-manifest\.md ]] && return 0
      [[ "$file" =~ deliverables/\.state\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/process\.log ]] && return 0
      # ARC 阶段 Orchestrator 可写归档目标（通过 archive-manifest 约束具体路径）
      local phase
      phase=$(grep "^phase:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
      ;;
    THINKER)
      [[ "$file" =~ deliverables/${req}/THINKER-.*\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.archiveignore ]] && return 0
      ;;
    WORKER)
      [[ "$file" =~ deliverables/${req}/WORKER-.*\.md ]] && return 0
      # 项目代码路径放行：WORKER 可写产品区下的项目代码目录（按 design.md 规划）
      # 排除 .engine/（引擎态）和其他角色的命名前缀产出（大小写不敏感，防止 .ENGINE/ 绕过）
      if [[ "$file" =~ deliverables/${req}/ ]] && \
         ! echo "$file" | grep -qiE "deliverables/${req}/\.?engine/" && \
         ! echo "$file" | grep -qi "deliverables/${req}/THINKER-" && \
         ! echo "$file" | grep -qi "deliverables/${req}/VERIFIER-" && \
         ! echo "$file" | grep -qi "deliverables/${req}/ORCHESTRATOR-" && \
         ! echo "$file" | grep -qi "deliverables/${req}/\.archiveignore"; then
        return 0
      fi
      ;;
    VERIFIER)
      [[ "$file" =~ deliverables/${req}/VERIFIER-.*\.md ]] && return 0
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

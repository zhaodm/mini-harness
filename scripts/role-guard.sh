#!/bin/bash
# role-guard.sh — PreToolUse hook，拦截角色越权文件写入
# Claude Code hook 协议：stdin 接收 JSON，非零退出码 = 拒绝操作
#
# 工作原理：
# 1. 从 stdin 读取 tool call JSON（Write / Edit / NotebookEdit）
# 2. 归一化路径后按归属路由：deliverables/ 归 /mh-run 角色白名单，其余归 mh-dev 框架治理
# 3. /mh-run 分支从 .engine/.state.md 读 current_role，检查目标是否在该角色白名单内
#    （非 ORCHESTRATOR 角色额外允许一条状态机边：把流程交还给 ORCHESTRATOR）
# 4. mh-dev 分支要求活跃治理授权 + approved_scope 命中；无授权时放行（默认会话透明）
# 5. 不在白名单 → exit 2（拒绝）
#
# 能力边界（CR-016 R6）：判据来自被治理方自己可写的状态文件，故本守卫是自授权机制；
# Bash 工具不在 hook matcher 内，重定向写入不受覆盖。定位是防误撞，不是安全边界。
# 详见 docs/kb/domains/guards.md「授权模型与能力边界」。

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# 工具与路径提取：仅拦截写入类工具。NotebookEdit 的路径参数是 notebook_path，
# 沿用 file_path 会取到空值而整条通道静默绕过守卫（CR-016 R5）。
# NEW_CONTENT 是本次写入的新内容，供交还谓词判定；.ipynb 不承载流程状态，不参与交还例外。
case "$TOOL_NAME" in
  Write|Edit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty')
    ;;
  NotebookEdit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.notebook_path // empty')
    NEW_CONTENT=""
    ;;
  *) exit 0 ;;
esac

# 路径参数缺失：保守放行并告警。此处 exit 2 会把任何载荷契约变动变成全局硬阻断，
# 且与真实越权无法区分；守卫定位是防误撞，硬阻断代价高于收益（CR-016 D3 有意偏离 R5）。
if [[ -z "$FILE_PATH" ]]; then
  echo "WARN: ${TOOL_NAME} 缺少路径参数，守卫跳过" >&2
  exit 0
fi

# 全局路径穿越检测：拒绝包含 .. 组件的路径（防止逃出 deliverables/ 沙箱）
if [[ "$FILE_PATH" =~ \.\.[/] ]]; then
  echo "BLOCKED: 路径包含 .. 组件，疑似路径穿越: $FILE_PATH"
  exit 2
fi

# 仓库根从脚本自身位置推导，不依赖调用方 cwd
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 路径归一化：仓库内绝对路径剥离仓库根前缀；仓库外绝对路径直接拦截
# （否则会被当作相对路径带进后续判定，配合仓库根目录条目可放行整个文件系统）。
# CR-016 D2：归一化上移到路由之前，两条流水线共用同一形态，绝对/相对写法结论一致。
case "$FILE_PATH" in
  "$ROOT"/*) NORM_PATH="${FILE_PATH#$ROOT/}" ;;
  /*)        echo "BLOCKED: 拒绝仓库外绝对路径: $FILE_PATH"; exit 2 ;;
  *)         NORM_PATH="$FILE_PATH" ;;
esac

# CR-016 D2：按路径归属路由，两条流水线的路径集不相交，故可共存、不互相阻断。
# 归属判定必须是目录前缀语义（case 的 */ 锚定），不能退化为子串匹配：
# deliverables-evil/、mydeliverables/、docs/deliverables/ 须落入框架分支而非被当作 /mh-run。
# 旧实现以「不存在活跃 REQ state」作为 mh-dev 分支的进入条件，导致两个缺陷：
# 残留 REQ state 永久关闭框架治理入口，空/畸形 REQ state 又使 approved_scope 被整体绕过。
case "$NORM_PATH" in
  deliverables/*) PATH_OWNER="mh-run" ;;
  *)              PATH_OWNER="framework" ;;
esac

# === 框架路径分支：mh-dev 治理 ===
# 运行态文件始终允许；phase 正则仅匹配活跃开发阶段；done/blocked 为终态，不激活治理；
# 框架文件必须被 approved_scope 精确列出，且治理关键路径只允许 formal 轨道。
if [[ "$PATH_OWNER" == "framework" ]]; then
  MH_DEV_STATE="${MH_DEV_RUNTIME:-$ROOT/tools/mh-dev/.mh-dev}/state.json"
  if [[ -f "$MH_DEV_STATE" ]] && jq -e '.workflow == "mh-dev" and (.phase | test("^(intake|propose|develop|verify|repair)$"))' "$MH_DEV_STATE" >/dev/null 2>&1; then
    [[ "$FILE_PATH" =~ tools/mh-dev/\.mh-dev/ ]] && exit 0

    # Tester 专属路径放行：tests/ 与 tools/mh-dev/tests/ 在 validate-changes.sh 的
    # tester_scope 内无条件认可，此处同口径放行，否则两道门禁对同一路径结论相反、
    # Tester 无法落盘任何测试。必须是目录前缀语义（case 的 */ 锚定），
    # 不能退化为子串匹配：tests-evil/x.sh、mytests/x.sh 须继续被拦截。
    # 放在归一化之后、scope 匹配之前：绝对与相对两种写入形态结论一致，
    # 且仓库外绝对路径已在上游拦下，/tmp/tests/x.sh 不会由此放行。
    case "$NORM_PATH" in
      tests/*|tools/mh-dev/tests/*) exit 0 ;;
    esac

    # scope 匹配：把 approved_scope 条目与目标路径一并转为绝对形态后比较，
    # 对 scope 的相对/绝对两种存储形态都正确；以 / 结尾的条目按目录前缀匹配。
    # jq 陷阱：目录前缀判定必须先用 `. as $s` 绑定当前条目，
    # 写成 `any($abs[]; endswith("/") and ($ap | startswith(.)))` 会因管道把 `.`
    # 重绑定为 $ap 而恒真，放行任意越权路径。
    MH_TRACK=$(jq -r '.track // empty' "$MH_DEV_STATE")
    if jq -e --arg p "$NORM_PATH" --arg root "$ROOT" '
          ([.approved_scope[] | if startswith("/") then . else $root + "/" + . end]) as $abs
          | ($root + "/" + $p) as $ap
          | ($abs | index($ap) != null)
            or any($abs[]; . as $s | ($s | endswith("/")) and ($ap | startswith($s)))
       ' "$MH_DEV_STATE" >/dev/null 2>&1; then
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

  # 无活跃 mh-dev 授权：框架路径放行。默认会话不启动任何流程（CLAUDE.md §6），
  # 守卫不得在此形态下拦截任何写入。
  exit 0
fi

# === deliverables/ 分支：/mh-run 角色白名单 ===

# 定位活跃需求的 .engine/.state.md
STATE_FILE=$(find "$ROOT/deliverables" -maxdepth 3 -name ".state.md" -path "*/.engine/.state.md" 2>/dev/null | head -1)

[[ -z "$STATE_FILE" ]] && exit 0  # 无活跃需求时不拦截

CURRENT_ROLES=$(grep "^current_role:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
REQ_ID=$(grep "^req_id:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
[[ -z "$CURRENT_ROLES" || -z "$REQ_ID" ]] && exit 0

# CR-016 D1：交还谓词。判据取自本次写入的新内容，不读磁盘旧值——磁盘旧值恒为派发角色，
# 用它判定等于永不成立。
#
# 不变量（audit P0-1 后收紧为双向）：**谓词接受集必须等于读取端判为 ORCHESTRATOR 的集合**。
# 更严 → 写入方按 schema 示例书写却被判伪交还（缺陷 1 换形态复发）；
# 更宽 → 写得进的内容其生效角色不是 ORCHESTRATOR，即横向夺权。
# 故实现直接复用读取端的解析：`grep '^current_role:' | head -1 | awk '{print $2}'`，
# 与第 124 行读取端同源。两端同源则结构上无从分歧，不必靠人工核对正则是否等价。
#
# 曾用 `grep -qE '^current_role:[[:space:]]+ORCHESTRATOR([[:space:]]|$)'`（存在性量词），
# 实测导致提权：内容含多行 current_role 时，只要**任一行**是合法交还行即放行，
# 而读取端只认**首行**。载荷「首行 current_role: THINKER,ORCHESTRATOR + 末行 current_role: ORCHESTRATOR」
# 因此写入放行、落盘生效角色为 THINKER,ORCHESTRATOR，持权者随即取得 ORCHESTRATOR 的整个
# .engine/ 写权（handoffs/、plan-action.md、SR*-record.md、lessons.md、process.log、全局 .state.md）。
# Edit 仅追加一行即可完成，原派发行无须触碰——「交还须一次完整写入」只约束合作者，不约束绕过。
# 该形态满足旧版单向不变量（更宽松也算满足），却仍是缺陷：**单侧不变量放过了它**。
#
# 首行语义同时承担了原三段锚定的职责：缩进/注释/引号形态不被 `^current_role:` 命中，
# `current_role_backup:` 同理；`ORCHESTRATORX` 与 `THINKER,ORCHESTRATOR` 作为 $2 整体值不等于
# ORCHESTRATOR。`current_role:ORCHESTRATOR`（无空格）两端一致解析为空值，故一致拒绝。
is_handback() {
  # 交还例外只接受 Write（audit F-01）。Edit 载荷只有 new_string 片段，守卫看不到
  # old_string 也看不到合并结果，故它判「片段的首行生效值」而落盘生效值由「合并后文件」决定。
  # 跨行 old_string 会把片段首行拼进上一行残段（`current_step: THINK-current_role: ORCHESTRATOR`），
  # 该行不再行首匹配，片段第二行的诱饵在合并后升为生效行——排列在合并这一步被反转。
  # 实测可落盘为 THINKER,ORCHESTRATOR（夺 ORCHESTRATOR 全部 .engine/ 写权）、WORKER（横向夺权），
  # 或使 current_role 行整体消失（读取端解析为空 → 第 126 行 exit 0 → 守卫在该 state 上整体失效）。
  # Write 的 content 即完整落盘内容，片段==合并态，该类分歧结构性消失。
  # 与协议既有约定「交还须一次完整写入」一致（CLAUDE.md §5、state-template.md 更新规则 8）。
  [[ "$TOOL_NAME" == "Write" ]] || return 1
  [[ -n "$NEW_CONTENT" ]] || return 1
  local effective
  effective=$(printf '%s\n' "$NEW_CONTENT" | grep '^current_role:' | head -1 | awk '{print $2}')
  [[ "$effective" == "ORCHESTRATOR" ]]
}

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
      [[ "$file" =~ deliverables/${req}/ORCHESTRATOR-.*\.(md|ipynb) ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/archive-manifest\.md ]] && return 0
      [[ "$file" =~ deliverables/\.state\.md ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.engine/process\.log ]] && return 0
      # ARC 阶段 Orchestrator 可写归档目标（通过 archive-manifest 约束具体路径）
      local phase
      phase=$(grep "^phase:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
      ;;
    THINKER)
      # 产出扩展名含 .ipynb：NotebookEdit 纳入守卫后（CR-016 R5），若白名单仍只锚定 .md，
      # 本角色将无法写入自己前缀的 notebook。只放开本角色前缀，不跨角色边界。
      [[ "$file" =~ deliverables/${req}/THINKER-.*\.(md|ipynb) ]] && return 0
      [[ "$file" =~ deliverables/${req}/\.archiveignore ]] && return 0
      # 交还例外：仅本需求的 .state.md，且本次写入把流程交还给 ORCHESTRATOR。
      # 不放大为引擎态直通——handoffs/、plan-action.md 等不在此正则内，
      # 即使写入内容含交还标记也落到原有拒绝路径。
      # 正则须 ^…$ 双向锚定（$file 已是归一化的仓库相对路径）：无 $ 锚时 .state.md 退化为
      # 前缀，.state.md.evil / .state.mdX / .state.md/child.md 全部命中例外；无 ^ 锚时
      # x/deliverables/${req}/.engine/.state.md 这类嵌套伪造路径同样命中。两者都把
      # 「单个 state 文件的状态机边」放大成 .engine/ 目录直通。
      [[ "$file" =~ ^deliverables/${req}/\.engine/\.state\.md$ ]] && is_handback && return 0
      ;;
    WORKER)
      [[ "$file" =~ deliverables/${req}/WORKER-.*\.md ]] && return 0
      # 交还例外，锚定口径同 THINKER 分支
      [[ "$file" =~ ^deliverables/${req}/\.engine/\.state\.md$ ]] && is_handback && return 0
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
      [[ "$file" =~ deliverables/${req}/VERIFIER-.*\.(md|ipynb) ]] && return 0
      # 交还例外，锚定口径同 THINKER 分支
      [[ "$file" =~ ^deliverables/${req}/\.engine/\.state\.md$ ]] && is_handback && return 0
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
  if check_permission "$ROLE" "$NORM_PATH" "$REQ_ID"; then
    ALLOWED=true
    break
  fi
done

if [[ "$ALLOWED" == "false" ]]; then
  echo "BLOCKED: ${CURRENT_ROLES} 无权写入 ${FILE_PATH}"
  echo "请通过 handoff 派发给有权限的角色处理。"
  exit 2
fi

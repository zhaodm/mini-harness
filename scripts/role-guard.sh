#!/bin/bash
# role-guard.sh — PreToolUse hook，拦截角色越权文件写入
# Claude Code hook 协议：stdin 接收 JSON，非零退出码 = 拒绝操作
#
# 工作原理：
# 1. 从 stdin 读取 tool call JSON（Write / Edit / NotebookEdit）
# 2. 归一化路径后按归属路由：deliverables/ 归 /mh-run 角色白名单，其余归 mh-dev 框架治理
# 3. /mh-run 分支以全局指针 deliverables/.state.md 的 project 定位活跃交付物（CR-018 D3.4，
#    不扫描文件系统），从该交付物的 .engine/.state.md 读 current_role，
#    再按肯定式路径归属表（CR-018 D3.1）检查目标是否属该角色
#    （非 ORCHESTRATOR 角色额外允许一条状态机边：把流程交还给 ORCHESTRATOR）
# 4. mh-dev 分支要求活跃治理授权 + approved_scope 命中；无授权时放行（默认会话透明）
# 5. 不在归属表 → exit 2（拒绝）
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

# 定位活跃交付物：以全局指针 deliverables/.state.md 的 project 字段为准（CR-018 D3.4）。
# 旧实现 `find … -path "*/.engine/.state.md" | head -1` 取文件系统首个命中项。
# 交付目录从 REQ00N 改为项目名后，deliverables/ 下多项目并存是常态形态，
# `head -1` 会取到任意一个项目的标识符与 current_role，据此判权即失效。
# **绝不退化为扫描**：以下任一异常形态都不再遍历 deliverables/ 寻找替代 state；
# 非指针所指的交付物其 current_role 不参与任何判权。
#
# 五形态语义（D3.4，放行为主与守卫定位一致——防误撞而非安全边界）：
#   指针文件不存在        → exit 0（无活跃交付物，等价于 /mh-run 未启动）
#   指针存在但 project 空 → exit 0（初始化中途的正常瞬态）
#   project 非法 slug     → exit 2（唯一收紧项：合法流程不会写入非法 slug，
#                                   出现即 state 被污染，此时放行等于在污染态下判权）
#   目标交付物/state 缺失 → exit 0（指针滞后于目录，如手工清理，非越权信号）
#   current_role 空/畸形  → exit 0（沿用既有语义）
POINTER_FILE="$ROOT/deliverables/.state.md"
[[ -f "$POINTER_FILE" ]] || exit 0

PROJECT=$(grep "^project:" "$POINTER_FILE" 2>/dev/null | head -1 | awk '{print $2}')
[[ -z "$PROJECT" ]] && exit 0

# 消费侧独立校验：state 是被治理方可写的文件，生成侧（mh-intake）校验可被绕过。
# 校验在插值进路径正则之前，故 D1.1 的字符集保证了 ${req} 的正则字面量安全。
if ! SLUG_ERR=$(bash "$ROOT/scripts/validate-slug.sh" "$PROJECT" 2>&1); then
  echo "BLOCKED: deliverables/.state.md 的 project 字段被污染 —— ${SLUG_ERR}"
  exit 2
fi

STATE_FILE="$ROOT/deliverables/$PROJECT/.engine/.state.md"
[[ -f "$STATE_FILE" ]] || exit 0

CURRENT_ROLES=$(grep "^current_role:" "$STATE_FILE" 2>/dev/null | awk '{print $2}')
[[ -z "$CURRENT_ROLES" ]] && exit 0

# CR-016 D1：交还谓词。判据取自本次写入的新内容，不读磁盘旧值——磁盘旧值恒为派发角色，
# 用它判定等于永不成立。
#
# 不变量（audit P0-1 后收紧为双向）：**谓词接受集必须等于读取端判为 ORCHESTRATOR 的集合**。
# 更严 → 写入方按 schema 示例书写却被判伪交还（缺陷 1 换形态复发）；
# 更宽 → 写得进的内容其生效角色不是 ORCHESTRATOR，即横向夺权。
# 故实现直接复用读取端的解析：`grep '^current_role:' | head -1 | awk '{print $2}'`，
# 与上方 CURRENT_ROLES 读取端同源。两端同源则结构上无从分歧，不必靠人工核对正则是否等价。
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
# CR-017 D1：完成回报独立落盘。回报从 handoff 文件内移出，落到
# .engine/reports/<handoff-basename>.report.md —— 被派发角色可写，handoffs/ 仍 ORCHESTRATOR 独占。
# 目录即权限边界：不在 handoffs/ 内按后缀区分写权，后缀区分会让 handoffs/x.report.md 与
# handoffs/x.md 的正则互相咬边。R2 由此满足——白名单在 handoff（角色不可写）、
# read_files 在回报（角色可写），比较的两侧落在两套写权，无法自洽伪造。
#
# **本条无内容判据**，且这是有意的：内容判据是 CR-016 两个 P0 的共同载体（存在性量词
# 与 Edit 片段/合并态分歧），能不引入就不引入。回报不承载流程状态，不需要 is_handback
# 那类检查；无多行判据即无排列可反转，故 AX-06 的排列对抗在本条上不适用。
# 因此四个分支共用同一条，也不按角色前缀细分：回报文件名由 handoff basename 派生，
# 同一时刻只有一个 handoff 在派发，current_role 即该棒执行者。加角色前缀判据会引入
# 「文件名声称的角色」与「state 里的角色」两个主体，正是本 CR 要消除的那类不一致。
#
# 正则口径与交还例外一致：`^…$` 双向锚定（左锚拒 x/deliverables/… 嵌套伪造，右锚拒
# .report.md.evil / .report.mdX / .report.md/child.md）；`${req}` 取自全局指针的 project
# 故不跨交付物；`.report.md` 双段后缀与 handoffs/ 下的命名形态显式区分。
is_report() {
  local file=$1 req=$2
  [[ "$file" =~ ^deliverables/${req}/\.engine/reports/.*\.report\.md$ ]]
}

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

# 产品区根文件白名单（CR-018 D3.2）：WORKER 可写的根文件逐条列出全名，
# 不用「根目录下任意文件」——那会让产品区根重新变成散落区，正是 R3 要消除的形态。
# 清单来源 templates/output-structure.md「产品区根目录允许的文件」。
# *.html / *.css 是 ppt track 单文件形态的产出（CR-014，落在产品区根），
# 无此两条 ppt track 的 Worker 无法交付任何产出物。
is_product_root_file() {
  local file=$1 req=$2
  [[ "$file" =~ ^deliverables/${req}/(README\.md|package\.json|pyproject\.toml|go\.mod|Cargo\.toml|tsconfig\.json|Makefile|\.env\.example|\.gitignore|vite\.config\.[a-z]+|webpack\.config\.[a-z]+|[A-Za-z0-9_-]+\.html|[A-Za-z0-9_-]+\.css)$ ]]
}

# 角色权限检查（单角色）
#
# CR-018 D3.1：肯定式路径归属表。每角色显式声明可写路径集，不再以「不含其他角色前缀」
# 作为授权谓词——产品区去掉角色前缀后，那条否定式谓词退化为「产品区全通」。
# 归属由**目录**承载：docs/ 归 THINKER（规格）与 ORCHESTRATOR（归档），
# src/、deploy/ 归 WORKER，tests/ 由 WORKER 与 VERIFIER 共写，assets/ 由 THINKER 与 WORKER 共写。
# 共写不构成越权：共写方产出同类文件，且 .engine/reports/ 已有四角色共写先例（CR-017 D1）。
#
# D3.3 匹配语义：**每一条都 `^…$` 双向锚定**，两种形态之一——
#   目录前缀：^deliverables/${req}/src/.+$      尾部 .+ 确保不匹配目录自身，
#                                              左锚拒 x/deliverables/${req}/src/a.ts 嵌套伪造
#   文件全名：^deliverables/${req}/\.engine/proposal\.md$
# 无 `$` 锚时文件名退化为前缀（`.state.md.evil`、`.state.md/child.md` 全部命中），
# 无 `^` 锚时嵌套伪造路径命中；两者都把单文件例外放大成目录直通（CR-016/CR-017 已详述）。
# `-evil` 后缀类绕过（deliverables-evil/、tests-evil/）由 `^deliverables/${req}/` 前缀
# 与 ${req} 的字符集（D1.1，经 validate-slug.sh 强制）共同排除。
check_permission() {
  local role=$1 file=$2 req=$3

  case "$role" in
    ORCHESTRATOR)
      [[ "$file" =~ ^deliverables/${req}/\.engine/\.state\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/handoffs/.+\.md$ ]] && return 0
      # 回报路径（CR-017 D1）：驳回轮次与 SubAgent 失联时的兜底代填仍需此权限。
      # 代填由此不再是绕过守卫，而是显式兜底。
      is_report "$file" "$req" && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/plan-action\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/SR.*-record\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/lessons\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/proposal\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/archive-manifest\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/baselines/.+$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/process\.log$ ]] && return 0
      # 质量门禁报告：Orchestrator 执行门禁命令后归因填写（templates/quality-gate-report-template.md、
      # agents/orchestrator.md 均如此声明），与 WORKER 共写。等价于原 L223 的
      # WORKER-apply-quality-gate-report 条在新命名下的形态，不是新增权限。
      [[ "$file" =~ ^deliverables/${req}/\.engine/quality-gate-report\.md$ ]] && return 0
      # 归档产出（ARC-5~8）：docs/metrics.md、docs/lessons-learned.md、docs/kb/、
      # change 模式 archiveMerge() 写 docs/spec/。原实现靠 ORCHESTRATOR-*.md 前缀 +
      # 一个取出后从未被使用的 phase 变量（既有死逻辑），现改为显式声明。
      [[ "$file" =~ ^deliverables/${req}/docs/.+$ ]] && return 0
      # ARC-5 回归套件沉淀：仅此一个 tests/ 下的文件，不放大为 tests/ 目录直通。
      [[ "$file" =~ ^deliverables/${req}/tests/regression-suite\.md$ ]] && return 0
      # 全局指针（活跃交付物切换）。此条不带 ${req}，故须单独双向锚定。
      [[ "$file" =~ ^deliverables/\.state\.md$ ]] && return 0
      ;;
    THINKER)
      # 规格文档（D2.1）：docs/spec/ 下的 requirement-spec.md、design.md、design-overview.md、
      # slide-spec.md 等。目录前缀条目不限扩展名，故 CR-016 R5 的 .ipynb 诉求由目录归属承载——
      # notebook 落在 docs/spec/ 或 assets/ 内自然放行，无需再枚举扩展名。
      [[ "$file" =~ ^deliverables/${req}/docs/spec/.+$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.archiveignore$ ]] && return 0
      # 设计稿/wireframes（ppt track visual 相位产出 assets/wireframes/），与 WORKER 共写
      [[ "$file" =~ ^deliverables/${req}/assets/.+$ ]] && return 0
      # 验证策略（原 THINKER-propose-verify-strategy.md）：消费者是引擎的集成预检，故归引擎态
      [[ "$file" =~ ^deliverables/${req}/\.engine/verify-strategy\.md$ ]] && return 0
      # 完成回报（CR-017 D1）：本交付物 .engine/reports/*.report.md。无内容判据，
      # 不放大到 handoffs/ 等其他引擎态文件——它们不在此正则内。
      is_report "$file" "$req" && return 0
      # 交还例外：仅本交付物的 .state.md，且本次写入把流程交还给 ORCHESTRATOR。
      # 不放大为引擎态直通——handoffs/、plan-action.md 等不在此正则内，
      # 即使写入内容含交还标记也落到原有拒绝路径。
      # 正则须 ^…$ 双向锚定（$file 已是归一化的仓库相对路径）：无 $ 锚时 .state.md 退化为
      # 前缀，.state.md.evil / .state.mdX / .state.md/child.md 全部命中例外；无 ^ 锚时
      # x/deliverables/${req}/.engine/.state.md 这类嵌套伪造路径同样命中。两者都把
      # 「单个 state 文件的状态机边」放大成 .engine/ 目录直通。
      [[ "$file" =~ ^deliverables/${req}/\.engine/\.state\.md$ ]] && is_handback && return 0
      ;;
    WORKER)
      # 项目代码与资源（D3.1）。原否定式谓词「产品区下不含其他角色前缀者皆可写」整体删除：
      # 去前缀后它退化为产品区全通。新表下 WORKER **不可写 docs/**——规格文档的写权归
      # THINKER（产出）与 ORCHESTRATOR（归档）。
      [[ "$file" =~ ^deliverables/${req}/src/.+$ ]] && return 0
      # tests/ 与 VERIFIER 共写：Worker 写实现测试（TDD 的 Red 步）、Verifier 写回归测试，
      # 这是 skills/mh-build/SKILL.md 的既有分工。
      [[ "$file" =~ ^deliverables/${req}/tests/.+$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/deploy/.+$ ]] && return 0
      # assets/ 与 THINKER 共写：Thinker 出 wireframes/设计稿，Worker 出运行期静态资源
      [[ "$file" =~ ^deliverables/${req}/assets/.+$ ]] && return 0
      # 产品区根的项目配置文件与 ppt 单文件产出（D3.2 全名白名单，非模式匹配）
      is_product_root_file "$file" "$req" && return 0
      # 代码报告与质量门禁报告（原 WORKER-apply-code-report-t{N}.md /
      # WORKER-apply-quality-gate-report.md）：消费者是门禁脚本，故归引擎态平铺
      [[ "$file" =~ ^deliverables/${req}/\.engine/code-report-[a-z0-9-]+\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/quality-gate-report\.md$ ]] && return 0
      # 完成回报（CR-017 D1），口径同 THINKER 分支
      is_report "$file" "$req" && return 0
      # 交还例外，锚定口径同 THINKER 分支
      [[ "$file" =~ ^deliverables/${req}/\.engine/\.state\.md$ ]] && is_handback && return 0
      ;;
    VERIFIER)
      # 回归测试，与 WORKER 共写（见 WORKER 分支说明）
      [[ "$file" =~ ^deliverables/${req}/tests/.+$ ]] && return 0
      # 测试报告（原 VERIFIER-apply-final-test-report.md / -temp-test-report.md）：
      # 消费者是 verify-qa.sh / verify-code-review.sh 门禁，故归引擎态平铺
      [[ "$file" =~ ^deliverables/${req}/\.engine/final-test-report\.md$ ]] && return 0
      [[ "$file" =~ ^deliverables/${req}/\.engine/temp-test-report\.md$ ]] && return 0
      # 完成回报（CR-017 D1），口径同 THINKER 分支
      is_report "$file" "$req" && return 0
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
  if check_permission "$ROLE" "$NORM_PATH" "$PROJECT"; then
    ALLOWED=true
    break
  fi
done

if [[ "$ALLOWED" == "false" ]]; then
  echo "BLOCKED: ${CURRENT_ROLES} 无权写入 ${FILE_PATH}"
  echo "请通过 handoff 派发给有权限的角色处理。"
  exit 2
fi

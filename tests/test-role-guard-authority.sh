#!/bin/bash
# test-role-guard-authority.sh — CR-016 授权模型回归测试（Tester 独占）
# 用法: bash tests/test-role-guard-authority.sh
# 退出码: 0=全部通过, 1=有失败
#
# 与 tests/test-role-guard.sh 的分工：那份覆盖既有白名单/归一化口径，本份覆盖
# CR-016 新增的授权模型——派发/交还状态轨迹、交还谓词的内容判据、路径归属路由、
# NotebookEdit 通道、以及轨迹用例自身的元验收（AX-10）。
#
# 隔离策略：所有 deliverables 分支断言在**沙箱仓库**内执行（cp 一份守卫脚本，
# 其 ROOT 由 BASH_SOURCE 推导为沙箱根）。原因有二：
#   1. 守卫用 `find deliverables -maxdepth 3 | head -1` 定位活跃 state，
#      在真实仓库内建夹具会与并发运行的其他套件互相夺取 head -1；
#   2. AX-10 需要在同一夹具上换用改动前的守卫副本，沙箱是唯一干净做法。

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# 元验收基线**按被验性质选取**，不随 CR 号统一前移：
# 本节各条要证明的是「CR-016 引入的交还/覆盖面/scope 判据仍有鉴别力」，
# 这些性质在 156c49a（CR-016 之前）才 FAIL，在 85a9912（CR-017 后的 HEAD）已全部具备。
# 若把基线统一改到 85a9912，三条断言会因「新旧同为 PASS」而恒假——
# 那不是实现退化，是选错了对照组。CR-018 自身新增性质（指针定位不退化为扫描）
# 的对照组是 85a9912，单列在下方 AX-12。
BASELINE_REF="${BASELINE_REF:-156c49a}"

SB="$(mktemp -d)"
MH_DEV_RUNTIME="$SB/.mh-dev"
export MH_DEV_RUNTIME
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/scripts" "$SB/deliverables" "$MH_DEV_RUNTIME"
cp "$REPO/scripts/role-guard.sh" "$SB/scripts/role-guard.sh"
# CR-018 D1.3：守卫消费侧独立校验 project，会调用同目录的 validate-slug.sh。
# 沙箱若只拷守卫，该调用失败会被 `if ! SLUG_ERR=$(...)` 判为校验不通过而 exit 2，
# 使所有放行类断言假失败。故依赖脚本须一并入沙箱。
cp "$REPO/scripts/validate-slug.sh" "$SB/scripts/validate-slug.sh"
git -C "$REPO" show "${BASELINE_REF}:scripts/role-guard.sh" > "$SB/scripts/role-guard.baseline.sh" 2>/dev/null

GUARD="$SB/scripts/role-guard.sh"
BASELINE_GUARD="$SB/scripts/role-guard.baseline.sh"

PASS=0
FAIL=0
TOTAL=0
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()  { echo -e "  ${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
bad() { echo -e "  ${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }

# --- 夹具 ---

# 写 REQ state；不重置磁盘则用 seed_state 一次、后续用 poke_state 改单字段，
# 以表达「派发→交还」的状态轨迹（既有 setup_state 每次重置，无法表达轨迹）。
seed_state() {
  local role=$1 req=${2:-test-proj} phase=${3:-propose}
  mkdir -p "$SB/deliverables/$req/.engine/handoffs"
  # CR-018 D3.4：守卫以全局指针 deliverables/.state.md 的 project 定位活跃交付物
  # （不再扫描文件系统），故夹具须同时写指针，否则守卫在形态「指针缺失」下 exit 0 放行，
  # 所有拒绝类断言会因放行而假通过/假失败。
  printf 'project: %s\n' "$req" > "$SB/deliverables/.state.md"
  cat > "$SB/deliverables/$req/.engine/.state.md" << EOF
project: ${req}
phase: ${phase}
current_step: THINK-DESIGN
current_role: ${role}
repair_round: 0
last_updated: "2026-08-13T10:00:00Z"
EOF
}

# 只改 current_role，保留文件其余内容（模拟守卫放行后 Agent 真实落盘的效果）
poke_role() {
  local role=$1 req=${2:-test-proj}
  local f="$SB/deliverables/$req/.engine/.state.md"
  awk -v r="$role" '/^current_role:/{print "current_role: " r; next} {print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

raw_state() {
  local body=$1 req=${2:-test-proj}
  mkdir -p "$SB/deliverables/$req/.engine/handoffs"
  printf 'project: %s\n' "$req" > "$SB/deliverables/.state.md"
  printf '%s' "$body" > "$SB/deliverables/$req/.engine/.state.md"
}

clear_req() { rm -rf "$SB/deliverables"; mkdir -p "$SB/deliverables"; }

set_mhdev() {
  local phase=$1 scope=$2 track=${3:-formal}
  mkdir -p "$MH_DEV_RUNTIME"
  cat > "$MH_DEV_RUNTIME/state.json" << EOF
{"workflow":"mh-dev","phase":"${phase}","approved_scope":${scope},"track":"${track}"}
EOF
}

clear_mhdev() { rm -rf "$MH_DEV_RUNTIME"; mkdir -p "$MH_DEV_RUNTIME"; }

# 携带写入内容的 hook 调用：AC-02/AX-02/AX-03 依赖 content / new_string，
# 既有 run_hook() 只发 file_path，无法表达交还判据。
# 用法: hook <guard> <tool> <path-key> <path> [<content-key> <content>]
hook() {
  local guard=$1 tool=$2 pkey=$3 pval=$4 ckey=${5:-} cval=${6:-}
  local json
  if [ -n "$ckey" ]; then
    json=$(jq -nc --arg t "$tool" --arg pk "$pkey" --arg pv "$pval" --arg ck "$ckey" --arg cv "$cval" \
      '{tool_name:$t, tool_input:(({} | .[$pk]=$pv) + ({} | .[$ck]=$cv))}')
  else
    json=$(jq -nc --arg t "$tool" --arg pk "$pkey" --arg pv "$pval" \
      '{tool_name:$t, tool_input:({} | .[$pk]=$pv)}')
  fi
  printf '%s' "$json" | bash "$guard" 2>&1
}

# expect <want-exit> <desc> <tool> <path-key> <path> [<content-key> <content>]
expect() {
  local want=$1 desc=$2; shift 2
  TOTAL=$((TOTAL + 1))
  local out code
  out=$(hook "$GUARD" "$@")
  code=$?
  if [ "$code" = "$want" ]; then
    ok "$desc"
  else
    bad "$desc (want exit=$want, got exit=$code)"
    echo "        output: ${out}"
  fi
}

# 写入内容形态的简写：Write + content 到本需求 state
expect_state_write() {
  local want=$1 desc=$2 content=$3 req=${4:-test-proj}
  expect "$want" "$desc" Write file_path "deliverables/$req/.engine/.state.md" content "$content"
}

echo "=== CR-016 role-guard 授权模型回归测试 ==="
echo "沙箱: $SB"

# ============================================================
# AC-01: 状态轨迹（派发 → 交还）两次写入均须 exit 0
# ============================================================
# 关键：第二次断言前不重置磁盘。磁盘此刻是被派发角色，若守卫读磁盘旧值判交还，
# 判据永不成立 → 单向闭锁，调度循环卡死。这是 CR-016 要修的核心缺陷。
echo ""
echo "--- AC-01: 派发/交还状态轨迹 ---"

# trajectory <role> —— 派发给 role 再由 role 交还，两步均须放行
trajectory() {
  local role=$1 guard=${2:-$GUARD}
  local rc1 rc2
  clear_req
  seed_state "ORCHESTRATOR"
  hook "$guard" Write file_path "deliverables/test-proj/.engine/.state.md" \
    content "$(printf 'project: test-proj\nphase: propose\ncurrent_role: %s\n' "$role")" > /dev/null 2>&1
  rc1=$?
  # 守卫放行后 Agent 真实落盘：磁盘 current_role 变为被派发角色
  poke_role "$role"
  hook "$guard" Write file_path "deliverables/test-proj/.engine/.state.md" \
    content "$(printf 'project: test-proj\nphase: propose\ncurrent_role: ORCHESTRATOR\n')" > /dev/null 2>&1
  rc2=$?
  echo "$rc1 $rc2"
}

for role in THINKER WORKER VERIFIER "THINKER,VERIFIER" "WORKER,VERIFIER"; do
  TOTAL=$((TOTAL + 1))
  read -r rc1 rc2 <<< "$(trajectory "$role")"
  if [ "$rc1" = "0" ] && [ "$rc2" = "0" ]; then
    ok "AC-01: 轨迹 ORCHESTRATOR→${role}→ORCHESTRATOR 两次写入均放行"
  else
    bad "AC-01: 轨迹 ORCHESTRATOR→${role}→ORCHESTRATOR (派发 exit=$rc1, 交还 exit=$rc2, 均应为 0)"
  fi
done

# ============================================================
# AC-02: 交还判据取本次写入的新内容，而非磁盘旧值
# ============================================================
echo ""
echo "--- AC-02: 交还判据取本次写入新内容 ---"
clear_req
seed_state "THINKER"
# 磁盘恒为 THINKER（派发后的真实形态），下列断言全部在该磁盘状态下进行
expect_state_write 0 "AC-02: Write content 含完整交还内容 → 放行" \
  "$(printf 'project: test-proj\nphase: propose\ncurrent_role: ORCHESTRATOR\nrepair_round: 0\n')"
# 交还例外只接受 Write（audit F-01 后的路线 B）：Edit 写本需求 state 一律拒绝，
# 即使 new_string 整行就是合法交还行。理由不是「这个片段有问题」，而是
# **守卫无法从 Edit 载荷得知合并结果**——放行任何 Edit 都等于用片段的生效值
# 替代合并后的生效值作判据，而这两者可被跨行 old_string 拉开（见下方 F-01 断言组）。
expect 2 "AC-02: Edit new_string 整行为交还行 → 仍拒绝（交还例外只接受 Write）" \
  Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "current_role: ORCHESTRATOR"
expect 0 "AC-02: 交还行位于文件中段亦可判定" \
  Write file_path "deliverables/test-proj/.engine/.state.md" \
  content "$(printf 'project: test-proj\nphase: apply\ncurrent_step: X\ncurrent_role: ORCHESTRATOR\nrepair_round: 0\n')"

# 不变量（guards.md「交还谓词的接受集不得窄于读取端」）：
# 判据接受集必须 ⊇ 读取端 awk '{print $2}' 判为 ORCHESTRATOR 的集合。
expect_state_write 0 "AC-02: 值 + 行尾注释形态（state-template.md 的书写形态）" \
  "current_role: ORCHESTRATOR # 交还给 Orchestrator"
expect_state_write 0 "AC-02: 多空格分隔形态（读取端解析得出 ORCHESTRATOR）" \
  "current_role:    ORCHESTRATOR"
expect_state_write 0 "AC-02: 制表符分隔形态" \
  "$(printf 'current_role:\tORCHESTRATOR')"

# ============================================================
# AX-02: 伪交还须被拒（内容不构成交还）
# ============================================================
echo ""
echo "--- AX-02: 伪交还拒绝 ---"
clear_req
seed_state "THINKER"
expect_state_write 2 "AX-02: 新内容 current_role 仍为 THINKER → 拒绝" \
  "$(printf 'project: test-proj\ncurrent_role: THINKER\n')"
expect_state_write 2 "AX-02: 新内容改为 WORKER（横向夺权）→ 拒绝" \
  "$(printf 'project: test-proj\ncurrent_role: WORKER\n')"
expect_state_write 2 "AX-02: 新内容不含 current_role 行 → 拒绝" \
  "$(printf 'project: test-proj\nphase: apply\nrepair_round: 1\n')"
# 路线 B 后此条由工具判据拦下（不再取决于 new_string 内容），保留作回归；
# 「内容与 current_role 无关须拒」的性质由上方 Write 侧同形态断言承载。
expect 2 "AX-02: Edit new_string 与 current_role 无关 → 拒绝" \
  Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "repair_round: 1"
expect 2 "AX-02: Write 无 content 键（无法判定交还）→ 拒绝" \
  Write file_path "deliverables/test-proj/.engine/.state.md"

# ============================================================
# AX-03: 伪造交还标记须被拒（判据锚定行首字段，非子串匹配）
# ============================================================
echo ""
echo "--- AX-03: 伪造交还标记拒绝 ---"
clear_req
seed_state "THINKER"
# 各例的实际生效字段仍为 THINKER，仅正文出现形似交还的文本
expect_state_write 2 "AX-03: 注释行 '# current_role: ORCHESTRATOR' → 拒绝" \
  "$(printf '# current_role: ORCHESTRATOR\ncurrent_role: THINKER\n')"
expect_state_write 2 "AX-03: 引号包裹 'current_role: \"ORCHESTRATOR\"' → 拒绝" \
  "$(printf 'current_role: "ORCHESTRATOR"\n')"
expect_state_write 2 "AX-03: 近名字段 current_role_backup: ORCHESTRATOR → 拒绝" \
  "$(printf 'current_role_backup: ORCHESTRATOR\ncurrent_role: THINKER\n')"
expect_state_write 2 "AX-03: 行首带缩进的交还行 → 拒绝" \
  "$(printf '  current_role: ORCHESTRATOR\ncurrent_role: THINKER\n')"
expect_state_write 2 "AX-03: YAML 列表项 '- current_role: ORCHESTRATOR' → 拒绝" \
  "$(printf -- '- current_role: ORCHESTRATOR\ncurrent_role: THINKER\n')"
# 值侧边界：读取端 awk 对下列形态解析不出裸 ORCHESTRATOR，判据须同样拒绝
expect_state_write 2 "AX-03: 值为 ORCHESTRATORX（值侧后缀）→ 拒绝" \
  "current_role: ORCHESTRATORX"
expect_state_write 2 "AX-03: 值为 THINKER,ORCHESTRATOR（多角色夹带）→ 拒绝" \
  "current_role: THINKER,ORCHESTRATOR"
expect_state_write 2 "AX-03: 值为 ORCHESTRATOR,THINKER（提权夹带）→ 拒绝" \
  "current_role: ORCHESTRATOR,THINKER"
expect_state_write 2 "AX-03: 冒号后无空白 current_role:ORCHESTRATOR → 拒绝" \
  "current_role:ORCHESTRATOR"
expect_state_write 2 "AX-03: 小写 orchestrator → 拒绝" \
  "current_role: orchestrator"
expect_state_write 2 "AX-03: 正文散文提及 current_role: ORCHESTRATOR 但非行首 → 拒绝" \
  "$(printf '说明：交还时写 current_role: ORCHESTRATOR 即可\ncurrent_role: THINKER\n')"

# ============================================================
# AX-02/AX-03: 多 current_role 行的**排列维度**（audit P0-1 的漏检根因）
# ============================================================
# 为什么必须显式分排列：存在性量词（`grep -qE '^current_role:...ORCHESTRATOR'`，任一行匹配即放行）
# 与读取端首行语义（`grep '^current_role:' | head -1 | awk '{print $2}'`）**只在「真交还行不在首行」
# 的排列上结论不同**。真值在前的排列两种实现都放行，故它恒绿、无鉴别力。
# 上一轮 217 项断言里 5 处双 current_role 载荷全是「诱饵在前、真值在后」——但那些断言期望值写的是
# 拒绝，恰好也是首行语义的结论，于是缺陷版本仍全绿：**期望值对了，覆盖的排列却漏了一半**。
# 本节的判定口径统一为「首行首值是否等于 ORCHESTRATOR」，即读取端将要生效的角色：
#   真值在首行 → 落盘后生效角色确为 ORCHESTRATOR → 合法交还 → exit 0
#   真值不在首行 → 落盘后生效角色是别的角色 → 横向夺权 → exit 2
echo ""
echo "--- AX-02/AX-03: 多 current_role 行的排列维度（真值在前 / 真值在后） ---"
clear_req
seed_state "THINKER"

# perm_pair <首行值> —— 同一对角色值的两种排列各断言一次，成对出现才叫覆盖了维度。
# 真值在后一律 2，真值在前一律 0；两条断言只差行序，任何单侧实现必在其中一条上失败。
perm_pair() {
  local decoy=$1
  expect_state_write 2 "AX-03: 排列[真值在后] 首行 ${decoy} + 末行 ORCHESTRATOR → 拒绝（生效角色为 ${decoy}）" \
    "$(printf 'current_role: %s\ncurrent_role: ORCHESTRATOR\n' "$decoy")"
  expect_state_write 0 "AX-02: 排列[真值在前] 首行 ORCHESTRATOR + 末行 ${decoy} → 放行（生效角色为 ORCHESTRATOR）" \
    "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: %s\n' "$decoy")"
}
# decoy 取值须是「非 ORCHESTRATOR 的值」——decoy=ORCHESTRATOR 时两行同值，
# 首行本就是合法交还行，两种排列退化为同一情形，不构成排列对。
for decoy in WORKER VERIFIER THINKER "THINKER,ORCHESTRATOR" "ORCHESTRATOR,THINKER" ORCHESTRATORX; do
  perm_pair "$decoy"
done
# 退化情形单独断言：两行皆 ORCHESTRATOR，首行生效即 ORCHESTRATOR，属合法交还
expect_state_write 0 "AX-02: 两行皆 ORCHESTRATOR（退化情形）→ 放行" \
  "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: ORCHESTRATOR\n')"

# 夹带其他字段：真交还行不在首个 current_role 行位置这一点不因中间插入无关字段而改变
expect_state_write 2 "AX-03: 排列[真值在后] 字段夹带 首 WORKER…末 ORCHESTRATOR → 拒绝" \
  "$(printf 'project: test-proj\ncurrent_role: WORKER\nphase: apply\nrepair_round: 1\ncurrent_role: ORCHESTRATOR\n')"
expect_state_write 0 "AX-02: 排列[真值在前] 字段夹带 首 ORCHESTRATOR…末 WORKER → 放行" \
  "$(printf 'project: test-proj\ncurrent_role: ORCHESTRATOR\nphase: apply\nrepair_round: 1\ncurrent_role: WORKER\n')"

# 三行形态：中间行是否为真交还行不影响结论，判据只看首行
expect_state_write 2 "AX-03: 三行 首 WORKER / 中 ORCHESTRATOR / 末 WORKER → 拒绝" \
  "$(printf 'current_role: WORKER\ncurrent_role: ORCHESTRATOR\ncurrent_role: WORKER\n')"
expect_state_write 2 "AX-03: 三行 首 THINKER / 中 WORKER / 末 ORCHESTRATOR → 拒绝" \
  "$(printf 'current_role: THINKER\ncurrent_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
expect_state_write 0 "AX-02: 三行 首 ORCHESTRATOR / 中 WORKER / 末 ORCHESTRATOR → 放行" \
  "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"

# 诱饵行为非行首形态（缩进/注释）时，首个 ^current_role: 行才是生效行——
# 与上面的排列断言互补：验证「首行」是按 ^ 锚定后的首个匹配行，而非文件物理首行。
expect_state_write 0 "AX-02: 缩进诱饵在前 + 行首 ORCHESTRATOR → 放行（缩进行不被 ^ 命中）" \
  "$(printf '  current_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
expect_state_write 2 "AX-03: 注释诱饵在前 + 行首 WORKER + 末行 ORCHESTRATOR → 拒绝" \
  "$(printf '# current_role: ORCHESTRATOR\ncurrent_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"

# Edit 通道：路线 B 下**两种排列都拒**，不再有排列之分。
# 这与 Write 侧不同，且差异本身要被断言——否则「Edit 恰好也拒」会被误读为排列判据生效，
# 而实际生效的是工具判据。真值在前的 Edit 载荷在 Write 侧是放行形态，此处须拒，
# 正是「拒绝来自工具判据而非内容判据」的直接证据。
expect 2 "AX-02: Edit 排列[真值在后] 首 WORKER + 末 ORCHESTRATOR → 拒绝" \
  Edit file_path "deliverables/test-proj/.engine/.state.md" \
  new_string "$(printf 'current_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
expect 2 "AX-02: Edit 排列[真值在后] 首 THINKER,ORCHESTRATOR + 末 ORCHESTRATOR → 拒绝" \
  Edit file_path "deliverables/test-proj/.engine/.state.md" \
  new_string "$(printf 'current_role: THINKER,ORCHESTRATOR\ncurrent_role: ORCHESTRATOR\n')"
expect 2 "AX-02: Edit 排列[真值在前] 首 ORCHESTRATOR + 末 WORKER → 亦拒绝（同载荷 Write 侧放行，故拒绝来自工具判据）" \
  Edit file_path "deliverables/test-proj/.engine/.state.md" \
  new_string "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER\n')"

# 同一载荷在两个工具上的结论对照：Write 放行 / Edit 拒绝。
# 单看 Edit 全拒无法区分「工具判据生效」与「内容判据把它们都判成伪交还」，
# 故必须与 Write 侧同载荷成对断言。
TOTAL=$((TOTAL + 1))
same_payload="$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER\n')"
hook "$GUARD" Write file_path "deliverables/test-proj/.engine/.state.md" content "$same_payload" >/dev/null 2>&1
w_code=$?
hook "$GUARD" Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "$same_payload" >/dev/null 2>&1
e_code=$?
if [ "$w_code" = "0" ] && [ "$e_code" = "2" ]; then
  ok "AC-02/AX-02: 同一交还载荷 Write exit=0 / Edit exit=2（工具判据是唯一差异）"
else
  bad "AC-02/AX-02: 工具判据未生效（Write exit=${w_code} 须 0，Edit exit=${e_code} 须 2）"
fi

# 工具判据的绕过尝试：判据读的是 TOOL_NAME，而 NEW_CONTENT 的取值链是
# `.content // .new_string`。若判据写成「载荷里有 content 键」而非「工具是 Write」，
# 则 Edit 带上 content 键即可绕过。此处确认判据锚定的是工具名。
expect 2 "AX-02: Edit 载荷改带 content 键 → 仍拒绝（判据锚定 TOOL_NAME 而非载荷键名）" \
  Edit file_path "deliverables/test-proj/.engine/.state.md" content "current_role: ORCHESTRATOR"
# 反向：Write 只带 new_string 时仍应识别为交还（NEW_CONTENT 回退链覆盖两个键名），
# 否则合作者按 Write 语义写入却被判伪交还，是 P0-1 修复时反复强调的「更严」侧违反。
expect 0 "AC-02: Write 只带 new_string 键 → 放行（NEW_CONTENT 回退链不因工具判据失效）" \
  Write file_path "deliverables/test-proj/.engine/.state.md" new_string "current_role: ORCHESTRATOR"
# NotebookEdit 指向 state：既无 content 也无交还资格，双重拒绝
expect 2 "AX-02: NotebookEdit 指向 .engine/.state.md → 拒绝（无交还资格且 NEW_CONTENT 为空）" \
  NotebookEdit notebook_path "deliverables/test-proj/.engine/.state.md"

# ------------------------------------------------------------
# AX-02: Edit 片段判据 vs 合并后生效值的分歧（F-01，已由路线 B 结构性关闭）
# ------------------------------------------------------------
# 缺陷形态：守卫只看到 new_string，看不到 old_string，也看不到合并后的文件，故它判
# 「片段的首个 ^current_role: 行」，而落盘生效值由**合并后文件**的首个该行决定。
# 当 old_string 跨行、从上一行中部吃到 current_role 行时，片段首行会被拼进上一行残段
# （变成 `current_step: THINK-current_role: ORCHESTRATOR`，不再行首匹配），
# 于是片段里的「诱饵」在合并后升为生效行——排列在合并这一步被反转。
# 与 P0-1 同源：P0-1 的分歧在「怎么解析」（量词），F-01 的分歧在「解析谁」（判定对象）。
#
# 路线 B 的关闭方式不是逐形态堵，而是取消 Edit 的交还例外资格：守卫无法从 Edit 载荷
# 得知合并结果，故不以片段判据放行任何 Edit。下列断言因此**不依赖枚举完所有跨行形态**——
# 它们验证的是同一条结构性性质在三种已知最危险形态上的体现。
# 每条仍打印合并后生效角色，作为「若放行则后果为何」的证据留档。
# 鉴别力由下方 AX-10 的「移除 TOOL_NAME 判据」突变体保证。
edit_merge_probe() {
  local want=$1 desc=$2 old=$3 new=$4
  TOTAL=$((TOTAL + 1))
  clear_req
  seed_state "THINKER"
  local f="$SB/deliverables/test-proj/.engine/.state.md"
  local code merged eff
  hook "$GUARD" Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "$new" >/dev/null 2>&1
  code=$?
  # 模拟 Edit 的精确单次替换，取合并后读取端生效值
  merged=$(python3 -c '
import sys
p,old,new=sys.argv[1:4]
s=open(p,encoding="utf-8").read()
if s.count(old)!=1: sys.exit("NONUNIQUE")
sys.stdout.write(s.replace(old,new,1))
' "$f" "$old" "$new")
  eff=$(printf '%s\n' "$merged" | grep '^current_role:' | head -1 | awk '{print $2}')
  [ -n "$eff" ] || eff="<空>"
  if [ "$code" = "$want" ]; then
    ok "$desc"
  else
    bad "$desc (want exit=$want, got exit=${code}, 合并后生效角色=${eff})"
  fi
}

echo ""
echo "--- AX-02: Edit 片段判据与合并后生效值的分歧 ---"
edit_merge_probe 2 "AX-02: Edit 跨行 old_string + 片段末行 THINKER,ORCHESTRATOR → 须拒绝（合并后生效 THINKER,ORCHESTRATOR = 夺 ORCHESTRATOR 全权）" \
  "$(printf 'DESIGN\ncurrent_role: THINKER')" \
  "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: THINKER,ORCHESTRATOR')"
edit_merge_probe 2 "AX-02: Edit 跨行 old_string + 片段末行 WORKER → 须拒绝（合并后生效 WORKER = 横向夺权）" \
  "$(printf 'DESIGN\ncurrent_role: THINKER')" \
  "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER')"
edit_merge_probe 2 "AX-02: Edit 跨行 old_string 使 current_role 行整体消失 → 须拒绝（合并后无生效角色，守卫在该 state 上整体失效）" \
  "$(printf 'DESIGN\ncurrent_role: THINKER')" \
  "current_role: ORCHESTRATOR"

# Edit 通道整体拒绝的覆盖：路线 B 是「取消工具资格」而非「堵形态」，故断言须覆盖
# 连合法形态也拒。三种持权角色 × 单行整行交还，确认无角色能借 Edit 交还。
clear_req
for holder in THINKER WORKER VERIFIER; do
  clear_req
  seed_state "$holder"
  expect 2 "AX-02: ${holder} 持权 Edit 整行交还 → 拒绝（Edit 无交还例外资格）" \
    Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "current_role: ORCHESTRATOR"
  expect 0 "AC-02: ${holder} 持权 Write 同等内容 → 放行（交还通道仍畅通，未变成单向闭锁）" \
    Write file_path "deliverables/test-proj/.engine/.state.md" content "current_role: ORCHESTRATOR"
done

# 其余持权角色下排列维度同样成立（夺权者可以是任一被派发角色）
for holder in WORKER VERIFIER "THINKER,VERIFIER"; do
  clear_req
  seed_state "$holder"
  expect_state_write 2 "AX-03: ${holder} 持权 排列[真值在后] 首 WORKER + 末 ORCHESTRATOR → 拒绝" \
    "$(printf 'current_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
  expect_state_write 0 "AX-02: ${holder} 持权 排列[真值在前] 首 ORCHESTRATOR + 末 WORKER → 放行" \
    "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER\n')"
done

# ============================================================
# AX-01 / AX-09: 交还例外不得放大为引擎态直通、不得跨需求
# ============================================================
echo ""
echo "--- AX-01: 交还例外不放大为引擎态直通 ---"
clear_req
seed_state "THINKER"
HB="$(printf 'project: test-proj\ncurrent_role: ORCHESTRATOR\n')"
for f in handoffs/x.md plan-action.md SR1-record.md lessons.md process.log archive-manifest.md; do
  expect 2 "AX-01: 含交还标记写 .engine/${f} → 拒绝" \
    Write file_path "deliverables/test-proj/.engine/${f}" content "$HB"
done
expect 2 "AC-03: 全局 deliverables/.state.md 含交还标记 → 拒绝（非本需求引擎态）" \
  Write file_path "deliverables/.state.md" content "$HB"

echo ""
echo "--- AX-09: 交还例外不跨需求 ---"
expect 2 "AX-09: REQ001 持权写 deliverables/other-proj/.engine/.state.md（含交还标记）→ 拒绝" \
  Write file_path "deliverables/other-proj/.engine/.state.md" content "$HB"
# 路线 B 后 Edit 一律被工具判据拦下，故「跨需求」这条性质若只用 Edit 断言就成了
# 过定条件——它会因错误的原因通过。跨需求性质必须由能走到交还例外的工具（Write）承载，
# 且须覆盖排列维度，确认 project 不匹配时首行合法也不放行。
expect 2 "AX-09: 跨需求 Write 首行合法交还 → 拒绝（project 不匹配优先于交还例外）" \
  Write file_path "deliverables/other-proj/.engine/.state.md" \
  content "$(printf 'project: other-proj\ncurrent_role: ORCHESTRATOR\n')"
expect 2 "AX-09: 跨需求 Edit 交还形态同样拒绝（此处由工具判据拦下）" \
  Edit file_path "deliverables/other-proj/.engine/.state.md" new_string "current_role: ORCHESTRATOR"

# 交还例外的路径正则须锚定到 .state.md 结尾。当前实现写作
#   [[ "$file" =~ deliverables/${req}/\.engine/\.state\.md ]]
# 无 $ 锚，故 .state.md 是前缀而非全名：持权的 THINKER/WORKER/VERIFIER 只要在内容里
# 带上交还行，就能往 .engine/ 里新建 .state.md* 命名的任意文件——这正是 AX-01 要禁止的
# 「交还例外放大为引擎态直通」。基线（改动前）对同样路径一律 exit 2，属本 CR 引入的放大。
echo ""
echo "--- AX-01: .state.md 路径后缀伪造（交还例外须锚定全名） ---"
for role in THINKER WORKER VERIFIER; do
  clear_req
  seed_state "$role"
  for f in .state.md.evil .state.md.sh .state.mdX; do
    expect 2 "AX-01: ${role} 含交还标记写 .engine/${f} → 拒绝（路径非本需求 state 全名）" \
      Write file_path "deliverables/test-proj/.engine/${f}" content "$HB"
  done
done
clear_req
seed_state "THINKER"
expect 2 "AX-01: 含交还标记写嵌套伪造路径 x/deliverables/test-proj/.engine/.state.md → 拒绝" \
  Write file_path "deliverables/test-proj/x/deliverables/test-proj/.engine/.state.md" content "$HB"

# ============================================================
# AX-04: 交还标记不得改变其他路径的判定
# ============================================================
echo ""
echo "--- AX-04: 交还标记不影响非 state 路径判定 ---"
clear_req
seed_state "THINKER"
expect 0 "AX-04: 含交还标记写 docs/spec/x.md → 按 THINKER 白名单放行" \
  Write file_path "deliverables/test-proj/docs/spec/x.md" content "$HB"
expect 2 "AX-04: 含交还标记写 tests/x.md → 仍拒绝" \
  Write file_path "deliverables/test-proj/tests/x.md" content "$HB"
expect 2 "AX-04: 含交还标记写 src/x.js → 仍拒绝" \
  Write file_path "deliverables/test-proj/src/x.js" content "$HB"
expect 2 "AX-04: 含交还标记写 src/app.js（THINKER 无项目代码权）→ 仍拒绝" \
  Write file_path "deliverables/test-proj/src/app.js" content "$HB"

# ============================================================
# AC-06: NotebookEdit 纳入守卫
# ============================================================
echo ""
echo "--- AC-06: NotebookEdit 通道 ---"
clear_req
seed_state "THINKER"
expect 2 "AC-06: THINKER 持权 NotebookEdit 写 tests/x.ipynb → 拒绝" \
  NotebookEdit notebook_path "deliverables/test-proj/tests/x.ipynb"
expect 0 "AC-06: THINKER 持权 NotebookEdit 写 docs/spec/x.ipynb → 放行" \
  NotebookEdit notebook_path "deliverables/test-proj/docs/spec/x.ipynb"
# .ipynb 不承载流程状态，不参与交还例外
expect 2 "AC-06: NotebookEdit 指向 .engine/.state.md → 拒绝（不参与交还例外）" \
  NotebookEdit notebook_path "deliverables/test-proj/.engine/.state.md"
clear_req
seed_state "VERIFIER"
expect 0 "AC-06: VERIFIER 持权写 tests/x.ipynb → 放行" \
  NotebookEdit notebook_path "deliverables/test-proj/tests/x.ipynb"
expect 2 "AC-06: VERIFIER 持权写 docs/spec/x.ipynb → 拒绝" \
  NotebookEdit notebook_path "deliverables/test-proj/docs/spec/x.ipynb"
expect 2 "AC-06: NotebookEdit 含 .. 穿越 → 拒绝" \
  NotebookEdit notebook_path "deliverables/../evil.ipynb"

# ORCHESTRATOR 分支的 .ipynb 扩展名（P2-1）：白名单曾只锚定 .md，NotebookEdit 纳入守卫后
# ORCHESTRATOR 无法写自己前缀的 notebook。放开须只限本角色前缀，不得放大为跨角色。
# 覆盖矩阵是「持权角色 × 目标前缀」两维，单看 ORCHESTRATOR 持权放行不足以排除放大。
clear_req
seed_state "ORCHESTRATOR"
expect 0 "AC-06: ORCHESTRATOR 持权写 docs/x.ipynb → 放行（P2-1）" \
  NotebookEdit notebook_path "deliverables/test-proj/docs/x.ipynb"
expect 0 "AC-06: ORCHESTRATOR 持权写 docs/x.md → 放行（.md 未因加 .ipynb 而回归）" \
  NotebookEdit notebook_path "deliverables/test-proj/docs/x.md"
# CR-018 D3.1：ORCHESTRATOR 归属为整个 docs/（含 docs/spec/，change 模式 archiveMerge 写规格），
# 故 docs/spec/ 不再是 ORCHESTRATOR 的越权样本；越权样本取其确实无权的 src/ 与 assets/。
for f in src/x.ipynb assets/x.ipynb; do
  expect 2 "AC-06: ORCHESTRATOR 持权写 ${f} → 拒绝（放开不跨角色）" \
    NotebookEdit notebook_path "deliverables/test-proj/${f}"
done
for role in THINKER WORKER VERIFIER; do
  clear_req
  seed_state "$role"
  expect 2 "AC-06: ${role} 持权写 docs/x.ipynb → 拒绝（跨角色仍隔离）" \
    NotebookEdit notebook_path "deliverables/test-proj/docs/x.ipynb"
done

TOTAL=$((TOTAL + 1))
if grep -q '"matcher": "Write|Edit|NotebookEdit"' "$REPO/.claude/settings.json"; then
  ok "AC-06: .claude/settings.json 的 PreToolUse matcher 含 NotebookEdit"
else
  bad "AC-06: settings.json matcher 未含 NotebookEdit（通道静默漏覆盖）"
fi

# ============================================================
# AC-04 / AC-05: 两条流水线共存（路径归属路由）
# ============================================================
# 旧实现以「不存在活跃 REQ state」作为 mh-dev 分支进入条件：残留 REQ state 会
# 永久关闭框架治理入口。新实现按路径归属路由，两条路径集不相交，故可共存。
echo ""
echo "--- AC-04: 共存时框架路径仍由 mh-dev 治理 ---"
set_mhdev develop '["scripts/role-guard.sh"]' formal
for phase in propose apply done; do
  clear_req
  seed_state "THINKER" test-proj "$phase"
  expect 0 "AC-04: REQ state phase=${phase} 存在时写 scope 内 scripts/role-guard.sh → 放行" \
    Write file_path "scripts/role-guard.sh" content "x"
done
clear_req
seed_state "ORCHESTRATOR" test-proj done
expect 0 "AC-04: 终态 REQ state（ORCHESTRATOR/done）不关闭框架治理入口" \
  Write file_path "scripts/role-guard.sh" content "x"

echo ""
echo "--- AC-05: 共存时角色白名单结论不受 mh-dev state 影响 ---"
set_mhdev develop '["scripts/role-guard.sh"]' formal
clear_req
seed_state "THINKER"
expect 0 "AC-05: THINKER 写 docs/spec/design.md → 放行" \
  Write file_path "deliverables/test-proj/docs/spec/design.md" content "x"
expect 2 "AC-05: THINKER 写 .engine/temp-test-report.md → 拒绝" \
  Write file_path "deliverables/test-proj/.engine/temp-test-report.md" content "x"
expect 0 "AC-05: 共存时轨迹交还仍放行（两条流水线互不阻断）" \
  Write file_path "deliverables/test-proj/.engine/.state.md" content "$HB"

# ============================================================
# AX-05: approved_scope 不得被残留/畸形 REQ state 绕过
# ============================================================
echo ""
echo "--- AX-05: approved_scope 不可被 REQ state 绕过 ---"
set_mhdev develop '["scripts/role-guard.sh"]' formal
clear_req
expect 2 "AX-05: 无 REQ state 时写 scope 外 CLAUDE.md → 拒绝" \
  Write file_path "CLAUDE.md" content "x"
raw_state ""
expect 2 "AX-05: 空 REQ state 时写 scope 外 CLAUDE.md → 拒绝（旧实现此处被绕过）" \
  Write file_path "CLAUDE.md" content "x"
raw_state "$(printf 'project: test-proj\nphase: propose\n')"
expect 2 "AX-05: 缺 current_role 的 REQ state 时写 CLAUDE.md → 拒绝" \
  Write file_path "CLAUDE.md" content "x"
clear_req
seed_state "THINKER"
expect 2 "AX-05: 有效 REQ state 时写 scope 外 CLAUDE.md → 拒绝" \
  Write file_path "CLAUDE.md" content "x"
raw_state "$(printf 'phase: propose\ncurrent_role: THINKER\n')"
expect 2 "AX-05: 缺 project 的 REQ state 时写 CLAUDE.md → 拒绝" \
  Write file_path "CLAUDE.md" content "x"
raw_state "$(printf 'project: test-proj\nphase: propose\ncurrent_role: ATTACKER\n')"
expect 2 "AX-05: 未知角色 REQ state 时写 CLAUDE.md → 拒绝" \
  Write file_path "CLAUDE.md" content "x"

# ============================================================
# AX-06: 默认会话不得被误拦（CLAUDE.md §6）
# ============================================================
echo ""
echo "--- AX-06: 默认会话透明 ---"
clear_mhdev
clear_req
for p in CLAUDE.md any/file.md scripts/foo.sh .claude/settings.json; do
  expect 0 "AX-06: 无 mh-dev 无 REQ state 时写 ${p} → 放行" Write file_path "$p" content "x"
done
# 畸形 REQ state 在无 mh-dev 治理时不得拦截 deliverables 写入
raw_state ""
expect 0 "AX-06: 空 REQ state 无治理时写 deliverables 产出 → 放行" \
  Write file_path "deliverables/test-proj/docs/spec/x.md" content "x"
raw_state "$(printf 'project: test-proj\nphase: propose\n')"
expect 0 "AX-06: 缺 current_role 时放行（与既有断言同口径）" \
  Write file_path "deliverables/test-proj/docs/spec/x.md" content "x"
raw_state "$(printf 'phase: propose\ncurrent_role: THINKER\n')"
expect 0 "AX-06: 缺 project 时放行" \
  Write file_path "deliverables/test-proj/docs/spec/x.md" content "x"
for r in PM ATTACKER; do
  raw_state "$(printf 'project: test-proj\nphase: propose\ncurrent_role: %s\n' "$r")"
  expect 2 "AX-06: 未知角色 ${r} → 拒绝 deliverables 写入（fail-closed，与既有断言一致）" \
    Write file_path "deliverables/test-proj/docs/spec/x.md" content "x"
done

# ============================================================
# AX-07 / AX-08: mh-dev 分支既有安全性质 + 归属路由前缀语义
# ============================================================
echo ""
echo "--- AX-07: mh-dev 分支安全性质不回归 ---"
clear_req
set_mhdev develop '["scripts/role-guard.sh","docs/m/"]' formal
expect 2 "AX-07: 未列出路径 evil/x.md → 拒绝" Write file_path "evil/x.md" content "x"
expect 2 "AX-07: 仓库外绝对路径 /tmp/evil.sh → 拒绝" Write file_path "/tmp/evil.sh" content "x"
expect 2 "AX-07: 含 .. 穿越 ${REPO}/../evil.sh → 拒绝" Write file_path "${REPO}/../evil.sh" content "x"
expect 2 "AX-07: 后缀伪造 scripts/role-guard.sh.evil → 拒绝" \
  Write file_path "scripts/role-guard.sh.evil" content "x"
expect 2 "AX-07: docs/m-evil/x.md 对 docs/m/ 条目 → 拒绝（目录前缀非子串）" \
  Write file_path "docs/m-evil/x.md" content "x"
expect 0 "AX-07: docs/m/ok.md 命中目录前缀条目 → 放行" \
  Write file_path "docs/m/ok.md" content "x"
set_mhdev develop '["scripts/role-guard.sh"]' light
expect 2 "AX-07: light 轨写治理关键路径 → 拒绝（消息含 formal）" \
  Write file_path "scripts/role-guard.sh" content "x"
TOTAL=$((TOTAL + 1))
out=$(hook "$GUARD" Write file_path "scripts/role-guard.sh" content "x")
if echo "$out" | grep -q "formal"; then
  ok "AX-07: light 轨拦截消息含 formal 关键字"
else
  bad "AX-07: light 轨拦截消息未含 formal（output: ${out}）"
fi

echo ""
echo "--- AX-08: deliverables 归属路由须为目录前缀语义 ---"
set_mhdev develop '["scripts/role-guard.sh"]' formal
clear_req
for p in deliverables-evil/REQ001/x.md mydeliverables/REQ001/x.md docs/deliverables/x.md; do
  expect 2 "AX-08: ${p} 落入框架分支 → 拒绝（不得被判为 /mh-run 归属）" \
    Write file_path "$p" content "x"
done
# 即便持有 REQ state 与交还标记，伪造前缀路径也不得走角色白名单
seed_state "THINKER"
for p in deliverables-evil/test-proj/.engine/.state.md mydeliverables/test-proj/docs/spec/x.md; do
  expect 2 "AX-08: ${p} 含交还标记仍拒绝（前缀伪造不得进 /mh-run 分支）" \
    Write file_path "$p" content "$HB"
done
expect 0 "AX-08: 真前缀 deliverables/test-proj/docs/spec/x.md → 走角色白名单放行" \
  Write file_path "deliverables/test-proj/docs/spec/x.md" content "x"

# ============================================================
# AX-11: 载荷形态覆盖
# ============================================================
echo ""
echo "--- AX-11: 载荷形态覆盖 ---"
clear_mhdev
clear_req
seed_state "THINKER"

# 缺路径参数：设计取「保守放行 + stderr WARN」（CR-016 D3 对 R5 的有意偏离），
# 断言按已审批设计口径写：exit 0 且必须打印 WARN，不得静默。
for tool in Write Edit; do
  TOTAL=$((TOTAL + 1))
  out=$(printf '{"tool_name":"%s","tool_input":{"content":"x"}}' "$tool" | bash "$GUARD" 2>&1)
  code=$?
  if [ "$code" = "0" ] && echo "$out" | grep -q "WARN"; then
    ok "AX-11: ${tool} 缺 file_path → exit 0 且打印 WARN（不静默）"
  else
    bad "AX-11: ${tool} 缺 file_path 处置异常 (exit=$code, output=$out)"
  fi
done
TOTAL=$((TOTAL + 1))
out=$(printf '{"tool_name":"NotebookEdit","tool_input":{"cell_id":"c1"}}' | bash "$GUARD" 2>&1)
code=$?
if [ "$code" = "0" ] && echo "$out" | grep -q "WARN"; then
  ok "AX-11: NotebookEdit 缺 notebook_path → exit 0 且打印 WARN"
else
  bad "AX-11: NotebookEdit 缺 notebook_path 处置异常 (exit=$code, output=$out)"
fi

# WARN 必须走 stderr（否则会被当作 hook 反馈注入对话）
TOTAL=$((TOTAL + 1))
out=$(printf '{"tool_name":"Write","tool_input":{"content":"x"}}' | bash "$GUARD" 2>/dev/null)
if [ -z "$out" ]; then
  ok "AX-11: 缺路径参数的 WARN 走 stderr（stdout 为空）"
else
  bad "AX-11: WARN 落在 stdout（output: ${out}）"
fi

# 两个路径参数同时存在：Write/Edit 取 file_path，判定以 file_path 为准
TOTAL=$((TOTAL + 1))
out=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"deliverables/test-proj/tests/x.md",notebook_path:"deliverables/test-proj/docs/spec/x.ipynb",content:"x"}}' | bash "$GUARD" 2>&1)
code=$?
if [ "$code" = "2" ] && echo "$out" | grep -q "tests/x.md"; then
  ok "AX-11: Write 同时带 file_path/notebook_path → 以 file_path 判定并拒绝"
else
  bad "AX-11: 双路径参数判定异常 (exit=$code, output=$out)"
fi
TOTAL=$((TOTAL + 1))
out=$(jq -nc '{tool_name:"NotebookEdit",tool_input:{file_path:"deliverables/test-proj/docs/spec/x.md",notebook_path:"deliverables/test-proj/tests/x.ipynb"}}' | bash "$GUARD" 2>&1)
code=$?
if [ "$code" = "2" ] && echo "$out" | grep -q "tests/x.ipynb"; then
  ok "AX-11: NotebookEdit 同时带两参数 → 以 notebook_path 判定并拒绝"
else
  bad "AX-11: NotebookEdit 双参数判定异常 (exit=$code, output=$out)"
fi

# 非写入工具一律放行，且不得出现 traceback / unbound variable
for tool in Read Bash Grep Glob Task; do
  TOTAL=$((TOTAL + 1))
  out=$(jq -nc --arg t "$tool" '{tool_name:$t,tool_input:{file_path:"deliverables/test-proj/tests/x.md",command:"echo x"}}' | bash "$GUARD" 2>&1)
  code=$?
  if [ "$code" = "0" ] && [ -z "$out" ]; then
    ok "AX-11: 非写入工具 ${tool} 放行且无输出"
  else
    bad "AX-11: 非写入工具 ${tool} 异常 (exit=$code, output=$out)"
  fi
done

# 畸形/空载荷：不得 traceback、unbound variable 或非预期退出码
echo ""
echo "--- AX-11: 畸形载荷健壮性 ---"
for payload in '{}' '{"tool_name":null}' '{"tool_name":"Write"}' '{"tool_name":"Write","tool_input":null}' 'not json' ''; do
  TOTAL=$((TOTAL + 1))
  out=$(printf '%s' "$payload" | bash "$GUARD" 2>&1)
  code=$?
  if { [ "$code" = "0" ] || [ "$code" = "2" ]; } && \
     ! echo "$out" | grep -qE "unbound variable|Traceback|syntax error|line [0-9]+:"; then
    ok "AX-11: 畸形载荷 '${payload:0:24}' → exit=$code 无解释器错误"
  else
    bad "AX-11: 畸形载荷 '${payload:0:24}' 异常 (exit=$code, output=$out)"
  fi
done

# ============================================================
# AX-10: 元验收 —— 轨迹用例在改动前版本下必须 FAIL
# ============================================================
# 目的：证明上面的轨迹/交还用例能捕获单向闭锁，而不是恒真装饰。
# 做法：对改动前的守卫副本（git show <baseline>:scripts/role-guard.sh）跑同一批断言，
# 期望它们失败；再对当前版本跑，期望通过。工作区文件本身不被修改。
echo ""
echo "--- AX-10: 轨迹用例元验收（对改动前版本须 FAIL） ---"

TOTAL=$((TOTAL + 1))
if [ -s "$BASELINE_GUARD" ]; then
  ok "AX-10: 取得改动前 role-guard.sh 副本（${BASELINE_REF}）"
else
  bad "AX-10: 无法取得 ${BASELINE_REF} 的 role-guard.sh，元验收无法执行"
fi

# 基线守卫从 .engine/.state.md 读 `req_id:` 定位需求（CR-018 才改为 project: + 全局指针）。
# 若拿新形态夹具喂基线，它 REQ_ID 解析为空 → 无条件 exit 0，三条对照将全部退化为
# 「旧放行/新放行」而假报无鉴别力。故元验收段的夹具须为**基线原生形态**：
# 同时写 req_id:（供基线读）与 project:（供新版读），使两版本都能定位到同一需求，
# 差异才收敛到判据本身。
legacy_state() {
  local role=$1 req=${2:-test-proj}
  rm -rf "$SB/deliverables"; mkdir -p "$SB/deliverables/$req/.engine/handoffs"
  printf 'project: %s\n' "$req" > "$SB/deliverables/.state.md"
  cat > "$SB/deliverables/$req/.engine/.state.md" << EOF
req_id: ${req}
project: ${req}
phase: propose
current_step: THINK-DESIGN
current_role: ${role}
repair_round: 0
EOF
}

if [ -s "$BASELINE_GUARD" ]; then
  # 轨迹：基线的交还一步必须失败（第一步派发在两版本均放行）
  TOTAL=$((TOTAL + 1))
  # 双形态轨迹：派发→落盘→交还，两版本各跑一遍（夹具含 req_id 与 project 双字段）
  legacy_trajectory() {
    local guard=$1 rc2
    legacy_state "ORCHESTRATOR"
    hook "$guard" Write file_path "deliverables/test-proj/.engine/.state.md" \
      content "$(printf 'req_id: test-proj\nproject: test-proj\ncurrent_role: THINKER\n')" >/dev/null 2>&1
    poke_role THINKER
    hook "$guard" Write file_path "deliverables/test-proj/.engine/.state.md" \
      content "$(printf 'req_id: test-proj\nproject: test-proj\ncurrent_role: ORCHESTRATOR\n')" >/dev/null 2>&1
    rc2=$?
    echo "$rc2"
  }
  b_rc2=$(legacy_trajectory "$BASELINE_GUARD")
  n_rc2=$(legacy_trajectory "$GUARD")
  if [ "$b_rc2" != "0" ] && [ "$n_rc2" = "0" ]; then
    ok "AX-10: 轨迹交还步在旧版本 FAIL(exit=$b_rc2)、新版本 PASS(exit=$n_rc2)"
  else
    bad "AX-10: 轨迹用例无鉴别力（旧版本 exit=${b_rc2}，新版本 exit=${n_rc2}；旧须非 0、新须 0）"
  fi

  # 内容判据：基线不读 content，THINKER 交还写入一律拒绝。
  # 只对 Write 断言「旧 FAIL / 新 PASS」——Edit 在路线 B 下新旧两版本同为 exit 2
  # （旧版因不读 content，新版因无交还例外资格），无差异可断言，留在此处只会恒假。
  # Edit 通道的鉴别力改由下方「移除 TOOL_NAME 判据」的突变体提供：那才是能证明
  # 「Edit 被拒是路线 B 所致，而非碰巧」的对照组。
  legacy_state "THINKER"
  for form in "Write:content"; do
    tool="${form%%:*}"; key="${form##*:}"
    TOTAL=$((TOTAL + 1))
    b_out=$(hook "$BASELINE_GUARD" "$tool" file_path "deliverables/test-proj/.engine/.state.md" "$key" "current_role: ORCHESTRATOR"); b_code=$?
    n_out=$(hook "$GUARD" "$tool" file_path "deliverables/test-proj/.engine/.state.md" "$key" "current_role: ORCHESTRATOR"); n_code=$?
    if [ "$b_code" != "0" ] && [ "$n_code" = "0" ]; then
      ok "AX-10: ${tool}.${key} 交还判据 旧版本 FAIL(exit=$b_code)、新版本 PASS"
    else
      bad "AX-10: ${tool}.${key} 用例无鉴别力（旧 exit=$b_code 新 exit=${n_code}）"
    fi
  done

  # NotebookEdit 通道：基线静默放行跨角色 notebook（漏覆盖），新版本拦截
  TOTAL=$((TOTAL + 1))
  b_out=$(hook "$BASELINE_GUARD" NotebookEdit notebook_path "deliverables/test-proj/tests/x.ipynb"); b_code=$?
  n_out=$(hook "$GUARD" NotebookEdit notebook_path "deliverables/test-proj/tests/x.ipynb"); n_code=$?
  if [ "$b_code" = "0" ] && [ "$n_code" = "2" ]; then
    ok "AX-10: NotebookEdit 越权 旧版本静默放行(exit=0)、新版本拦截(exit=2)"
  else
    bad "AX-10: NotebookEdit 用例无鉴别力（旧 exit=$b_code 新 exit=${n_code}）"
  fi

  # approved_scope 绕过：基线在空 REQ state 下放行 scope 外框架路径，新版本拦截
  TOTAL=$((TOTAL + 1))
  set_mhdev develop '["scripts/role-guard.sh"]' formal
  # 空 REQ state：基线以「无活跃需求」为 mh-dev 分支进入条件，空 state 使其整体绕过 scope
  rm -rf "$SB/deliverables"; mkdir -p "$SB/deliverables/test-proj/.engine"
  : > "$SB/deliverables/test-proj/.engine/.state.md"
  b_out=$(hook "$BASELINE_GUARD" Write file_path "CLAUDE.md" content "x"); b_code=$?
  n_out=$(hook "$GUARD" Write file_path "CLAUDE.md" content "x"); n_code=$?
  if [ "$b_code" = "0" ] && [ "$n_code" = "2" ]; then
    ok "AX-10: 空 REQ state 下 scope 绕过 旧版本放行(exit=0)、新版本拦截(exit=2)"
  else
    bad "AX-10: AX-05 用例无鉴别力（旧 exit=$b_code 新 exit=${n_code}）"
  fi

  # 恢复态确认：工作区实现文件未被本套件改动
  TOTAL=$((TOTAL + 1))
  if [ "$(shasum -a 256 < "$REPO/scripts/role-guard.sh" | awk '{print $1}')" = \
       "$(shasum -a 256 < "$GUARD" | awk '{print $1}')" ]; then
    ok "AX-10: 元验收未污染工作区 scripts/role-guard.sh（哈希一致）"
  else
    bad "AX-10: 工作区 scripts/role-guard.sh 与沙箱副本不一致，疑被改动"
  fi
fi

# ============================================================
# AX-10: 突变测试 —— 排列维度断言对存在性量词实现须有鉴别力
# ============================================================
# 上面的基线对照证明不了排列维度：基线 is_handback 完全不读 content，任何交还写入一律 exit 2，
# 因此「真值在后须拒绝」在基线上恰好也成立（原因不同、结论相同）——恒绿，无鉴别力。
# 要证明新断言真的守住 P0-1，必须构造**只差解析方式一处**的突变体（M1）：
# 把首行解析换回存在性量词，**其余一切保留**——特别是 TOOL_NAME == Write 工具判据必须留下。
# 若连工具判据一起删掉，M1 就同时含两个突变，Edit 侧的差异无法归因，
# 「Edit 拒绝源自工具判据」这条断言也会假失败。故此处只替换那两行解析语句。
# 突变只作用于沙箱副本，工作区文件不动（下方哈希断言复核）。
echo ""
echo "--- AX-10: 突变测试 M1（首行解析换回存在性量词，排列断言须 FAIL） ---"

MUTANT="$SB/scripts/role-guard.mutant.sh"
# 定点替换：`local effective` + `effective=$(... head -1 ...)` + `[[ "$effective" == ... ]]`
# 三行换成一条存在性量词判定，其余行（含工具判据、空内容判据、注释）原样保留。
awk '
  /^  local effective$/ { next }
  /^  effective=\$\(printf/ {
    print "  # M1 突变：CR-016 修复前的存在性量词实现（任一行匹配即放行）"
    print "  printf '\''%s\\n'\'' \"$NEW_CONTENT\" | grep -qE '\''^current_role:[[:space:]]+ORCHESTRATOR([[:space:]]|$)'\''"
    print "  return $?"
    next }
  /^  \[\[ "\$effective" == "ORCHESTRATOR" \]\]$/ { next }
  { print }
' "$GUARD" > "$MUTANT"

# 构造自检须只看 is_handback 函数体：`head -1` 在守卫别处有合法用途
# （第 120 行 STATE_FILE 的 find | head -1，以及注释），全文件 grep 会恒假。
# 同时校验工具判据仍在——这是 M1 与 M2 的分界，缺了它两个突变体就退化成同一个。
TOTAL=$((TOTAL + 1))
MUTANT_FN=$(awk '/^is_handback\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$MUTANT")
if printf '%s' "$MUTANT_FN" | grep -q 'grep -qE' && \
   ! printf '%s' "$MUTANT_FN" | grep -q 'head -1' && \
   printf '%s' "$MUTANT_FN" | grep -q 'TOOL_NAME' && \
   bash -n "$MUTANT" 2>/dev/null; then
  ok "AX-10: M1 构造成功（解析换为存在性量词、工具判据保留、语法可解析）"
else
  bad "AX-10: M1 构造失败，突变测试无法执行（函数体: ${MUTANT_FN}）"
fi

# 突变体与当前实现在同一批排列载荷上对跑。
# 「真值在后」组：当前须 2（拒绝夺权），突变体须 0（暴露缺陷）→ 断言有鉴别力
# 「真值在前」组：两者均须 0 → 确认突变体除该维度外未被改坏（否则鉴别力可能来自无关破坏）
if [ -s "$MUTANT" ]; then
  clear_req
  seed_state "THINKER"
  for decoy in WORKER VERIFIER THINKER "THINKER,ORCHESTRATOR"; do
    payload="$(printf 'current_role: %s\ncurrent_role: ORCHESTRATOR\n' "$decoy")"
    TOTAL=$((TOTAL + 1))
    hook "$GUARD"   Write file_path "deliverables/test-proj/.engine/.state.md" content "$payload" >/dev/null 2>&1
    n_code=$?
    hook "$MUTANT" Write file_path "deliverables/test-proj/.engine/.state.md" content "$payload" >/dev/null 2>&1
    m_code=$?
    if [ "$n_code" = "2" ] && [ "$m_code" = "0" ]; then
      ok "AX-10: 排列[真值在后 首=${decoy}] 断言有鉴别力（当前 exit=2 拒绝、突变体 exit=0 放行）"
    else
      bad "AX-10: 排列[真值在后 首=${decoy}] 断言无鉴别力（当前 exit=$n_code 突变体 exit=${m_code}；须 2/0）"
    fi
  done

  for decoy in WORKER "THINKER,ORCHESTRATOR"; do
    payload="$(printf 'current_role: ORCHESTRATOR\ncurrent_role: %s\n' "$decoy")"
    TOTAL=$((TOTAL + 1))
    hook "$GUARD"   Write file_path "deliverables/test-proj/.engine/.state.md" content "$payload" >/dev/null 2>&1
    n_code=$?
    hook "$MUTANT" Write file_path "deliverables/test-proj/.engine/.state.md" content "$payload" >/dev/null 2>&1
    m_code=$?
    if [ "$n_code" = "0" ] && [ "$m_code" = "0" ]; then
      ok "AX-10: 排列[真值在前 末=${decoy}] 两实现同为放行（该排列恒绿，故单独覆盖它不足以守住 P0-1）"
    else
      bad "AX-10: 排列[真值在前 末=${decoy}] 异常（当前 exit=$n_code 突变体 exit=${m_code}；均须 0）"
    fi
  done

  # Edit 通道在 M1 下不该有差异：M1 保留了 TOOL_NAME == Write 判据，故新旧同为 exit 2。
  # 断言这一点是为了把「Edit 被拒的原因」钉死在工具判据上——若此处出现差异，
  # 说明 Edit 的拒绝仍受内容判据影响，路线 B 的结构性保证没真正生效。
  TOTAL=$((TOTAL + 1))
  ns="$(printf 'current_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
  hook "$GUARD"   Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "$ns" >/dev/null 2>&1
  n_code=$?
  hook "$MUTANT" Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "$ns" >/dev/null 2>&1
  m_code=$?
  if [ "$n_code" = "2" ] && [ "$m_code" = "2" ]; then
    ok "AX-10: Edit 通道对量词突变不敏感（两者均 exit=2，拒绝源自工具判据而非内容判据）"
  else
    bad "AX-10: Edit 通道拒绝仍受内容判据影响（当前 exit=$n_code 突变体 exit=${m_code}；均须 2）"
  fi

  # 恢复语义：突变仅在副本上进行，工作区与沙箱主副本均未被改动
  TOTAL=$((TOTAL + 1))
  if [ "$(shasum -a 256 < "$REPO/scripts/role-guard.sh" | awk '{print $1}')" = \
       "$(shasum -a 256 < "$GUARD" | awk '{print $1}')" ] && \
     [ "$(shasum -a 256 < "$MUTANT" | awk '{print $1}')" != \
       "$(shasum -a 256 < "$GUARD" | awk '{print $1}')" ]; then
    ok "AX-10: 突变测试后工作区实现未变（且突变体与主副本确实不同）"
  else
    bad "AX-10: 突变测试污染了工作区实现，或突变体与主副本无差异"
  fi
fi

# ============================================================
# AX-10: 突变体 M2 —— 移除 TOOL_NAME == Write 判据，Edit 断言须 FAIL
# ============================================================
# M1（量词突变）证明不了 Edit 侧断言的鉴别力：M1 保留工具判据，Edit 在它下面照样 exit 2，
# 于是「Edit 须拒」在 M1 上恒真。要证明这批断言锁住的是**路线 B 本身**而非碰巧为真，
# 必须构造只删掉 `[[ "$TOOL_NAME" == "Write" ]] || return 1` 一行的突变体：
# 它退回 F-01 的缺陷形态（首行解析正确，但把片段判据用在 Edit 上），
# 此时三种跨行提权形态与整行交还形态都会被放行。
echo ""
echo "--- AX-10: 突变体 M2（移除工具判据，Edit 提权断言须 FAIL） ---"

MUTANT2="$SB/scripts/role-guard.mutant2.sh"
grep -v '\[\[ "\$TOOL_NAME" == "Write" \]\] || return 1' "$GUARD" > "$MUTANT2"

TOTAL=$((TOTAL + 1))
M2_FN=$(awk '/^is_handback\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$MUTANT2")
if ! printf '%s' "$M2_FN" | grep -q 'TOOL_NAME' && \
   printf '%s' "$M2_FN" | grep -q 'head -1' && \
   bash -n "$MUTANT2" 2>/dev/null && \
   [ "$(shasum -a 256 < "$MUTANT2" | awk '{print $1}')" != "$(shasum -a 256 < "$GUARD" | awk '{print $1}')" ]; then
  ok "AX-10: M2 构造成功（工具判据已移除、首行解析保留、语法可解析、与主副本不同）"
else
  bad "AX-10: M2 构造失败，Edit 侧鉴别力无法验证（函数体: ${M2_FN}）"
fi

if [ -s "$MUTANT2" ]; then
  # 三种跨行提权形态 + 整行交还：当前须 2，M2 须 0
  clear_req
  seed_state "THINKER"
  m2_probe() {
    local label=$1 ns=$2
    TOTAL=$((TOTAL + 1))
    hook "$GUARD"   Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "$ns" >/dev/null 2>&1
    local n_code=$?
    hook "$MUTANT2" Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "$ns" >/dev/null 2>&1
    local m_code=$?
    if [ "$n_code" = "2" ] && [ "$m_code" = "0" ]; then
      ok "AX-10: Edit ${label} 断言有鉴别力（当前 exit=2、M2 exit=0 复现 F-01）"
    else
      bad "AX-10: Edit ${label} 断言无鉴别力（当前 exit=$n_code M2 exit=${m_code}；须 2/0）"
    fi
  }
  m2_probe "跨行片段末行 THINKER,ORCHESTRATOR" \
    "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: THINKER,ORCHESTRATOR')"
  m2_probe "跨行片段末行 WORKER" \
    "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER')"
  m2_probe "跨行片段单行（合并后 current_role 消失）" \
    "current_role: ORCHESTRATOR"
  m2_probe "整行交还（路线 B 取消资格，M2 下恢复放行）" \
    "current_role: ORCHESTRATOR"

  # Write 通道在 M2 下不得受影响：路线 B 只该收紧 Edit，不该改变 Write 的结论。
  # 若此处出现差异，说明 M2 的删改牵动了 Write 侧，前面的 2/0 对照就不能归因到工具判据。
  TOTAL=$((TOTAL + 1))
  hook "$GUARD"   Write file_path "deliverables/test-proj/.engine/.state.md" content "current_role: ORCHESTRATOR" >/dev/null 2>&1
  n_code=$?
  hook "$MUTANT2" Write file_path "deliverables/test-proj/.engine/.state.md" content "current_role: ORCHESTRATOR" >/dev/null 2>&1
  m_code=$?
  if [ "$n_code" = "0" ] && [ "$m_code" = "0" ]; then
    ok "AX-10: M2 未牵动 Write 通道（两者均 exit=0，故 Edit 侧差异可归因于工具判据）"
  else
    bad "AX-10: M2 牵动了 Write 通道（当前 exit=$n_code M2 exit=${m_code}；均须 0）"
  fi

  TOTAL=$((TOTAL + 1))
  if [ "$(shasum -a 256 < "$REPO/scripts/role-guard.sh" | awk '{print $1}')" = \
       "$(shasum -a 256 < "$GUARD" | awk '{print $1}')" ]; then
    ok "AX-10: M2 突变未污染工作区 scripts/role-guard.sh"
  else
    bad "AX-10: M2 突变污染了工作区实现"
  fi
fi

# ============================================================
# AC-07 / AC-08: 既有回归不退化 + 文档口径同步
# ============================================================
# 这两条此前只在 Tester 的 verdict 里以命令证据体现，套件内无断言，
# 于是「谁来守」依赖每轮 Tester 记得跑。落成断言后由套件自身持续守。
echo ""
echo "--- AC-07: 既有回归套件不退化 ---"
TOTAL=$((TOTAL + 1))
rg_out=$(bash "$REPO/tests/test-role-guard.sh" 2>&1)
rg_code=$?
rg_line=$(printf '%s\n' "$rg_out" | grep -o '总计: [0-9]*' | tail -1)
rg_total=$(printf '%s\n' "$rg_out" | grep -o '总计: [0-9]*' | tail -1 | grep -o '[0-9]*')
# 断言「全绿且断言数不低于 CR-018 前的 100 项」而非锁死等于 100：
# 条数随后续轮次新增用例只增不减，锁死具体值会使每次加用例都必须改本断言，
# 而本断言要守的性质是「既有覆盖未被删减」，下界即可表达。
if [ "$rg_code" = "0" ] && [ "${rg_total:-0}" -ge 100 ]; then
  ok "AC-07: tests/test-role-guard.sh 全绿且覆盖未减（${rg_line} ≥ 100）"
else
  bad "AC-07: test-role-guard.sh 退化（exit=${rg_code}, ${rg_line}；须 exit 0 且总计 ≥ 100）"
fi

TOTAL=$((TOTAL + 1))
if bash "$REPO/scripts/check-harness.sh" >/dev/null 2>&1; then
  ok "AC-07: scripts/check-harness.sh 通过"
else
  bad "AC-07: scripts/check-harness.sh 未通过"
fi

echo ""
echo "--- AC-08: 文档口径同步（首行语义 + 自授权边界） ---"
# 判据是「文档描述的口径与实现一致」，故断言文档明示首行语义、并留存存在性量词的否决记录。
# 只查关键词存在性——语义正确性由 Auditor 负责，此处守的是「实现改了文档没跟」这一类退化。
for doc in CLAUDE.md docs/designs/source-of-truth.md docs/kb/domains/guards.md templates/state-template.md; do
  TOTAL=$((TOTAL + 1))
  if grep -qE '首个|首行' "$REPO/$doc" && grep -q '存在性量词' "$REPO/$doc"; then
    ok "AC-08: ${doc} 描述首行语义并留存存在性量词否决记录"
  else
    bad "AC-08: ${doc} 未同步新授权口径（缺首行语义或存在性量词记录）"
  fi
done

# 路线 B 口径（交还例外只接受 Write）须在面向写入方的文档里明示，否则合作者会按
# 「Edit 也行」的旧口径拆分写入而被拦，且无处可查原因。判据用宽松匹配：
# 只要求同一处提到 Write 与 Edit 的差别，不锁死具体措辞。
for doc in CLAUDE.md docs/designs/source-of-truth.md docs/kb/domains/guards.md templates/state-template.md skills/mh-codeflow/SKILL.md; do
  TOTAL=$((TOTAL + 1))
  if grep -qE 'Write' "$REPO/$doc" && grep -qE 'Edit' "$REPO/$doc" && \
     grep -qE '只接受 .?Write|仅接受 .?Write|只认 .?Write|必须用 .?Write|须用 .?Write|用 .?Write. 一次完整写入' "$REPO/$doc"; then
    ok "AC-08: ${doc} 明示交还例外只接受 Write（路线 B 口径）"
  else
    bad "AC-08: ${doc} 未同步路线 B 口径（交还例外只接受 Write）"
  fi
done

# 实现侧须存在工具判据，且与文档口径一致
TOTAL=$((TOTAL + 1))
if awk '/^is_handback\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$REPO/scripts/role-guard.sh" \
   | grep -q 'TOOL_NAME.*Write'; then
  ok "AC-08: 实现侧 is_handback 含 TOOL_NAME == Write 工具判据"
else
  bad "AC-08: is_handback 缺工具判据，与文档口径不一致"
fi

# guards.md 须明示自授权性质与 Bash 通道不受覆盖（AC-08 点名要求）
TOTAL=$((TOTAL + 1))
if grep -q '自授权' "$REPO/docs/kb/domains/guards.md" && \
   grep -q 'Bash' "$REPO/docs/kb/domains/guards.md"; then
  ok "AC-08: guards.md 明示自授权性质与 Bash 通道不受覆盖"
else
  bad "AC-08: guards.md 未明示自授权/Bash 能力边界"
fi

# 实现侧不得残留存在性量词谓词（注释中的历史说明除外）
TOTAL=$((TOTAL + 1))
if awk '/^is_handback\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$REPO/scripts/role-guard.sh" \
   | grep -q 'head -1'; then
  ok "AC-08: 实现侧 is_handback 为首行解析（与读取端同源）"
else
  bad "AC-08: is_handback 未复用读取端首行解析"
fi

# ============================================================
# AX-12: CR-018 自身新性质的元验收（对照组 = 85a9912）
# ============================================================
# 上方 AX-10 的对照组是 156c49a，验的是 CR-016 判据；本节验 CR-018 新增性质：
# 「多交付物并存时以全局指针定位，绝不退化为扫描」。
# 该性质的改动前版本是 85a9912（find … | head -1 取文件系统首个命中项）。
# 分两节而非合并的理由与 AX-10 注释同源：对照组须按被验性质选取。
echo ""
echo "--- AX-12: 指针定位不退化为扫描（对照组 85a9912）---"

CR18_BASE="$SB/scripts/role-guard.cr018base.sh"
git -C "$REPO" show "85a9912:scripts/role-guard.sh" > "$CR18_BASE" 2>/dev/null

TOTAL=$((TOTAL + 1))
if [ -s "$CR18_BASE" ]; then
  ok "AX-12: 取得 85a9912 的 role-guard.sh 副本"
else
  bad "AX-12: 无法取得 85a9912 的 role-guard.sh，本节元验收无法执行"
fi

if [ -s "$CR18_BASE" ]; then
  # 夹具：两个交付物并存，双字段（基线读 req_id，新版读全局指针）。
  #
  # 关键：**不能假设 find 的命中顺序**。APFS 下 `find` 既非字典序也非创建序（目录哈希序），
  # 写死「aaa-other 排在前面」的夹具在别的机器/文件系统上会翻转而使本条恒假。
  # 故在运行时先问出基线实际会选中谁（scan_pick），再把全局指针指向**另一个**，
  # 目标路径取 scan_pick 名下的 WORKER 路径：
  #   基线 → 定位到 scan_pick（WORKER 持权），目标正是其 WORKER 路径 → 放行 exit 0
  #   新版 → 定位到指针所指者，目标不在该交付物名下 → 拒绝 exit 2
  # 两版本的差异由此只来自定位机制，与文件系统枚举顺序无关。
  build_multi() {
    rm -rf "$SB/deliverables"
    mkdir -p "$SB/deliverables/proj-alpha/.engine" "$SB/deliverables/proj-beta/.engine"
    printf 'req_id: proj-alpha\nproject: proj-alpha\ncurrent_role: WORKER\n' \
      > "$SB/deliverables/proj-alpha/.engine/.state.md"
    printf 'req_id: proj-beta\nproject: proj-beta\ncurrent_role: WORKER\n' \
      > "$SB/deliverables/proj-beta/.engine/.state.md"
  }

  build_multi
  # 基线的定位表达式（85a9912 L120）原样复刻，问出它会选中谁
  scan_pick=$(find "$SB/deliverables" -maxdepth 3 -name ".state.md" -path "*/.engine/.state.md" \
                2>/dev/null | head -1 | xargs dirname | xargs dirname | xargs basename)
  if [ "$scan_pick" = "proj-alpha" ]; then other_proj=proj-beta; else other_proj=proj-alpha; fi
  # 指针指向 scan_pick 之外的那个
  printf 'project: %s\n' "$other_proj" > "$SB/deliverables/.state.md"
  TARGET="deliverables/${scan_pick}/src/a.ts"

  TOTAL=$((TOTAL + 1))
  b_out=$(hook "$CR18_BASE" Write file_path "$TARGET" content "x"); b_code=$?
  n_out=$(hook "$GUARD" Write file_path "$TARGET" content "x"); n_code=$?
  if [ "$b_code" = "0" ] && [ "$n_code" = "2" ]; then
    ok "AX-12: 多交付物并存 旧版本按扫描命中 ${scan_pick} 而放行(exit=0)、新版本按指针(${other_proj})拒绝(exit=2)"
  else
    bad "AX-12: 指针定位用例无鉴别力（旧 exit=$b_code 新 exit=${n_code}；旧须 0、新须 2）"
  fi

  # 非指针所指的交付物，其 current_role 不参与判权
  TOTAL=$((TOTAL + 1))
  if [ "$n_code" = "2" ]; then
    ok "AX-12: 非指针所指交付物（${scan_pick}）的 current_role 不参与判权（exit=2）"
  else
    bad "AX-12: 写他项交付物按其自身 current_role 放行了（exit=$n_code），指针语义失效"
  fi

  # project 非法 slug 是唯一收紧项（D3.4）：基线无此概念而放行，新版拦截
  TOTAL=$((TOTAL + 1))
  rm -rf "$SB/deliverables"; mkdir -p "$SB/deliverables/test-proj/.engine"
  printf 'project: WEB-CLI\n' > "$SB/deliverables/.state.md"
  printf 'req_id: test-proj\nproject: test-proj\ncurrent_role: THINKER\n' \
    > "$SB/deliverables/test-proj/.engine/.state.md"
  n_out=$(hook "$GUARD" Write file_path "deliverables/test-proj/docs/spec/design.md" content "x"); n_code=$?
  if [ "$n_code" = "2" ] && printf '%s' "$n_out" | grep -q '污染'; then
    ok "AX-12: 指针 project 非法 slug → exit 2 且提示 state 被污染"
  else
    bad "AX-12: 污染态未拦截或原因不可读（exit=$n_code, output=${n_out}）"
  fi
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

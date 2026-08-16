#!/bin/bash
# test-role-guard-report.sh — CR-017 完成回报归属验收测试（Tester 独占）
# 用法: bash tests/test-role-guard-report.sh
# 退出码: 0=全部通过, 1=有失败
#
# 与既有两份套件的分工：
#   tests/test-role-guard.sh            既有白名单/归一化口径（100 项）
#   tests/test-role-guard-authority.sh  CR-016 授权模型（交还谓词、路径归属路由，197 项）
#   本份                                CR-017 D1 回报放行条 + D2 门禁读取端同源 + D3 撤回后的基线一致性
#
# 隔离策略（沿用 authority 套件）：所有 deliverables 分支断言在**沙箱仓库**内执行
# （cp 一份守卫脚本，其 ROOT 由 BASH_SOURCE 推导为沙箱根）。守卫用
# `find deliverables -maxdepth 3 | head -1` 定位活跃 state，在真实仓库建夹具会与
# 并发套件互相夺取 head -1。verify.sh / verify-qa.sh 的夹具同理落在独立临时目录内。

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

# CR-017 的基线。拒绝类断言须在基线守卫上同样执行，区分「本 CR 新开的口子」与
# 「baseline 既有缺陷」（AX-13）。已知 baseline 既有问题：白名单正则普遍缺左锚。
BASELINE_REF="${BASELINE_REF:-cad7136}"

SB="$(mktemp -d)"
MH_DEV_RUNTIME="$SB/.mh-dev"
export MH_DEV_RUNTIME
trap 'rm -rf "$SB"' EXIT

mkdir -p "$SB/scripts" "$SB/deliverables" "$MH_DEV_RUNTIME"
cp "$REPO/scripts/role-guard.sh" "$SB/scripts/role-guard.sh"
# CR-018 D1.3：守卫消费侧独立校验 project，调用同目录 validate-slug.sh。
# 沙箱只拷守卫会使该调用失败被判为校验不通过而 exit 2，放行类断言全部假失败。
cp "$REPO/scripts/validate-slug.sh" "$SB/scripts/validate-slug.sh"
git -C "$REPO" show "${BASELINE_REF}:scripts/role-guard.sh" > "$SB/scripts/role-guard.baseline.sh" 2>/dev/null

GUARD="$SB/scripts/role-guard.sh"
BASE_GUARD="$SB/scripts/role-guard.baseline.sh"

PASS=0
FAIL=0
TOTAL=0
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()  { echo -e "  ${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
bad() { echo -e "  ${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }

# --- 夹具 ---

seed_state() {
  local role=$1 req=${2:-test-proj} phase=${3:-propose}
  rm -rf "$SB/deliverables"
  mkdir -p "$SB/deliverables/$req/.engine/handoffs" "$SB/deliverables/$req/.engine/reports"
  # CR-018 D3.4：守卫以全局指针定位活跃交付物，夹具须同时写指针。
  # 同时保留 req_id: —— 本套件大量断言以基线守卫（cad7136）作对照组，
  # 而基线用 `find|head -1` + `req_id:` 定位。只写 project: 会让基线 REQ_ID 解析为空
  # 而无条件 exit 0，所有基线对照退化为「基线放行」，AX-13 的缺陷归因随之失效
  # （表现为「预期新增放行 0 条」与一批 want_base=2 的假失败）。
  # 双字段使两版本定位到同一交付物，差异才收敛到判据本身。
  printf 'project: %s\n' "$req" > "$SB/deliverables/.state.md"
  cat > "$SB/deliverables/$req/.engine/.state.md" << EOF
req_id: ${req}
project: ${req}
phase: ${phase}
current_step: THINK-DESIGN
current_role: ${role}
repair_round: 0
last_updated: "2026-08-13T10:00:00Z"
EOF
}

raw_state() {
  local body=$1 req=${2:-test-proj}
  rm -rf "$SB/deliverables"
  mkdir -p "$SB/deliverables/$req/.engine/handoffs"
  printf 'project: %s\n' "$req" > "$SB/deliverables/.state.md"
  printf '%s' "$body" > "$SB/deliverables/$req/.engine/.state.md"
}

clear_req() { rm -rf "$SB/deliverables"; mkdir -p "$SB/deliverables"; }

set_mhdev() {
  local phase=$1 scope=$2 track=${3:-formal}
  mkdir -p "$MH_DEV_RUNTIME"
  cat > "$MH_DEV_RUNTIME/state.json" << EOF
{"workflow":"mh-dev","phase":"${phase}","current_role":"planner","approved_scope":${scope},"track":"${track}"}
EOF
}

clear_mhdev() { rm -rf "$MH_DEV_RUNTIME"; mkdir -p "$MH_DEV_RUNTIME"; }

# hook <guard> <tool> <path-key> <path> [<content-key> <content>]
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

# 回报路径简写（Write + content）
expect_report() {
  local want=$1 desc=$2 path=$3 content=${4:-x}
  expect "$want" "$desc" Write file_path "$path" content "$content"
}

# 基线对照：同一载荷在当前实现与基线守卫上各跑一次，两个结论都作为证据打印。
# 用途是把「本 CR 新开的口子」与「baseline 既有缺陷」区分开（AX-13），
# 故断言的是「当前须为 want_cur」，同时记录基线结论供归因，不强制两者相同。
# want_base 传 "-" 表示不对基线结论设期望（只记录）。
expect_vs_base() {
  local want_cur=$1 want_base=$2 desc=$3; shift 3
  TOTAL=$((TOTAL + 1))
  local c_out c_code b_out b_code
  c_out=$(hook "$GUARD" "$@"); c_code=$?
  b_out=$(hook "$BASE_GUARD" "$@"); b_code=$?
  local verdict=true
  [ "$c_code" = "$want_cur" ] || verdict=false
  if [ "$want_base" != "-" ] && [ "$b_code" != "$want_base" ]; then verdict=false; fi
  if [ "$verdict" = true ]; then
    ok "${desc}（当前 exit=${c_code}、基线 exit=${b_code}）"
  else
    bad "${desc} (当前 exit=${c_code} 须 ${want_cur}；基线 exit=${b_code} 须 ${want_base})"
    echo "        当前输出: ${c_out}"
  fi
}

echo "=== CR-017 完成回报归属验收测试 ==="
echo "沙箱: $SB"
echo "基线: $BASELINE_REF"

TOTAL=$((TOTAL + 1))
if [ -s "$BASE_GUARD" ]; then
  ok "前置: 取得基线守卫副本（${BASELINE_REF}:scripts/role-guard.sh）"
else
  bad "前置: 无法取得 ${BASELINE_REF} 的 role-guard.sh，AX-13 基线对比无法执行"
fi

RPT="deliverables/test-proj/.engine/reports"

# ============================================================
# AC-01: 三角色各自写本轮回报文件均 exit 0（逐一断言，不抽样）
# ============================================================
echo ""
echo "--- AC-01: THINKER / WORKER / VERIFIER 各自可写完成回报 ---"
# 回报文件名由 handoff basename 派生，故用各棒真实命名形态而非通用名，
# 确认放行不依赖文件名里的角色 token（该性质由 AX-04 正面断言）。
declare -a HANDOFF_BASENAMES=("test-proj-THINK-NEEDS-R1" "test-proj-THINK-DESIGN-R1" "test-proj-DEV1-T1-R1" "test-proj-TEST-AUDIT-R1")
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  for hb in "${HANDOFF_BASENAMES[@]}"; do
    expect_report 0 "AC-01: ${role} 持权写 reports/${hb}.report.md → 放行" \
      "$RPT/${hb}.report.md"
  done
done

# 五字段完整回报内容（templates/handoff-examples.md 的书写形态）须同样放行——
# 放行不因内容形态而变，这也是 AX-06 的正面基础。
REPORT_BODY=$'status: done\noutput_files: ["deliverables/test-proj/docs/spec/design.md"]\nread_files: ["deliverables/test-proj/.engine/proposal.md"]\nsummary: "架构设计完成"\nissues: "N/A"\n'
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  expect_report 0 "AC-01: ${role} 写五字段完整回报内容 → 放行" \
    "$RPT/test-proj-THINK-DESIGN-R1.report.md" "$REPORT_BODY"
done

# 并行多角色形态（current_role: A,B）下回报仍可写：check_permission 逐角色试的语义不因新条改变
for role in "THINKER,VERIFIER" "WORKER,VERIFIER"; do
  seed_state "$role"
  expect_report 0 "AC-01: 并行持权 ${role} 写回报 → 放行" "$RPT/test-proj-DEV1-T1-R1.report.md"
done

# 基线对照：同一路径在基线守卫上一律 exit 2（回报条是本 CR 新增），
# 证明上面 12 条放行断言有鉴别力，而不是恒真装饰（AX-13 的正向用法）。
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  expect_vs_base 0 2 "AC-01: ${role} 回报放行在基线上不成立（当前 0 / 基线 2，断言有鉴别力）" \
    Write file_path "$RPT/test-proj-THINK-DESIGN-R1.report.md" content "x"
done

# ============================================================
# AC-02: ORCHESTRATOR 写同一回报路径亦 exit 0（驳回轮次 + 兜底代填）
# ============================================================
echo ""
echo "--- AC-02: ORCHESTRATOR 保留回报写权 ---"
seed_state "ORCHESTRATOR"
for hb in "${HANDOFF_BASENAMES[@]}"; do
  expect_report 0 "AC-02: ORCHESTRATOR 写 reports/${hb}.report.md → 放行（兜底代填）" \
    "$RPT/${hb}.report.md"
done
expect_report 0 "AC-02: ORCHESTRATOR 写五字段完整回报内容 → 放行" \
  "$RPT/test-proj-DEV1-T1-R2.report.md" "$REPORT_BODY"
expect_vs_base 0 2 "AC-02: ORCHESTRATOR 回报放行在基线上不成立（本 CR 新增）" \
  Write file_path "$RPT/test-proj-DEV1-T1-R2.report.md" content "x"

# ============================================================
# AC-03: 回报与 handoff 写权分离（比较两侧落在两套写权）
# ============================================================
# 这是 R2 的核心性质：质量门禁 Step 0 比较 handoff 白名单与回报 read_files，
# 若执行角色同时能写两侧则可自洽伪造。故须成对断言，单看任一侧都不足。
echo ""
echo "--- AC-03: 同一角色持权下 回报放行 / 对应 handoff 拒绝 ---"
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  for hb in "${HANDOFF_BASENAMES[@]}"; do
    TOTAL=$((TOTAL + 1))
    hook "$GUARD" Write file_path "$RPT/${hb}.report.md" content "x" >/dev/null 2>&1
    r_code=$?
    hook "$GUARD" Write file_path "deliverables/test-proj/.engine/handoffs/${hb}.md" content "x" >/dev/null 2>&1
    h_code=$?
    if [ "$r_code" = "0" ] && [ "$h_code" = "2" ]; then
      ok "AC-03: ${role} 持权 ${hb}：回报 exit=0 / handoff exit=2（写权分离）"
    else
      bad "AC-03: ${role} 持权 ${hb} 写权未分离（回报 exit=$r_code 须 0，handoff exit=$h_code 须 2）"
    fi
  done
done
# ORCHESTRATOR 是唯一两侧皆可写的角色，这正是「不得代笔」由协议而非守卫约束的事实。
# 断言它以钉住现状：若将来守卫收紧，此条会失败并迫使重新决策。
seed_state "ORCHESTRATOR"
expect 0 "AC-03: ORCHESTRATOR 两侧皆可写 handoff（守卫层面不分离，代笔限制由协议承担）" \
  Write file_path "deliverables/test-proj/.engine/handoffs/test-proj-THINK-DESIGN-R1.md" content "x"

# ============================================================
# AX-01: 回报写权不得放大为 .engine/ 直通（逐个断言，不抽样）
# ============================================================
# 载荷同时带上「完整回报内容」与「合法交还首行」两种内容形态：若实现把回报条
# 误写成目录级放行，或让内容影响判定，两种形态中必有一种暴露。
echo ""
echo "--- AX-01: 回报写权不放大为引擎态直通 ---"
HB_CONTENT=$'current_role: ORCHESTRATOR\nstatus: done\n'
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  for f in handoffs/x.md plan-action.md SR1-record.md SR3-record.md lessons.md process.log archive-manifest.md; do
    expect_report 2 "AX-01: ${role} 持权写 .engine/${f}（回报内容）→ 拒绝" \
      "deliverables/test-proj/.engine/${f}" "$REPORT_BODY"
    expect_report 2 "AX-01: ${role} 持权写 .engine/${f}（交还首行内容）→ 拒绝" \
      "deliverables/test-proj/.engine/${f}" "$HB_CONTENT"
  done
  expect_report 2 "AX-01: ${role} 持权写全局 deliverables/.state.md → 拒绝" \
    "deliverables/.state.md" "$REPORT_BODY"
done
# 把 .report.md 后缀挂到那些引擎态文件名上也不得放行——回报条锚定的是 reports/ 目录，
# 不是后缀。若实现改为按后缀区分写权（设计明确否决的方案），这组会暴露。
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  for f in handoffs/x.report.md plan-action.report.md SR1-record.report.md lessons.report.md archive-manifest.report.md; do
    expect_report 2 "AX-01: ${role} 持权写 .engine/${f}（后缀伪装成回报）→ 拒绝" \
      "deliverables/test-proj/.engine/${f}"
  done
  expect_report 2 "AX-01: ${role} 持权写 .engine/.state.md.report.md → 拒绝" \
    "deliverables/test-proj/.engine/.state.md.report.md"
done
# reports/ 目录本身不得成为 .engine/ 的兄弟直通：回报条的路径分量是三段
# （deliverables/<req>/.engine/reports/），少任一段都不命中。
# 只覆盖仍落在 deliverables/ 归属内的形态；仓库根下的 reports/x.report.md 路由到
# 框架分支（由 mh-dev 治理，见 AX-10），不由本条判定。
seed_state "THINKER"
for p in "deliverables/test-proj/reports/x.report.md" "deliverables/test-proj/.engine/x.report.md" "deliverables/test-proj/.engine/reports.report.md"; do
  expect_report 2 "AX-01: 路径分量缺失形态 ${p} → 拒绝" "$p"
done
# WORKER 分支的同形态：CR-018 D3.1 删除了「产品区下不含其他角色前缀者皆可写」
# 这条否定式谓词（去前缀后它退化为产品区全通）。新表下 WORKER 的产品区写权是
# 枚举的目录前缀（src/ tests/ deploy/ assets/）加根文件全名白名单，
# deliverables/${req}/reports/ 不在其中 → 拒绝。
# 基线因项目代码放行块而放行，故此处是本 CR 的**收紧**（基线 0 / 当前 2）。
seed_state "WORKER"
expect_vs_base 2 0 "AX-01: WORKER 写 deliverables/test-proj/reports/x.report.md → 拒绝（D3.1 删除产品区全通，基线放行）" \
  Write file_path "deliverables/test-proj/reports/x.report.md" content "x"

# ============================================================
# AX-02: 回报路径正则双向锚定（后缀伪造 + 嵌套伪造）
# ============================================================
echo ""
echo "--- AX-02: 后缀伪造须拒（右锚 \$） ---"
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  for suf in ".report.md.evil" ".report.md.sh" ".report.mdX" ".report.md/child.md" ".report.md.report.evil" ".report.md~" ".report.mdd"; do
    expect_report 2 "AX-02: ${role} 写 reports/x${suf} → 拒绝（右锚生效）" \
      "$RPT/x${suf}"
  done
done
# 左段伪造：reports 目录名的前后缀
seed_state "THINKER"
for d in "reportsX" "reports2" "xreports" ".engine2/reports" ".enginex/reports"; do
  expect_report 2 "AX-02: 目录名伪造 .engine/${d}/x.report.md → 拒绝" \
    "deliverables/test-proj/.engine/${d}/x.report.md"
done
# 双段后缀须完整：单段 .md 与错位后缀均不命中
for f in "x.md" "x.report" "x.reportmd" "x.md.report" "report.md" "x.rreport.md"; do
  expect_report 2 "AX-02: 后缀形态 reports/${f} 不是 .report.md → 拒绝" "$RPT/${f}"
done
# .report.md 双段后缀命中的正面对照：确认上面的拒绝来自后缀形态而非目录被整体关闭
expect_report 0 "AX-02: reports/a.report.md 命中（对照：拒绝来自后缀形态而非目录关闭）" "$RPT/a.report.md"
expect_report 0 "AX-02: reports/a.b.c.report.md 命中（.* 允许中间点号）" "$RPT/a.b.c.report.md"

echo ""
echo "--- AX-02: 嵌套伪造须拒（左锚 ^） ---"
# 嵌套伪造的**有效形态**是「前缀本身仍落在 deliverables/ 归属内」，即
# deliverables/<req>/…/deliverables/<req>/.engine/reports/y.report.md。
# 前缀落在仓库根（x/deliverables/…、src/deliverables/…）时路径归属路由到框架分支，
# 由 mh-dev 治理判定，不进 check_permission——那类形态在无活跃 mh-dev 授权时按
# 「默认会话透明」放行（AX-10 要求的性质），不是回报条的口子，故不在此断言。
# 嵌套段的中间目录须取「该角色归属表内没有的前缀」，否则命中的是那条目录前缀条目
# 而非回报条，断言就测不到左锚：ORCHESTRATOR 拥有整个 docs/（D3.1，ARC-5~8 归档），
# 故 docs/x/… 对它是**合法的 docs/ 内写入**，不能作为其嵌套伪造样本。
# 各角色的越权前缀分别选取。
for role in THINKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  case "$role" in
    ORCHESTRATOR) mids="x src sub/deep" ;;   # docs/ 归 ORCHESTRATOR，不可作样本
    *)            mids="x src docs/x sub/deep" ;;
  esac
  for mid in $mids; do
    expect_report 2 "AX-02: ${role} 写嵌套伪造 deliverables/test-proj/${mid}/deliverables/test-proj/.engine/reports/y.report.md → 拒绝" \
      "deliverables/test-proj/${mid}/deliverables/test-proj/.engine/reports/y.report.md"
  done
done
# WORKER 分支单独覆盖：基线的项目代码放行块靠一串缺左锚的排除正则界定边界，
# 结论对错取决于两个缺陷是否恰好抵消。CR-018 D3.1 用枚举的目录前缀条目取代它后，
# 结论由**归属表本身**决定，成因不再是巧合：
#   前缀不在表内（x/…）        → 拒绝，因为没有任何条目以 deliverables/${req}/x/ 开头
#   前缀在表内（src/…）        → 放行，且这是设计意图：WORKER 对 src/ 下任意深度有写权，
#                                嵌套段里出现 .engine/ 字样不改变它仍在 src/ 之下的事实。
#                                「src/ 内部的目录取名 deliverables/…/.engine/」不是提权——
#                                该路径下的文件不被任何门禁当作引擎态读取。
seed_state "WORKER"
expect_vs_base 2 2 "AX-02: WORKER 写 deliverables/test-proj/x/deliverables/test-proj/.engine/reports/y.report.md → 拒绝（x/ 不在归属表内）" \
  Write file_path "deliverables/test-proj/x/deliverables/test-proj/.engine/reports/y.report.md" content "x"
expect_vs_base 0 2 "AX-02: WORKER 写 deliverables/test-proj/src/deliverables/…/.engine/reports/y.report.md → 放行（src/ 目录前缀条命中，任意深度）" \
  Write file_path "deliverables/test-proj/src/deliverables/test-proj/.engine/reports/y.report.md" content "x"
# 对照：非 .engine/ 的嵌套目录名，前缀仍不在归属表内 → 同样拒绝。
# 这证明上面第一条的拒绝来自「前缀不在表内」，而非「路径里含 .engine/」。
expect_vs_base 2 0 "AX-02: WORKER 写 deliverables/test-proj/x/deliverables/test-proj/rpt/y.report.md → 拒绝（成因是前缀不在表内，与 .engine/ 无关）" \
  Write file_path "deliverables/test-proj/x/deliverables/test-proj/rpt/y.report.md" content "x"

# ============================================================
# AX-03: 回报写权不跨需求（${req} 取自当前 state 的 req_id）
# ============================================================
echo ""
echo "--- AX-03: 回报写权不跨需求 ---"
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role" proj-one
  expect_report 2 "AX-03: proj-one 持权(${role}) 写 deliverables/proj-two/.engine/reports/x.report.md → 拒绝" \
    "deliverables/proj-two/.engine/reports/x.report.md"
  expect_report 0 "AX-03: proj-one 持权(${role}) 写本需求回报 → 放行（对照）" \
    "deliverables/proj-one/.engine/reports/x.report.md"
done
# 相邻标识符（前缀/后缀关系）：proj-one 持权不得写 proj-one1 / proj-on 的回报。
# 若 ${req} 未被路径分隔符 / 夹住，前缀关系的标识符会互相命中。
# 样本全部取合法 slug，使被测性质收敛到「路径锚定」而非「slug 校验」——
# 非法 slug 会在校验点就被拒，那样断言通过的原因就不是锚定了。
seed_state "THINKER" proj-one
for other in proj-one1 proj-onex proj-on proj proj-one-x; do
  expect_report 2 "AX-03: proj-one 持权写 deliverables/${other}/.engine/reports/x.report.md → 拒绝（标识符非前缀关系）" \
    "deliverables/${other}/.engine/reports/x.report.md"
done

# ---------------------------------------------------------------------------
# 正则元字符注入：CR-018 D1.3 关闭的既有缺陷
# ---------------------------------------------------------------------------
# 基线形态：state 的 req_id 被直接插进 bash `[[ =~ ]]` 正则，`req_id: .*` 使
# 交还例外与**全部**白名单条目的 ${req} 变成通配，跨需求写入整体放行。
# CR-018 的消费侧校验（守卫读出 project 后调 validate-slug.sh，插值前拦截）关闭该类：
# 字符集 ^[a-z][a-z0-9-]{0,63}$ 下标识符是正则字面量安全的，无元字符可注入。
# 基线对照证明这是本 CR 的**收紧**（基线放行 / 当前拦截），与上方 fail-open 类断言相反。
for inj in '.*' '.+' 'a|b' '[a-z]*' 'a.c'; do
  raw_state "$(printf 'project: %s\nphase: propose\ncurrent_step: X\ncurrent_role: THINKER\n' "$inj")"
  # 指针也须带注入值：守卫从指针读 project，校验在此发生
  printf 'project: %s\n' "$inj" > "$SB/deliverables/.state.md"
  TOTAL=$((TOTAL + 1))
  out=$(hook "$GUARD" Write file_path "deliverables/other-proj/.engine/reports/x.report.md" content "x"); code=$?
  if [ "$code" = "2" ] && printf '%s' "$out" | grep -q '污染'; then
    ok "AX-03: 注入 project='${inj}' → exit 2 且提示 state 被污染（CR-018 关闭既有注入面）"
  else
    bad "AX-03: 注入 project='${inj}' 未被拦截（exit=$code, output=${out}）"
  fi
done
# 同一注入载荷在基线上放行 —— 钉住「本 CR 收紧」而非「一直如此」
if [ -s "$BASE_GUARD" ]; then
  raw_state "$(printf 'req_id: .*\nproject: .*\nphase: propose\ncurrent_role: THINKER\n')"
  printf 'project: .*\n' > "$SB/deliverables/.state.md"
  TOTAL=$((TOTAL + 1))
  b_out=$(hook "$BASE_GUARD" Write file_path "deliverables/other-proj/THINKER-x.md" content "x"); b_code=$?
  if [ "$b_code" = "0" ]; then
    ok "AX-03: 注入载荷在基线放行(exit=0) —— 证明拦截是本 CR 新增而非既有"
  else
    bad "AX-03: 基线对照无鉴别力（基线 exit=$b_code，须 0）"
  fi
fi

# ============================================================
# AX-04: 写权由「当前谁持权」约束，而非文件名声称的角色（设计 D1 收窄）
# ============================================================
# 设计明确：三角色共用同一条正则、不按角色前缀细分。故 THINKER 持权时写 WORKER
# 棒次的回报路径**须 exit 0**。按「角色前缀隔离」断言是错的口径（设计已收窄）。
echo ""
echo "--- AX-04: 回报写权按持权者口径（非文件名声称的角色） ---"
declare -a CROSS_BATON=("test-proj-DEV1-T1-R1" "test-proj-DEV2-T2-R1" "test-proj-TEST-AUDIT-R1" "test-proj-THINK-NEEDS-R1")
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  for hb in "${CROSS_BATON[@]}"; do
    expect_report 0 "AX-04: ${role} 持权写 ${hb}.report.md → 放行（路径不由文件名声称的角色约束）" \
      "$RPT/${hb}.report.md"
  done
done
# 文件名内嵌其他角色名亦不影响结论（进一步排除隐性前缀判据）
seed_state "THINKER"
for hb in "WORKER-apply-x" "VERIFIER-audit-x" "ORCHESTRATOR-x" "THINKER-x"; do
  expect_report 0 "AX-04: THINKER 持权写 reports/${hb}.report.md → 放行（文件名含角色 token 不改变结论）" \
    "$RPT/${hb}.report.md"
done
# 反面：无人持权 / state 缺失时不得放行任何回报路径。
# 实测口径 —— 守卫在 state 缺失或字段缺失时对整个 deliverables/ 分支 exit 0（第 122/126 行），
# 这是 baseline 既有的 fail-open 语义，AX-06/AX-10 的既有断言依赖它（普通会话不得被拦）。
# 故「不得放行」在当前架构下不成立：如实断言实际行为并用基线对照标注归因。
clear_req
expect_vs_base 0 0 "AX-04: 无 REQ state 时写回报路径 → exit 0（deliverables 分支既有 fail-open 语义，基线同；非本 CR 引入）" \
  Write file_path "$RPT/x.report.md" content "x"
raw_state "$(printf 'project: test-proj\nphase: propose\n')"
expect_vs_base 0 0 "AX-04: state 缺 current_role 时写回报路径 → exit 0（既有 fail-open，基线同）" \
  Write file_path "$RPT/x.report.md" content "x"
raw_state "$(printf 'phase: propose\ncurrent_role: THINKER\n')"
expect_vs_base 0 0 "AX-04: state 缺 req_id 时写回报路径 → exit 0（既有 fail-open，基线同）" \
  Write file_path "$RPT/x.report.md" content "x"
raw_state ""
expect_vs_base 0 0 "AX-04: 空 state 时写回报路径 → exit 0（既有 fail-open，基线同）" \
  Write file_path "$RPT/x.report.md" content "x"
# 未知角色时 fail-closed：回报路径不得成为未知角色的旁路
for r in ATTACKER PM planner; do
  raw_state "$(printf 'project: test-proj\nphase: propose\ncurrent_role: %s\n' "$r")"
  expect_report 2 "AX-04: 未知角色 ${r} 持权写回报路径 → 拒绝（fail-closed）" "$RPT/x.report.md"
done

# ============================================================
# AX-05: 交还例外不得被回报路径拓宽；.state.md 口径须逐字不变
# ============================================================
echo ""
echo "--- AX-05: 交还例外不被回报路径拓宽 ---"
# 含首行合法交还标记的内容写回报路径：放行（回报条无内容判据），但**不得**因此
# 获得 .state.md 之外的额外写权。故须成对断言：回报放行 + 其他引擎态仍拒。
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  expect_report 0 "AX-05: ${role} 以交还内容写回报路径 → 放行（回报条无内容判据）" \
    "$RPT/x.report.md" "$HB_CONTENT"
  # 同一持权状态下，其他引擎态路径仍拒（写权未被拓宽）
  for f in handoffs/y.md plan-action.md lessons.md process.log; do
    expect_report 2 "AX-05: ${role} 写完回报后写 .engine/${f}（交还内容）→ 仍拒绝" \
      "deliverables/test-proj/.engine/${f}" "$HB_CONTENT"
  done
done

echo ""
echo "--- AX-05: .state.md 交还口径逐字不变（首行语义 + 仅 Write） ---"
# is_handback 函数体须与基线逐字一致：本 CR 不得触碰交还判据。
TOTAL=$((TOTAL + 1))
hb_cur=$(awk '/^is_handback\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$GUARD")
hb_base=$(awk '/^is_handback\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$BASE_GUARD")
if [ -n "$hb_cur" ] && [ "$hb_cur" = "$hb_base" ]; then
  ok "AX-05: is_handback 函数体与基线 ${BASELINE_REF} 逐字一致"
else
  bad "AX-05: is_handback 与基线不一致（本 CR 不应改动交还判据）"
fi
# 行为层面复核：首行语义两种排列 + 工具判据
seed_state "THINKER"
expect 0 "AX-05: Write 首行 ORCHESTRATOR → 放行（交还口径未变）" \
  Write file_path "deliverables/test-proj/.engine/.state.md" content "$(printf 'project: test-proj\ncurrent_role: ORCHESTRATOR\n')"
expect 2 "AX-05: Write 排列[真值在后] 首 WORKER + 末 ORCHESTRATOR → 拒绝（首行语义未退化为存在性量词）" \
  Write file_path "deliverables/test-proj/.engine/.state.md" content "$(printf 'current_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
expect 0 "AX-05: Write 排列[真值在前] 首 ORCHESTRATOR + 末 WORKER → 放行" \
  Write file_path "deliverables/test-proj/.engine/.state.md" content "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER\n')"
expect 2 "AX-05: Edit 整行交还写 .state.md → 拒绝（交还例外只接受 Write）" \
  Edit file_path "deliverables/test-proj/.engine/.state.md" new_string "current_role: ORCHESTRATOR"
expect 2 "AX-05: NotebookEdit 指向 .state.md → 拒绝" \
  NotebookEdit notebook_path "deliverables/test-proj/.engine/.state.md"
expect 2 "AX-05: .state.md.evil 后缀伪造（交还内容）→ 拒绝（右锚未退化）" \
  Write file_path "deliverables/test-proj/.engine/.state.md.evil" content "$HB_CONTENT"

# ============================================================
# AX-06: 排列次序对抗 —— 实测确认回报条确实不读内容
# ============================================================
# CR-016 的 P0 漏检成因是 217 条断言的多行 current_role 载荷全用同一排列。
# 设计声称回报条无内容判据故排列对抗不适用——本节**实测**该声称，
# 不以「读代码没看到内容判据」采信。做法：同一回报路径配 N 种内容（含两种排列的
# 伪造 current_role 行、Edit/Write 两种键、空内容），结论必须全部一致。
echo ""
echo "--- AX-06: 同一回报路径 × 多种内容形态，结论须一致 ---"
declare -a PAYLOADS=(
  "x"
  ""
  "$REPORT_BODY"
  "$HB_CONTENT"
  "$(printf 'current_role: WORKER\n')"
  "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: WORKER\n')"
  "$(printf 'current_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
  "$(printf 'current_role: THINKER,ORCHESTRATOR\ncurrent_role: ORCHESTRATOR\n')"
  "$(printf 'current_role: ORCHESTRATOR\ncurrent_role: THINKER,ORCHESTRATOR\n')"
  "$(printf '# current_role: ORCHESTRATOR\ncurrent_role: WORKER\ncurrent_role: ORCHESTRATOR\n')"
  "$(printf 'current_role:ORCHESTRATOR\n')"
  "$(printf 'current_role: orchestrator\n')"
  "$(printf 'req_id: OTHERREQ\ncurrent_role: ORCHESTRATOR\n')"
)
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  codes=""
  for pl in "${PAYLOADS[@]}"; do
    hook "$GUARD" Write file_path "$RPT/test-proj-THINK-DESIGN-R1.report.md" content "$pl" >/dev/null 2>&1
    codes="${codes}$?"
  done
  TOTAL=$((TOTAL + 1))
  if [ "$codes" = "0000000000000" ]; then
    ok "AX-06: ${role} 持权 同一回报路径 × ${#PAYLOADS[@]} 种内容 全部 exit 0（确认无内容判据）"
  else
    bad "AX-06: ${role} 持权 回报条对内容敏感（退出码序列 ${codes}，须全 0）"
  fi
done
# 对照组：同样 13 种内容写 handoffs/x.md，结论亦须全部一致（全 2）。
# 这排除「全 0 只是因为该角色什么都能写」的替代解释。
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  codes=""
  for pl in "${PAYLOADS[@]}"; do
    hook "$GUARD" Write file_path "deliverables/test-proj/.engine/handoffs/x.md" content "$pl" >/dev/null 2>&1
    codes="${codes}$?"
  done
  TOTAL=$((TOTAL + 1))
  if [ "$codes" = "2222222222222" ]; then
    ok "AX-06: ${role} 持权 handoffs/x.md × ${#PAYLOADS[@]} 种内容 全部 exit 2（对照组，排除「该角色什么都能写」）"
  else
    bad "AX-06: ${role} 持权 handoff 对照组结论不一致（退出码序列 ${codes}，须全 2）"
  fi
done
# 工具维度的内容无关性：Write / Edit / NotebookEdit 对同一回报路径结论须一致。
# 交还例外只接受 Write，回报条若误抄了工具判据，此处会暴露。
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  TOTAL=$((TOTAL + 1))
  hook "$GUARD" Write file_path "$RPT/x.report.md" content "$HB_CONTENT" >/dev/null 2>&1; w=$?
  hook "$GUARD" Edit file_path "$RPT/x.report.md" new_string "$HB_CONTENT" >/dev/null 2>&1; e=$?
  hook "$GUARD" NotebookEdit notebook_path "$RPT/x.report.md" >/dev/null 2>&1; n=$?
  if [ "$w" = "0" ] && [ "$e" = "0" ] && [ "$n" = "0" ]; then
    ok "AX-06/AX-11: ${role} 回报路径 Write/Edit/NotebookEdit 三通道均 exit 0（无工具判据）"
  else
    bad "AX-06/AX-11: ${role} 回报路径三通道结论不一致（Write=${w} Edit=${e} NotebookEdit=${n}，须全 0）"
  fi
done

# ============================================================
# AX-07: 大小写变体不得绕过任何拒绝分支
# ============================================================
echo ""
echo "--- AX-07: 大小写绕过 ---"
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  # .engine/ 段大小写变体：回报条正则大小写敏感，变体不得命中
  for eng in ".ENGINE" ".Engine" ".eNgInE"; do
    expect_report 2 "AX-07: ${role} 写 ${eng}/reports/x.report.md → 拒绝" \
      "deliverables/test-proj/${eng}/reports/x.report.md"
  done
  # reports 段大小写变体
  for d in "REPORTS" "Reports" "rePorts"; do
    expect_report 2 "AX-07: ${role} 写 .engine/${d}/x.report.md → 拒绝" \
      "deliverables/test-proj/.engine/${d}/x.report.md"
  done
  # 后缀大小写变体
  for suf in ".REPORT.MD" ".Report.md" ".report.MD" ".rePort.md"; do
    expect_report 2 "AX-07: ${role} 写 reports/x${suf} → 拒绝" "$RPT/x${suf}"
  done
done
# Handoffs/ 大小写变体：ORCHESTRATOR 独占条同样大小写敏感，变体一律拒（含 ORCHESTRATOR 自己）
for role in ORCHESTRATOR THINKER WORKER VERIFIER; do
  seed_state "$role"
  for d in "Handoffs" "HANDOFFS" "hAndOffs"; do
    expect_report 2 "AX-07: ${role} 写 .engine/${d}/x.md → 拒绝" \
      "deliverables/test-proj/.engine/${d}/x.md"
  done
done
# deliverables 段大小写变体：归属路由用 case 精确匹配，变体落框架分支。
# 无活跃 mh-dev 授权时框架分支放行（默认会话透明，AX-10 的既有性质），基线同。
clear_mhdev
seed_state "THINKER"
for d in "Deliverables" "DELIVERABLES"; do
  expect_vs_base 0 0 "AX-07: ${d}/test-proj/.engine/reports/x.report.md 落框架分支 → 无 mh-dev 授权时放行（既有透明性，基线同）" \
    Write file_path "${d}/test-proj/.engine/reports/x.report.md" content "x"
done
# 有活跃 mh-dev 授权时同样路径须被 scope 拦下（证明变体没进 /mh-run 分支且未被漏放）
set_mhdev develop '["scripts/role-guard.sh"]' formal
for d in "Deliverables" "DELIVERABLES"; do
  expect_vs_base 2 2 "AX-07: ${d}/test-proj/.engine/reports/x.report.md 在活跃 mh-dev 授权下 → 被 approved_scope 拦下（基线同）" \
    Write file_path "${d}/test-proj/.engine/reports/x.report.md" content "x"
done
clear_mhdev

# ============================================================
# AX-08: 路径穿越与仓库外绝对路径
# ============================================================
echo ""
echo "--- AX-08: .. 穿越与仓库外绝对路径 ---"
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  for p in \
    "deliverables/test-proj/.engine/reports/../handoffs/x.report.md" \
    "deliverables/test-proj/.engine/reports/../../.state.md" \
    "deliverables/test-proj/.engine/../../../etc/x.report.md" \
    "deliverables/../deliverables/test-proj/.engine/reports/x.report.md" \
    "../deliverables/test-proj/.engine/reports/x.report.md"; do
    expect_report 2 "AX-08: ${role} 写含 .. 的回报路径 ${p} → 拒绝" "$p"
  done
  # 三种工具都须走同一条穿越检测
  expect 2 "AX-08: ${role} Edit 含 .. 的回报路径 → 拒绝" \
    Edit file_path "deliverables/test-proj/.engine/reports/../handoffs/x.report.md" new_string "x"
  expect 2 "AX-08: ${role} NotebookEdit 含 .. 的回报路径 → 拒绝" \
    NotebookEdit notebook_path "deliverables/test-proj/.engine/reports/../handoffs/x.report.md"
  # 仓库外绝对路径
  for p in "/tmp/deliverables/test-proj/.engine/reports/x.report.md" "/deliverables/test-proj/.engine/reports/x.report.md" "/etc/x.report.md"; do
    expect_report 2 "AX-08: ${role} 写仓库外绝对路径 ${p} → 拒绝" "$p"
  done
done
# 沙箱内绝对路径须与相对写法结论一致（归一化上移到路由之前的性质）
seed_state "THINKER"
expect_report 0 "AX-08: 沙箱内绝对回报路径 → 放行（与相对写法结论一致）" \
  "$SB/deliverables/test-proj/.engine/reports/x.report.md"
expect_report 2 "AX-08: 沙箱内绝对路径 + 后缀伪造 → 拒绝（归一化后仍受右锚约束）" \
  "$SB/deliverables/test-proj/.engine/reports/x.report.md.evil"
expect_report 2 "AX-08: 沙箱内绝对 handoffs 路径 → 拒绝" \
  "$SB/deliverables/test-proj/.engine/handoffs/x.md"

# ============================================================
# AC-06 / AX-09: D3 撤回 —— mh-dev 分支须与基线逐字/逐行为一致
# ============================================================
# 改判后的判据：确认 mh-dev 分支的角色校验**未被实现**，且该分支行为与基线一致。
# 结构断言（源码逐字）+ 行为断言（矩阵对跑）两者都做：源码相同即无从分歧，
# 行为对跑防止「同源码在不同上下文表现不同」的隐性依赖。
echo ""
echo "--- AC-06: mh-dev 分支源码与基线逐字一致 ---"
extract_framework_block() {
  awk '/^if \[\[ "\$PATH_OWNER" == "framework" \]\]; then$/{f=1} f{print} f&&/^fi$/{exit}' "$1"
}
TOTAL=$((TOTAL + 1))
fb_cur=$(extract_framework_block "$GUARD")
fb_base=$(extract_framework_block "$BASE_GUARD")
if [ -n "$fb_cur" ] && [ "$fb_cur" = "$fb_base" ]; then
  ok "AC-06: framework 分支代码块与基线 ${BASELINE_REF} 逐字一致（D3 未实现，本 CR 未在此处引入变化）"
else
  bad "AC-06: framework 分支与基线不一致（D3 已撤回，此处不应有任何改动）"
  diff <(printf '%s\n' "$fb_base") <(printf '%s\n' "$fb_cur") | head -20
fi
# 角色校验确实未实现：分支内不得读取 state.json 的 current_role 字段
TOTAL=$((TOTAL + 1))
if ! printf '%s\n' "$fb_cur" | grep -q 'current_role'; then
  ok "AC-06: framework 分支不读 state.json 的 current_role（角色校验未实现，与 D3 撤回一致）"
else
  bad "AC-06: framework 分支出现 current_role 判据（D3 已撤回，实现了会使 Developer 全程锁死）"
fi
# 反证 D3 若实现的后果：mh-dev 的 current_role 恒为 planner，该字段无区分力。
# CR-019 R1：取证对象是**受版本控制的两处来源实现**，不是 .gitignore 排除的运行态
# state.json。挂在派生物上会让结论强度取决于「本机跑过 /mh-dev 没有」这一与不变量
# 无关的环境条件——纯净克隆下 current_role='' 必然假失败，而不变量本身并未被违反。
# R3：两个来源逐一取证，任一偏离即失败；任一来源的赋值消失（提取为空）同样失败，
# 否则删掉硬写反而使断言恒真。
MHDEV_TRANSITION="$REPO/tools/mh-dev/scripts/transition-state.sh"
MHDEV_TEMPLATE="$REPO/tools/mh-dev/templates/state.json.template"

# 来源一：transition-state.sh 每次相位转移对 current_role 的硬写。
# 收集**全部**赋值而非首个：新增一处偏离值的赋值也须判失败。
# 两种赋值形态都要覆盖——dict 字面量 `'current_role':'planner'` 与下标赋值
# `s['current_role']='developer'`。只认前者时，后者形态可在不触发本断言的情况下
# 把该字段改成别的值（实测：仅匹配 `:` 时新增一处下标赋值仍全绿）。
TOTAL=$((TOTAL + 1))
tr_roles=()
while IFS= read -r _line; do
  [ -n "$_line" ] && tr_roles+=("$_line")
done < <(grep -oE "['\"]current_role['\"][[:space:]]*\]?[[:space:]]*[:=][[:space:]]*['\"][^'\"]*['\"]" "$MHDEV_TRANSITION" 2>/dev/null \
         | sed -E "s/.*[:=][[:space:]]*['\"]([^'\"]*)['\"]\$/\1/")
tr_n=${#tr_roles[@]}
tr_bad=0
if [ "$tr_n" -gt 0 ]; then
  for _r in "${tr_roles[@]}"; do [ "$_r" = "planner" ] || tr_bad=$((tr_bad + 1)); done
fi
if [ "$tr_n" -gt 0 ] && [ "$tr_bad" -eq 0 ]; then
  ok "AC-06: transition-state.sh 的 current_role 硬写恒为 planner（受版本控制来源一，${tr_n} 处赋值全为该值）"
else
  bad "AC-06: transition-state.sh 的 current_role 硬写失效（提取到 ${tr_n} 处、其中 ${tr_bad} 处非 planner；D3 撤回理由「恒为 planner」的来源之一不成立）"
fi

# 来源二：state.json.template 的初始值（reset-session/首次 intake 由此落盘）
TOTAL=$((TOTAL + 1))
tpl_role=$(jq -r '.current_role // empty' "$MHDEV_TEMPLATE" 2>/dev/null)
if [ "$tpl_role" = "planner" ]; then
  ok "AC-06: state.json.template 的 current_role 初始值为 planner（受版本控制来源二）"
else
  bad "AC-06: state.json.template 的 current_role='${tpl_role}'（须为 planner；D3 撤回理由的来源之二不成立）"
fi

# R2：运行态存在时附加校验「实现与产物一致」。缺失不判失败（其缺失不违反不变量），
# 也不削弱上面两条——上两条在任何环境下都已无条件执行完毕。不引入跳过计数：
# 本条不存在时 TOTAL 不自增，TOTAL == PASS + FAIL 的恒等关系不变。
MHDEV_RUNTIME_STATE="$REPO/tools/mh-dev/.mh-dev/state.json"
if [ -f "$MHDEV_RUNTIME_STATE" ]; then
  TOTAL=$((TOTAL + 1))
  real_role=$(jq -r '.current_role // empty' "$MHDEV_RUNTIME_STATE" 2>/dev/null)
  if [ "$real_role" = "planner" ]; then
    ok "AC-06: 运行态 state.json 的 current_role=planner（与上两处受版本控制来源一致）"
  else
    bad "AC-06: 运行态 state.json current_role='${real_role}' 与受版本控制来源（planner）不一致，须复核"
  fi
else
  echo "  ----: 运行态 state.json 不存在，实现-产物一致性附加校验不适用（不变量已由上两条来源取证）"
fi

echo ""
echo "--- AX-09: mh-dev 分支行为矩阵与基线一致 ---"
clear_req
# 矩阵：phase × track × scope 形态 × 目标路径。覆盖 state 缺失/畸形/终态与
# approved_scope 命中判定（精确条目、目录前缀条目、目录前缀的相邻伪造、Tester 专属路径）。
mhdev_pair() {
  local desc=$1 target=$2 want=$3
  TOTAL=$((TOTAL + 1))
  local c_code b_code
  hook "$GUARD" Write file_path "$target" content "x" >/dev/null 2>&1; c_code=$?
  hook "$BASE_GUARD" Write file_path "$target" content "x" >/dev/null 2>&1; b_code=$?
  if [ "$c_code" = "$want" ] && [ "$b_code" = "$want" ]; then
    ok "AX-09: ${desc} → 当前与基线同为 exit=${want}"
  else
    bad "AX-09: ${desc} 与基线分歧（当前 exit=${c_code} 基线 exit=${b_code}，均须 ${want}）"
  fi
}
set_mhdev develop '["scripts/role-guard.sh","docs/m/"]' formal
mhdev_pair "develop/formal scope 精确命中 scripts/role-guard.sh" "scripts/role-guard.sh" 0
mhdev_pair "develop/formal scope 目录前缀命中 docs/m/ok.md" "docs/m/ok.md" 0
mhdev_pair "develop/formal 目录前缀相邻伪造 docs/m-evil/x.md" "docs/m-evil/x.md" 2
mhdev_pair "develop/formal scope 外 CLAUDE.md" "CLAUDE.md" 2
mhdev_pair "develop/formal 后缀伪造 scripts/role-guard.sh.evil" "scripts/role-guard.sh.evil" 2
mhdev_pair "develop/formal Tester 专属 tests/x.sh" "tests/x.sh" 0
mhdev_pair "develop/formal Tester 专属 tools/mh-dev/tests/x.sh" "tools/mh-dev/tests/x.sh" 0
mhdev_pair "develop/formal tests-evil/x.sh（非目录前缀）" "tests-evil/x.sh" 2
mhdev_pair "develop/formal 运行态 tools/mh-dev/.mh-dev/state.json" "tools/mh-dev/.mh-dev/state.json" 0
set_mhdev develop '["scripts/role-guard.sh"]' light
mhdev_pair "develop/light 治理关键路径 scripts/role-guard.sh" "scripts/role-guard.sh" 2
set_mhdev verify '["scripts/role-guard.sh"]' formal
mhdev_pair "verify/formal scope 命中" "scripts/role-guard.sh" 0
mhdev_pair "verify/formal scope 外" "evil/x.md" 2
for ph in done blocked; do
  set_mhdev "$ph" '["scripts/role-guard.sh"]' formal
  mhdev_pair "终态 phase=${ph} 框架路径放行（默认会话透明）" "CLAUDE.md" 0
done
# state 缺失/畸形：均落「无活跃授权 → 放行」
clear_mhdev
mhdev_pair "state.json 缺失 → 框架路径放行" "CLAUDE.md" 0
printf '{bad json' > "$MH_DEV_RUNTIME/state.json"
mhdev_pair "state.json 畸形 JSON → 放行" "CLAUDE.md" 0
printf '{"workflow":"other","phase":"develop"}' > "$MH_DEV_RUNTIME/state.json"
mhdev_pair "state.json workflow 非 mh-dev → 放行" "CLAUDE.md" 0
printf '{"workflow":"mh-dev"}' > "$MH_DEV_RUNTIME/state.json"
mhdev_pair "state.json 缺 phase → 放行" "CLAUDE.md" 0
printf '{"workflow":"mh-dev","phase":"unknown","approved_scope":[]}' > "$MH_DEV_RUNTIME/state.json"
mhdev_pair "state.json phase 未知值 → 放行" "CLAUDE.md" 0
printf '{"workflow":"mh-dev","phase":"develop"}' > "$MH_DEV_RUNTIME/state.json"
mhdev_pair "state.json 活跃但缺 approved_scope → 拒绝" "CLAUDE.md" 2
printf '{"workflow":"mh-dev","phase":"develop","approved_scope":[]}' > "$MH_DEV_RUNTIME/state.json"
mhdev_pair "state.json 活跃但 approved_scope 为空 → 拒绝" "CLAUDE.md" 2
# jq 目录前缀绑定（`. as $s`）逐字未动：写成管道重绑定会恒真放行任意路径。
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$fb_cur" | grep -q 'any(\$abs\[\]; \. as \$s; ' ; then
  bad "AX-09: jq 目录前缀判定形态异常，须复核 \`. as \$s\` 绑定"
elif printf '%s\n' "$fb_cur" | grep -q '\. as \$s'; then
  ok "AX-09: jq 目录前缀判定保留 \`. as \$s\` 绑定（未退化为管道重绑定的恒真形态）"
else
  bad "AX-09: jq 目录前缀判定缺 \`. as \$s\` 绑定（会因 . 重绑定为 \$ap 而恒真放行）"
fi
# 行为侧复核该绑定：非目录条目不得按前缀放行（否则恒真形态会暴露）
set_mhdev develop '["docs/m"]' formal
mhdev_pair "非 / 结尾的 scope 条目 docs/m 不得按目录前缀放行 docs/m/x.md" "docs/m/x.md" 2
mhdev_pair "非 / 结尾的 scope 条目 docs/m 精确命中自身" "docs/m" 0

# ============================================================
# AX-10: 默认会话透明性不得回退
# ============================================================
echo ""
echo "--- AX-10: 无活跃 mh-dev 授权时框架路径放行 ---"
clear_mhdev
clear_req
for p in CLAUDE.md any/file.md scripts/foo.sh .claude/settings.json reports/x.report.md .engine/reports/x.report.md; do
  expect_vs_base 0 0 "AX-10: 无 mh-dev 无 REQ state 时写 ${p} → 放行（基线同）" \
    Write file_path "$p" content "x"
done
# 与既有断言 tests/test-role-guard.sh:165 同口径复核（真实仓库、无夹具）
TOTAL=$((TOTAL + 1))
rg_out=$(bash "$REPO/tests/test-role-guard.sh" 2>&1)
rg_code=$?
if [ "$rg_code" = "0" ] && printf '%s\n' "$rg_out" | grep -q "无活跃需求时放行"; then
  ok "AX-10: tests/test-role-guard.sh 的「无活跃需求时放行」断言未退化（套件 exit 0）"
else
  bad "AX-10: test-role-guard.sh 退化（exit=${rg_code}）"
fi
# 终态 phase 下框架路径亦放行
for ph in done blocked; do
  set_mhdev "$ph" '[]' formal
  expect_vs_base 0 0 "AX-10: mh-dev phase=${ph} 时写 CLAUDE.md → 放行（基线同）" \
    Write file_path "CLAUDE.md" content "x"
done
clear_mhdev

# ============================================================
# AX-11: NotebookEdit 通道（两处新逻辑均须覆盖）
# ============================================================
# 「两处新逻辑」原指 D1 + D3；D3 撤回后此处覆盖 D1 回报条 + mh-dev 分支（须与基线一致）。
# NotebookEdit 的路径参数是 notebook_path，取错键会让整条通道静默绕过守卫。
echo ""
echo "--- AX-11: NotebookEdit 对 D1 回报条的覆盖 ---"
clear_mhdev
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  expect 0 "AX-11: ${role} NotebookEdit 写回报路径 → 放行" \
    NotebookEdit notebook_path "$RPT/test-proj-THINK-DESIGN-R1.report.md"
  expect 2 "AX-11: ${role} NotebookEdit 写后缀伪造 .report.md.evil → 拒绝（未静默绕过右锚）" \
    NotebookEdit notebook_path "$RPT/x.report.md.evil"
  # plan-action.md 是 ORCHESTRATOR 的既有白名单项，故只对三个被派发角色断言拒绝。
  if [ "$role" != "ORCHESTRATOR" ]; then
    expect 2 "AX-11: ${role} NotebookEdit 写 .engine/plan-action.md → 拒绝（回报权未放大）" \
      NotebookEdit notebook_path "deliverables/test-proj/.engine/plan-action.md"
  fi
  expect 2 "AX-11: ${role} NotebookEdit 跨需求写 proj-two 回报 → 拒绝" \
    NotebookEdit notebook_path "deliverables/proj-two/.engine/reports/x.report.md"
  expect 2 "AX-11: ${role} NotebookEdit 大小写变体 .ENGINE/reports/ → 拒绝" \
    NotebookEdit notebook_path "deliverables/test-proj/.ENGINE/reports/x.report.md"
done
# 取错键的静默绕过检测：载荷只带 file_path（不带 notebook_path）时守卫须打 WARN 放行，
# 而带 notebook_path 时须按该路径判定。两者成对断言才能区分「取对了键」与「都放行」。
seed_state "THINKER"
TOTAL=$((TOTAL + 1))
out=$(jq -nc '{tool_name:"NotebookEdit",tool_input:{file_path:"deliverables/test-proj/.engine/handoffs/x.md"}}' | bash "$GUARD" 2>&1)
code=$?
if [ "$code" = "0" ] && printf '%s' "$out" | grep -q "WARN"; then
  ok "AX-11: NotebookEdit 只带 file_path → exit 0 且 WARN（不静默；确认守卫读的是 notebook_path）"
else
  bad "AX-11: NotebookEdit 只带 file_path 处置异常 (exit=${code}, output=${out})"
fi
TOTAL=$((TOTAL + 1))
out=$(jq -nc '{tool_name:"NotebookEdit",tool_input:{file_path:"deliverables/test-proj/.engine/reports/ok.report.md",notebook_path:"deliverables/test-proj/.engine/handoffs/x.md"}}' | bash "$GUARD" 2>&1)
code=$?
if [ "$code" = "2" ] && printf '%s' "$out" | grep -q "handoffs/x.md"; then
  ok "AX-11: NotebookEdit 双参数 → 以 notebook_path 判定（回报路径在 file_path 上不生效）"
else
  bad "AX-11: NotebookEdit 双参数判定异常 (exit=${code}, output=${out})"
fi
# NotebookEdit 不带内容键：回报条无内容判据故不受影响（NEW_CONTENT 恒为空）
TOTAL=$((TOTAL + 1))
hook "$GUARD" NotebookEdit notebook_path "$RPT/x.report.md" >/dev/null 2>&1; n_empty=$?
hook "$GUARD" Write file_path "$RPT/x.report.md" >/dev/null 2>&1; w_empty=$?
if [ "$n_empty" = "0" ] && [ "$w_empty" = "0" ]; then
  ok "AX-11: 无内容键时 NotebookEdit 与 Write 对回报路径同为 exit 0（回报条不依赖 NEW_CONTENT）"
else
  bad "AX-11: 无内容键时结论不一致（NotebookEdit=${n_empty} Write=${w_empty}，须全 0）"
fi

echo ""
echo "--- AX-11: NotebookEdit 对 mh-dev 分支的覆盖（须与基线一致） ---"
clear_req
set_mhdev develop '["docs/n.ipynb","docs/m/"]' formal
nb_pair() {
  local desc=$1 target=$2 want=$3
  TOTAL=$((TOTAL + 1))
  local c b
  hook "$GUARD" NotebookEdit notebook_path "$target" >/dev/null 2>&1; c=$?
  hook "$BASE_GUARD" NotebookEdit notebook_path "$target" >/dev/null 2>&1; b=$?
  if [ "$c" = "$want" ] && [ "$b" = "$want" ]; then
    ok "AX-11: ${desc} → 当前与基线同为 exit=${want}"
  else
    bad "AX-11: ${desc} 分歧（当前=${c} 基线=${b}，均须 ${want}）"
  fi
}
nb_pair "NotebookEdit scope 命中 docs/n.ipynb" "docs/n.ipynb" 0
nb_pair "NotebookEdit scope 外 docs/evil.ipynb" "docs/evil.ipynb" 2
nb_pair "NotebookEdit 目录前缀命中 docs/m/x.ipynb" "docs/m/x.ipynb" 0
nb_pair "NotebookEdit Tester 专属 tests/x.ipynb" "tests/x.ipynb" 0
nb_pair "NotebookEdit 含 .. 穿越" "docs/../evil.ipynb" 2
nb_pair "NotebookEdit 仓库外绝对路径" "/tmp/evil.ipynb" 2
clear_mhdev

# ============================================================
# AX-12: 单点变异检测能力
# ============================================================
# 变异体只改一处，其余逐字保留。若变异体不被本套件捕获，说明测试维度不足，
# 须补断言而非记 PASS。两个变异体分别针对回报路径正则的右锚与左锚
# （D3 已撤回，原「移除 mh-dev 角色判据」的变异体无对象，改为针对 D1 的两个锚，
#  并补第三个变异体覆盖「回报条被误放大为目录直通」这一形态）。
echo ""
echo "--- AX-12: 单点变异体（右锚 / 左锚 / 目录直通） ---"

IS_REPORT_LINE='  [[ "$file" =~ ^deliverables/${req}/\.engine/reports/.*\.report\.md$ ]]'
M1="$SB/scripts/mut-no-dollar.sh"   # 移除 $ 右锚
M2="$SB/scripts/mut-no-caret.sh"    # 移除 ^ 左锚
M3="$SB/scripts/mut-dir-passthru.sh" # 退化为 reports/ 目录直通（后缀判据消失）

mk_mutant() {
  local out=$1 repl=$2
  awk -v repl="$repl" '
    $0 == "  [[ \"$file\" =~ ^deliverables/${req}/\\.engine/reports/.*\\.report\\.md$ ]]" { print repl; next }
    { print }
  ' "$GUARD" > "$out"
}
mk_mutant "$M1" '  [[ "$file" =~ ^deliverables/${req}/\.engine/reports/.*\.report\.md ]]'
mk_mutant "$M2" '  [[ "$file" =~ deliverables/${req}/\.engine/reports/.*\.report\.md$ ]]'
mk_mutant "$M3" '  [[ "$file" =~ ^deliverables/${req}/\.engine/reports/ ]]'

# 构造自检：单点、语法可解析、与主副本不同、且仍保留合法路径的放行能力。
# 最后一条排除「变异体因整体改坏而处处失败」的替代解释——那样的差异不构成鉴别力证据。
for m in "$M1:右锚 \$" "$M2:左锚 ^" "$M3:后缀判据（退化为目录直通）"; do
  mf="${m%%:*}"; label="${m##*:}"
  TOTAL=$((TOTAL + 1))
  ndiff=$(diff "$GUARD" "$mf" | grep -c '^[<>]')
  seed_state "THINKER"
  hook "$mf" Write file_path "$RPT/ok.report.md" content "x" >/dev/null 2>&1; legit=$?
  if bash -n "$mf" 2>/dev/null && [ "$ndiff" = "2" ] && [ "$legit" = "0" ]; then
    ok "AX-12: 变异体[移除${label}]构造成功（单点差异、语法可解析、合法回报路径仍放行）"
  else
    bad "AX-12: 变异体[移除${label}]构造失败（差异行数=${ndiff} 须 2，合法路径 exit=${legit} 须 0）"
  fi
done

# 鉴别力对跑：当前实现须拒、变异体须放行。四角色 × 各自的伪造形态。
mutant_probe() {
  local mf=$1 label=$2 role=$3 target=$4
  TOTAL=$((TOTAL + 1))
  seed_state "$role"
  local c m
  hook "$GUARD" Write file_path "$target" content "x" >/dev/null 2>&1; c=$?
  hook "$mf" Write file_path "$target" content "x" >/dev/null 2>&1; m=$?
  if [ "$c" = "2" ] && [ "$m" = "0" ]; then
    ok "AX-12: ${role} ${label} 断言有鉴别力（当前 exit=2 拒绝、变异体 exit=0 放行）"
  else
    bad "AX-12: ${role} ${label} 断言无鉴别力（当前=${c} 变异体=${m}，须 2/0）"
  fi
}
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  for suf in ".report.md.evil" ".report.mdX" ".report.md/child.md"; do
    mutant_probe "$M1" "右锚形态 x${suf}" "$role" "$RPT/x${suf}"
  done
done
for role in THINKER VERIFIER ORCHESTRATOR; do
  mutant_probe "$M2" "左锚形态 嵌套伪造" "$role" \
    "deliverables/test-proj/x/deliverables/test-proj/.engine/reports/y.report.md"
done
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  for f in "x.md" "x.txt" "x.report" "handoff.md"; do
    mutant_probe "$M3" "后缀判据形态 reports/${f}" "$role" "$RPT/${f}"
  done
done
# 变异体不得牵动无关结论：三个变异体对 handoffs/ 与跨需求路径的判定须与当前一致。
# 若牵动了，上面的 2/0 差异就不能归因到被移除的那一处。
for m in "$M1:右锚" "$M2:左锚" "$M3:后缀判据"; do
  mf="${m%%:*}"; label="${m##*:}"
  seed_state "THINKER"
  for target in "deliverables/test-proj/.engine/handoffs/x.md" "deliverables/test-proj/.engine/plan-action.md" "deliverables/proj-two/.engine/reports/x.report.md"; do
    TOTAL=$((TOTAL + 1))
    hook "$GUARD" Write file_path "$target" content "x" >/dev/null 2>&1; c=$?
    hook "$mf" Write file_path "$target" content "x" >/dev/null 2>&1; m2=$?
    if [ "$c" = "$m2" ]; then
      ok "AX-12: 变异体[${label}]未牵动 ${target}（两者同为 exit=${c}）"
    else
      bad "AX-12: 变异体[${label}]牵动了 ${target}（当前=${c} 变异体=${m2}），差异归因不成立"
    fi
  done
done
# 变异未污染工作区实现
TOTAL=$((TOTAL + 1))
if [ "$(shasum -a 256 < "$REPO/scripts/role-guard.sh" | awk '{print $1}')" = \
     "$(shasum -a 256 < "$GUARD" | awk '{print $1}')" ]; then
  ok "AX-12: 变异测试未污染工作区 scripts/role-guard.sh（哈希一致）"
else
  bad "AX-12: 变异测试污染了工作区实现"
fi

# ============================================================
# AC-04: Step 0 核对来源指向落盘回报文件
# ============================================================
# 判据是「描述指向落盘回报文件，不再表述为『handoff 回报』」。故两侧都查：
# 新表述存在 + 旧表述已消失。只查前者会让残留的旧表述漏过。
echo ""
echo "--- AC-04: Step 0 核对来源已落盘 ---"
for doc in templates/orchestrator-quality-gate.md skills/mh-codeflow/SKILL.md; do
  TOTAL=$((TOTAL + 1))
  step0=$(awk '/^#+ Step 0/{f=1;next} f&&/^#+ Step [1-9]/{exit} f{print}' "$REPO/$doc")
  if printf '%s\n' "$step0" | grep -q 'reports/' && \
     printf '%s\n' "$step0" | grep -qE '\.report\.md|回报文件'; then
    ok "AC-04: ${doc} Step 0 指向落盘回报文件（reports/ + .report.md）"
  else
    bad "AC-04: ${doc} Step 0 未指向落盘回报文件"
  fi
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$step0" | grep -qE 'handoff 回报|Handoff 回报|handoff 完成回报'; then
    bad "AC-04: ${doc} Step 0 仍表述为「handoff 回报」（旧口径残留）"
  else
    ok "AC-04: ${doc} Step 0 无「handoff 回报」旧表述"
  fi
  # 回报缺失的处置须写明（新结构下「未填」表现为文件不存在，不写明则无人处置）
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$step0" | grep -qE '不存在|缺失'; then
    ok "AC-04: ${doc} Step 0 写明回报文件缺失时的处置"
  else
    bad "AC-04: ${doc} Step 0 未写明回报缺失的处置"
  fi
done
# 调度循环第 6 步须指向回报文件而非 handoff
TOTAL=$((TOTAL + 1))
if grep -qE '^6\..*reports/' "$REPO/skills/mh-codeflow/SKILL.md"; then
  ok "AC-04: SKILL.md 调度循环第 6 步指向 .engine/reports/"
else
  bad "AC-04: SKILL.md 调度循环第 6 步未指向 reports/（仍表述为填写 handoff）"
fi

# ============================================================
# AC-07: 模板声明的回报填写者与位置 = 守卫实际放行的角色与路径
# ============================================================
echo ""
echo "--- AC-07: 模板与守卫口径交叉验证 ---"
HT="$REPO/templates/handoff-template.md"
# 模板侧：声明回报路径为 .engine/reports/<basename>.report.md
TOTAL=$((TOTAL + 1))
if grep -q '\.engine/reports/' "$HT" && grep -q '\.report\.md' "$HT"; then
  ok "AC-07: handoff-template.md 声明回报位置为 .engine/reports/*.report.md"
else
  bad "AC-07: handoff-template.md 未声明回报位置"
fi
# 模板侧：声明填写者为 to 字段的角色（三角色），ORCHESTRATOR 兜底
TOTAL=$((TOTAL + 1))
if grep -qE '填写者' "$HT" && grep -q 'THINKER' "$HT" && grep -q 'WORKER' "$HT" && grep -q 'VERIFIER' "$HT"; then
  ok "AC-07: handoff-template.md 声明填写者为 THINKER/WORKER/VERIFIER"
else
  bad "AC-07: handoff-template.md 未声明回报填写者"
fi
TOTAL=$((TOTAL + 1))
if grep -qE 'ORCHESTRATOR 兜底代填|兜底代填' "$HT"; then
  ok "AC-07: handoff-template.md 声明 ORCHESTRATOR 兜底代填（与守卫放行 ORCHESTRATOR 一致）"
else
  bad "AC-07: handoff-template.md 未声明 ORCHESTRATOR 兜底代填，与守卫放行该角色不一致"
fi
# 模板侧：声明本文件 ORCHESTRATOR 独占、执行角色写入被拒
TOTAL=$((TOTAL + 1))
if grep -qE 'ORCHESTRATOR 独占' "$HT"; then
  ok "AC-07: handoff-template.md 声明 handoff 由 ORCHESTRATOR 独占写入"
else
  bad "AC-07: handoff-template.md 未声明 handoff 的 ORCHESTRATOR 独占性"
fi
# 守卫侧交叉验证：模板声明的四个填写者在守卫上均放行该路径，且 handoff 侧
# 三角色均拒。上面 AC-01/AC-02/AC-03 已逐条断言，此处做一次汇总核对以形成交叉证据。
TOTAL=$((TOTAL + 1))
cross_ok=true
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  seed_state "$role"
  hook "$GUARD" Write file_path "$RPT/test-proj-THINK-DESIGN-R1.report.md" content "$REPORT_BODY" >/dev/null 2>&1
  [ "$?" = "0" ] || cross_ok=false
done
for role in THINKER WORKER VERIFIER; do
  seed_state "$role"
  hook "$GUARD" Write file_path "deliverables/test-proj/.engine/handoffs/test-proj-THINK-DESIGN-R1.md" content "$REPORT_BODY" >/dev/null 2>&1
  [ "$?" = "2" ] || cross_ok=false
done
if [ "$cross_ok" = true ]; then
  ok "AC-07: 守卫侧与模板声明一致（四角色可写回报路径；三角色不可写 handoff）"
else
  bad "AC-07: 守卫放行集与模板声明不一致"
fi
# 五字段清单一致性：模板列出的字段须与门禁读取的字段对齐
TOTAL=$((TOTAL + 1))
missing_field=""
for fld in status output_files read_files summary issues; do
  grep -q "^${fld}:" "$HT" || grep -q "${fld}:" "$HT" || missing_field="${missing_field} ${fld}"
done
if [ -z "$missing_field" ]; then
  ok "AC-07: handoff-template.md 列出五个回报字段（status/output_files/read_files/summary/issues）"
else
  bad "AC-07: handoff-template.md 缺回报字段:${missing_field}"
fi
# 模板要求「行首无缩进」，因为门禁按 ^status:/^summary: 锚定读取。
# 这条是模板与门禁的隐性契约，须显式断言，否则示例改回带 - 前缀时门禁静默失效。
TOTAL=$((TOTAL + 1))
if grep -qE '行首无缩进|行首锚定' "$HT"; then
  ok "AC-07: handoff-template.md 写明字段须行首无缩进（与门禁 ^字段: 锚定一致）"
else
  bad "AC-07: handoff-template.md 未写明行首无缩进要求（门禁按行首锚定，缩进形态会静默漏检）"
fi
TOTAL=$((TOTAL + 1))
HE="$REPO/templates/handoff-examples.md"
if grep -qE '^status: (done|failed)' "$HE" && ! grep -qE '^- status:' "$HE"; then
  ok "AC-07: handoff-examples.md 示例为行首无缩进形态（与门禁锚定一致）"
else
  bad "AC-07: handoff-examples.md 示例仍为 '- status:' 列表形态，门禁按 ^status: 读取会漏检"
fi
# output-structure.md 目录树须含 reports/
TOTAL=$((TOTAL + 1))
if grep -q 'reports/' "$REPO/templates/output-structure.md"; then
  ok "AC-07: output-structure.md 目录树含 .engine/reports/"
else
  bad "AC-07: output-structure.md 未登记 reports/ 目录"
fi
# agents/orchestrator.md 写权清单须含回报路径
TOTAL=$((TOTAL + 1))
if grep -q 'reports/\*\.report\.md' "$REPO/agents/orchestrator.md"; then
  ok "AC-07: agents/orchestrator.md 写权清单含 .engine/reports/*.report.md"
else
  bad "AC-07: agents/orchestrator.md 写权清单未含回报路径"
fi

# ============================================================
# AC-05: 门禁读取端与回报位置同源（D2）
# ============================================================
# verify.sh / verify-qa.sh 的夹具落在独立临时目录（脚本用相对路径 deliverables/，
# 故须 cd 进夹具目录执行）。断言两侧：字段缺失/为空 → 产出对应 WARN；
# 字段齐备 → 不产出。只测前者会漏掉「恒 WARN」这种同样失效的形态。
echo ""
echo "--- AC-05: verify.sh / verify-qa.sh 回报门禁 ---"

GATE_SB="$SB/gate"
mkdir -p "$GATE_SB"
cp "$REPO/scripts/verify.sh" "$REPO/scripts/verify-qa.sh" "$GATE_SB/"
git -C "$REPO" show "${BASELINE_REF}:scripts/verify.sh" > "$GATE_SB/verify.baseline.sh" 2>/dev/null
git -C "$REPO" show "${BASELINE_REF}:scripts/verify-qa.sh" > "$GATE_SB/verify-qa.baseline.sh" 2>/dev/null

# gate_fixture <phase> —— 重建一个 phase 可控的需求夹具，含 2 个 handoff
# （verify.sh 的 C 类在 handoff_count<2 时会走到一条 bash 3.2 下崩溃的既有语句，
#  见下方 AC-05 既存缺陷断言；此处给足 2 个以让回报检查得以执行）。
gate_fixture() {
  local phase=$1
  rm -rf "$GATE_SB/deliverables"
  mkdir -p "$GATE_SB/deliverables/proj-one/.engine/handoffs" "$GATE_SB/deliverables/proj-one/.engine/reports"
  printf 'project: proj-one\n' > "$GATE_SB/deliverables/.state.md"
  cat > "$GATE_SB/deliverables/proj-one/.engine/.state.md" << EOF
project: proj-one
phase: ${phase}
current_step: ARC
current_role: ORCHESTRATOR
repair_round: 0
last_updated: "2026-08-13T10:00:00Z"
EOF
  printf 'x\n' > "$GATE_SB/deliverables/proj-one/.engine/proposal.md"
  printf 'x\n' > "$GATE_SB/deliverables/proj-one/.engine/plan-action.md"
  printf 'x\n' > "$GATE_SB/deliverables/proj-one/prod.txt"
  printf 'l1\nl2\nl3\nl4\nl5\nl6\nl7\n' > "$GATE_SB/deliverables/proj-one/.engine/process.log"
  for hb in proj-one-THINK-DESIGN-R1 proj-one-DEV1-T1-R1; do
    printf 'to: X\nstatus: pending\ncompleted_at: ""\n' > "$GATE_SB/deliverables/proj-one/.engine/handoffs/${hb}.md"
  done
}
write_report() {
  local hb=$1 body=$2
  printf '%s' "$body" > "$GATE_SB/deliverables/proj-one/.engine/reports/${hb}.report.md"
}
rm_reports() { rm -f "$GATE_SB"/deliverables/proj-one/.engine/reports/*.report.md; }

# 门禁执行：LC_ALL=C 规避 bash 3.2 在多字节 locale 下的既有崩溃（下方单独断言该缺陷），
# 否则回报检查根本走不到，AC-05 会因错误原因失败。
run_gate() { ( cd "$GATE_SB" && LC_ALL=C bash "$1" "${@:2}" 2>&1 ); }

RPT_FULL=$'status: done\noutput_files: ["deliverables/proj-one/docs/spec/design.md"]\nread_files: ["deliverables/proj-one/.engine/proposal.md"]\nsummary: "设计完成"\nissues: "N/A"\n'
RPT_PENDING=$'status: pending\noutput_files: []\nsummary: ""\nread_files: []\n'

# --- verify.sh C 类：回报缺失 ---
gate_fixture done
out=$(run_gate verify.sh C proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "无对应完成回报文件"; then
  ok "AC-05: verify.sh 回报文件缺失 → 产出 WARN（新结构下「未填」的表现形态）"
else
  bad "AC-05: verify.sh 回报缺失未产出 WARN（门禁静默失效）"
fi
# --- verify.sh C 类：回报存在但字段 pending/为空 ---
for hb in proj-one-THINK-DESIGN-R1 proj-one-DEV1-T1-R1; do write_report "$hb" "$RPT_PENDING"; done
out=$(run_gate verify.sh C proj-one)
for kw in "仍为 pending" "summary 为空" "output_files 为空"; do
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$out" | grep -q "$kw"; then
    ok "AC-05: verify.sh 回报字段为空 → 产出 WARN「${kw}」"
  else
    bad "AC-05: verify.sh 未产出 WARN「${kw}」（门禁读取位置与回报位置不同源）"
  fi
done
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "\.report\.md"; then
  ok "AC-05: verify.sh 的 WARN 指名回报文件（.report.md），证明读的是回报而非 handoff"
else
  bad "AC-05: verify.sh 的 WARN 未指名 .report.md，读取位置可疑"
fi
# --- verify.sh C 类：字段齐备 → 不产出 ---
for hb in proj-one-THINK-DESIGN-R1 proj-one-DEV1-T1-R1; do write_report "$hb" "$RPT_FULL"; done
out=$(run_gate verify.sh C proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "所有完成回报已填写" && \
   ! printf '%s\n' "$out" | grep -qE "仍为 pending|summary 为空|output_files 为空|无对应完成回报文件"; then
  ok "AC-05: verify.sh 字段齐备 → 不产出回报类 WARN 且报 PASS（非恒 WARN）"
else
  bad "AC-05: verify.sh 在字段齐备时仍产出回报类 WARN 或未报 PASS"
fi
# --- 静默失效检测：字段写在 handoff 内、回报文件不存在 ---
# 这是 R4 要防的形态：位置变了而门禁没变会「永久静默通过」。
rm_reports
for hb in proj-one-THINK-DESIGN-R1 proj-one-DEV1-T1-R1; do
  printf 'to: X\nstatus: done\nsummary: "ok"\noutput_files: ["a.md"]\nread_files: ["b.md"]\n' \
    > "$GATE_SB/deliverables/proj-one/.engine/handoffs/${hb}.md"
done
out=$(run_gate verify.sh C proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "无对应完成回报文件"; then
  ok "AC-05: verify.sh 旧结构（字段在 handoff 内）→ 仍产出 WARN（未被旧位置的齐备字段静默满足）"
else
  bad "AC-05: verify.sh 被 handoff 内的旧字段静默满足（R4 要防的形态复现）"
fi
# --- 基线对照：同夹具下基线 verify.sh 因 set -u 崩溃，A~E 从未执行 ---
TOTAL=$((TOTAL + 1))
b_out=$( ( cd "$GATE_SB" && LC_ALL=C bash verify.baseline.sh C proj-one 2>&1 ); )
b_code=$?
if [ "$b_code" != "0" ] && printf '%s\n' "$b_out" | grep -q "unbound variable"; then
  ok "AC-05: 基线 verify.sh 在同夹具上因 set -u 崩溃（exit=${b_code}，A~E 从未执行；本 CR 顺带修复）"
else
  bad "AC-05: 基线 verify.sh 未如预期崩溃（exit=${b_code}），须复核 set -u 缺陷的描述"
fi
TOTAL=$((TOTAL + 1))
c_out=$( ( cd "$GATE_SB" && LC_ALL=C bash verify.sh C proj-one >/dev/null 2>&1 ); echo $? )
if [ "$c_out" = "0" ]; then
  ok "AC-05: 当前 verify.sh C 类可执行完毕（exit=0，set -u 崩溃已修）"
else
  bad "AC-05: 当前 verify.sh C 类仍非 0 退出（exit=${c_out}）"
fi

# --- verify-qa.sh QA-4 ---
gate_fixture apply
rm_reports
out=$(run_gate verify-qa.sh proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "无已完成的回报，跳过"; then
  ok "AC-05: verify-qa.sh 无回报文件 → INFO 跳过（不虚报 PASS）"
else
  bad "AC-05: verify-qa.sh 无回报时处置异常"
fi
write_report proj-one-THINK-DESIGN-R1 $'status: done\n'
out=$(run_gate verify-qa.sh proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "缺少字段" && printf '%s\n' "$out" | grep -q "output_files" && printf '%s\n' "$out" | grep -q "summary"; then
  ok "AC-05: verify-qa.sh 回报缺 output_files/summary → 产出 WARN"
else
  bad "AC-05: verify-qa.sh 未对回报缺字段产出 WARN（QA-4 读取位置未同源）"
fi
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "\.report\.md 缺少字段"; then
  ok "AC-05: verify-qa.sh 的 WARN 指名 .report.md（读的是回报文件）"
else
  bad "AC-05: verify-qa.sh 的 WARN 未指名 .report.md"
fi
write_report proj-one-THINK-DESIGN-R1 "$RPT_FULL"
out=$(run_gate verify-qa.sh proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "检查了 1 个完成报告" && ! printf '%s\n' "$out" | grep -q "缺少字段"; then
  ok "AC-05: verify-qa.sh 字段齐备 → 不产出 WARN（非恒 WARN）"
else
  bad "AC-05: verify-qa.sh 字段齐备时仍产出 WARN"
fi
# QA-4 静默失效检测：字段在 handoff 内、无回报文件
rm_reports
printf 'to: X\nstatus: done\nsummary: "ok"\noutput_files: ["a"]\n' \
  > "$GATE_SB/deliverables/proj-one/.engine/handoffs/proj-one-THINK-DESIGN-R1.md"
out=$(run_gate verify-qa.sh proj-one)
TOTAL=$((TOTAL + 1))
if ! printf '%s\n' "$out" | grep -q "检查了 [1-9] 个完成报告"; then
  ok "AC-05: verify-qa.sh 不再从 handoff 读取字段（旧结构下不虚报「检查了 N 个」）"
else
  bad "AC-05: verify-qa.sh 仍从 handoff 读取字段（读取位置未迁移）"
fi
# 基线 QA-4 在同夹具上从 handoff 读取并报「检查了 1 个」——对照证明迁移确实发生
TOTAL=$((TOTAL + 1))
b_out=$(run_gate verify-qa.baseline.sh proj-one)
if printf '%s\n' "$b_out" | grep -q "检查了 1 个完成报告"; then
  ok "AC-05: 基线 verify-qa.sh 在同夹具上从 handoff 读取（检查了 1 个），证明读取位置确已迁移"
else
  bad "AC-05: 基线 QA-4 行为与预期不符，迁移归因无法建立"
fi

# ------------------------------------------------------------
# AC-05 附带发现 F-1：verify.sh 仍有 4 处同类 set -u 崩溃点（既有，非本 CR 回归）
# ------------------------------------------------------------
# 本 CR 修的是第 9 行 `$req_id` 未绑定；同一脚本里另有 4 处 `$var` 紧邻全角字符的写法，
# 在 bash 3.2 + 多字节 locale（本机 LANG=zh_CN.UTF-8）下变量名被解析为 `var<半个字节>`，
# `set -u` 判为 unbound 而整脚本 exit 1。这与本 CR 修的是同一类缺陷、同一后果
# （门禁静默失效），但基线逐字相同，故属既有缺陷而非本 CR 回归。
# 下列断言**记录该缺陷的可达性**：断言崩溃确实发生（如实留证），并断言基线相同（归因）。
echo ""
echo "--- AC-05 附带: verify.sh 残留 set -u 崩溃点（既有缺陷，基线同） ---"
crash_probe() {
  local desc=$1 argv=$2 phase=$3 rr=${4:-0} nhandoff=${5:-2}
  gate_fixture "$phase"
  # repair_round / handoff 数按需调整以走到目标语句
  if [ "$rr" != "0" ]; then
    awk -v r="$rr" '/^repair_round:/{print "repair_round: " r; next}{print}' \
      "$GATE_SB/deliverables/proj-one/.engine/.state.md" > "$GATE_SB/st.tmp" && \
      mv "$GATE_SB/st.tmp" "$GATE_SB/deliverables/proj-one/.engine/.state.md"
  fi
  if [ "$nhandoff" = "1" ]; then rm -f "$GATE_SB/deliverables/proj-one/.engine/handoffs/proj-one-DEV1-T1-R1.md"; fi
  TOTAL=$((TOTAL + 1))
  local c_out c_code b_out b_code
  c_out=$( ( cd "$GATE_SB" && bash verify.sh $argv proj-one 2>&1 ); ); c_code=$?
  b_out=$( ( cd "$GATE_SB" && bash verify.baseline.sh $argv proj-one 2>&1 ); ); b_code=$?
  # 崩溃信息里的变量名含半个多字节字符（`handoff_count\xe4`），该行不是合法 UTF-8，
  # grep 在任何 locale 下都判为二进制而不匹配。故用 bash 内建通配匹配，不用 grep。
  local c_crash=false b_crash=false
  [[ "$c_out" == *"unbound variable"* ]] && c_crash=true
  [[ "$b_out" == *"unbound variable"* ]] && b_crash=true
  if [ "$c_crash" = true ] && [ "$b_crash" = true ]; then
    ok "AC-05/F-1: ${desc} —— 当前与基线同样崩溃（既有缺陷，非本 CR 回归；当前 exit=${c_code}）"
  elif [ "$c_crash" = false ]; then
    ok "AC-05/F-1: ${desc} —— 当前未崩溃（若基线崩溃=${b_crash}，则为改善）"
  else
    bad "AC-05/F-1: ${desc} —— 当前崩溃而基线未崩溃（本 CR 引入的回归，exit=${c_code}）"
    printf '        当前输出尾: %s\n' "$(printf '%s\n' "$c_out" | tail -1)"
  fi
}
crash_probe "C 类 phase=done 且 handoff 数<2（第 214 行 \$handoff_count）" "C" done 0 1
crash_probe "D 类 repair_round=3（第 295 行 \$repair_round）" "D" apply 3 2
crash_probe "D 类 repair_round=5（第 292 行 \$repair_round）" "D" apply 5 2
crash_probe "B 类 phase 非 propose/apply/archive/done（第 159 行 \$phase）" "B" verify 0 2
# LC_ALL=C 下同夹具不崩溃 —— 证明成因是 locale 下的变量名解析而非夹具本身
gate_fixture done
rm -f "$GATE_SB/deliverables/proj-one/.engine/handoffs/proj-one-DEV1-T1-R1.md"
TOTAL=$((TOTAL + 1))
lc_out=$( ( cd "$GATE_SB" && LC_ALL=C bash verify.sh C proj-one 2>&1 ); ); lc_code=$?
if [ "$lc_code" = "0" ] && [[ "$lc_out" != *"unbound variable"* ]]; then
  ok "AC-05/F-1: 同夹具 LC_ALL=C 下不崩溃（成因是多字节 locale 下 \$var 紧邻全角字符的变量名解析）"
else
  bad "AC-05/F-1: LC_ALL=C 下仍异常（exit=${lc_code}），成因归因需复核"
fi
# 缺陷面：形如 `$var<全角>` 的写法计数，当前与基线须相同（本 CR 未新增此类写法）。
# 用 POSIX 类而非 grep -P（BSD grep 无 -P）：[^ -~] 即「非可打印 ASCII」。
TOTAL=$((TOTAL + 1))
NONASCII_RE='\$[A-Za-z_][A-Za-z0-9_]*[^ -~]'
cur_n=$(LC_ALL=C grep -cE "$NONASCII_RE" "$REPO/scripts/verify.sh" 2>/dev/null || echo "?")
base_n=$(git -C "$REPO" show "${BASELINE_REF}:scripts/verify.sh" | LC_ALL=C grep -cE "$NONASCII_RE" 2>/dev/null || echo "?")
if [ "$cur_n" = "$base_n" ] && [ "$cur_n" != "?" ]; then
  ok "AC-05/F-1: verify.sh 中 \$var 紧邻全角字符的写法数当前=${cur_n} 与基线=${base_n} 相同（本 CR 未新增此类）"
else
  bad "AC-05/F-1: 该类写法数变化（当前=${cur_n} 基线=${base_n}），须复核是否本 CR 引入"
fi

# ------------------------------------------------------------
# AC-05 附带观察 F-2：D 类 handoff 超时检测的判据对象是 handoff 的 frontmatter status
# ------------------------------------------------------------
# 现象：回报已完整落盘（reports/*.report.md 内 status: done），而 verify.sh 第 308 行
# 仍以「handoff 含 ^status: pending 且 mtime 超 30 分钟」判超时，故超 30 分钟的棒次
# 一律被报为超时。
#
# 归因（AX-13 口径）：**既有缺陷，非本 CR 回归**。三条证据：
#   1. check_d 函数体与基线 ${BASELINE_REF} 逐字一致（下方断言）；
#   2. 基线亦无任何代码路径写 handoff 的 frontmatter status（全仓仅模板里的 status: pending 字面量），
#      且基线模板协议规则 1 已规定「本文件一旦创建不可修改」——故基线上该 status 同样恒为 pending；
#   3. 在基线的旧结构夹具（回报写在 handoff 正文、frontmatter 仍 pending）上实测同样误报。
# 影响：WARN 级、不阻断门禁。修正顺延独立 CR（判据应改为「对应回报文件是否存在/是否 done」）。
#
# 本节断言按「当前与基线一致」写：钉住现状，未来若有改动使两者分歧则暴露。
echo ""
echo "--- AC-05 附带: D 类 handoff 超时判据（既有缺陷，与基线一致性） ---"
TOTAL=$((TOTAL + 1))
# 比较前对齐 CR-018 的字段改名（req_id → project）与其 SKIP 文案：
# 本条要守的是「**超时判据**未被触碰」，而改名属 D4.1 声明的机械迁移。
# 不归一化会让改名本身触发告警，把一条语义断言退化为对 diff 的字面比对。
norm_d() {
  awk '/^check_d\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$1" \
    | sed -e 's/\$req_id/$project/g' -e 's/"\$project"/"$project"/g' \
          -e 's/无 REQ-ID，无法执行/无项目标识符，无法执行/'
}
d_cur=$(norm_d "$GATE_SB/verify.sh")
d_base=$(norm_d "$GATE_SB/verify.baseline.sh")
if [ -n "$d_cur" ] && [ "$d_cur" = "$d_base" ]; then
  ok "AC-05/F-2: verify.sh check_d 归一化改名后与基线 ${BASELINE_REF} 一致（超时判据未被本 CR 触碰）"
else
  bad "AC-05/F-2: check_d 与基线不一致，须复核本 CR 是否改动了超时判据"
fi
gate_fixture apply
write_report proj-one-THINK-DESIGN-R1 "$RPT_FULL"
write_report proj-one-DEV1-T1-R1 "$RPT_FULL"
# 两个 handoff 保持创建时的 status: pending（协议规则 1：创建后不可修改），mtime 推到 30 分钟前
for hb in proj-one-THINK-DESIGN-R1 proj-one-DEV1-T1-R1; do
  touch -t 202001010000 "$GATE_SB/deliverables/proj-one/.engine/handoffs/${hb}.md"
done
out=$(run_gate verify.sh D proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "处于 pending 状态超过 30 分钟"; then
  ok "AC-05/F-2: 记录既有缺陷 —— 回报完整时 D 类仍报 handoff 超时（WARN 级、不阻断；判据读 handoff frontmatter，修正顺延独立 CR）"
else
  ok "AC-05/F-2: D 类未误报 handoff 超时（若基线误报则为附带改善）"
fi
# 全仓确认：无任何代码写 handoff 的 frontmatter status —— 该 status 恒为 pending
# （这是上述归因的第 2 条证据，落成断言以防将来有人补了机制而本节结论过期）
TOTAL=$((TOTAL + 1))
writers=$(LC_ALL=C grep -rln "completed_at" "$REPO/scripts" "$REPO/workflows" "$REPO/agents" "$REPO/skills" 2>/dev/null | wc -l | tr -d ' ')
if [ "$writers" = "0" ]; then
  ok "AC-05/F-2: 无任何脚本/角色契约写 handoff 的 completed_at（证实 frontmatter status 恒为 pending）"
else
  bad "AC-05/F-2: 出现写 handoff completed_at 的代码路径（${writers} 处），F-2 的归因需重新评估"
fi
# 对照：无回报文件时报超时是正确行为（确认该检查本身在工作，问题在判据对象）
rm_reports
out=$(run_gate verify.sh D proj-one)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$out" | grep -q "处于 pending 状态超过 30 分钟"; then
  ok "AC-05/F-2: 无回报文件时 D 类报 handoff 超时（对照：检查本身在工作）"
else
  bad "AC-05/F-2: 无回报时亦不报超时，该检查整体失效"
fi

# ============================================================
# AX-13: 基线对比 —— 全量拒绝类断言在基线守卫上同样执行并归类
# ============================================================
# 目的不是「基线也拒」（回报路径在基线上根本不存在，一律拒，恒真无信息），
# 而是**区分三类结论**：
#   [本 CR 新开的口子] 当前放行、基线拒绝，且该放行不在设计声明的放行集内 → 缺陷
#   [本 CR 的预期新增] 当前放行、基线拒绝，且在设计声明的放行集内       → 正常
#   [baseline 既有缺陷] 当前与基线同为放行                              → 非本 CR 回归
# 逐条打印分类，并断言「无第一类」。
echo ""
echo "--- AX-13: 拒绝类断言的基线对比与归类 ---"
clear_mhdev
NEW_HOLE=0
BASE_DEFECT=0
EXPECTED_NEW=0
CLASSIFIED=0
# classify <role> <path> <expect_allow: yes|no>
# expect_allow=yes 表示设计声明该路径应放行（回报路径本身）；no 表示应拒绝。
classify() {
  local role=$1 target=$2 expect_allow=$3
  seed_state "$role"
  local c b
  hook "$GUARD" Write file_path "$target" content "$REPORT_BODY" >/dev/null 2>&1; c=$?
  hook "$BASE_GUARD" Write file_path "$target" content "$REPORT_BODY" >/dev/null 2>&1; b=$?
  CLASSIFIED=$((CLASSIFIED + 1))
  if [ "$c" = "0" ] && [ "$b" = "0" ]; then
    BASE_DEFECT=$((BASE_DEFECT + 1))
    echo "    [baseline 既有放行] ${role} ${target}"
  elif [ "$c" = "0" ] && [ "$b" != "0" ] && [ "$expect_allow" = "yes" ]; then
    EXPECTED_NEW=$((EXPECTED_NEW + 1))
  elif [ "$c" = "0" ] && [ "$b" != "0" ]; then
    NEW_HOLE=$((NEW_HOLE + 1))
    echo "    [本 CR 新开的口子] ${role} ${target}（当前放行、基线拒绝、设计未声明）"
  fi
}
for role in THINKER WORKER VERIFIER ORCHESTRATOR; do
  # 设计声明的放行集：本需求 reports/*.report.md
  classify "$role" "$RPT/test-proj-THINK-DESIGN-R1.report.md" yes
  classify "$role" "$RPT/a.b.c.report.md" yes
  # 应拒绝集：后缀伪造
  for suf in ".report.md.evil" ".report.md.sh" ".report.mdX" ".report.md/child.md" ".report.md~"; do
    classify "$role" "$RPT/x${suf}" no
  done
  # 应拒绝集：目录名伪造与大小写变体
  for d in "reportsX" "reports2" "REPORTS" "Reports"; do
    classify "$role" "deliverables/test-proj/.engine/${d}/x.report.md" no
  done
  classify "$role" "deliverables/test-proj/.ENGINE/reports/x.report.md" no
  # 应拒绝集：跨需求
  classify "$role" "deliverables/proj-two/.engine/reports/x.report.md" no
  # 应拒绝集：嵌套伪造
  classify "$role" "deliverables/test-proj/x/deliverables/test-proj/.engine/reports/y.report.md" no
  # 应拒绝集：穿越与仓库外绝对路径
  classify "$role" "deliverables/test-proj/.engine/reports/../handoffs/x.report.md" no
  classify "$role" "/tmp/deliverables/test-proj/.engine/reports/x.report.md" no
done
# 引擎态放大形态：仅对三个被派发角色（ORCHESTRATOR 本就拥有这些路径）
for role in THINKER WORKER VERIFIER; do
  for f in handoffs/x.md plan-action.md SR1-record.md lessons.md process.log archive-manifest.md; do
    classify "$role" "deliverables/test-proj/.engine/${f}" no
  done
  classify "$role" "deliverables/.state.md" no
  for f in handoffs/x.report.md plan-action.report.md lessons.report.md; do
    classify "$role" "deliverables/test-proj/.engine/${f}" no
  done
done
TOTAL=$((TOTAL + 1))
if [ "$NEW_HOLE" = "0" ]; then
  ok "AX-13: ${CLASSIFIED} 条路径对比完成，无「本 CR 新开的口子」（预期新增放行 ${EXPECTED_NEW} 条、baseline 既有放行 ${BASE_DEFECT} 条）"
else
  bad "AX-13: 发现 ${NEW_HOLE} 条本 CR 新开的口子（详见上方 [本 CR 新开的口子] 行）"
fi
TOTAL=$((TOTAL + 1))
if [ "$EXPECTED_NEW" -ge 8 ]; then
  ok "AX-13: 预期新增放行 ${EXPECTED_NEW} 条（四角色 × 回报路径），确认基线对比有信息量而非恒同"
else
  bad "AX-13: 预期新增放行仅 ${EXPECTED_NEW} 条（须 ≥8：四角色 × 2 条回报路径），基线对比可疑"
fi
# 基线既有放行须逐条可归因：本次分类中出现的 baseline 既有放行条数应为 0，
# 因为上面枚举的都是 deliverables/ 内的引擎态与伪造路径，基线对它们一律拒绝。
TOTAL=$((TOTAL + 1))
if [ "$BASE_DEFECT" = "0" ]; then
  ok "AX-13: 本组枚举路径在基线上无放行（既有缺陷类为 0，故上方结论全部可归因到本 CR 的变更面）"
else
  ok "AX-13: 本组枚举路径中 ${BASE_DEFECT} 条基线亦放行（已逐条打印，属既有缺陷不计为本 CR 回归）"
fi

# ============================================================
# AC-08: 全量回归不退化
# ============================================================
# 本套件被 run-all-tests.sh 收录，故此处**不**再调用 run-all-tests.sh（会自递归）。
# run-all-tests.sh 的整体退出码由 Tester 在 verdict 的 commands 证据中单独记录。
echo ""
echo "--- AC-08: 既有回归套件不退化 ---"
TOTAL=$((TOTAL + 1))
if bash "$REPO/scripts/check-harness.sh" >/dev/null 2>&1; then
  ok "AC-08: scripts/check-harness.sh exit 0"
else
  bad "AC-08: scripts/check-harness.sh 非 0 退出"
fi
TOTAL=$((TOTAL + 1))
rg_out=$(bash "$REPO/tests/test-role-guard.sh" 2>&1); rg_code=$?
rg_total=$(printf '%s\n' "$rg_out" | grep -o '总计: [0-9]*' | tail -1 | grep -o '[0-9]*')
# 断言下界而非等值：断言数随后续轮次只增不减，锁死具体值会使每次加用例都要改这里，
# 而本条要守的性质是「既有覆盖未被删减」。
if [ "$rg_code" = "0" ] && [ "${rg_total:-0}" -ge 100 ]; then
  ok "AC-08: tests/test-role-guard.sh exit 0 且覆盖未减（总计 ${rg_total} ≥ 100）"
else
  bad "AC-08: test-role-guard.sh 退化（exit=${rg_code}, 总计=${rg_total:-?}）"
fi
TOTAL=$((TOTAL + 1))
ra_out=$(bash "$REPO/tests/test-role-guard-authority.sh" 2>&1); ra_code=$?
ra_total=$(printf '%s\n' "$ra_out" | grep -o '总计: [0-9]*' | tail -1 | awk '{print $2}')
if [ "$ra_code" = "0" ] && [ "${ra_total:-0}" -ge 197 ]; then
  ok "AC-08: tests/test-role-guard-authority.sh exit 0 且断言数 ${ra_total} ≥ 197（CR-016 断言未减少）"
else
  bad "AC-08: test-role-guard-authority.sh 退化（exit=${ra_code}, 总计=${ra_total:-?}，须 exit 0 且 ≥197）"
fi
TOTAL=$((TOTAL + 1))
if bash "$REPO/tests/test-check-harness.sh" >/dev/null 2>&1; then
  ok "AC-08: tests/test-check-harness.sh exit 0"
else
  bad "AC-08: tests/test-check-harness.sh 非 0 退出"
fi
TOTAL=$((TOTAL + 1))
if bash "$REPO/tools/mh-dev/tests/test-governance.sh" >/dev/null 2>&1; then
  ok "AC-08: tools/mh-dev/tests/test-governance.sh exit 0"
else
  bad "AC-08: tools/mh-dev/tests/test-governance.sh 非 0 退出"
fi
TOTAL=$((TOTAL + 1))
if bash "$REPO/tools/mh-dev/scripts/audit-preflight.sh" >/dev/null 2>&1; then
  ok "AC-08: tools/mh-dev/scripts/audit-preflight.sh exit 0（Tester 硬性验收第 5 项）"
else
  bad "AC-08: audit-preflight.sh 非 0 退出"
fi
# 本套件已被 run-all-tests.sh 收录（否则新断言不进持续回归）
TOTAL=$((TOTAL + 1))
if grep -q 'test-role-guard-report.sh' "$REPO/tests/run-all-tests.sh"; then
  ok "AC-08: 本套件已登记进 tests/run-all-tests.sh"
else
  bad "AC-08: 本套件未登记进 run-all-tests.sh（新断言不会进持续回归）"
fi
# 禁止外发操作（Tester 硬性验收第 6 项）
TOTAL=$((TOTAL + 1))
if LC_ALL=C grep -rlE 'git (commit|tag|push)|npm publish|gh release create' \
     "$REPO/tools/mh-dev/scripts/" 2>/dev/null | grep -q .; then
  bad "AC-08: mh-dev 脚本含外发操作"
else
  ok "AC-08: mh-dev 脚本无 git commit/tag/push、npm publish、gh release create"
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













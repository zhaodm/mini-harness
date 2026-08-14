#!/bin/bash
# verify-ppt.sh - PPT 产出物校验脚本（静态层 bash + 渲染层 Node/Playwright）
# 退出码: 0=全部通过, 1=存在失败项, 2=用法错误, 3=渲染测量环境不可用
# 用法: ./scripts/verify-ppt.sh [A|B|C|D|all] [project]
#       ./scripts/verify-ppt.sh export <html> <out.pdf>
#
# 检查分层：
#   A 文件存在性 · B 静态合规（字号/版式/结构）· C 内容完整性 · D 渲染几何测量
# ⛔ 关键检查禁止 2>/dev/null 配合 || true：字号扫描与登记表解析经 require_ok 包装，
#    执行失败时打印实际 stderr 并累加 ERRORS，绝不当作"无违规"。
# ⛔ 禁止 GNU grep 专有扩展（-P、\K、断言）：仓库运行于 macOS BSD grep。

set -euo pipefail

DELIVERABLES_DIR="deliverables"
TEMPLATES_DIR="templates"
REGISTRY="$TEMPLATES_DIR/ppt-templates/registry.json"
ERRORS=0
WARNINGS=0

check_type="${1:-all}"

# export 子命令：产出单文件 HTML → PDF（复用渲染层依赖，无新增依赖）
if [ "$check_type" = "export" ]; then
    src="${2:-}"; out="${3:-}"
    if [ -z "$src" ] || [ -z "$out" ]; then
        echo "用法: $0 export <html> <out.pdf>" >&2
        exit 2
    fi
    node --input-type=module - "$src" "$out" <<'MJS'
// 全页导出：.slide 默认 visibility:hidden，仅 .is-active 可见。屏幕态下单次 page.pdf()
// 只能截到活跃页——4 页产出出 1 页 PDF 却报 PASS 正是「能力缺失包装成通过」的失效模式。
// 处置：注入打印态样式把叠放的舞台展开为纵向文档流、每页一分页，交由 Chromium 自身
// 分页输出，再断言页数等于 .slide 数，不等即非 0 退出。
const [src, out] = process.argv.slice(2);
let chromium;
try { ({ chromium } = await import('playwright')); }
catch { console.error('FAIL: playwright 未安装 — 执行 npm install'); process.exit(3); }
let browser = null;
for (const opts of [{ channel: 'chrome' }, {}, { channel: 'msedge' }]) {
  try { browser = await chromium.launch(opts); break; } catch { /* 依次回退 */ }
}
if (!browser) { console.error('FAIL: 无可用浏览器引擎'); process.exit(3); }
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto(new URL(src, `file://${process.cwd()}/`).href, { waitUntil: 'load' });
await page.waitForTimeout(300);

const total = await page.evaluate(() => document.querySelectorAll('.slide').length);
if (!total) {
  console.error('FAIL: 未找到 .slide 容器，无可导出页面');
  await browser.close();
  process.exit(1);
}

// 打印态：把绝对定位叠放的 .slide 展开为 1920×1080 的纵向文档流，逐页强制分页。
// 舞台缩放 transform 必须清零——否则 PDF 里是缩放后的尺寸。
await page.addStyleTag({ content: `
@page { size: 1920px 1080px; margin: 0; }
html, body { height: auto !important; overflow: visible !important; background: #fff !important; }
.ppt-viewport { position: static !important; inset: auto !important; display: block !important; overflow: visible !important; }
.ppt-stage { width: 1920px !important; height: auto !important; transform: none !important; position: static !important; }
.ppt-stage > .slide, .slide {
  position: relative !important; inset: auto !important;
  visibility: visible !important; opacity: 1 !important;
  width: 1920px !important; height: 1080px !important;
  transition: none !important;
  break-after: page; page-break-after: always;
}
.ppt-stage > .slide:last-child { break-after: auto; page-break-after: auto; }
.ppt-indicator, .ppt-overview { display: none !important; }
` });
await page.emulateMedia({ media: 'print' });
await page.waitForTimeout(200);

const pdf = await page.pdf({ path: out, width: '1920px', height: '1080px', printBackground: true, preferCSSPageSize: true });
await browser.close();

// 交付断言：导出页数必须等于 .slide 数。不等即失败退出——导出能力缺失不得包装成 PASS。
const got = (pdf.toString('latin1').match(/\/Type\s*\/Page[^s]/g) || []).length;
if (got !== total) {
  console.error(`FAIL: 导出页数 ${got} ≠ 产出页数 ${total} —— 导出不完整（${out} 已写出，勿用于分发）`);
  process.exit(1);
}
console.log(`PASS: 已导出 ${out}（${got}/${total} 页）`);

MJS
    exit $?
fi

project="${2:-}"

if [ -z "$project" ]; then
    if [ -f "$DELIVERABLES_DIR/.state.md" ]; then
        project=$(grep "^project:" "$DELIVERABLES_DIR/.state.md" | awk '{print $2}' || echo "")
    fi
fi

if [ -z "$project" ]; then
    echo "WARN: 未指定项目标识符且无法从 .state.md 读取"
fi

REQ_DIR="$DELIVERABLES_DIR/$project"

fail() { echo "FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

# require_ok DESC CMD... —— 关键检查包装：命令失败时打印实际 stderr 并累加 ERRORS，
# 而非以 2>/dev/null + || true 同时吞掉错误与退出码（缺陷 1 的失效模式）。
#
# 命令输出经全局 REQUIRE_OK_OUT 回传，而不是写到 stdout 供 $(...) 捕获——后者会把
# require_ok 放进子 shell，ERRORS 的累加随子 shell 一同丢弃，包装就成了纯装饰。
# 用法：require_ok "描述" cmd args || 附加处置; 随后读 "$REQUIRE_OK_OUT"
# 失败时 REQUIRE_OK_OUT 被清空，故"输出为空"只可能是真无违规或已记为错误两种情况。
REQUIRE_OK_OUT=""
require_ok() {
    local desc="$1"; shift
    local rc=0
    REQUIRE_OK_OUT=""
    REQUIRE_OK_OUT=$("$@" 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "$desc 执行失败（退出码 ${rc}）: $REQUIRE_OK_OUT"
        REQUIRE_OK_OUT=""
        return 1
    fi
    return 0
}

# 读取密度档：读不到时默认低密度（speaker，更严格档），不默认宽松档
read_density() {
    local d=""
    if [ -n "$project" ] && [ -f "$REQ_DIR/.engine/.state.md" ]; then
        d=$(grep "^ppt_density:" "$REQ_DIR/.engine/.state.md" | awk '{print $2}' | tr -d '"' || echo "")
    fi
    case "$d" in
        reading) echo "reading" ;;
        *) echo "speaker" ;;
    esac
}

read_design_mode() {
    local m=""
    if [ -n "$project" ] && [ -f "$REQ_DIR/.engine/.state.md" ]; then
        m=$(grep "^ppt_design_mode:" "$REQ_DIR/.engine/.state.md" | awk '{print $2}' | tr -d '"' || echo "")
    fi
    case "$m" in
        creative) echo "creative" ;;
        *) echo "system" ;;
    esac
}

DENSITY="$(read_density)"
DESIGN_MODE="$(read_design_mode)"
case "$DENSITY" in
    reading) FONT_FLOOR=14 ;;
    *) FONT_FLOOR=18 ;;
esac

# ---------------------------------------------------------------------------
# 版式登记表读取（registry.json 每个 layout 对象单行，见 ppt-quality-rules.md）
# ---------------------------------------------------------------------------
registry_table() {
    [ -f "$REGISTRY" ] || return 1
    awk '
      /"id":/ && /"density":/ {
        id=""; den=""; typ=""
        if (match($0, /"id": *"[^"]*"/)) { id=substr($0, RSTART, RLENGTH); sub(/"id": *"/, "", id); sub(/"$/, "", id) }
        if (match($0, /"density": *"[^"]*"/)) { den=substr($0, RSTART, RLENGTH); sub(/"density": *"/, "", den); sub(/"$/, "", den) }
        if (match($0, /"layout_type": *"[^"]*"/)) { typ=substr($0, RSTART, RLENGTH); sub(/"layout_type": *"/, "", typ); sub(/"$/, "", typ) }
        if (id != "" && den != "") print id "\t" den "\t" typ
      }
    ' "$REGISTRY"
}

# 登记表解析是关键检查：解析失败会让全部版式取值校验静默放行，故经 require_ok 累加
REGISTRY_TABLE=""
if [ -f "$REGISTRY" ]; then
    require_ok "$REGISTRY 登记表解析" registry_table || true
    REGISTRY_TABLE="$REQUIRE_OK_OUT"
    if [ -z "$REGISTRY_TABLE" ]; then
        fail "$REGISTRY 解析结果为空（每个 layout 对象须单行且含 id/density）"
    fi
fi

registry_ids() { printf '%s\n' "$REGISTRY_TABLE" | awk -F'\t' 'NF>0 {print $1}'; }
registry_density_of() { printf '%s\n' "$REGISTRY_TABLE" | awk -F'\t' -v k="$1" '$1==k {print $2; exit}'; }
registry_type_of() { printf '%s\n' "$REGISTRY_TABLE" | awk -F'\t' -v k="$1" '$1==k {print $3; exit}'; }

# 按文件名解析所属密度档：登记版式用登记密度，主题 CSS 按主题归属，其余用流程密度
floor_for_file() {
    local base id den
    base=$(basename "$1")
    case "$base" in
        ppt-base.css) echo 18; return ;;
        ppt-light.css) echo 14; return ;;
    esac
    id=$(printf '%s' "$base" | awk -F'-' '{print $1}')
    den=$(registry_density_of "$id")
    case "$den" in
        reading) echo 14 ;;
        speaker) echo 18 ;;
        *) echo "$FONT_FLOOR" ;;
    esac
}

# ---------------------------------------------------------------------------
# 字号扫描（AC-01 / AC-09 / AX-01 / AX-05）
#   纯 POSIX awk。覆盖三种字号声明形态，缺一即为绕过通道：
#     1. font-size: <n>px      字面量
#     2. --font-*: <n>px       设计系统字号 token 定义（CSS 本体的字号只在此处出现字面值）
#     3. font: 600 <n>px/1 ... 简写中的字号分量（ppt-base.html 骨架本身即用此写法）
#   逐行判定：一行内出现的每个声明都与该行的豁免资格结合判断。
#   豁免（AX-05）：仅当该行文本内容去掉符号字符后不含字母/汉字/数字时生效——
#   data-glyph 或图形 class 无法被用作承载可读文字的绕过后门。
# 输出：每个违规一行 "行号:字号:上下文"
# ---------------------------------------------------------------------------
scan_small_fonts() {
    local file="$1" floor="$2"
    awk -v floor="$floor" '
      function report(size, floor, line, lineno,   ctx) {
        if (size + 0 >= floor + 0) return
        ctx = line; gsub(/^[ \t]+/, "", ctx)
        if (length(ctx) > 70) ctx = substr(ctx, 1, 70) "..."
        print lineno ":" size ":" ctx
      }
      {
        line = $0
        # 该行是否声明豁免资格
        marked = (line ~ /data-glyph="true"/) || (line ~ /trend-arrow/) || (line ~ /icon-dot/) || (line ~ /timeline-node/)
        exempt = 0
        if (marked) {
          # 取出可读文本载荷。HTML 行取标签之间的文本节点；CSS/JS 行（无标签）
          # 只取 content: 的值——否则整条规则文本（选择器、属性名）会被误当作可读文字。
          payload = ""
          if (line ~ /</) {
            payload = line
            gsub(/<[^>]*>/, " ", payload)        # 去标签，只留文本节点
          }
          # content 值的引号用字符类表达，避免在 shell 单引号 awk 程序中嵌入引号字面量
          if (match(line, /content: *[\047"][^\047"]*[\047"]/)) {
            c = substr(line, RSTART, RLENGTH)
            sub(/content: *./, "", c); sub(/.$/, "", c)
            payload = payload " " c
          }
          # 剥离已登记的图形符号字符
          gsub(/▲|▼|◆|◇|●|○|■|□|★|☆|→|←|↑|↓|•|·|▪|▸|✓|✔|✕|✖|—|–/, "", payload)
          gsub(/[ \t]/, "", payload)
          # 残留含字母/数字/非 ASCII（汉字）则豁免失效
          if (payload !~ /[0-9A-Za-z]/ && payload !~ /[^\000-\177]/) exempt = 1
        }
        if (exempt) next

        # 形态 1: font-size: <n>px 字面量
        rest = line
        while (match(rest, /font-size: *[0-9]+px/)) {
          decl = substr(rest, RSTART, RLENGTH)
          rest = substr(rest, RSTART + RLENGTH)
          size = decl
          sub(/font-size: *=?/, "", size); sub(/px/, "", size)
          report(size, floor, line, NR)
        }

        # 形态 2: CSS 自定义属性字号 token 定义（--font-caption: 18px）
        #   设计系统 CSS 的字号全部走 var(--font-*)，字面 px 只出现在 token 定义行。
        #   不判定 token 取值 = 字号底线对设计系统本体不生效（缺陷 F-01）。
        rest = line
        while (match(rest, /--font-[A-Za-z-]*: *[0-9]+px/)) {
          decl = substr(rest, RSTART, RLENGTH)
          rest = substr(rest, RSTART + RLENGTH)
          size = decl
          sub(/--font-[A-Za-z-]*: */, "", size); sub(/px.*$/, "", size)
          report(size, floor, line, NR)
        }

        # 形态 3: font 简写（font: 600 8px/1 sans-serif）—— 取值中首个 <n>px 即字号分量。
        #   前置字符为 - 或字母数字时跳过（避免把 x-font: 之类同后缀属性当作简写）。
        rest = line
        while (match(rest, /font: *[^;{}"\047]*/)) {
          decl = substr(rest, RSTART, RLENGTH)
          prevch = (RSTART > 1) ? substr(rest, RSTART - 1, 1) : ""
          rest = substr(rest, RSTART + RLENGTH)
          if (prevch ~ /[-_A-Za-z0-9]/) continue
          if (!match(decl, /[0-9]+px/)) continue
          size = substr(decl, RSTART, RLENGTH); sub(/px/, "", size)
          report(size, floor, line, NR)
        }
      }
    ' "$file"
}

# ---------------------------------------------------------------------------
# 检查器自检（防复发）
#   缺陷 1 的本质不是正则写错，而是检查器失效时无人知晓。静态扫描防不住新引入的
#   等价写法，运行时自检才防得住：对已知违规/合规 fixture 各测一次，行为不符即阻断。
# ---------------------------------------------------------------------------
selftest_font_checker() {
    local tmp rc=0
    tmp=$(mktemp -t ppt-selftest) || { echo "FAIL: 自检临时文件创建失败"; exit 1; }
    {
        printf '%s\n' '<div style="font-size:13px">违规正文</div>'
        printf '%s\n' '<div style="font-size: 18px">合规正文</div>'
        printf '%s\n' '<span data-glyph="true" style="font-size:8px">▲</span>'
        printf '%s\n' '<span data-glyph="true" style="font-size:8px">营收上升</span>'
        printf '%s\n' '  --font-caption: 9px;'
        printf '%s\n' '  --font-body: 26px;'
        printf '%s\n' '<div style="font: 600 8px/1 sans-serif">简写违规</div>'
        printf '%s\n' '<div style="font: 600 20px/1.4 sans-serif">简写合规</div>'
        printf '%s\n' '  font-family: -apple-system, sans-serif; /* 8px 不在取值中 */'
    } > "$tmp"

    local result
    result=$(scan_small_fonts "$tmp" 18) || rc=$?
    rm -f "$tmp"
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: 检查器自身失效 —— 字号扫描器执行异常（退出码 ${rc}）"
        exit 1
    fi

    # 期望检出：L1（13px 字面量）· L4（豁免滥用于可读文字）· L5（token 定义 9px）· L7（简写 8px）
    # 期望放行：L2（18px）· L3（纯符号 8px）· L6（token 26px）· L8（简写 20px）· L9（font-family 非字号）
    local hit_violation hit_abuse hit_ok hit_glyph hit_token hit_token_ok hit_short hit_short_ok hit_family
    hit_violation=$(printf '%s\n' "$result" | grep -c '^1:13:' || true)
    hit_ok=$(printf '%s\n' "$result" | grep -c '^2:' || true)
    hit_glyph=$(printf '%s\n' "$result" | grep -c '^3:' || true)
    hit_abuse=$(printf '%s\n' "$result" | grep -c '^4:8:' || true)
    hit_token=$(printf '%s\n' "$result" | grep -c '^5:9:' || true)
    hit_token_ok=$(printf '%s\n' "$result" | grep -c '^6:' || true)
    hit_short=$(printf '%s\n' "$result" | grep -c '^7:8:' || true)
    hit_short_ok=$(printf '%s\n' "$result" | grep -c '^8:' || true)
    hit_family=$(printf '%s\n' "$result" | grep -c '^9:' || true)

    if [ "$hit_violation" -ne 1 ] || [ "$hit_abuse" -ne 1 ] || [ "$hit_token" -ne 1 ] || [ "$hit_short" -ne 1 ] \
       || [ "$hit_ok" -ne 0 ] || [ "$hit_glyph" -ne 0 ] || [ "$hit_token_ok" -ne 0 ] \
       || [ "$hit_short_ok" -ne 0 ] || [ "$hit_family" -ne 0 ]; then
        echo "FAIL: 检查器自身失效 —— 字号检查未按预期工作"
        echo "      期望: 检出 font-size 13px / 豁免滥用 8px / token 9px / 简写 8px"
        echo "            放行 18px、纯符号 8px、token 26px、简写 20px、font-family"
        echo "      实测: literal=$hit_violation abuse=$hit_abuse token=$hit_token shorthand=$hit_short"
        echo "            误报: ok=$hit_ok glyph=$hit_glyph token_ok=$hit_token_ok shorthand_ok=$hit_short_ok family=$hit_family"
        echo "      提示: 若刚修改过 scan_small_fonts，其行为已与契约不符，禁止以此状态报告通过"
        exit 1
    fi
    echo "PASS: 检查器自检通过（字号扫描器行为符合契约：字面量 + token + 简写三形态）"
}

# 设计系统在效判定（AC-08 / 设计文档 D3）
#   形态 1: 外链 ppt-base.css / ppt-light.css —— 开发期与仓库内形态
#   形态 2: 内联 <style> 含设计系统标识性 token 定义 —— 自包含可分发形态
#   两者等效：判据是产出是否真受设计系统约束，而非是否写了某个文件名。
design_system_in_effect() {
    local f="$1"
    grep -q 'ppt-base.css\|ppt-light.css' "$f" && return 0
    grep -q -- '--font-body: *[0-9]' "$f" && grep -q -- '--slide-width: *[0-9]' "$f" && return 0
    return 1
}

# 解析待检目标：优先产品区根 HTML（最终产出），其次 wireframes，最后 templates
resolve_target_dir() {
    if [ -n "$project" ] && [ -d "$REQ_DIR" ]; then
        if [ "$(find "$REQ_DIR" -maxdepth 1 -name "*.html" | wc -l | tr -d ' ')" -gt 0 ]; then
            echo "$REQ_DIR"; return
        fi
    fi
    if [ -n "$project" ] && [ -d "$REQ_DIR/assets/wireframes" ]; then
        if [ "$(find "$REQ_DIR/assets/wireframes" -maxdepth 1 -name "*.html" | wc -l | tr -d ' ')" -gt 0 ]; then
            echo "$REQ_DIR/assets/wireframes"; return
        fi
    fi
    echo "$TEMPLATES_DIR/ppt-templates/layouts"
}

# A类检查: 文件存在性
check_a() {
    echo "=== A类检查: PPT 文件存在性 ==="

    if [ -z "$project" ]; then
        echo "SKIP: 无项目标识符"
        return
    fi

    if [ ! -s "$REQ_DIR/docs/spec/slide-spec.md" ]; then
        fail "$REQ_DIR/docs/spec/slide-spec.md 缺失或为空"
    else
        echo "PASS: $REQ_DIR/docs/spec/slide-spec.md"
    fi

    if [ ! -d "$REQ_DIR/assets/wireframes" ]; then
        fail "$REQ_DIR/assets/wireframes/ 目录不存在"
    else
        local wf_count
        wf_count=$(find "$REQ_DIR/assets/wireframes" -maxdepth 1 -name "*.html" | wc -l | tr -d ' ')
        if [ "$wf_count" -eq 0 ]; then
            fail "$REQ_DIR/assets/wireframes/ 无 HTML 文件"
        else
            echo "PASS: $REQ_DIR/assets/wireframes/ ($wf_count 个文件)"
        fi
    fi

    # 单文件形态（AC-08）：产品区根应恰有 1 个 HTML
    if [ -d "$REQ_DIR" ]; then
        local out_count
        out_count=$(find "$REQ_DIR" -maxdepth 1 -name "*.html" | wc -l | tr -d ' ')
        if [ "$out_count" -eq 0 ]; then
            echo "INFO: $REQ_DIR/ 无 HTML 文件（Worker 尚未实现）"
        elif [ "$out_count" -gt 1 ]; then
            fail "$REQ_DIR/ 有 $out_count 个 HTML —— 单文件形态要求恰好 1 个（导航在文件内实现一次）"
        else
            echo "PASS: $REQ_DIR/ 单文件产出形态"
        fi
    fi
}

# B类检查: 静态合规（结构 + 字号 + 版式声明与多样性）
check_b() {
    echo "=== B类检查: 静态合规 ==="

    selftest_font_checker

    local target_dir
    target_dir="$(resolve_target_dir)"
    echo "INFO: 检查目录 $target_dir · 密度档 ${DENSITY}（绝对下限 ${FONT_FLOOR}px）· 设计模式 $DESIGN_MODE"

    local html_files
    html_files=$(find "$target_dir" -maxdepth 1 -name "*.html" -not -name ".*" | sort)

    if [ -z "$html_files" ]; then
        fail "$target_dir 无 HTML 文件可检查（PPT 轨必须有产出，不得静默跳过）"
        return
    fi

    local is_single_file=0
    if [ "$(printf '%s\n' "$html_files" | wc -l | tr -d ' ')" -eq 1 ] && [ "$target_dir" = "$REQ_DIR" ]; then
        is_single_file=1
    fi

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        local fname file_errors floor
        fname=$(basename "$f")
        file_errors=0
        floor=$(floor_for_file "$f")

        if ! grep -q 'width=1920' "$f"; then
            fail "$fname - 缺少 viewport width=1920"
            file_errors=$((file_errors + 1))
        fi

        if ! grep -q 'class="slide' "$f"; then
            fail "$fname - 缺少 .slide 容器"
            file_errors=$((file_errors + 1))
        fi

        # 设计系统在效（system 模式）。判据是「产出真的受设计系统约束」，不是「写了某个
        # 文件名」——强制外链会把内联 CSS 的真正自包含产出误判为 FAIL，而外链产出脱离
        # 仓库后样式全失。故外链与内联 token 二者任一即通过（设计文档 D3）。
        if [ "$DESIGN_MODE" != "creative" ]; then
            if ! design_system_in_effect "$f"; then
                fail "$fname - 设计系统未在效：既未外链 ppt-base.css/ppt-light.css，内联样式中也无设计系统 token（--font-body / --slide-width 等）"
                file_errors=$((file_errors + 1))
            fi
        fi

        # 字号底线（AC-01 / AC-09 / AX-01）—— 扫描器自身执行失败经 require_ok 计入错误，
        # 不得被当作"无违规"
        local small
        require_ok "$fname 字号扫描" scan_small_fonts "$f" "$floor" \
            || file_errors=$((file_errors + 1))
        small="$REQUIRE_OK_OUT"
        if [ -n "$small" ]; then
            fail "$fname - 存在低于 ${floor}px 底线的字号（$(printf '%s\n' "$small" | wc -l | tr -d ' ') 处）:"
            printf '%s\n' "$small" | head -5 | while IFS= read -r line; do
                echo "      L${line%%:*}: ${line#*:}"
            done
            file_errors=$((file_errors + 1))
        fi

        # 导航（单文件形态下导航只需在文件内实现一次；布局模板片段不要求）
        if [ "$is_single_file" -eq 1 ]; then
            if ! grep -q 'ArrowRight' "$f" || ! grep -q 'ArrowLeft' "$f"; then
                fail "$fname - 缺少方向键导航（←→ 键盘处理）"
                file_errors=$((file_errors + 1))
            fi
        fi

        if [ "$file_errors" -eq 0 ]; then
            echo "PASS: ${fname}（底线 ${floor}px）"
        fi
    done <<< "$html_files"

    check_layout_declarations "$html_files"
}

# ---------------------------------------------------------------------------
# 版式声明与多样性（AC-06 / AC-07 / AX-08）
#   声明形态: <section class="slide" data-layout="L03" data-slide-id="s02">
#   creative 模式须同时声明 data-layout-type（自定义 ID 不在登记表内，无法反查类型）
# ---------------------------------------------------------------------------
check_layout_declarations() {
    local html_files="$1"
    echo "--- 版式声明与多样性 ---"

    # 逐页收集：每个 .slide 容器一条记录 "layout<TAB>type"
    local pages
    pages=$(printf '%s\n' "$html_files" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        awk '
          # 只匹配真正的页面容器：class 值以 slide 起始且后随引号/空格，
          # 排除 .slide-header / .slide-title / .slide-meta 等页内元素
          /class="slide["[:space:]]/ || /class="slide$/ {
            lay=""; typ=""
            if (match($0, /data-layout="[^"]*"/)) { lay=substr($0, RSTART, RLENGTH); sub(/data-layout="/, "", lay); sub(/"$/, "", lay) }
            if (match($0, /data-layout-type="[^"]*"/)) { typ=substr($0, RSTART, RLENGTH); sub(/data-layout-type="/, "", typ); sub(/"$/, "", typ) }
            print lay "\t" typ
          }
        ' "$f"
    done)

    if [ -z "$pages" ]; then
        fail "未找到任何 .slide 页面容器，版式统计无法进行"
        return
    fi

    local total missing
    total=$(printf '%s\n' "$pages" | wc -l | tr -d ' ')
    missing=$(printf '%s\n' "$pages" | awk -F'\t' '$1=="" {c++} END {print c+0}')

    # 声明缺失：两种模式均 FAIL（AX-08——多样性统计依赖该标识存在）
    if [ "$missing" -gt 0 ]; then
        fail "$missing/$total 页缺少 data-layout 声明（system 与 creative 模式均要求声明存在）"
    fi

    # 取值校验：system 模式须属登记集合；creative 模式放行任意取值（AX-08）
    if [ "$DESIGN_MODE" != "creative" ]; then
        local known unknown
        known="$(registry_ids)"
        unknown=$(printf '%s\n' "$pages" | awk -F'\t' '$1!="" {print $1}' | sort -u | while IFS= read -r id; do
            printf '%s\n' "$known" | grep -qx "$id" || echo "$id"
        done)
        if [ -n "$unknown" ]; then
            fail "system 模式下声明了未登记版式: $(printf '%s' "$unknown" | tr '\n' ' ')（登记表 ${REGISTRY}）"
        fi
    else
        echo "INFO: creative 模式 —— 版式取值不受登记集合限制"
        local untyped
        untyped=$(printf '%s\n' "$pages" | awk -F'\t' '$1!="" && $2=="" {print $1}' | sort -u | while IFS= read -r id; do
            registry_type_of "$id" | grep -q . || echo "$id"
        done)
        if [ -n "$untyped" ]; then
            fail "creative 模式下自定义版式缺少 data-layout-type，无法参与多样性统计: $(printf '%s' "$untyped" | tr '\n' ' ')"
        fi
    fi

    # 多样性 1：layout_type 去重种类 < 4 → FAIL
    local types kinds
    types=$(printf '%s\n' "$pages" | awk -F'\t' '$1!="" {print $1 "\t" $2}' | while IFS="$(printf '\t')" read -r id typ; do
        if [ -n "$typ" ]; then
            echo "$typ"
        else
            registry_type_of "$id"
        fi
    done | grep . | sort -u)
    kinds=$(printf '%s\n' "$types" | grep -c . || true)
    if [ "$total" -ge 4 ] && [ "$kinds" -lt 4 ]; then
        fail "版式类型仅 $kinds 种（要求 ≥4）: $(printf '%s' "$types" | tr '\n' ' ')"
    elif [ "$kinds" -ge 4 ]; then
        echo "PASS: 版式类型 $kinds 种（$total 页）"
    fi

    # 多样性 2：连续 ≥3 页同一 data-layout → FAIL
    local streak
    streak=$(printf '%s\n' "$pages" | awk -F'\t' '
      $1=="" { prev=""; run=0; next }
      {
        if ($1==prev) run++; else { prev=$1; run=1 }
        if (run>=3 && run>best) { best=run; who=$1 }
      }
      END { if (best>0) print who "\t" best }
    ')
    if [ -n "$streak" ]; then
        fail "连续 $(printf '%s' "$streak" | cut -f2) 页使用同一版式 $(printf '%s' "$streak" | cut -f1)（上限：连续 2 页）"
    else
        echo "PASS: 无连续 3 页同一版式"
    fi
}

# C类检查: 内容完整性 + 页数一致性 + CSS 字号覆盖
check_c() {
    echo "=== C类检查: 内容完整性 ==="

    # CSS 文件字号检查（AC-09：字号检查须覆盖 CSS 文件，此前仅扫 *.html）
    echo "--- CSS 字号底线 ---"
    local css_files css_floor css_small css_scan_ok
    css_files=$(find "$TEMPLATES_DIR" -maxdepth 1 -name "ppt-*.css" | sort)
    if [ -n "$project" ] && [ -d "$REQ_DIR" ]; then
        local req_css
        req_css=$(find "$REQ_DIR" -maxdepth 1 -name "*.css" | sort)
        [ -n "$req_css" ] && css_files=$(printf '%s\n%s' "$css_files" "$req_css")
    fi
    if [ -z "$css_files" ]; then
        echo "INFO: 无 CSS 文件可检查"
    else
        while IFS= read -r c; do
            [ -n "$c" ] || continue
            css_floor=$(floor_for_file "$c")
            css_scan_ok=1
            require_ok "$(basename "$c") 字号扫描" scan_small_fonts "$c" "$css_floor" \
                || css_scan_ok=0
            css_small="$REQUIRE_OK_OUT"
            if [ -n "$css_small" ]; then
                fail "$(basename "$c") - 存在低于 ${css_floor}px 底线的字号（$(printf '%s\n' "$css_small" | wc -l | tr -d ' ') 处）:"
                printf '%s\n' "$css_small" | head -5 | while IFS= read -r line; do
                    echo "      L${line%%:*}: ${line#*:}"
                done
            elif [ "$css_scan_ok" -eq 1 ]; then
                echo "PASS: $(basename "$c")（底线 ${css_floor}px）"
            fi
        done <<< "$css_files"
    fi

    if [ -z "$project" ]; then
        echo "SKIP: 无项目标识符 —— 跳过产出内容检查"
        return
    fi

    local target_dir
    target_dir="$(resolve_target_dir)"

    local html_files
    html_files=$(find "$target_dir" -maxdepth 1 -name "*.html" -not -name ".*" | sort)

    if [ -z "$html_files" ]; then
        fail "$target_dir 无 HTML 文件（PPT 轨必须有产出）"
        return
    fi

    # 占位符残留
    local placeholder_patterns="Lorem\|placeholder\|TODO\|FIXME\|TBD\|待填充\|占位符"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        local fname
        fname=$(basename "$f")
        if grep -qi "$placeholder_patterns" "$f"; then
            warn "$fname - 检测到可能的占位符残留"
            grep -n -i "$placeholder_patterns" "$f" | head -3 | while IFS= read -r line; do
                echo "      $line"
            done
        else
            echo "PASS: $fname - 无占位符残留"
        fi
    done <<< "$html_files"

    # 页数一致性（AC-02 / AC-03）
    #   AC-02: -maxdepth 1 排除 wireframe 子目录与归档副本
    #   AC-03: grep -c 无匹配时已自行输出 0 并返回 1，用 || true 而非 || echo "0"
    #          （后者产出 "0\n0"，令整数比较报语法错误后被吞没）
    if [ -f "$REQ_DIR/docs/spec/slide-spec.md" ]; then
        local spec_pages html_pages slide_sections
        spec_pages=$(grep -c "^## Slide" "$REQ_DIR/docs/spec/slide-spec.md" || true)
        spec_pages=${spec_pages:-0}

        # 单文件形态下"实际页数"= 文件内 .slide 容器数；多文件形态下 = HTML 文件数
        html_pages=$(printf '%s\n' "$html_files" | wc -l | tr -d ' ')
        if [ "$html_pages" -eq 1 ]; then
            # 与版式统计同口径：只数页面容器，排除 .slide-header/.slide-title 等页内元素
            slide_sections=$(grep -cE 'class="slide("|[[:space:]])' "$(printf '%s\n' "$html_files" | head -1)" || true)
            html_pages=${slide_sections:-0}
        fi

        if [ "$spec_pages" -eq 0 ]; then
            fail "slide-spec 不含任何 '## Slide' 页面条目 —— 规格为空不得判定通过"
        elif [ "$spec_pages" -ne "$html_pages" ]; then
            fail "页数不一致 - slide-spec 定义 $spec_pages 页，实际 $html_pages 页"
        else
            echo "PASS: 页数一致 ($spec_pages 页)"
        fi
    fi
}

# ---------------------------------------------------------------------------
# D类检查: 渲染几何测量（AC-04 / AC-05 / AX-02）
#   在 1920×1080 视口真实渲染后测量：DOM 溢出、视觉溢出、元素重叠、留白占比、标题间距。
#   ⛔ 测量环境缺失 → 非 0 退出码阻断。不降级、不 SKIP、不 WARN —— 关键检查未跑而
#      报告通过正是缺陷 1 的失效模式。
# ---------------------------------------------------------------------------
check_d() {
    echo "=== D类检查: 渲染几何测量 ==="

    local target_dir target_file
    target_dir="$(resolve_target_dir)"
    target_file=$(find "$target_dir" -maxdepth 1 -name "*.html" -not -name ".*" | sort | head -1)

    if [ -z "$target_file" ]; then
        fail "$target_dir 无 HTML 文件可测量"
        return
    fi

    local ratio_min
    case "$DENSITY" in
        reading) ratio_min="0.45" ;;
        *) ratio_min="0.25" ;;
    esac

    echo "INFO: 测量 $target_file · 留白判定按 ${DENSITY} 档（内容占比下限 ${ratio_min}）· 计算字号底线 ${FONT_FLOOR}px"

    local rc=0
    node --input-type=module - "$target_file" "$ratio_min" "$DENSITY" "$FONT_FLOOR" <<'MJS' || rc=$?
const [target, ratioMin, density, fontFloor] = process.argv.slice(2);

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  console.error('FAIL: 渲染测量环境不可用 —— 未安装 playwright');
  console.error('      安装: npm install');
  console.error('      浏览器: npx playwright install chromium（或使用系统 Chrome）');
  console.error('      ⛔ 该检查不可跳过：几何事实无法由静态扫描替代');
  process.exit(3);
}

let browser = null;
for (const opts of [{ channel: 'chrome' }, {}, { channel: 'msedge' }]) {
  try { browser = await chromium.launch(opts); break; } catch { /* 依次回退 */ }
}
if (!browser) {
  console.error('FAIL: 渲染测量环境不可用 —— 无可用浏览器引擎');
  console.error('      安装: npx playwright install chromium');
  console.error('      ⛔ 该检查不可跳过：几何事实无法由静态扫描替代');
  process.exit(3);
}

const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
const url = new URL(target, `file://${process.cwd()}/`).href;

// 测量器自身异常 ≠ 被测产出违规：前者以 3 阻断（检查未跑），后者以 1 判失败。
process.on('uncaughtException', async (err) => {
  console.error(`FAIL: 渲染测量执行异常（测量器自身故障，非产出违规）: ${err && err.message}`);
  console.error('      ⛔ 该状态不构成通过结论，也不构成产出违规结论');
  try { await browser.close(); } catch { /* ignore */ }
  process.exit(3);
});

await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(300);

const report = await page.evaluate((cfg) => {
  const ratioMin = parseFloat(cfg.ratioMin);
  const density = cfg.density;
  const fontFloor = parseFloat(cfg.fontFloor);
  const STAGE_W = 1920, STAGE_H = 1080;
  const TITLE_GAP = { global: 32, local: 14 };
  const findings = [];
  const slides = [...document.querySelectorAll('.slide')];
  if (!slides.length) return { error: '未找到 .slide 容器' };

  const label = (el) => {
    const cls = el.className && typeof el.className === 'string' ? `.${el.className.trim().split(/\s+/).join('.')}` : el.tagName.toLowerCase();
    const txt = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40);
    return `${cls}${txt ? ` "${txt}"` : ''}`;
  };
  const isDecor = (el) => {
    const s = getComputedStyle(el);
    if (s.position === 'fixed') return true;
    const r = el.getBoundingClientRect();
    if (s.position === 'absolute' && r.width * r.height > STAGE_W * STAGE_H * 0.5) return true;
    return false;
  };
  const hasText = (el) => {
    if (!el.textContent || !el.textContent.trim()) return false;
    return [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
  };

  slides.forEach((slide, idx) => {
    const pageNo = idx + 1;
    const id = slide.dataset.slideId || slide.dataset.layout || `#${pageNo}`;
    const prevVis = slide.style.visibility, prevOp = slide.style.opacity;
    slide.style.visibility = 'visible';
    slide.style.opacity = '1';

    const sr = slide.getBoundingClientRect();

    // 1. DOM 溢出
    if (slide.scrollWidth > Math.ceil(sr.width) + 1) {
      findings.push({ page: pageNo, id, kind: 'dom-overflow-x', detail: `scrollWidth ${slide.scrollWidth} 超出舞台 ${Math.round(sr.width)}（偏差 ${slide.scrollWidth - Math.round(sr.width)}px）` });
    }
    if (slide.scrollHeight > Math.ceil(sr.height) + 1) {
      findings.push({ page: pageNo, id, kind: 'dom-overflow-y', detail: `scrollHeight ${slide.scrollHeight} 超出舞台 ${Math.round(sr.height)}（偏差 ${slide.scrollHeight - Math.round(sr.height)}px）` });
    }

    // 2. 视觉溢出 + 内容包围盒
    const descendants = [...slide.querySelectorAll('*')].filter((el) => {
      const s = getComputedStyle(el);
      if (s.display === 'none' || s.visibility === 'hidden' || parseFloat(s.opacity) === 0) return false;
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    });

    let box = null;
    for (const el of descendants) {
      const r = el.getBoundingClientRect();
      if (isDecor(el)) continue;
      box = box
        ? { top: Math.min(box.top, r.top), left: Math.min(box.left, r.left), bottom: Math.max(box.bottom, r.bottom), right: Math.max(box.right, r.right) }
        : { top: r.top, left: r.left, bottom: r.bottom, right: r.right };
      const over = [];
      if (r.right > sr.right + 1) over.push(`右越界 ${Math.round(r.right - sr.right)}px`);
      if (r.bottom > sr.bottom + 1) over.push(`下越界 ${Math.round(r.bottom - sr.bottom)}px`);
      if (r.left < sr.left - 1) over.push(`左越界 ${Math.round(sr.left - r.left)}px`);
      if (r.top < sr.top - 1) over.push(`上越界 ${Math.round(sr.top - r.top)}px`);
      if (over.length) findings.push({ page: pageNo, id, kind: 'visual-overflow', detail: `${over.join(' / ')} — ${label(el)}` });
    }

    // 3. 元素重叠（仅文本元素，排除父子关系与装饰层）
    const texts = descendants.filter((el) => hasText(el) && !isDecor(el));
    for (let i = 0; i < texts.length; i++) {
      for (let j = i + 1; j < texts.length; j++) {
        const a = texts[i], b = texts[j];
        if (a.contains(b) || b.contains(a)) continue;
        const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
        const ox = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left);
        const oy = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top);
        if (ox > 2 && oy > 2) {
          findings.push({ page: pageNo, id, kind: 'overlap', detail: `重叠 ${Math.round(ox)}×${Math.round(oy)}px — ${label(a)} ⇄ ${label(b)}` });
        }
      }
    }

    // 4. 留白占比
    if (box) {
      const ratio = ((box.right - box.left) * (box.bottom - box.top)) / (sr.width * sr.height);
      if (ratio < ratioMin) {
        findings.push({ page: pageNo, id, kind: 'whitespace', level: 'warn', detail: `内容占比 ${(ratio * 100).toFixed(1)}% 低于 ${density} 档下限 ${(ratioMin * 100).toFixed(0)}%` });
      }
    }

    // 5. 标题间距
    for (const el of descendants) {
      const cls = typeof el.className === 'string' ? el.className : '';
      const isGlobal = /slide-title|text-title/.test(cls) || el.tagName === 'H1';
      const isLocal = /section-title|card-title|text-subtitle/.test(cls) || el.tagName === 'H2' || el.tagName === 'H3';
      if (!isGlobal && !isLocal) continue;
      const need = isGlobal ? TITLE_GAP.global : TITLE_GAP.local;
      const r = el.getBoundingClientRect();
      let next = null;
      for (const cand of descendants) {
        if (cand === el || el.contains(cand) || cand.contains(el)) continue;
        const rc = cand.getBoundingClientRect();
        if (rc.top < r.bottom - 1) continue;
        const hOverlap = Math.min(r.right, rc.right) - Math.max(r.left, rc.left);
        if (hOverlap <= 0) continue;
        if (!next || rc.top < next.top) next = { top: rc.top, el: cand };
      }
      if (next) {
        const gap = next.top - r.bottom;
        if (gap < need) {
          findings.push({ page: pageNo, id, kind: 'title-gap', detail: `标题下方间距 ${Math.round(gap)}px 低于下限 ${need}px — ${label(el)}` });
        }
      }
    }

    // 6. 计算字号（静态扫描的运行时兜底）
    //    静态层只能看见源码里的字面 px。var(--font-*) 层层引用、简写、外部样式表覆盖
    //    都在这里落定为一个数——getComputedStyle 是唯一不可绕过的口径。
    //    豁免与静态层同口径：显式图形标记 + 剥离符号后无可读载荷。
    const GLYPH_CLS = /trend-arrow|icon-dot|timeline-node/;
    const SYMBOLS = /[▲▼◆◇●○■□★☆→←↑↓•·▪▸✓✔✕✖—–\s]/g;
    const isGlyphExempt = (el) => {
      const cls = typeof el.className === 'string' ? el.className : '';
      if (el.dataset.glyph !== 'true' && !GLYPH_CLS.test(cls)) return false;
      return !(el.textContent || '').replace(SYMBOLS, '');
    };
    for (const el of descendants) {
      if (!hasText(el) || isGlyphExempt(el)) continue;
      const fs = parseFloat(getComputedStyle(el).fontSize);
      if (fs && fs < fontFloor - 0.01) {
        findings.push({ page: pageNo, id, kind: 'computed-font', detail: `计算字号 ${fs}px 低于 ${density} 档底线 ${fontFloor}px（偏差 ${(fontFloor - fs).toFixed(1)}px）— ${label(el)}` });
      }
    }

    slide.style.visibility = prevVis;
    slide.style.opacity = prevOp;
  });

  return { pages: slides.length, findings };
}, { ratioMin, density, fontFloor });

await browser.close();

if (report.error) {
  console.error(`FAIL: ${report.error}`);
  process.exit(1);
}

const fails = report.findings.filter((f) => f.level !== 'warn');
const warns = report.findings.filter((f) => f.level === 'warn');

// 明细按类别截断：单个 CSS token 违规可放大成上百条同因发现，全量打印会淹没其他类别。
// 截断只影响打印量，不影响 fails 计数与退出码。
const DETAIL_CAP = 8;
const byKind = {};
for (const f of fails) (byKind[f.kind] = byKind[f.kind] || []).push(f);
for (const [kind, list] of Object.entries(byKind)) {
  for (const f of list.slice(0, DETAIL_CAP)) console.log(`FAIL: [p${f.page} ${f.id}] ${f.kind} — ${f.detail}`);
  if (list.length > DETAIL_CAP) console.log(`FAIL: ${kind} 另有 ${list.length - DETAIL_CAP} 项同类违规（已截断明细，计数仍全额计入）`);
}
for (const w of warns) console.log(`WARN: [p${w.page} ${w.id}] ${w.kind} — ${w.detail}`);

// 留白 WARN 连续多页触发 → FAIL（防"修溢出时过度收缩"）
const wsPages = [...new Set(warns.filter((w) => w.kind === 'whitespace').map((w) => w.page))].sort((a, b) => a - b);
let run = 0, worst = 0;
for (let i = 0; i < wsPages.length; i++) {
  run = i > 0 && wsPages[i] === wsPages[i - 1] + 1 ? run + 1 : 1;
  worst = Math.max(worst, run);
}
let extra = 0;
if (worst >= 3) {
  console.log(`FAIL: 连续 ${worst} 页留白超限 —— 内容过度收缩，非设计留白`);
  extra = 1;
}

console.log(`INFO: 已测量 ${report.pages} 页，${fails.length} 项失败，${warns.length} 项警告`);
if (fails.length + extra > 0) process.exit(1);
console.log('PASS: 渲染几何测量通过');
MJS

    if [ "$rc" -eq 3 ]; then
        echo ""
        echo "=== PPT 校验阻断: 渲染测量环境不可用 ==="
        echo "⛔ 未执行渲染测量的结果不构成通过结论（AX-02）"
        exit 3
    elif [ "$rc" -ne 0 ]; then
        fail "渲染几何测量检出违规（见上方明细）"
    fi
}

# 执行检查
case "$check_type" in
    A|a) check_a ;;
    B|b) check_b ;;
    C|c) check_c ;;
    D|d) check_d ;;
    all)
        check_a
        echo ""
        check_b
        echo ""
        check_c
        echo ""
        check_d
        ;;
    *)
        echo "用法: $0 [A|B|C|D|all] [project]"
        echo "      $0 export <html> <out.pdf>"
        exit 2
        ;;
esac

echo ""
if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -gt 0 ]; then
        echo "=== PPT 校验通过（$WARNINGS 项警告）==="
    else
        echo "=== PPT 校验通过 ==="
    fi
    exit 0
else
    echo "=== PPT 校验失败: $ERRORS 项错误 ==="
    exit 1
fi

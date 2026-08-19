#!/bin/bash
# session-context.sh — SessionStart hook，打印当前活跃流程状态（CR-020 R4）
#
# 形态是 sensor，不是判权点：只读状态、只打印、**恒 exit 0**，不返回权限决策。
# 与 role-guard.sh 的分工见 docs/kb/domains/guards.md「宿主原生能力与 role-guard 的分工」。
#
# 目的：使断点恢复不依赖对话历史。新会话开场即可见「有无活跃流程、走到哪一步、谁持权」，
# 无需先翻 skills 再逐个 cat state 文件。
#
# 恒 exit 0 的实现方式（AX-03，设计 §2.3）：
#   1. 主体放进函数并在**子 shell**中调用，set -u/pipefail 的失败被围栏挡在子 shell 内；
#   2. 末尾无条件 exit 0，不用 `|| true` 之类逐条兜底（漏一条即阻断会话）。
# 曾出现的真实缺陷：`"$project（..."` 中全角括号被 bash 并入变量名，set -u 下直接 exit 1，
# 使 sensor 反而阻断了每一个会话。变量插值一律用 ${var} 花括号形态，勿依赖裸 $var 的边界。
#
# 非法 slug 在此只提示、不 exit 2：判权是 role-guard 的职责，sensor 不判权（同一约束
# 不在两处独立声明）。此处收紧只会把污染态变成会话级硬阻断，而 role-guard 已在写入时拦。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# .engine/.state.md 与全局指针的 YAML 取值：与 role-guard.sh 读取端同源
# （`grep '^key:' | head -1 | awk '{print $2}'`），避免两处对同一文件解析口径分歧。
yaml_field() {
    grep "^${2}:" "$1" 2>/dev/null | head -1 | awk '{print $2}'
}

report_mh_run() {
    local pointer="$ROOT/deliverables/.state.md"
    if [[ ! -f "$pointer" ]]; then
        echo "  /mh-run  : 无活跃交付物流程（全局指针不存在）"
        return
    fi

    local project
    project=$(yaml_field "$pointer" project)
    if [[ -z "$project" ]]; then
        echo "  /mh-run  : 无活跃交付物流程（全局指针的 project 为空）"
        return
    fi

    if ! bash "$ROOT/scripts/validate-slug.sh" "${project}" >/dev/null 2>&1; then
        echo "  /mh-run  : 全局指针的 project 非法标识符（state 疑被污染，role-guard 会在写入时拦截）"
        return
    fi

    local state="$ROOT/deliverables/${project}/.engine/.state.md"
    if [[ ! -f "$state" ]]; then
        echo "  /mh-run  : 指针指向 ${project}，但其 .engine/.state.md 不存在（指针滞后于目录）"
        return
    fi

    echo "  /mh-run  : ${project} · phase=$(yaml_field "$state" phase) · step=$(yaml_field "$state" current_step) · role=$(yaml_field "$state" current_role) · track=$(yaml_field "$state" track)"
}

report_mh_dev() {
    local state="${MH_DEV_RUNTIME:-$ROOT/tools/mh-dev/.mh-dev}/state.json"
    if [[ ! -f "$state" ]]; then
        echo "  /mh-dev  : 无活跃框架自开发流程（state.json 不存在）"
        return
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "  /mh-dev  : state.json 存在，但 jq 不可用，无法解析"
        return
    fi
    if ! jq -e '.workflow == "mh-dev"' "$state" >/dev/null 2>&1; then
        echo "  /mh-dev  : state.json 缺失 workflow=mh-dev 字段或非合法 JSON（state 疑被污染）"
        return
    fi
    jq -r '"  /mh-dev  : phase=\(.phase // "?") · role=\(.current_role // "?") · track=\(.track // "?") · repair.round=\(.repair.round // 0)"' "$state" 2>/dev/null
}

main() {
    echo "=== Mini-Harness 会话上下文 ==="
    report_mh_run
    report_mh_dev
    echo "  提示     : 默认会话不启动任何多角色流程；流程纪律仅在显式调用 /mh-run、/mh-ppt、/mh-dev 后生效（CLAUDE.md §6）"
}

# 子 shell 围栏：主体内任何失败（含 set -u 触发的 exit 1）都止步于此，不外泄为 hook 非零退出
( main )

exit 0

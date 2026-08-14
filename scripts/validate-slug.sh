#!/bin/bash
# validate-slug.sh — 项目标识符（slug）字符集校验（CR-018 D1.3）
# 退出码: 0=合法, 2=非法（stdout 打印拒绝原因）
# 用法: ./scripts/validate-slug.sh <slug>
#
# 单一实现 + 两处调用（生成侧 skills/mh-intake、消费侧 scripts/role-guard.sh）。
# 判据集中在此，避免正则在多处漂移——CR-015 的教训：判据分散即口径分歧。
#
# 消费侧（role-guard）必须独立调用本脚本，不能信任生成侧：state 文件是被治理方
# 自己可写的（docs/kb/domains/guards.md 的自授权定位），生成侧校验可被绕过。
#
# 字符集 ^[a-z][a-z0-9-]{0,63}$ 的四条约束各自排除一类构造：
#   全小写      — 守卫的排除规则曾用 grep -qi（大小写不敏感），大写标识符会与排除项非预期交叉命中
#   仅 a-z0-9-  — ${project} 被插入 bash [[ =~ ]] 正则与路径拼接：`.` 是通配符
#                 （web.cli 会命中 webXcli）、`/` 与 `..` 是路径穿越、空格破坏词法
#   首字符 a-z  — 前导 `-` 在脚本中会被当作选项；数字开头不是合法包名
#   ≤64 字符    — 路径长度上界
# 该字符集下标识符是正则字面量安全的（a-z0-9- 在 ERE 中无元字符语义），
# 故守卫的 ${project} 插值无需再引入转义层。

set -uo pipefail

slug="${1:-}"

# 与产品区顶层目录或引擎态目录同名的值即使满足字符集也须拒绝：
# 交付目录与其内部目录同名会使路径归属产生歧义（D1.2）。
RESERVED="docs src tests deploy assets reference engine"

if [[ -z "$slug" ]]; then
    echo "非法项目标识符: 值为空（须匹配 ^[a-z][a-z0-9-]{0,63}\$）"
    exit 2
fi

if [[ ${#slug} -gt 64 ]]; then
    echo "非法项目标识符 '${slug}': 长度 ${#slug} 超过 64 字符上限"
    exit 2
fi

if [[ ! "$slug" =~ ^[a-z][a-z0-9-]{0,63}$ ]]; then
    echo "非法项目标识符 '${slug}': 须匹配 ^[a-z][a-z0-9-]{0,63}\$（小写字母开头，仅含小写字母、数字、连字符）"
    exit 2
fi

for r in $RESERVED; do
    if [[ "$slug" == "$r" ]]; then
        echo "非法项目标识符 '${slug}': 与保留目录名冲突（保留: ${RESERVED}）"
        exit 2
    fi
done

exit 0

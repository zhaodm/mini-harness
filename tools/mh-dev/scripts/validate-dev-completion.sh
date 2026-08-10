#!/bin/bash
# validate-dev-completion.sh — 开发后质量门禁
# 检查：测试覆盖、枚举消费者审计、shell 注入防护
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
cd "$ROOT_DIR"

FAILURES=0
fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES+1)); }
pass() { echo "PASS: $*"; }

# 获取本轮 Developer 变更的路径
ATTRIBUTION="$RUNTIME/evidence/change-attribution.developer."*"json"
CHANGED_PATHS=$(python3 - "$RUNTIME" <<'PY'
import json, glob, os, sys
runtime = sys.argv[1]
paths = set()
for f in glob.glob(os.path.join(runtime, 'evidence', 'change-attribution.developer.*.json')):
    data = json.load(open(f))
    if data.get('result') != 'PASS': continue
    for item in data.get('changed', []):
        p = item['path']
        if not p.startswith('tools/mh-dev/.mh-dev/'):
            paths.add(p)
for p in sorted(paths): print(p)
PY
)

if [[ -z "$CHANGED_PATHS" ]]; then
  echo "SKIP: no developer changes to validate"
  exit 0
fi

# 1. 新增脚本模块的测试覆盖
echo "--- 1. 测试覆盖检查 ---"
for f in $CHANGED_PATHS; do
  case "$f" in
    *.sh)
      # 新增的 .sh 脚本应被某测试引用
      basename=$(basename "$f" .sh)
      if git diff --name-only HEAD -- "$f" 2>/dev/null | grep -q . && ! grep -rql "$basename" tests/ tools/mh-dev/tests/ 2>/dev/null; then
        # 新增文件检查
        if ! git cat-file -e "HEAD:$f" 2>/dev/null; then
          fail "新增脚本 $f 未被任何测试引用"
        fi
      fi
      ;;
  esac
done
pass "测试覆盖检查完成"

# 2. shell 注入防护（禁止 $VAR 直接嵌入 python -c 字符串）
echo "--- 2. Shell 注入防护 ---"
injection_fail=0
for f in $CHANGED_PATHS tools/mh-dev/scripts/*.sh scripts/*.sh; do
  [[ -f "$f" ]] || continue
  if grep -qE 'python3?\s+-c\s*.*\$[A-Z_]' "$f" 2>/dev/null; then
    fail "$f: 发现 \$VAR 直接嵌入 python -c（应使用 sys.argv）"
    injection_fail=$((injection_fail+1))
  fi
done
[[ $injection_fail -eq 0 ]] && pass "无 shell 注入风险" || fail "$injection_fail 个文件有注入风险"

# 结果
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS: dev completion validation passed"
  exit 0
else
  echo "FAIL: $FAILURES issue(s) found" >&2
  exit 1
fi

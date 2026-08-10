#!/bin/bash
# reset-session.sh — 会话重置：归档上一轮运行态，从模板重新初始化 state.json
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
TEMPLATE="$ROOT_DIR/tools/mh-dev/templates/state.json.template"
cd "$ROOT_DIR"

# 归档上一轮运行态（如果存在且有内容）
if [[ -d "$RUNTIME" && -n "$(ls -A "$RUNTIME" 2>/dev/null)" ]]; then
  ARCHIVE="$ROOT_DIR/tools/mh-dev/.mh-dev-archive/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$(dirname "$ARCHIVE")"
  # 只归档有意义的运行态文件，不归档 .gitkeep
  if [[ -f "$RUNTIME/state.json" ]] || [[ -d "$RUNTIME/evidence" ]] || [[ -d "$RUNTIME/snapshots" ]]; then
    mkdir -p "$ARCHIVE"
    cp -r "$RUNTIME"/* "$ARCHIVE/" 2>/dev/null || true
    echo "PASS: archived previous session to ${ARCHIVE#$ROOT_DIR/}"
  fi
fi

# 清空运行态
rm -rf "$RUNTIME"
mkdir -p "$RUNTIME/evidence" "$RUNTIME/snapshots" "$RUNTIME/release"
touch "$RUNTIME/.gitkeep"

# 从模板重新生成 state.json
if [[ -f "$TEMPLATE" ]]; then
  python3 - "$TEMPLATE" "$RUNTIME/state.json" <<'PY'
import json, datetime, sys, os
template_path, output_path = sys.argv[1], sys.argv[2]
with open(template_path, encoding='utf-8') as f:
    state = json.load(f)
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
state['last_updated'] = now
state.setdefault('phase_timestamps', {})['intake'] = {'started': now}
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, 'w', encoding='utf-8') as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
  echo "PASS: state.json initialized from template"
else
  echo "WARN: template not found at ${TEMPLATE#$ROOT_DIR/}, state.json not created" >&2
fi

# 复制工作文件模板到运行态
for tmpl in requirement.md acceptance-criteria.md acceptance-criteria.json; do
  src="$ROOT_DIR/tools/mh-dev/templates/$tmpl"
  dst="$RUNTIME/$tmpl"
  if [[ -f "$src" ]] && [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "PASS: copied $tmpl to runtime"
  fi
done

# 设置当前 Git 基线
BASELINE=$(git rev-parse HEAD 2>/dev/null || echo "HEAD")
if [[ -f "$RUNTIME/state.json" ]]; then
  python3 - "$RUNTIME/state.json" "$BASELINE" <<'PY'
import json, sys
path, baseline = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    state = json.load(f)
state['baseline'] = baseline
with open(path, 'w', encoding='utf-8') as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
  echo "PASS: baseline set to $BASELINE"
fi

echo "PASS: session reset complete"

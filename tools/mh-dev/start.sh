#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f "CLAUDE.md" || ! -d "tools/mh-dev" ]]; then
  echo "ERROR: tools/mh-dev 必须从 Mini-Harness 仓库中运行" >&2
  exit 1
fi

exec claude --project-dir tools/mh-dev "$@"

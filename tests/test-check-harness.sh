#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

pass=0
fail=0
assert_success() {
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    echo "FAIL: expected success: $*" >&2
    fail=$((fail + 1))
  fi
}

assert_success bash scripts/check-harness.sh

if (( fail > 0 )); then
  echo "FAIL: $fail assertion(s) failed" >&2
  exit 1
fi

echo "PASS: $pass check-harness assertion(s) passed"

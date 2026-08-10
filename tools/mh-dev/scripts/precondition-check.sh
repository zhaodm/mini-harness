#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; RUNTIME="${MH_DEV_RUNTIME:-$ROOT_DIR/tools/mh-dev/.mh-dev}"; STATE="$RUNTIME/state.json"
[[ -f "$STATE" ]] || { echo "BLOCKED: missing mh-dev state" >&2;exit 1; }
bash "$ROOT_DIR/tools/mh-dev/scripts/validate-outputs.sh" propose
TRACK=$(jq -r '.track // empty' "$STATE"); INTAKE=$(jq -r '.approvals.intake // empty' "$STATE"); DESIGN=$(jq -r '.approvals.design // empty' "$STATE")
[[ "$INTAKE" == approved ]] || { echo "BLOCKED: intake approval required" >&2;exit 1; }
[[ "$TRACK" != formal || "$DESIGN" == approved ]] || { echo "BLOCKED: formal design approval required" >&2;exit 1; }
if jq -e '.track_assessment.required_track == "formal" and .track != "formal"' "$STATE" >/dev/null; then echo "BLOCKED: formal track escalation unresolved" >&2;exit 1;fi
echo "PASS: development preconditions met"

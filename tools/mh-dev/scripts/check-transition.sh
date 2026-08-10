#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; STATE="$ROOT_DIR/tools/mh-dev/.mh-dev/state.json"; NEXT="${1:-}"
[[ -n "$NEXT" && -f "$STATE" ]] || { echo "Usage: $0 <phase>" >&2; exit 2; }
python3 - "$STATE" "$NEXT" <<'PY'
import json,sys
s,n=json.load(open(sys.argv[1])),sys.argv[2]; p=s.get('phase'); repair=s.get('repair',{}); approvals=s.get('approvals',{})
def blocked(msg): print('BLOCKED: '+msg);raise SystemExit(1)
if n not in {'propose','develop','verify','audit','repair','release-candidate','archive','blocked'}: raise SystemExit(2)
if n=='propose' and p=='intake': pass
elif n=='develop' and p in {'propose','repair'}:
 if approvals.get('intake')!='approved': blocked('intake approval required')
 if s.get('track')=='formal' and approvals.get('design')!='approved': blocked('formal design approval required')
elif n=='verify' and p=='develop':
 if str(repair.get('round',0)) not in s.get('change_ownership',{}).get('developer',{}): blocked('developer attribution required')
elif n=='audit' and p=='verify':
 if s.get('mechanical_preflight')!='pass' or s.get('test_verdict')!='PASS': blocked('mechanical and tester PASS required')
elif n=='repair' and p in {'verify','audit'}:
 if repair.get('round',0)>=repair.get('max_rounds',3): blocked('repair limit reached')
elif n=='release-candidate' and p=='audit':
 if s.get('semantic_audit')!='PASS' or approvals.get('delivery')!='approved': blocked('semantic PASS and delivery approval required')
elif n=='archive' and p=='release-candidate': pass
elif n=='blocked': pass
else: blocked(f'{p} cannot transition to {n}')
print(f'PASS: {p} -> {n}')
PY

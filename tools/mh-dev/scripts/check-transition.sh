#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; RUNTIME="${MH_DEV_RUNTIME:-$ROOT_DIR/tools/mh-dev/.mh-dev}"; STATE="$RUNTIME/state.json"; NEXT="${1:-}"
[[ -n "$NEXT" && -f "$STATE" ]] || { echo "Usage: $0 <phase>" >&2; exit 2; }
python3 - "$STATE" "$NEXT" <<'PY'
import json,sys
s,n=json.load(open(sys.argv[1])),sys.argv[2]; p=s.get('phase'); repair=s.get('repair',{}); approvals=s.get('approvals',{})
def blocked(msg): print('BLOCKED: '+msg);raise SystemExit(1)
if n not in {'propose','develop','verify','done','repair','blocked'}: raise SystemExit(2)
if n=='propose' and p=='intake':
 # 会话状态不可跨 CR 复用：残留的开发循环产物或阶段历史一律要求先 reset-session.sh
 # 不检 approved_scope —— intake 阶段登记 scope 是正常流程，非残留信号
 stale=[]
 if s.get('revision',0)!=0: stale.append('revision=%s'%s['revision'])
 if s.get('change_ownership'): stale.append('change_ownership non-empty')
 if s.get('snapshots'): stale.append('snapshots non-empty')
 if repair.get('status','not_started')!='not_started': stale.append('repair.status='+str(repair.get('status')))
 if s.get('test_verdict','pending')!='pending': stale.append('test_verdict='+str(s.get('test_verdict')))
 if s.get('mechanical_preflight','pending')!='pending': stale.append('mechanical_preflight='+str(s.get('mechanical_preflight')))
 for ph in ('develop','verify','done'):
  if ph in s.get('phase_timestamps',{}): stale.append('phase_timestamps.%s present'%ph)
 if stale: blocked('stale session state detected ('+'; '.join(stale)+'); run reset-session.sh first')
elif n=='develop' and p in {'propose','repair'}:
 if approvals.get('intake')!='approved': blocked('intake approval required')
 if s.get('track')=='formal' and approvals.get('design')!='approved': blocked('formal design approval required')
elif n=='verify' and p=='develop':
 dev_attr=s.get('change_ownership',{}).get('developer',{})
 rr=str(repair.get('round',0))
 if rr not in dev_attr: blocked('developer attribution required')
elif n=='done' and p=='verify':
 if s.get('mechanical_preflight')!='pass' or s.get('test_verdict')!='PASS': blocked('mechanical and tester PASS required')
elif n=='repair' and p=='verify':
 if repair.get('round',0)>=repair.get('max_rounds',3): blocked('repair limit reached')
elif n=='blocked': pass
else: blocked(f'{p} cannot transition to {n}')
print(f'PASS: {p} -> {n}')
PY

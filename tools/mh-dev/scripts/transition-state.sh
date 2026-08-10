#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; STATE="$ROOT_DIR/tools/mh-dev/.mh-dev/state.json"; NEXT="${1:-}"; shift || true
ACTOR="" EXPECTED="" REASON=""
while [[ $# -gt 0 ]]; do case "$1" in --actor) ACTOR="$2";shift 2;;--expected-revision) EXPECTED="$2";shift 2;;--reason) REASON="$2";shift 2;;*) echo "Usage: $0 <phase> --actor planner --expected-revision N [--reason text]" >&2;exit 2;;esac;done
[[ "$ACTOR" == planner && "$EXPECTED" =~ ^[0-9]+$ ]] || { echo "BLOCKED: planner and expected revision required" >&2;exit 2; }
bash "$ROOT_DIR/tools/mh-dev/scripts/check-transition.sh" "$NEXT"
python3 - "$STATE" "$NEXT" "$EXPECTED" "$REASON" <<'PY'
import datetime,json,os,sys,tempfile
path,next_,expected,reason=sys.argv[1:]; expected=int(expected)
with open(path,encoding='utf-8') as f:s=json.load(f)
if s.get('revision')!=expected: raise SystemExit('BLOCKED: stale state revision')
now=datetime.datetime.now(datetime.timezone.utc).isoformat(); previous=s['phase']
if next_=='repair':
 r=s.setdefault('repair',{}); r['round']=r.get('round',0)+1;r['status']='active';r['reason']=reason or 'verification_failure';r['source_verdict']='evidence/test-verdict.json' if previous=='verify' else 'evidence/semantic-verdict.json'
if next_=='blocked': s.setdefault('repair',{})['status']='escalated'
s.setdefault('phase_timestamps',{}).setdefault(previous,{})['ended']=now
s.setdefault('phase_timestamps',{}).setdefault(next_,{})['started']=now
s.update({'phase':next_,'current_role':'planner','revision':expected+1,'last_updated':now})
d=os.path.dirname(path);fd,tmp=tempfile.mkstemp(dir=d,prefix='.state.',text=True)
with os.fdopen(fd,'w',encoding='utf-8') as f:json.dump(s,f,ensure_ascii=False,indent=2);f.write('\n')
os.replace(tmp,path)
print(f'PASS: state advanced to {next_} revision {expected+1}')
PY

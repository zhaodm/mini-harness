#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; RUNTIME="${MH_DEV_RUNTIME:-$ROOT_DIR/tools/mh-dev/.mh-dev}"; STATE="$RUNTIME/state.json"; PHASE="${1:-}"
[[ -n "$PHASE" && -f "$STATE" ]] || { echo "Usage: $0 <propose|develop|verify|audit>" >&2; exit 2; }
python3 - "$ROOT_DIR" "$RUNTIME" "$STATE" "$PHASE" <<'PY'
import json,os,re,sys
root,runtime,state_path,phase=sys.argv[1:]
def load(name):
 with open(os.path.join(runtime,name),encoding='utf-8') as f:return json.load(f)
def fail(msg): raise SystemExit('BLOCKED: '+msg)
def nonempty(v): return isinstance(v,str) and v.strip() and not re.search(r'\b(TBD|TODO|待补充)\b',v,re.I)
s=load('state.json'); track=s.get('track'); round_=s.get('repair',{}).get('round',0)
criteria_path=os.path.join(runtime,'acceptance-criteria.json')
if phase=='propose':
 if not os.path.isfile(criteria_path): fail('acceptance inventory missing')
 c=load('acceptance-criteria.json'); items=c.get('items',[]); ids=[]
 for x in items:
  if not re.fullmatch(r'A[CX]-[0-9]+',x.get('id','')) or x.get('kind') not in {'AC','AX'} or not nonempty(x.get('statement')) or not x.get('required_evidence'): fail('invalid acceptance item')
  ids.append(x['id'])
 if len(ids)!=len(set(ids)) or not any(x.startswith('AC-') for x in ids): fail('criteria require unique AC items')
 if track=='formal' and not any(x.startswith('AX-') for x in ids): fail('formal track requires AX items')
 for x in items:
  if re.search(r'\b(TBD|TODO|待补充|请补充)\b',x.get('statement',''),re.I): fail(f'placeholder in acceptance item {x.get("id")}')
 md=open(os.path.join(runtime,'acceptance-criteria.md'),encoding='utf-8').read()
 if set(re.findall(r'\bA[CX]-[0-9]+\b',md)) != set(ids): fail('Markdown and JSON acceptance IDs differ')
 print('PASS: proposal criteria complete');raise SystemExit(0)
if phase=='develop':
 if str(round_) not in s.get('change_ownership',{}).get('developer',{}): fail('developer attribution missing')
 print('PASS: developer attribution complete');raise SystemExit(0)
if phase not in {'verify','audit'}: fail('unsupported phase')
c=load('acceptance-criteria.json'); required={x['id'] for x in c['items']}
def validate_verdict(name,role):
 v=load(name)
 if v.get('schema_version')!=1 or v.get('role')!=role or v.get('round')!=round_ or v.get('verdict') not in {'PASS','FAIL','BLOCKED'} or not nonempty(v.get('generated_at','')): fail(f'invalid {role} verdict header')
 actual={x.get('id') for x in v.get('acceptance',[])}
 if actual!=required or len(actual)!=len(v.get('acceptance',[])): fail(f'{role} acceptance coverage incomplete')
 return v
if phase in {'verify','audit'}:
 v=validate_verdict('evidence/test-verdict.json','tester'); commands={x.get('id'):x for x in v.get('commands',[])}
 if not commands: fail('tester command evidence missing')
 for cmd in commands.values():
  if not all(nonempty(cmd.get(k,'')) for k in ('command','cwd','started_at','ended_at','summary')) or not isinstance(cmd.get('exit_code'),int): fail('invalid tester command evidence')
 for item in v['acceptance']:
  if item.get('status') not in {'PASS','FAIL','BLOCKED'} or not nonempty(item.get('summary','')) or not item.get('evidence') or not set(item['evidence']) <= set(commands): fail('invalid tester acceptance evidence')
 if v['verdict']=='PASS' and (any(x['status']!='PASS' for x in v['acceptance']) or any(x['exit_code']!=0 for x in commands.values()) or v.get('failures')): fail('tester PASS conflicts with evidence')
 if v['verdict']!='PASS' and not (v.get('failures') or any(x['status']!= 'PASS' for x in v['acceptance'])): fail('non-PASS tester verdict lacks failure/blocker')
 if phase=='verify':
  ref=s.get('snapshots',{}).get(f'tester.{round_}',{}).get('attribution')
  if not ref: fail('tester attribution missing')
  attribution=load(ref)
  if attribution.get('result')!='PASS' or attribution.get('role')!='tester' or attribution.get('round')!=round_: fail('tester attribution invalid')
  s.setdefault('change_ownership',{}).setdefault('tester',{})[str(round_)]=ref
  import tempfile
  fd,tmp=tempfile.mkstemp(dir=os.path.dirname(state_path),prefix='.state.',text=True)
  with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(s,f,ensure_ascii=False,indent=2); f.write('\n')
  os.replace(tmp,state_path)
  # testcase_adding_required 验证（从 propose 移到 verify）
  tc_required=s.get('testcase_adding_required',False)
  if tc_required:
   import subprocess
   changed=subprocess.check_output(['git','-C',root,'diff','--name-only','HEAD'],text=True).splitlines()+subprocess.check_output(['git','-C',root,'ls-files','--others','--exclude-standard'],text=True).splitlines()
   has_test=any('test' in p for p in changed if p)
   if not has_test: fail('testcase_adding_required=true but no test file changes detected')
  print('PASS: tester verdict complete');raise SystemExit(0)
if phase=='audit':
 a=validate_verdict('evidence/semantic-verdict.json','auditor')
 if a.get('tester_verdict_ref')!='evidence/test-verdict.json' or a.get('mechanical_preflight',{}).get('exit_code')!=0: fail('auditor prerequisites invalid')
 evidence={x.get('id') for x in a.get('evidence',[]) if nonempty(x.get('id',''))}
 for item in a['acceptance']:
  if item.get('status') not in {'PASS','FAIL','BLOCKED'} or not nonempty(item.get('summary','')) or not item.get('evidence') or not set(item['evidence']) <= evidence: fail('invalid auditor acceptance evidence')
 if a['verdict']=='PASS' and (any(x['status']!='PASS' for x in a['acceptance']) or a.get('findings') or a.get('release_recommendation')!='APPROVE'): fail('auditor PASS conflicts with evidence')
 if a['verdict']!='PASS' and not (a.get('findings') or any(x['status']!='PASS' for x in a['acceptance'])): fail('non-PASS auditor verdict lacks findings')
 if phase=='audit': print('PASS: semantic verdict complete');raise SystemExit(0)

PY

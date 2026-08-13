#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; RUNTIME="${MH_DEV_RUNTIME:-$ROOT_DIR/tools/mh-dev/.mh-dev}"; STATE="$RUNTIME/state.json"; PHASE="${1:-}"
[[ -n "$PHASE" && -f "$STATE" ]] || { echo "Usage: $0 <propose|develop|verify|audit>" >&2; exit 2; }
python3 - "$ROOT_DIR" "$RUNTIME" "$STATE" "$PHASE" <<'PY'
import json,os,re,sys
root,runtime,state_path,phase=sys.argv[1:]
def fail(msg): raise SystemExit('BLOCKED: '+msg)
def load(name):
 # 任何缺失/畸形输入都转 BLOCKED，不向上抛 traceback
 try:
  with open(os.path.join(runtime,name),encoding='utf-8') as f:return json.load(f)
 except FileNotFoundError: fail('required runtime file missing: '+name)
 except json.JSONDecodeError as e: fail('malformed JSON in %s: %s'%(name,e))
# nonempty() 只判空值，不判占位符——两者是不同的检查，混在一起会误伤合法叙述。
# 占位符残留由 propose 相位的专项检查负责（见下方 placeholder 扫描，覆盖 TBD/TODO/待补充/请补充），
# 它只扫模板需填写的 acceptance statement；verify/audit 的 summary 是叙述正文，
# 合法引用「待补充」这类词（如描述"无备注页显示 — 而非待补充"）不得判为占位符残留。
def nonempty(v): return isinstance(v,str) and bool(v.strip())
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
 # 占位符残留检测：只认「整条 statement 就是未填写的骨架」，不扫叙述正文中的引用。
 # 判据是占位词独立成句（可带前后空白与成对引号/括号），而非出现在句中——
 # 「验收标准待补充」是未填写，「须显示「—」而非「待补充」字样」是在描述正确行为，不得误伤。
 PLACEHOLDER=re.compile(r'^[\s\'"「『（(<\[]*(?:TBD|TODO|待补充|请补充)[\s\'"」』）)>\].。!！]*$',re.I)
 for x in items:
  if PLACEHOLDER.match(x.get('statement','').strip()): fail(f'placeholder in acceptance item {x.get("id")}')
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
if phase=='verify':
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
  # R5: tester verdict PASS 时回填 test_verdict
  if v['verdict']=='PASS':
   s['test_verdict']='PASS'
   # R6: mechanical_preflight 有独立证据源，仅在证据存在且 exit_code==0 时回填。
   # 缺失或非零时保持 pending，交由 done 门禁阻断；此处不 fail（机械预检是 Planner 职责）。
   pf=os.path.join(runtime,'evidence/audit-preflight.json')
   if os.path.isfile(pf):
    try:
     with open(pf,encoding='utf-8') as f: pfd=json.load(f)
     if pfd.get('exit_code')==0: s['mechanical_preflight']='pass'
    except json.JSONDecodeError: pass
  import tempfile
  fd,tmp=tempfile.mkstemp(dir=os.path.dirname(state_path),prefix='.state.',text=True)
  with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(s,f,ensure_ascii=False,indent=2); f.write('\n')
  os.replace(tmp,state_path)
  # testcase_adding_required 验证（从 propose 移到 verify）
  tc_required=s.get('testcase_adding_required',False)
  if tc_required:
   import subprocess
   changed=subprocess.check_output(['git','-C',root,'diff','--name-only','HEAD'],text=True).splitlines()+subprocess.check_output(['git','-C',root,'ls-files','--others','--exclude-standard'],text=True).splitlines()
   # R15: 路径前缀语义，与 role-guard.sh 的 Tester 放行、validate-changes.sh 的 tester_scope 同口径。
   # 旧实现 'test' in p 是任意位置子串，docs/latest-notes.md 之类路径可误满足。
   has_test=any(p.startswith('tests/') or p.startswith('tools/mh-dev/tests/') for p in changed if p)
   if not has_test: fail('testcase_adding_required=true but no test file changes detected')
  print('PASS: tester verdict complete');raise SystemExit(0)
if phase=='audit':
 # 登记制：校验对象由 state.json 的 audit_verdict_path 指定（相对仓库根），
 # 不猜「最新文件」——否则本次结论会受目录内历史文件影响。
 # audit 分支完全不读 evidence/test-verdict.json：审计已提交范围时开发轨运行态证据不参与判定。
 rel=s.get('audit_verdict_path','')
 if not rel: fail('audit_verdict_path not registered in state.json')
 target=os.path.join(root,rel)
 if not os.path.isfile(target): fail('registered audit verdict not found: '+rel)
 try:
  with open(target,encoding='utf-8') as f:a=json.load(f)
 except json.JSONDecodeError as e: fail('malformed JSON in %s: %s'%(rel,e))
 if a.get('role')!='auditor' or a.get('verdict') not in {'PASS','FAIL','BLOCKED'} or not nonempty(a.get('generated_at','')): fail('invalid auditor verdict header')
 if a.get('tester_verdict_ref')!='evidence/test-verdict.json' or a.get('mechanical_preflight',{}).get('exit_code')!=0: fail('auditor prerequisites invalid')
 evidence={x.get('id') for x in a.get('evidence',[]) if nonempty(x.get('id',''))}
 for item in a['acceptance']:
  if item.get('status') not in {'PASS','FAIL','BLOCKED'} or not nonempty(item.get('summary','')) or not item.get('evidence') or not set(item['evidence']) <= evidence: fail('invalid auditor acceptance evidence')
 if a['verdict']=='PASS' and (any(x['status']!='PASS' for x in a['acceptance']) or a.get('findings') or a.get('release_recommendation')!='APPROVE'): fail('auditor PASS conflicts with evidence')
 if a['verdict']!='PASS' and not (a.get('findings') or any(x['status']!='PASS' for x in a['acceptance'])): fail('non-PASS auditor verdict lacks findings')
 if phase=='audit': print('PASS: semantic verdict complete');raise SystemExit(0)

PY

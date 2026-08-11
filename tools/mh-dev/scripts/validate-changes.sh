#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
RUNTIME="${MH_DEV_RUNTIME:-$ROOT_DIR/tools/mh-dev/.mh-dev}"
STATE="$RUNTIME/state.json"
ROLE="" ROUND="" BEFORE="" AFTER=""
while [[ $# -gt 0 ]]; do case "$1" in --role) ROLE="$2"; shift 2;; --round) ROUND="$2"; shift 2;; --before) BEFORE="$2"; shift 2;; --after) AFTER="$2"; shift 2;; *) echo "Usage: $0 --role developer|tester --round N --before FILE --after FILE" >&2; exit 2;; esac; done
[[ "$ROLE" =~ ^(developer|tester)$ && "$ROUND" =~ ^[0-9]+$ && -f "$STATE" && -f "$BEFORE" && -f "$AFTER" ]] || { echo "BLOCKED: invalid role delta input" >&2; exit 2; }
python3 - "$ROOT_DIR" "$RUNTIME" "$STATE" "$ROLE" "$ROUND" "$BEFORE" "$AFTER" <<'PY'
import datetime, hashlib, json, os, sys, tempfile
root,runtime,state_path,role,round_,before_path,after_path=sys.argv[1:]
round_=int(round_)
def load(path):
 with open(path,encoding='utf-8') as f:return json.load(f)
def atomically_write(path,data):
 d=os.path.dirname(path); fd,tmp=tempfile.mkstemp(dir=d,prefix='.state.',text=True)
 with os.fdopen(fd,'w',encoding='utf-8') as f: json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n')
 os.replace(tmp,path)
state,before,after=load(state_path),load(before_path),load(after_path)
if state.get('workflow')!='mh-dev': raise SystemExit('BLOCKED: invalid mh-dev state')
for snap,point in [(before,'before'),(after,'after')]:
 if snap.get('role')!=role or snap.get('round')!=round_ or snap.get('point')!=point: raise SystemExit(f'BLOCKED: {point} snapshot provenance mismatch')
b={x['path']:x for x in before.get('entries',[])}; a={x['path']:x for x in after.get('entries',[])}
# Detect renames: a path in after with old_path pointing to a path in before.
rename_old_to_new={}
for path,new in a.items():
 old=new.get('old_path')
 if old and old in b and old not in a:
  rename_old_to_new[old]=path
# Build changes, skipping old rename sources (they are represented by the new path).
paths=sorted(set(b)|set(a)); changes=[]; violations=[]
sensitive={'CLAUDE.md','.claude/settings.json','scripts/role-guard.sh','tools/mh-dev/templates/state.json.template','tools/mh-dev/scripts/check-transition.sh','tools/mh-dev/scripts/transition-state.sh','tools/mh-dev/scripts/validate-changes.sh','tools/mh-dev/scripts/validate-outputs.sh'}
scope=set(state.get('approved_scope',[])); track=state.get('track')
# Normalize: approved_scope may contain absolute paths, but snapshot paths from git porcelain are relative to ROOT_DIR.
abs_scope=set(os.path.join(root,p) if not os.path.isabs(p) else p for p in scope)
def allowed_dev(path):
 ap=os.path.join(root,path) if not os.path.isabs(path) else path
 return ap in abs_scope or any(x.endswith('/') and ap.startswith(x) for x in abs_scope)
for path in paths:
 if path in rename_old_to_new: continue
 old=b.get(path); new=a.get(path)
 # If this is the new side of a rename, include old_path and treat as renamed.
 is_rename = new and new.get('old_path') and new['old_path'] in b and new['old_path'] not in a
 if old and new and not is_rename and old.get('sha256')==new.get('sha256') and old.get('porcelain_status')==new.get('porcelain_status'): continue
 if is_rename:
  change='renamed'; old_ref=b.get(new['old_path'])
  item={'path':path,'change':change,'before_sha256':old_ref and old_ref.get('sha256'),'after_sha256':new.get('sha256'),'old_path':new.get('old_path')}
 else:
  change='added' if not old else 'deleted' if not new or new.get('sha256') is None else 'modified'
  item={'path':path,'change':change,'before_sha256':old and old.get('sha256'),'after_sha256':new and new.get('sha256'),'old_path':(new or old).get('old_path')}
 if path.startswith('tools/mh-dev/.mh-dev/'):
  tester_allowed = {'tools/mh-dev/.mh-dev/evidence/test-verdict.json','tools/mh-dev/.mh-dev/evidence/test-report.md'}
  developer_allowed = path.startswith('tools/mh-dev/.mh-dev/snapshots/') or path.startswith('tools/mh-dev/.mh-dev/evidence/change-attribution.developer.')
  tester_runtime_allowed = path.startswith('tools/mh-dev/.mh-dev/snapshots/') or path in tester_allowed or path.startswith('tools/mh-dev/.mh-dev/evidence/change-attribution.tester.')
  if role == 'tester' and not tester_runtime_allowed:
   violations.append(f'unauthorized tester runtime path: {path}')
  elif role == 'developer' and not developer_allowed:
   violations.append(f'unauthorized developer runtime path: {path}')
  else:
   item['allowed_by']='role_runtime_evidence'
  changes.append(item); continue
 if role=='developer':
  if not allowed_dev(path): violations.append(f'unapproved developer path: {path}')
  elif path in sensitive and track!='formal': violations.append(f'formal track required: {path}')
  else: item['allowed_by']='approved_scope'
 else:
  if not (path.startswith('tools/mh-dev/tests/') or path.startswith('tests/') or path in {'tools/mh-dev/.mh-dev/evidence/test-verdict.json','tools/mh-dev/.mh-dev/evidence/test-report.md'}):
   violations.append(f'unauthorized tester path: {path}')
  else: item['allowed_by']='tester_scope'
 changes.append(item)
result='PASS' if not violations else 'FAIL'
rel=f'evidence/change-attribution.{role}.{round_}.json'; out=os.path.join(runtime,rel)
os.makedirs(os.path.dirname(out),exist_ok=True)
if os.path.exists(out): raise SystemExit(f'BLOCKED: immutable attribution exists: {rel}')
artifact={'schema_version':1,'role':role,'round':round_,'before_snapshot':os.path.relpath(before_path,runtime),'after_snapshot':os.path.relpath(after_path,runtime),'changed':changes,'violations':violations,'result':result,'validated_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
with open(out,'w',encoding='utf-8') as f:json.dump(artifact,f,ensure_ascii=False,indent=2);f.write('\n')
if violations:
 if any('formal track required' in x for x in violations):
  state.setdefault('track_escalations',[]).append({'round':round_,'reason_codes':['GOVERNANCE_PATH'],'paths':[x.split(': ',1)[1] for x in violations if 'formal track required' in x],'at':artifact['validated_at']})
 atomically_write(state_path,state)
 raise SystemExit('BLOCKED: '+'; '.join(violations))
state.setdefault('snapshots',{})[f'{role}.{round_}']={'before':artifact['before_snapshot'],'after':artifact['after_snapshot'],'attribution':rel}
if role == 'developer':
 state.setdefault('change_ownership',{}).setdefault(role,{})[str(round_)]=rel
 # 文档同步检查：改动脚本/角色/模板时检查对应文档是否同步
 doc_sync = {
  'CLAUDE.md': ['README.md','docs/designs/workflow.md','docs/designs/source-of-truth.md'],
  'scripts/role-guard.sh': ['CLAUDE.md','docs/designs/source-of-truth.md'],
 }
 dev_paths = [x['path'] for x in changes if not x['path'].startswith('tools/mh-dev/.mh-dev/') and x['change'] != 'deleted']
 for path in dev_paths:
  if path in doc_sync:
   for doc in doc_sync[path]:
    if doc not in dev_paths:
     violations.append(f'doc sync required: {path} changed but {doc} not in same delta')
 if violations:
  state.setdefault('track_escalations',[]).append({'round':round_,'reason_codes':['DOC_SYNC'],'paths':violations,'at':artifact['validated_at']})
  atomically_write(state_path,state)
  raise SystemExit('BLOCKED: '+'; '.join(violations))
atomically_write(state_path,state)
print(f'PASS: {role} delta validated: {len(changes)} change(s)')
PY

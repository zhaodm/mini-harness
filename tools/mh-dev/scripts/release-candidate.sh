#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"; STATE="$RUNTIME/state.json"
[[ -f "$STATE" ]] || { echo "BLOCKED: missing mh-dev state" >&2;exit 1; }
bash "$ROOT_DIR/tools/mh-dev/scripts/validate-outputs.sh" release-candidate
python3 - "$ROOT_DIR" "$RUNTIME" "$STATE" <<'PY'
import hashlib,json,os,subprocess,sys,datetime
root,runtime,state_path=sys.argv[1:]; state=json.load(open(state_path)); baseline=state.get('baseline')
if not baseline: raise SystemExit('BLOCKED: intake baseline required')
head=subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip()
raw=subprocess.check_output(['git','-C',root,'status','--porcelain=v1','-z']); parts=raw.split(b'\0'); items=[];i=0
while i<len(parts)-1:
 s=parts[i].decode('utf-8','surrogateescape');i+=1
 if not s:continue
 status,path=s[:2],s[3:];old=None
 if status[0] in 'RC' and i<len(parts)-1: old=parts[i].decode('utf-8','surrogateescape');i+=1
 if path.startswith('tools/mh-dev/.mh-dev/'):continue
 digest=None
 try:
  with open(os.path.join(root,path),'rb') as f:digest=hashlib.sha256(f.read()).hexdigest()
 except FileNotFoundError:pass
 items.append({'path':path,'old_path':old,'porcelain_status':status,'sha256':digest,'tracked':status!='??'})
owned=[]
for role,rounds in state.get('change_ownership',{}).items(): owned.extend(rounds.values())
if not owned:raise SystemExit('BLOCKED: verified change ownership required')
owned_paths=set()
for ref in owned:
 artifact=json.load(open(os.path.join(runtime,ref)))
 if artifact.get('result')!='PASS':raise SystemExit('BLOCKED: failed ownership artifact')
 owned_paths.update(x['path'] for x in artifact.get('changed',[]) if not x['path'].startswith('tools/mh-dev/.mh-dev/'))
missing=[x['path'] for x in items if x['path'] not in owned_paths]
if missing:raise SystemExit('BLOCKED: unaudited dirty paths: '+', '.join(missing))
release=os.path.join(runtime,'release');os.makedirs(release,exist_ok=True)
patch=os.path.join(release,'working-tree.patch')
with open(patch,'wb') as f: subprocess.run(['git','-C',root,'diff','--binary',baseline],stdout=f,check=True)
patch_hash=hashlib.sha256(open(patch,'rb').read()).hexdigest()
manifest={'schema_version':2,'baseline':{'commit':baseline},'candidate':{'head_commit':head,'captured_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'working_tree_dirty':bool(items),'patch_path':'release/working-tree.patch','patch_sha256':patch_hash},'changed_paths':[x['path'] for x in items],'worktree_changes':items,'verified_ownership':owned,'verification':{'mechanical_preflight':'PASS','tester_verdict':'PASS','semantic_audit':'PASS'},'release_status':'candidate'}
with open(os.path.join(release,'release-manifest.json'),'w',encoding='utf-8') as f:json.dump(manifest,f,ensure_ascii=False,indent=2);f.write('\n')
with open(os.path.join(release,'release-notes.md'),'w',encoding='utf-8') as f:f.write('# Mini-Harness Release Candidate\n\n该候选物描述当前经验证的脏工作区；mh-dev 未执行 commit、tag、push 或发布。\n')
print('PASS: release candidate captures %d dirty path(s)'%len(items))
PY

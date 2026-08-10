#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"; RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
trap 'rm -rf "$RUNTIME"' EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); }; bad(){ echo "FAIL: $*" >&2; fail=$((fail+1)); }
expect_pass(){ if "$@" >/dev/null 2>&1; then ok; else bad "expected pass: $*"; fi; }
expect_fail(){ if "$@" >/dev/null 2>&1; then bad "expected failure: $*"; else ok; fi; }
write_evidence(){
  python3 - "$RUNTIME" <<'PY'
import json,os,sys
r=sys.argv[1]
items=[{'id':'AC-01','kind':'AC','statement':'functional check','required_evidence':['command']},
{'id':'AX-01','kind':'AX','statement':'boundary check','required_evidence':['command']},
{'id':'AX-02','kind':'AX','statement':'error path','required_evidence':['command']},
{'id':'AX-03','kind':'AX','statement':'integration point','required_evidence':['command']},
{'id':'AX-04','kind':'AX','statement':'regression','required_evidence':['command']},
{'id':'AX-05','kind':'AX','statement':'implicit constraint','required_evidence':['command']}]
json.dump({'schema_version':1,'items':items},open(r+'/acceptance-criteria.json','w'),indent=2)
commands=[{'id':'cmd-01','command':'true','cwd':'/tmp','started_at':'2026-01-01T00:00:00Z','ended_at':'2026-01-01T00:00:01Z','exit_code':0,'summary':'passed'}]
accept=[{'id':x['id'],'status':'PASS','evidence':['cmd-01'],'summary':'passed'} for x in items]
json.dump({'schema_version':1,'role':'tester','round':0,'verdict':'PASS','generated_at':'2026-01-01T00:00:00Z','delta_ref':'snapshots/developer.r0.after.json','commands':commands,'acceptance':accept,'failures':[],'summary':'passed'},open(r+'/evidence/test-verdict.json','w'),indent=2)
audit_evidence=[{'id':'audit-01','kind':'inspection','location':'test','summary':'passed'}]
audit_accept=[{'id':x['id'],'status':'PASS','evidence':['audit-01'],'summary':'passed'} for x in items]
json.dump({'schema_version':1,'role':'auditor','round':0,'verdict':'PASS','generated_at':'2026-01-01T00:00:00Z','tester_verdict_ref':'evidence/test-verdict.json','mechanical_preflight':{'exit_code':0,'evidence':'evidence/audit-preflight.json'},'acceptance':audit_accept,'evidence':audit_evidence,'findings':[],'disposition':'PASS','release_recommendation':'APPROVE'},open(r+'/evidence/semantic-verdict.json','w'),indent=2)
PY
}
setup_state(){
  rm -rf "$RUNTIME"; mkdir -p "$RUNTIME/evidence" "$RUNTIME/snapshots"
  cp "$ROOT_DIR/tools/mh-dev/templates/requirement.md" "$RUNTIME/requirement.md"
  cp "$ROOT_DIR/tools/mh-dev/templates/acceptance-criteria.md" "$RUNTIME/acceptance-criteria.md"
  write_evidence
  cat > "$RUNTIME/state.json" <<EOF
{"schema_version":2,"workflow":"mh-dev","revision":0,"phase":"$1","current_role":"planner","baseline":"HEAD","approved_scope":$2,"track":"$3","track_assessment":{"requested_track":"$3","required_track":"$3","reason_codes":[],"paths":[],"confirmed":true,"assessed_at":"t"},"track_escalations":[],"approvals":{"intake":"$4","design":"$5","delivery":"$6"},"mechanical_preflight":"$7","test_verdict":"$8","semantic_audit":"$9","repair":{"round":0,"max_rounds":3,"status":"not_started","reason":"","source_verdict":""},"snapshots":{},"change_ownership":{},"evidence":[],"phase_timestamps":{},"release_status":"not_requested","last_updated":"t"}
EOF
}

# Transition and atomic revision behaviour.
setup_state intake '["README.md"]' formal approved pending pending pending pending pending
expect_pass bash "$ROOT_DIR/tools/mh-dev/scripts/check-transition.sh" propose
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/check-transition.sh" develop
setup_state propose '["README.md"]' formal approved approved pending pending pending pending
expect_pass bash "$ROOT_DIR/tools/mh-dev/scripts/transition-state.sh" develop --actor planner --expected-revision 0
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/transition-state.sh" verify --actor planner --expected-revision 0

# Repair route and bounded retries.
setup_state verify '["README.md"]' formal approved approved pending pass FAIL pending
expect_pass bash "$ROOT_DIR/tools/mh-dev/scripts/check-transition.sh" repair
setup_state audit '["README.md"]' formal approved approved pending pass PASS FAIL
expect_pass bash "$ROOT_DIR/tools/mh-dev/scripts/check-transition.sh" repair
python3 - "$RUNTIME/state.json" <<'PY'
import json,sys
p=sys.argv[1];s=json.load(open(p));s['repair']['round']=3;json.dump(s,open(p,'w'))
PY
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/check-transition.sh" repair

# Criteria and verdict negative validation.
setup_state propose '["README.md"]' formal approved pending pending pending pending pending
expect_pass bash "$ROOT_DIR/tools/mh-dev/scripts/validate-outputs.sh" propose
echo '{"schema_version":1,"items":[]}' > "$RUNTIME/acceptance-criteria.json"
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/validate-outputs.sh" propose
setup_state verify '["README.md"]' formal approved approved pending pending pending pending
python3 - "$RUNTIME/evidence/test-verdict.json" <<'PY'
import json,sys
p=sys.argv[1];v=json.load(open(p));v['commands']=[];json.dump(v,open(p,'w'))
PY
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/validate-outputs.sh" verify

# Release requires all gates and verified ownership.
setup_state release-candidate '["README.md"]' formal approved approved approved pass PASS PASS
expect_pass bash "$ROOT_DIR/tools/mh-dev/scripts/validate-outputs.sh" release-candidate
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/release-candidate.sh"
setup_state release-candidate '["README.md"]' formal approved approved pending pass PASS PASS
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/validate-outputs.sh" release-candidate

# Rename attribution: porcelain -z order is new-path then old-path.
setup_state develop '["old.txt"]' formal approved approved pending pending pending pending
python3 - "$RUNTIME" <<'PY'
import json,os,sys
r=sys.argv[1]
before={'schema_version':1,'workflow':'mh-dev','role':'developer','round':0,'point':'before','captured_at':'t','repo_head':'h','entries':[{'path':'old.txt','old_path':None,'porcelain_status':'  ','sha256':'a','tracked':True}]}
after={'schema_version':1,'workflow':'mh-dev','role':'developer','round':0,'point':'after','captured_at':'t','repo_head':'h','entries':[{'path':'new.txt','old_path':'old.txt','porcelain_status':'R ','sha256':'b','tracked':True}]}
json.dump(before,open(r+'/snapshots/developer.r0.before.json','w'))
json.dump(after,open(r+'/snapshots/developer.r0.after.json','w'))
PY
expect_fail bash "$ROOT_DIR/tools/mh-dev/scripts/validate-changes.sh" --role developer --round 0 --before "$RUNTIME/snapshots/developer.r0.before.json" --after "$RUNTIME/snapshots/developer.r0.after.json"
# When new path is in scope, validation passes and attribution records correct rename.
setup_state develop '["new.txt"]' formal approved approved pending pending pending pending
python3 - "$RUNTIME" <<'PY'
import json,os,sys
r=sys.argv[1]
before={'schema_version':1,'workflow':'mh-dev','role':'developer','round':0,'point':'before','captured_at':'t','repo_head':'h','entries':[{'path':'old.txt','old_path':None,'porcelain_status':'  ','sha256':'a','tracked':True}]}
after={'schema_version':1,'workflow':'mh-dev','role':'developer','round':0,'point':'after','captured_at':'t','repo_head':'h','entries':[{'path':'new.txt','old_path':'old.txt','porcelain_status':'R ','sha256':'b','tracked':True}]}
json.dump(before,open(r+'/snapshots/developer.r0.before.json','w'))
json.dump(after,open(r+'/snapshots/developer.r0.after.json','w'))
PY
expect_pass bash "$ROOT_DIR/tools/mh-dev/scripts/validate-changes.sh" --role developer --round 0 --before "$RUNTIME/snapshots/developer.r0.before.json" --after "$RUNTIME/snapshots/developer.r0.after.json"
python3 - "$RUNTIME" <<'PY'
import json,sys
a=json.load(open(sys.argv[1]+'/evidence/change-attribution.developer.0.json'))
changed=[x for x in a['changed'] if x['path']=='new.txt']
if not changed or changed[0].get('old_path')!='old.txt': raise SystemExit('rename attribution order incorrect')
PY
ok "rename attribution records new path and old_path"

if (( fail>0 )); then echo "FAIL: $fail mh-dev governance assertion(s) failed" >&2; exit 1; fi
echo "PASS: $pass mh-dev governance assertion(s) passed"

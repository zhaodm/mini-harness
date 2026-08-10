#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
RUNTIME="$ROOT_DIR/tools/mh-dev/.mh-dev"
ROLE="" ROUND="" KIND="" OUT=""
if [[ $# -eq 1 && "$1" != --* ]]; then OUT="$1"; ROLE="legacy"; ROUND=0; KIND="capture"
else
  while [[ $# -gt 0 ]]; do case "$1" in --role) ROLE="$2"; shift 2;; --round) ROUND="$2"; shift 2;; --kind) KIND="$2"; shift 2;; *) echo "Usage: $0 --role developer|tester --round N --kind before|after" >&2; exit 2;; esac; done
  [[ "$ROLE" =~ ^(developer|tester)$ && "$ROUND" =~ ^[0-9]+$ && "$KIND" =~ ^(before|after)$ ]] || { echo "BLOCKED: invalid snapshot arguments" >&2; exit 2; }
  OUT="$RUNTIME/snapshots/$ROLE.r$ROUND.$KIND.json"
fi
[[ ! -e "$OUT" ]] || { echo "BLOCKED: snapshot already exists: $OUT" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
cd "$ROOT_DIR"
python3 - "$OUT" "$ROLE" "$ROUND" "$KIND" <<'PY'
import hashlib,json,os,subprocess,sys,datetime
out,role,round_,kind=sys.argv[1:]
def run(*args): return subprocess.check_output(args).decode()
head=run('git','rev-parse','HEAD').strip()
raw=subprocess.check_output(['git','status','--porcelain=v1','-z'])
parts=raw.split(b'\0'); entries=[]; i=0
while i < len(parts)-1:
 s=parts[i].decode('utf-8','surrogateescape'); i+=1
 if not s: continue
 status,path=s[:2],s[3:]; old_path=None
 if status[0] in 'RC' and i < len(parts)-1:
  old_path=parts[i].decode('utf-8','surrogateescape'); i+=1
 digest=None
 try:
  with open(path,'rb') as f: digest=hashlib.sha256(f.read()).hexdigest()
 except FileNotFoundError: pass
 entries.append({'path':path,'old_path':old_path,'porcelain_status':status,'sha256':digest,'tracked':status!='??'})
data={'schema_version':1,'workflow':'mh-dev','role':role,'round':int(round_),'point':kind,'captured_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'repo_head':head,'entries':entries}
with open(out,'w',encoding='utf-8') as f: json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n')
PY
echo "PASS: snapshot written to ${OUT#$ROOT_DIR/}"

#!/usr/bin/env bash
# Load all demo dashboards into the running Grafana (otel-lgtm). Idempotent.
set -euo pipefail
G="${GRAFANA_URL:-http://localhost:3939}"
DIR="$(cd "$(dirname "$0")" && pwd)/dashboards"
for f in "$DIR"/*.json; do
  echo "loading $(basename "$f") ..."
  python3 - "$f" "$G" <<'PY'
import json,sys,urllib.request
f,g=sys.argv[1],sys.argv[2]
d=json.load(open(f))
body=json.dumps({"dashboard":d,"overwrite":True}).encode()
req=urllib.request.Request(g+"/api/dashboards/db",data=body,headers={"Content-Type":"application/json"})
r=json.load(urllib.request.urlopen(req)); print("  ->",r.get("status"),r.get("url"))
PY
done

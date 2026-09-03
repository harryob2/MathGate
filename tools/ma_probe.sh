#!/usr/bin/env bash
# Probe Math Academy's login + previous-tasks API from this machine.
#
# Prints ONLY: HTTP status codes, redirect targets, cookie names + attributes
# (values stripped), and a summary of the returned tasks. The password is read
# without echo, passed to curl via stdin (never argv, never a file), and the
# cookie jar lives in a temp dir that is deleted on exit.
set -euo pipefail

BASE="https://www.mathacademy.com"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
JAR="$TMP/jar"

read -r -p "Math Academy username or email: " U
read -r -s -p "Math Academy password (not echoed): " P
echo

echo "== 1. login =="
printf '%s' "$P" | curl -sS -A "$UA" -c "$JAR" -b "$JAR" \
  -D "$TMP/login.headers" -o "$TMP/login.body" \
  -d "usernameOrEmail=$U" --data-urlencode "password@-" -d "submit=LOGIN" \
  -w 'login -> HTTP %{http_code} redirect=%{redirect_url}\n' \
  "$BASE/login"
unset P
grep -i '^set-cookie:' "$TMP/login.headers" | sed -E 's/^[Ss]et-[Cc]ookie: ([^=]+)=[^;]*(.*)$/  set-cookie: \1 \2/' || echo "  (no Set-Cookie headers)"
echo "  body bytes: $(wc -c < "$TMP/login.body" | tr -d ' ')"
if grep -qi 'errorMessage' "$TMP/login.body"; then
  echo "  body contains login page (errorMessage div) -> login likely FAILED"
  grep -o '<div id="errorMessage">[^<]*' "$TMP/login.body" | head -1 || true
fi

echo "== 2. cookie jar (values stripped) =="
awk '!/^#/ && NF>=7 {print "  " $6 "  expires=" $5 "  secure=" $4 "  path=" $3}' "$JAR" || true
awk '!/^#/ && NF>=7 {print $5}' "$JAR" | while read -r e; do [ "$e" -gt 0 ] 2>/dev/null && echo "  -> $(date -r "$e" '+%Y-%m-%d %H:%M %Z')"; done || true

echo "== 3. check-is-auth =="
curl -sS -A "$UA" -b "$JAR" -c "$JAR" -H 'Accept: application/json' \
  -o "$TMP/auth.body" -w 'check-is-auth -> HTTP %{http_code} content-type=%{content_type} redirect=%{redirect_url}\n' \
  "$BASE/api/check-is-auth"
echo "  body: $(head -c 200 "$TMP/auth.body")"

echo "== 4. previous-tasks =="
DATE="$(python3 -c 'import datetime,urllib.parse; d=datetime.datetime.now()+datetime.timedelta(days=1); print(urllib.parse.quote(d.strftime("%a %b %d %Y %H:%M:%S")+" GMT-0800 (Pacific Standard Time)", safe=""))')"
echo "  date path segment: $DATE"
curl -sS -A "$UA" -b "$JAR" -c "$JAR" -H 'Accept: application/json' -H "Referer: $BASE/learn" \
  -o "$TMP/tasks.json" -w 'previous-tasks -> HTTP %{http_code} content-type=%{content_type} redirect=%{redirect_url}\n' \
  "$BASE/api/previous-tasks/$DATE"
python3 - "$TMP/tasks.json" <<'PY'
import json, sys
raw = open(sys.argv[1], 'rb').read()
try:
    d = json.loads(raw)
except Exception as e:
    print("  NOT JSON:", e); print("  first 300 bytes:", raw[:300]); sys.exit(0)
if not isinstance(d, list):
    print("  JSON but not a list; type:", type(d).__name__); print("  ", json.dumps(d)[:400]); sys.exit(0)
print("  items:", len(d))
print("  types:", sorted({str(x.get('type')) for x in d}))
print("  top-level keys:", sorted(d[0].keys()) if d else None)
for x in d[:5]:
    print("  -", x.get('type'), "completed=", x.get('completed'), "points=", x.get('points'), "pointsAwarded=", x.get('pointsAwarded'), "progress=", x.get('progress'))
if d:
    print("  first item:", json.dumps(d[0])[:600])
PY

echo "== 5. previous-tasks with ?minumum=5 (does the param still work?) =="
curl -sS -A "$UA" -b "$JAR" -H 'Accept: application/json' -o "$TMP/tasks5.json" \
  -w 'previous-tasks(min=5) -> HTTP %{http_code}\n' "$BASE/api/previous-tasks/$DATE?minumum=5"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("  items:", len(d) if isinstance(d,list) else type(d).__name__)' "$TMP/tasks5.json" 2>/dev/null || echo "  (not json)"

echo "== done (temp files deleted) =="

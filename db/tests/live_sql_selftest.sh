#!/usr/bin/env bash
# Self-test for db/tests/live_sql.sh — the runner that applies SQL to the live
# Supabase project through the Management API.
#
# The real API needs the access token, so this points PROBE_API_BASE at a local
# mock that answers with the two response shapes the API uses: a JSON array of
# rows, or {"message": ...} for a failure. It verifies
#   -c  ad-hoc queries (success and error),
#   -f  file mode (success, error, missing/empty file, 200-with-message),
#   --migrations / --rollbacks run every file in order and report a failure,
#   the token lookup order (env → ~/.raizey-audit/live_rw) and exit 2 with none,
#   and that the token value is never echoed into the output.
#
# Run: bash db/tests/live_sql_selftest.sh   (also part of local_sql_suite.sh)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MOCK_PORT="${MEEM_MOCK_PORT:-5621}"

CHECK_TMP="$(mktemp -d)"
MARKER_FILE="$CHECK_TMP/mock-marker"

python3 - "$MOCK_PORT" "$MARKER_FILE" >"${TMPDIR:-/tmp}/meem-live-mock.log" 2>&1 <<'PY' &
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, MARKER_FILE = int(sys.argv[1]), sys.argv[2]


def marker():
    try:
        with open(MARKER_FILE, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        query = json.loads(self.rfile.read(length) or b"{}").get("query", "")
        needle = marker()
        if "/*mock:boom*/" in query or (needle and needle in query):
            payload, status = {"message": "synthetic SQL error", "code": "XX000"}, 400
        elif "/*mock:msg200*/" in query:
            payload, status = {"message": "synthetic error with a 200 status"}, 200
        else:
            payload, status = [{"rows": 1}], 200
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PY
MOCK_PID=$!
cleanup() { kill "$MOCK_PID" 2>/dev/null; rm -rf "$CHECK_TMP"; }
trap cleanup EXIT

for _ in $(seq 1 50); do
  python3 -c "
import socket, sys
s = socket.socket()
s.settimeout(0.3)
sys.exit(0 if s.connect_ex(('127.0.0.1', $MOCK_PORT)) == 0 else 1)" && break
  sleep 0.1
done

export SUPABASE_ACCESS_TOKEN="selftest"
export PROBE_API_BASE="http://127.0.0.1:$MOCK_PORT"
export PROJECT_REF="selftest"
unset PROBE_TOKEN_FILE

selftest_fail=0
check_exit() { # check_exit <label> <expected code> <actual code>
  if [ "$2" = "$3" ]; then printf 'ok    %s (exit %s)\n' "$1" "$3"
  else printf 'FAIL  %s (expected exit %s, got %s)\n' "$1" "$2" "$3"; selftest_fail=$((selftest_fail + 1)); fi
}

printf 'select 1;' > "$CHECK_TMP/ok.sql"
: > "$CHECK_TMP/empty.sql"
printf 'select /*mock:boom*/ 1;' > "$CHECK_TMP/boom.sql"
printf 'select /*mock:msg200*/ 1;' > "$CHECK_TMP/msg.sql"

bash "$HERE/live_sql.sh" -c "select 1;" >/dev/null 2>&1; check_exit "-c runs a query" 0 $?
bash "$HERE/live_sql.sh" -c "select /*mock:boom*/ 1;" >/dev/null 2>&1; check_exit "-c reports a SQL error" 1 $?
bash "$HERE/live_sql.sh" -f "$CHECK_TMP/ok.sql" >/dev/null 2>&1; check_exit "-f applies a file" 0 $?
bash "$HERE/live_sql.sh" -f "$CHECK_TMP/boom.sql" >/dev/null 2>&1; check_exit "-f reports a SQL error" 1 $?
bash "$HERE/live_sql.sh" -f "$CHECK_TMP/msg.sql" >/dev/null 2>&1; check_exit "-f rejects a 200 carrying a message" 1 $?
bash "$HERE/live_sql.sh" -f "$CHECK_TMP/nope.sql" >/dev/null 2>&1; check_exit "-f rejects a missing file" 1 $?
bash "$HERE/live_sql.sh" -f "$CHECK_TMP/empty.sql" >/dev/null 2>&1; check_exit "-f rejects an empty file" 1 $?
bash "$HERE/live_sql.sh" >/dev/null 2>&1; check_exit "usage exits 2" 2 $?

# batches: all 10 migrations / 8 rollbacks exist, are applied, and are reported
bash "$HERE/live_sql.sh" --migrations >/dev/null 2>&1; check_exit "--migrations applies every file" 0 $?
bash "$HERE/live_sql.sh" --rollbacks  >/dev/null 2>&1; check_exit "--rollbacks applies every file" 0 $?
# the lists must stay in step with the files on disk
for f in $(grep -oE '^  "db/(migrations|rollback)/[^"]+' "$HERE/live_sql.sh" | sed 's/^  "//'); do
  [ -s "$ROOT/$f" ] || { printf 'FAIL  listed but missing: %s\n' "$f"; selftest_fail=$((selftest_fail + 1)); }
done
# The expected counts come from the runner's own lists, so adding a migration or
# a rollback file cannot silently desynchronise this check.
expected_mig="$(grep -c '^  "db/migrations/' "$HERE/live_sql.sh")"
expected_roll="$(grep -c '^  "db/rollback/' "$HERE/live_sql.sh")"
applied="$(bash "$HERE/live_sql.sh" --migrations 2>/dev/null | grep -c '^ok ')"
if [ "$applied" = "$expected_mig" ]; then printf 'ok    --migrations applies every listed file (%s)\n' "$applied"
else printf 'FAIL  --migrations applied %s files, list has %s\n' "$applied" "$expected_mig"; selftest_fail=$((selftest_fail + 1)); fi
rolled="$(bash "$HERE/live_sql.sh" --rollbacks 2>/dev/null | grep -c '^ok ')"
if [ "$rolled" = "$expected_roll" ]; then printf 'ok    --rollbacks applies every listed file (%s)\n' "$rolled"
else printf 'FAIL  --rollbacks applied %s files, list has %s\n' "$rolled" "$expected_roll"; selftest_fail=$((selftest_fail + 1)); fi

# a failing file inside a batch must be reported and fail the run
printf 'get_top_ordered_products' > "$MARKER_FILE"
out="$(bash "$HERE/live_sql.sh" --migrations 2>&1)"; code=$?
check_exit "a failing file fails the batch" 1 "$code"
if printf '%s' "$out" | grep -q '^FAIL  db/migrations/2026-10-13_home_highlights.sql'; then
  printf 'ok    the failing file is named\n'
else printf 'FAIL  the failing file was not named\n'; selftest_fail=$((selftest_fail + 1)); fi
if printf '%s' "$out" | grep -q '^ok  '; then
  printf 'ok    the earlier files are still applied\n'
else printf 'FAIL  the batch stopped before the earlier files\n'; selftest_fail=$((selftest_fail + 1)); fi
: > "$MARKER_FILE"

# token lookup: no env token and no files → refusal with exit 2
empty_home="$CHECK_TMP/home"
mkdir -p "$empty_home/.raizey-audit"
env -u SUPABASE_ACCESS_TOKEN HOME="$empty_home" bash "$HERE/live_sql.sh" -f "$CHECK_TMP/ok.sql" >/dev/null 2>&1
check_exit "refuses to run without a token" 2 $?
# token lookup: reads ~/.raizey-audit/live_rw when the env var is absent
printf 'TOKENMUSTNOTLEAK\n' > "$empty_home/.raizey-audit/live_rw"
env -u SUPABASE_ACCESS_TOKEN HOME="$empty_home" bash "$HERE/live_sql.sh" -f "$CHECK_TMP/ok.sql" >/dev/null 2>&1
check_exit "falls back to ~/.raizey-audit/live_rw" 0 $?
leak="$(env -u SUPABASE_ACCESS_TOKEN HOME="$empty_home" bash "$HERE/live_sql.sh" -c "select 1" 2>&1 | grep -c 'TOKENMUSTNOTLEAK')"
if [ "$leak" = "0" ]; then printf 'ok    the token is never echoed\n'
else printf 'FAIL  the token leaked into the output\n'; selftest_fail=$((selftest_fail + 1)); fi

if [ "$selftest_fail" -eq 0 ]; then printf '\nself-test OK\n'
else printf '\nself-test FAILED (%s checks)\n' "$selftest_fail"; fi
exit "$selftest_fail"

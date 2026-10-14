#!/usr/bin/env bash
# Self-test for db/tests/probe_lib.sh.
#
# The live backend (Supabase Management API) cannot run without an access token,
# so this points PROBE_API_BASE at a local mock that answers with the exact
# response shapes the API uses — a JSON array of {v: ...} rows, or
# {"message": ...} with a 4xx status for an error. That way both the value
# parsing and the error detection of the harness are verified here, and any
# regression that would make every live probe "pass" or "fail" silently is
# caught before the token ever arrives.
#
# Run: bash db/tests/probe_lib_selftest.sh   (also part of local_sql_suite.sh)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK_PORT="${MEEM_MOCK_PORT:-5617}"

python3 - "$MOCK_PORT" >"${TMPDIR:-/tmp}/meem-probe-mock.log" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        query = json.loads(self.rfile.read(length) or b"{}").get("query", "")
        if "/*mock:boom*/" in query:
            payload, status = {"message": "synthetic SQL error", "code": "XX000"}, 400
        elif "/*mockfirst:" in query:
            # a query whose result column is named something other than "v"
            start = query.find("/*mockfirst:")
            value = query[start + len("/*mockfirst:"):query.index("*/", start)]
            payload, status = [{"some_other_name": value}], 200
        else:
            start = query.find("/*mock:")
            value = ""
            if start >= 0:
                value = query[start + len("/*mock:"):query.index("*/", start)]
            payload, status = [{"v": value}], 200
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
trap 'kill "$MOCK_PID" 2>/dev/null' EXIT

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
unset MEEM_LOCAL_DSN
# shellcheck source=probe_lib.sh
. "$HERE/probe_lib.sh"

echo "--- live-backend parsing (mock of the Management API)"
probe "a returned value is compared" 3 "select /*mock:3*/ 1 as v;"
probe "a column not named v is read by position" 42 "select /*mockfirst:42*/ 1;"
probe "an empty result row is read as empty" "" "select /*mock:*/ 1;"
probe "a returned error becomes ERROR" ERROR "select /*mock:boom*/ 1 as v;"
probe "a wrong expectation is reported" 4 "select /*mock:3*/ 1 as v;"
probe_any "either of two accepted results passes" "select /*mock:A*/ 1;" B A
probe_msg "a rejection reason is matched" "already_used" "select /*mock:Rejected: already_used*/ 1;"
probe_msg "a wrong rejection reason fails" "insufficient" "select /*mock:Rejected: already_used*/ 1;"
probe_ok "probe_ok accepts a value" "select /*mock:ok*/ 1 as v;"
probe_ok "probe_ok rejects an error" "select /*mock:boom*/ 1 as v;"
skip "a skipped probe is not a pass" "synthetic reason"

selftest_fail=0
check() { # check <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok    %s = %s\n' "$1" "$3"
  else printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$2" "$3"; selftest_fail=$((selftest_fail + 1)); fi
}
check "passes" 7 "$probe_pass"
check "failures" 3 "$probe_fail"
check "skips" 1 "$probe_skip"

if [ "$selftest_fail" -eq 0 ]; then
  printf '\nself-test OK\n'
else
  printf '\nself-test FAILED (%s checks)\n' "$selftest_fail"
fi
exit "$selftest_fail"

#!/usr/bin/env bash
# MEEM STORE — shared probe harness for the SQL security suites.
#
# A probe is one SQL string that runs inside its own transaction and ends in
# ROLLBACK, so it can never change production data. Two backends:
#
#   live   SUPABASE_ACCESS_TOKEN, else $PROBE_TOKEN_FILE, else
#          ~/.raizey-audit/live_rw, else ~/.raizey-audit/live_ro (legacy) →
#          the Supabase Management API (/database/query). Optional PROJECT_REF,
#          and PROBE_API_BASE for the db/tests/probe_lib_selftest.sh mock.
#   local  MEEM_LOCAL_DSN="postgresql://postgres@/postgres?host=/tmp/meem&port=5599"
#          → a local PostgreSQL started by db/tests/local_sql_suite.sh
#
# probe  <label> <expect: ERROR|value> <sql>   exact value / "must raise"
# probe_any <label> <sql> <expected>...       accepts any of the listed results
# probe_ok <label> <sql>                      any non-error result
# probe_msg <label> <needle> <sql>            result contains <needle>
# skip   <label> <reason>
#
# Counters: probe_pass / probe_fail / probe_skip. The suite exits non-zero when
# probe_fail > 0. Probes that need an admin identity are skipped (never counted
# as passed) when the database has no usable admin.

probe_pass=0
probe_fail=0
probe_skip=0
PROBE_PSQL="${MEEM_PSQL:-psql}"

probe_token() {
  local t="${SUPABASE_ACCESS_TOKEN:-}"
  [ -n "$t" ] || t="$(cat "${PROBE_TOKEN_FILE:-$HOME/.raizey-audit/live_rw}" 2>/dev/null || true)"
  [ -n "$t" ] || t="$(cat "$HOME/.raizey-audit/live_ro" 2>/dev/null || true)"
  printf '%s' "$(printf '%s' "$t" | tr -d '[:space:]')"
}

# _probe_run <sql> → prints "ERROR" or the scalar value of the last statement.
_probe_run() {
  local sql="$1" out rc
  if [ -n "${MEEM_LOCAL_DSN:-}" ]; then
    out="$("$PROBE_PSQL" "$MEEM_LOCAL_DSN" -At -q -v ON_ERROR_STOP=0 -c "$sql" 2>&1)"
    rc=$?
    # Drop psql chatter and command tags, keep the last real value line.
    out="$(printf '%s\n' "$out" | grep -v -E '^(WARNING|NOTICE|HINT|DETAIL|CONTEXT|BEGIN|ROLLBACK|COMMIT|SET|INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALTER|DROP|GRANT|REVOKE|DO|SELECT [0-9])' | grep -v '^[[:space:]]*$' | tail -1)"
    if [ "$rc" -ne 0 ] || printf '%s' "$out" | grep -q -E '(^|: )(ERROR|FATAL)'; then
      printf 'ERROR'
    else
      printf '%s' "$out"
    fi
  else
    local ref="${PROJECT_REF:-rglbfizqolrenwfsndyv}" base token body
    base="${PROBE_API_BASE:-https://api.supabase.com}"
    token="$(probe_token)"
    if [ -z "$token" ]; then printf 'NO_TOKEN'; return 0; fi
    body="$(python3 -c 'import json,sys;print(json.dumps({"query":sys.argv[1]}))' "$sql")"
    out="$(curl -s -X POST -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
           --data-binary "$body" "$base/v1/projects/$ref/database/query")"
    if printf '%s' "$out" | grep -q '"message"'; then
      printf 'ERROR'
    else
      # First column of the first row — the same value psql -At would print on
      # the local backend. Reading a fixed "v" key silently returned None for
      # any query that names its column something else.
      printf '%s' "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin);r=d[0] if d else None;print("" if not isinstance(r,dict) or not r else str(next(iter(r.values()))))' 2>/dev/null || printf '?'
    fi
  fi
}

# probe <label> <expect: ERROR|value> <sql>
probe() {
  local label="$1" expect="$2" sql="$3" got
  got="$(_probe_run "$sql")"
  if [ "$expect" = "ERROR" ]; then
    if [ "$got" = "ERROR" ]; then printf 'PASS  %s\n' "$label"; probe_pass=$((probe_pass + 1))
    else printf 'FAIL  %s (expected an error, got %s)\n' "$label" "$got"; probe_fail=$((probe_fail + 1)); fi
  else
    if [ "$got" = "$expect" ]; then printf 'PASS  %s\n' "$label"; probe_pass=$((probe_pass + 1))
    else printf 'FAIL  %s (expected %s, got %s)\n' "$label" "$expect" "$got"; probe_fail=$((probe_fail + 1)); fi
  fi
}

# probe_ok <label> <sql> — the call must not raise (any non-error value passes).
probe_ok() {
  local label="$1" sql="$2" got
  got="$(_probe_run "$sql")"
  if [ "$got" = "ERROR" ] || [ "$got" = "NO_TOKEN" ]; then
    printf 'FAIL  %s (expected a non-error result%s)\n' "$label" "$([ "$got" = NO_TOKEN ] && printf ' — no access token')"
    probe_fail=$((probe_fail + 1))
  else
    printf 'PASS  %s\n' "$label"; probe_pass=$((probe_pass + 1))
  fi
}

# probe_msg <label> <needle> <sql> — the result must contain <needle> (case-insensitive).
# Used when the point of the probe is *why* a call was rejected: the SQL catches
# the exception and returns sqlerrm, so the report shows the real server message.
probe_msg() {
  local label="$1" needle="$2" sql="$3" got low
  got="$(_probe_run "$sql")"
  low="$(printf '%s' "$got" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
    *"$needle"*) printf 'PASS  %s\n' "$label"; probe_pass=$((probe_pass + 1)) ;;
    *) printf 'FAIL  %s (expected a message containing "%s", got: %s)\n' "$label" "$needle" "$got"
       probe_fail=$((probe_fail + 1)) ;;
  esac
}

# probe_any <label> <sql> <expected>... — passes when the result equals any of
# the expected values. Used where two databases can both be correct-but-different
# (e.g. a missing GRANT rejects the statement on the live project while a local
# stub grants the table and RLS returns zero rows).
probe_any() {
  local label="$1" sql="$2" got e
  shift 2
  got="$(_probe_run "$sql")"
  for e in "$@"; do
    if [ "$got" = "$e" ]; then printf 'PASS  %s\n' "$label"; probe_pass=$((probe_pass + 1)); return 0; fi
  done
  printf 'FAIL  %s (expected one of [%s], got %s)\n' "$label" "$*" "$got"
  probe_fail=$((probe_fail + 1))
}

# skip <label> <reason> — counted separately, never as a pass.
skip() { printf 'SKIP  %s (%s)\n' "$1" "$2"; probe_skip=$((probe_skip + 1)); }

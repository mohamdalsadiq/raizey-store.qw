#!/usr/bin/env bash
# MEEM STORE — run SQL against the LIVE Supabase project (Management API).
#
#   bash db/tests/live_sql.sh -c "select 1"          one-off query
#   bash db/tests/live_sql.sh -f db/migrations/x.sql one SQL file
#   bash db/tests/live_sql.sh --migrations           the 10 pending migrations, documented order
#   bash db/tests/live_sql.sh --rollbacks            the rollback files, reverse order
#
# Token lookup (first hit wins), never printed:
#   $SUPABASE_ACCESS_TOKEN → $PROBE_TOKEN_FILE
#   → $HOME/.raizey-audit/live_rw (read/write token) → $HOME/.raizey-audit/live_ro (legacy)
# The token file lives outside the repository on purpose: it must never be committed.
#
# Override the project with PROJECT_REF (default rglbfizqolrenwfsndyv) or the whole
# endpoint with PROBE_API_BASE (used by db/tests/probe_lib_selftest.sh's mock).
#
# Exit status: 0 when every file/query succeeded, 1 on the first failure (the
# failing response is printed, the token is never echoed). LIVE_SQL_MAX caps how
# many characters of a successful response are echoed (default 600 per file).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# Migrations in the order documented in docs/FINAL_REPORT.md §3.
MIGRATIONS=(
  "db/migrations/2026-10-12_referral_prefix_meem.sql"
  "db/migrations/2026-10-12_banners.sql"
  "db/migrations/2026-10-12_banners_repoint_assets.sql"
  "db/migrations/2026-10-12_banners_seed_slides.sql"
  "db/migrations/2026-10-12_settings_whatsapp_number.sql"
  "db/migrations/2026-10-12_banner_mobile_aspect.sql"
  "db/migrations/2026-10-13_p1_oracle_scope_and_coupon_strength.sql"
  "db/migrations/2026-10-13_banners_v2.sql"
  "db/migrations/2026-10-13_section_category_icons.sql"
  "db/migrations/2026-10-13_home_highlights.sql"
  "db/migrations/2026-10-14_revoke_internal_execute.sql"
  "db/migrations/2026-10-14_referral_code_check_for_anon.sql"
)
# Rollbacks, reverse of the application order (files that ship one).
ROLLBACKS=(
  "db/rollback/2026-10-14_referral_code_check_for_anon_rollback.sql"
  "db/rollback/2026-10-14_revoke_internal_execute_rollback.sql"
  "db/rollback/2026-10-13_home_highlights_rollback.sql"
  "db/rollback/2026-10-13_section_category_icons_rollback.sql"
  "db/rollback/2026-10-13_banners_v2_rollback.sql"
  "db/rollback/2026-10-13_p1_oracle_scope_and_coupon_strength_rollback.sql"
  "db/rollback/2026-10-12_banner_mobile_aspect_rollback.sql"
  "db/rollback/2026-10-12_banners_repoint_assets_rollback.sql"
  "db/rollback/2026-10-12_banners_rollback.sql"
  "db/rollback/2026-10-12_referral_prefix_meem_rollback.sql"
)

token() {
  local t="${SUPABASE_ACCESS_TOKEN:-}"
  [ -n "$t" ] || t="$(cat "${PROBE_TOKEN_FILE:-$HOME/.raizey-audit/live_rw}" 2>/dev/null || true)"
  [ -n "$t" ] || t="$(cat "$HOME/.raizey-audit/live_ro" 2>/dev/null || true)"
  printf '%s' "$(printf '%s' "$t" | tr -d '[:space:]')"
}
T="$(token)"
if [ -z "$T" ]; then
  echo "no access token — set SUPABASE_ACCESS_TOKEN or ~/.raizey-audit/live_rw" >&2
  exit 2
fi
export LIVE_TOKEN="$T"
export PROJECT_REF="${PROJECT_REF:-rglbfizqolrenwfsndyv}"
export PROBE_API_BASE="${PROBE_API_BASE:-https://api.supabase.com}"
unset T

run_file() {
  # run_file <path> <label> — the path is repo-relative unless it is absolute
  local arg="$1" label="${2:-$1}" f
  case "$arg" in /*) f="$arg" ;; *) f="$ROOT/$arg" ;; esac
  if [ ! -s "$f" ]; then echo "FAIL  $label (missing or empty)"; return 1; fi
  SQL_FILE="$f" LABEL="$label" python3 - <<'PY'
import json, os, sys, urllib.error, urllib.request
sql = open(os.environ["SQL_FILE"], encoding="utf-8").read()
label = os.environ["LABEL"]
url = "%s/v1/projects/%s/database/query" % (os.environ["PROBE_API_BASE"], os.environ["PROJECT_REF"])
req = urllib.request.Request(url, data=json.dumps({"query": sql}).encode(),
    headers={"Authorization": "Bearer " + os.environ["LIVE_TOKEN"],
             "Content-Type": "application/json"}, method="POST")
try:
    r = urllib.request.urlopen(req, timeout=300)
    body = r.read().decode()
except urllib.error.HTTPError as e:
    body = e.read().decode()
    print("FAIL  %s (HTTP %s) %s" % (label, e.code, body[:800]))
    sys.exit(1)
except Exception as e:  # network/timeout
    print("FAIL  %s (%s)" % (label, e))
    sys.exit(1)
if '"message"' in body and body.lstrip().startswith("{"):
    print("FAIL  %s %s" % (label, body[:800]))
    sys.exit(1)
limit = int(os.environ.get("LIVE_SQL_MAX", "600"))
print("ok    %s" % label)
print("      %s" % body.strip()[:limit])
PY
}

run_sql() {
  local sql="$1" label="${2:-query}"
  local tmp; tmp="$(mktemp)"
  printf '%s' "$sql" > "$tmp"
  local rc=0
  SQL_FILE="$tmp" LABEL="$label" python3 - <<'PY' || rc=$?
import json, os, sys, urllib.error, urllib.request
sql = open(os.environ["SQL_FILE"], encoding="utf-8").read()
url = "%s/v1/projects/%s/database/query" % (os.environ["PROBE_API_BASE"], os.environ["PROJECT_REF"])
req = urllib.request.Request(url, data=json.dumps({"query": sql}).encode(),
    headers={"Authorization": "Bearer " + os.environ["LIVE_TOKEN"],
             "Content-Type": "application/json"}, method="POST")
try:
    r = urllib.request.urlopen(req, timeout=300)
    print(r.read().decode()[:int(os.environ.get("LIVE_SQL_MAX", "2000"))])
except urllib.error.HTTPError as e:
    print("HTTP %s %s" % (e.code, e.read().decode()[:800]))
    sys.exit(1)
PY
  rm -f "$tmp"
  return $rc
}

case "${1:-}" in
  -c) [ $# -ge 2 ] || { echo "usage: live_sql.sh -c \"<sql>\"" >&2; exit 2; }
      run_sql "$2" "query"; exit $? ;;
  -f) [ $# -ge 2 ] || { echo "usage: live_sql.sh -f <file.sql>" >&2; exit 2; }
      run_file "$2"; exit $? ;;
  --migrations)
      rc=0
      for m in "${MIGRATIONS[@]}"; do run_file "$m" "$m" || rc=1; done
      exit $rc ;;
  --rollbacks)
      rc=0
      for r in "${ROLLBACKS[@]}"; do run_file "$r" "$r" || rc=1; done
      exit $rc ;;
  *) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac

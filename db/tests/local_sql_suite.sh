#!/usr/bin/env bash
# MEEM STORE — run the SQL suites without a Supabase token.
#
#   bash db/tests/local_sql_suite.sh
#
# What it does, in order, against a throwaway PostgreSQL on this machine:
#   1. creates a fresh database
#   2. loads db/tests/local_bootstrap.sql (live-shaped stubs, no live rows)
#   3. applies every pending migration in db/migrations (documented order)
#   4. applies them a second time (they are declared idempotent)
#   5. runs db/tests/run_banners_security.sh and run_storefront_security.sh
#   6. applies every rollback in reverse order and re-checks the suites fail-safe
#
# A green local run proves the migrations execute and the probe SQL is correct;
# it is NOT a substitute for the live run with SUPABASE_ACCESS_TOKEN (that run is
# the one that touches the project's real rows, always inside ROLLBACK).
#
# MEEM_KEEP_PG=1     leave the throwaway server running for manual psql poking
# MEEM_SKIP_ROLLBACK=1  stop after the suites (keeps the migrated schema)
#
# PostgreSQL comes from the `pgserver` wheel in the Python venv:
#   python3 -m venv ~/work/pgvenv && ~/work/pgvenv/bin/pip install pgserver
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

PGDATA="${MEEM_PGDATA:-$HOME/.meem-pgdata}"
SOCK="${MEEM_PGSOCK:-/tmp/meem-pg}"
PORT="${MEEM_PGPORT:-5599}"
DBNAME="meem_check"
DSN="postgresql://postgres@/$DBNAME?host=$SOCK&port=$PORT"
ADMIN_DSN="postgresql://postgres@/postgres?host=$SOCK&port=$PORT"

# --- Postgres binaries -------------------------------------------------------
if [ -n "${MEEM_PGBIN:-}" ]; then
  PGBIN="$MEEM_PGBIN"
else
  PGBIN="$(command -v pg_ctl >/dev/null 2>&1 && dirname "$(command -v pg_ctl)" || true)"
fi
if [ -z "$PGBIN" ] || [ ! -x "$PGBIN/psql" ]; then
  PGBIN="$(ls -d "$HOME"/work/pgvenv/lib/python*/site-packages/pgserver/pginstall/bin 2>/dev/null | head -1)"
fi
if [ -z "$PGBIN" ] || [ ! -x "$PGBIN/psql" ]; then
  echo "no PostgreSQL binaries found — see the header for the pgserver setup" >&2
  exit 3
fi

# Migrations in the order documented in docs/FINAL_REPORT.md §5.
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
)
ROLLBACKS=(
  "db/rollback/2026-10-13_home_highlights_rollback.sql"
  "db/rollback/2026-10-13_section_category_icons_rollback.sql"
  "db/rollback/2026-10-13_banners_v2_rollback.sql"
  "db/rollback/2026-10-13_p1_oracle_scope_and_coupon_strength_rollback.sql"
  "db/rollback/2026-10-12_banner_mobile_aspect_rollback.sql"
  "db/rollback/2026-10-12_referral_prefix_meem_rollback.sql"
  "db/rollback/2026-10-12_banners_repoint_assets_rollback.sql"
  "db/rollback/2026-10-12_banners_rollback.sql"
)

step() { printf '\n=== %s\n' "$*"; }
steps_failed=0

psql_admin() { "$PGBIN/psql" "$ADMIN_DSN" -q -At "$@"; }
psql_db() { "$PGBIN/psql" "$DSN" -q "$@"; }

run_file() { # run_file <path> <label>
  local file="$1" label="$2"
  if "$PGBIN/psql" "$DSN" -q -v ON_ERROR_STOP=1 -f "$ROOT/$file" >/dev/null 2>"$PGDATA/last-error.log"; then
    printf 'ok    %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    head -20 "$PGDATA/last-error.log" | sed 's/^/      /'
    steps_failed=$((steps_failed + 1))
  fi
}

stop_server() {
  [ "${MEEM_KEEP_PG:-}" = "1" ] && { echo "(server left running on $SOCK:$PORT — MEEM_KEEP_PG=1)"; return 0; }
  "$PGBIN/pg_ctl" -D "$PGDATA" -w stop >/dev/null 2>&1
}
trap stop_server EXIT

# --- server ------------------------------------------------------------------
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  step "initdb ($PGDATA)"
  rm -rf "$PGDATA"
  "$PGBIN/initdb" -D "$PGDATA" -U postgres --auth=trust >/dev/null 2>&1 || { echo "initdb failed"; exit 3; }
fi
mkdir -p "$SOCK"
step "starting PostgreSQL on $SOCK:$PORT"
"$PGBIN/pg_ctl" -D "$PGDATA" -l "$PGDATA/server.log" \
  -o "-k $SOCK -p $PORT -c listen_addresses=''" -w start >/dev/null || {
    tail -20 "$PGDATA/server.log"; exit 3; }
psql_admin -c "drop database if exists $DBNAME;" >/dev/null
psql_admin -c "create database $DBNAME;" >/dev/null

# --- bootstrap ---------------------------------------------------------------
step "bootstrap (db/tests/local_bootstrap.sql)"
run_file "db/tests/local_bootstrap.sql" "local_bootstrap.sql"

# --- migrations --------------------------------------------------------------
step "migrations (first pass)"
for m in "${MIGRATIONS[@]}"; do run_file "$m" "$m"; done
step "migrations (second pass — idempotency)"
for m in "${MIGRATIONS[@]}"; do run_file "$m" "$m (again)"; done

# --- suites ------------------------------------------------------------------
export MEEM_LOCAL_DSN="$DSN"
export MEEM_PSQL="$PGBIN/psql"
suite_status=0
step "db/tests/run_banners_security.sh"
bash "$HERE/run_banners_security.sh" || suite_status=1
step "db/tests/run_storefront_security.sh"
bash "$HERE/run_storefront_security.sh" || suite_status=1

# --- rollbacks ---------------------------------------------------------------
if [ "${MEEM_SKIP_ROLLBACK:-}" = "1" ]; then
  step "rollbacks skipped (MEEM_SKIP_ROLLBACK=1)"
else
  step "rollbacks (reverse order)"
  for r in "${ROLLBACKS[@]}"; do run_file "$r" "$r"; done
  # settings_whatsapp_number ships no rollback file (documented: delete the key)
  if psql_db -c "delete from public.settings where key = 'whatsapp_number';" >/dev/null 2>&1; then
    printf 'ok    settings whatsapp_number key removed\n'
  fi
fi

step "summary"
printf 'migrations+rollbacks: %s failures\n' "$steps_failed"
if [ "$steps_failed" -ne 0 ] || [ "$suite_status" -ne 0 ]; then
  printf 'RESULT: FAILED\n'
  exit 1
fi
printf 'RESULT: OK\n'

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/scripts/ci/.branch.env"
SCHEMA_DUMP_FILE="${ROOT_DIR}/scripts/ci/.parent-schema.sql"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: ${name}"
    exit 1
  fi
}

require_env SUPABASE_ACCESS_TOKEN
require_env SUPABASE_PROJECT_ID
require_env POSTGRES_URL_NON_POOLING
require_env SUPABASE_DB_PASSWORD

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required to bootstrap branch schema"
  exit 1
fi

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "pg_dump is required to bootstrap branch schema"
  exit 1
fi

PARENT_DB_HOST="${SUPABASE_DB_HOST:-db.${SUPABASE_PROJECT_ID}.supabase.co}"
PARENT_DB_PORT="${SUPABASE_DB_PORT:-5432}"
PARENT_DB_NAME="postgres"
PARENT_DB_USER="postgres"

echo "PostgreSQL client versions:"
pg_dump --version
psql --version

echo "Preflight: connecting to parent database at ${PARENT_DB_HOST}:${PARENT_DB_PORT}"
export PGPASSWORD="${SUPABASE_DB_PASSWORD}"
export PGSSLMODE=require

if ! psql \
  --host "$PARENT_DB_HOST" \
  --port "$PARENT_DB_PORT" \
  --username "$PARENT_DB_USER" \
  --dbname "$PARENT_DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -c 'select 1 as parent_db_ok'; then
  echo "Failed to connect to parent database."
  echo "Check SUPABASE_DB_PASSWORD and optional SUPABASE_DB_HOST (Dashboard → Project Settings → Database, direct connection port 5432)."
  unset PGPASSWORD PGSSLMODE
  exit 1
fi

echo "Dumping parent project schema from ${SUPABASE_PROJECT_ID} via native pg_dump (no Docker)"
pg_dump \
  --schema-only \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --host "$PARENT_DB_HOST" \
  --port "$PARENT_DB_PORT" \
  --username "$PARENT_DB_USER" \
  --dbname "$PARENT_DB_NAME" \
  --schema public \
  --schema auth \
  --schema extensions \
  --file "$SCHEMA_DUMP_FILE"

unset PGPASSWORD PGSSLMODE

if [ ! -s "$SCHEMA_DUMP_FILE" ]; then
  echo "Parent schema dump is empty."
  exit 1
fi

echo "Applying parent schema to branch database"
psql "$POSTGRES_URL_NON_POOLING" -v ON_ERROR_STOP=0 -f "$SCHEMA_DUMP_FILE"

echo "Validating restored schema on branch"
validation_output="$(
  psql "$POSTGRES_URL_NON_POOLING" -v ON_ERROR_STOP=1 -tA -c "
    select
      coalesce(to_regclass('public.profiles')::text, ''),
      coalesce(to_regclass('public.pet_market_items')::text, ''),
      coalesce(to_regclass('auth.users')::text, '');
  "
)"

IFS='|' read -r profiles_ok market_ok auth_ok <<< "$validation_output"

if [ -z "$profiles_ok" ] || [ -z "$market_ok" ] || [ -z "$auth_ok" ]; then
  echo "Schema bootstrap incomplete — required tables missing after restore:"
  echo "  public.profiles: ${profiles_ok:-MISSING}"
  echo "  public.pet_market_items: ${market_ok:-MISSING}"
  echo "  auth.users: ${auth_ok:-MISSING}"
  exit 1
fi

echo "Branch schema bootstrap completed."

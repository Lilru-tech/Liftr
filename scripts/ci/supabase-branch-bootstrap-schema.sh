#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${ROOT_DIR}/Liftr"
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

export SUPABASE_ACCESS_TOKEN

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "pg_dump is required to bootstrap branch schema"
  exit 1
fi

PARENT_DB_HOST="db.${SUPABASE_PROJECT_ID}.supabase.co"
PARENT_DB_NAME="postgres"
PARENT_DB_USER="postgres"

echo "Dumping parent project schema from ${SUPABASE_PROJECT_ID} via native pg_dump (no Docker)"
export PGPASSWORD="${SUPABASE_DB_PASSWORD}"
pg_dump \
  --schema-only \
  --no-owner \
  --no-privileges \
  --format=p \
  --file "$SCHEMA_DUMP_FILE" \
  --host "$PARENT_DB_HOST" \
  --username "$PARENT_DB_USER" \
  --dbname "$PARENT_DB_NAME" \
  --sslmode=require
unset PGPASSWORD

if [ ! -s "$SCHEMA_DUMP_FILE" ]; then
  echo "Parent schema dump is empty."
  exit 1
fi

echo "Applying parent schema to branch database"
psql "$POSTGRES_URL_NON_POOLING" -v ON_ERROR_STOP=0 -f "$SCHEMA_DUMP_FILE"

echo "Branch schema bootstrap completed."

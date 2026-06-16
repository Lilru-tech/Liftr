#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/scripts/ci/.branch.env"
SEED_SQL="${ROOT_DIR}/Liftr/supabase/seed/ui_regression_user.sql"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/ci/supabase-branch-psql.sh"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: ${name}"
    exit 1
  fi
}

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

require_env POSTGRES_URL_NON_POOLING
require_env UI_TEST_EMAIL
require_env UI_TEST_PASSWORD

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required to seed the UI regression user"
  exit 1
fi

if [ ! -f "$SEED_SQL" ]; then
  echo "Seed SQL not found at ${SEED_SQL}"
  exit 1
fi

echo "Verifying required tables exist before seeding"
validation_output="$(
  branch_psql -v ON_ERROR_STOP=1 -tA -c "
    select
      coalesce(to_regclass('public.profiles')::text, ''),
      coalesce(to_regclass('auth.users')::text, '');
  "
)"

IFS='|' read -r profiles_ok auth_ok <<< "$validation_output"

if [ -z "$profiles_ok" ] || [ -z "$auth_ok" ]; then
  echo "Schema bootstrap incomplete — bootstrap step did not restore required tables:"
  echo "  public.profiles: ${profiles_ok:-MISSING}"
  echo "  auth.users: ${auth_ok:-MISSING}"
  exit 1
fi

echo "Seeding UI regression user ${UI_TEST_EMAIL}"
branch_psql \
  -v ON_ERROR_STOP=1 \
  -v email="'${UI_TEST_EMAIL}'" \
  -v password="'${UI_TEST_PASSWORD}'" \
  -f "$SEED_SQL"

echo "UI regression user seeded successfully."

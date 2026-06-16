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

require_env POSTGRES_URL
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
escaped_email="$(printf '%s' "$UI_TEST_EMAIL" | sed "s/'/''/g")"
escaped_password="$(printf '%s' "$UI_TEST_PASSWORD" | sed "s/'/''/g")"
seed_sql="$(sed \
  -e "s/__EMAIL__/${escaped_email}/g" \
  -e "s/__PASSWORD__/${escaped_password}/g" \
  "$SEED_SQL")"
printf '%s\n' "$seed_sql" | branch_psql -v ON_ERROR_STOP=1 -f -

echo "Verifying seeded auth identity and market fixtures"
seed_validation="$(
  branch_psql -v ON_ERROR_STOP=1 -tA -c "
    select
      coalesce((
        select count(*)::text
        from auth.identities i
        join auth.users u on u.id = i.user_id
        where u.email = '${escaped_email}'
          and i.provider = 'email'
      ), '0'),
      coalesce((
        select count(*)::text
        from public.pet_market_items
        where item_type = 'food_baby'
          and is_active = true
      ), '0');
  "
)"

IFS='|' read -r identity_ok market_ok <<< "$seed_validation"

if [ "$identity_ok" != "1" ]; then
  echo "UI regression seed incomplete — auth.identities row missing for ${UI_TEST_EMAIL}"
  exit 1
fi

if [ "$market_ok" != "1" ]; then
  echo "UI regression seed incomplete — active food_baby market item missing"
  exit 1
fi

echo "UI regression user seeded successfully."

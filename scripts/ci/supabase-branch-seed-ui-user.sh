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

export SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-${ANON_KEY:-}}"
require_env SUPABASE_URL
require_env SUPABASE_ANON_KEY

echo "Verifying GoTrue password sign-in for ${UI_TEST_EMAIL}"
sign_in_status="$(
  curl -sS -o /tmp/ui-regression-gotrue.json -w "%{http_code}" \
    -X POST "${SUPABASE_URL}/auth/v1/token?grant_type=password" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${UI_TEST_EMAIL}\",\"password\":\"${UI_TEST_PASSWORD}\"}"
)"

if [ "$sign_in_status" != "200" ]; then
  echo "GoTrue sign-in verification failed with HTTP ${sign_in_status}"
  cat /tmp/ui-regression-gotrue.json || true
  exit 1
fi

access_token="$(python3 -c 'import json; print(json.load(open("/tmp/ui-regression-gotrue.json")).get("access_token",""))')"
if [ -z "$access_token" ]; then
  echo "GoTrue sign-in response did not include an access token"
  cat /tmp/ui-regression-gotrue.json || true
  exit 1
fi

echo "Verifying authenticated pet RPC for ${UI_TEST_EMAIL}"
pet_rpc_status="$(
  curl -sS -o /tmp/ui-regression-pet.json -w "%{http_code}" \
    -X POST "${SUPABASE_URL}/rest/v1/rpc/get_my_pet_v1" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -d '{}'
)"

if [ "$pet_rpc_status" != "200" ]; then
  echo "get_my_pet_v1 verification failed with HTTP ${pet_rpc_status}"
  cat /tmp/ui-regression-pet.json || true
  exit 1
fi

if ! python3 -c 'import json,sys; data=json.load(open("/tmp/ui-regression-pet.json")); pet=data.get("pet") if isinstance(data,dict) else None; sys.exit(0 if pet else 1)'; then
  echo "get_my_pet_v1 returned no active pet for ${UI_TEST_EMAIL}"
  cat /tmp/ui-regression-pet.json || true
  exit 1
fi

echo "Verifying pet and market RPC prerequisites for UI regression"
rpc_validation="$(
  branch_psql -v ON_ERROR_STOP=1 -tA -c "
    select
      coalesce(to_regprocedure('public.get_my_pet_v1()')::text, ''),
      coalesce(to_regprocedure('public.list_pet_market_items_v1()')::text, ''),
      coalesce(to_regprocedure('public.buy_pet_market_item_v1(text,integer)')::text, ''),
      coalesce((
        select count(*)::text
        from public.pet_instances pi
        join auth.users u on u.id = pi.user_id
        where u.email = '${escaped_email}'
          and pi.is_active = true
      ), '0');
  "
)"

IFS='|' read -r get_my_pet_rpc list_market_rpc buy_item_rpc active_pet_ok <<< "$rpc_validation"

if [ -z "$get_my_pet_rpc" ] || [ -z "$list_market_rpc" ] || [ -z "$buy_item_rpc" ]; then
  echo "Pet market RPCs are missing on the branch database."
  echo "  get_my_pet_v1: ${get_my_pet_rpc:-MISSING}"
  echo "  list_pet_market_items_v1: ${list_market_rpc:-MISSING}"
  echo "  buy_pet_market_item_v1: ${buy_item_rpc:-MISSING}"
  exit 1
fi

if [ "$active_pet_ok" != "1" ]; then
  echo "UI regression seed incomplete — active pet instance missing for ${UI_TEST_EMAIL}"
  exit 1
fi

echo "UI regression user seeded successfully."

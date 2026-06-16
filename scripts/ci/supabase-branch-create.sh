#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${ROOT_DIR}/Liftr"
ENV_FILE="${ROOT_DIR}/scripts/ci/.branch.env"
BRANCH_NAME="${BRANCH_NAME:-ui-regression-${GITHUB_RUN_ID:-local}}"
TIMEOUT_SECONDS="${BRANCH_READY_TIMEOUT_SECONDS:-900}"
POLL_INTERVAL_SECONDS="${BRANCH_POLL_INTERVAL_SECONDS:-30}"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: ${name}"
    exit 1
  fi
}

require_env SUPABASE_ACCESS_TOKEN
require_env SUPABASE_PROJECT_ID

export SUPABASE_ACCESS_TOKEN
mkdir -p "$(dirname "$ENV_FILE")"
: >"$ENV_FILE"

echo "Linking Supabase project ${SUPABASE_PROJECT_ID} (workdir: ${WORK_DIR})"
supabase link --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR"

echo "Creating preview branch: ${BRANCH_NAME}"
create_branch() {
  supabase branches create "$BRANCH_NAME" --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR"
}

if ! create_branch; then
  if ! supabase --experimental branches create "$BRANCH_NAME" --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR"; then
    if supabase branches list --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR" -o json \
      | jq -e --arg name "$BRANCH_NAME" '.[] | select(.name == $name)' >/dev/null 2>&1; then
      echo "Branch ${BRANCH_NAME} already exists; continuing."
    else
      echo "Failed to create branch ${BRANCH_NAME}"
      exit 1
    fi
  fi
fi

echo "Waiting for branch ${BRANCH_NAME} to become healthy (timeout ${TIMEOUT_SECONDS}s)"
elapsed=0
branch_status=""
while [ "$elapsed" -lt "$TIMEOUT_SECONDS" ]; do
  branch_status="$(
    supabase branches list --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR" -o json \
      | jq -r --arg name "$BRANCH_NAME" '.[] | select(.name == $name) | .status // empty' \
      | head -n 1
  )"

  if [ -z "$branch_status" ]; then
    echo "Branch ${BRANCH_NAME} not found in list yet (elapsed ${elapsed}s)"
  else
    echo "Branch status: ${branch_status} (elapsed ${elapsed}s)"
    case "$branch_status" in
      ACTIVE_HEALTHY|FUNCTIONS_DEPLOYED|RUNNING)
        break
        ;;
      MIGRATIONS_FAILED|FAILED|UNHEALTHY)
        echo "Branch ${BRANCH_NAME} failed with status ${branch_status}"
        supabase branches list --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR" -o json \
          | jq --arg name "$BRANCH_NAME" '.[] | select(.name == $name)'
        exit 1
        ;;
    esac
  fi

  sleep "$POLL_INTERVAL_SECONDS"
  elapsed=$((elapsed + POLL_INTERVAL_SECONDS))
done

if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
  echo "Timed out waiting for branch ${BRANCH_NAME} to become healthy"
  exit 1
fi

echo "Fetching branch credentials"
fetch_branch_env() {
  supabase branches get "$BRANCH_NAME" -o env --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR"
}

if ! fetch_branch_env | tee "$ENV_FILE"; then
  supabase --experimental branches get "$BRANCH_NAME" -o env --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR" | tee "$ENV_FILE"
fi

if [ -n "${GITHUB_ENV:-}" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "$line" >>"$GITHUB_ENV"
  done <"$ENV_FILE"

  if grep -q '^ANON_KEY=' "$ENV_FILE" && ! grep -q '^SUPABASE_ANON_KEY=' "$ENV_FILE"; then
    anon_key="$(grep '^ANON_KEY=' "$ENV_FILE" | cut -d= -f2-)"
    echo "SUPABASE_ANON_KEY=${anon_key}" >>"$GITHUB_ENV"
    echo "SUPABASE_ANON_KEY=${anon_key}" >>"$ENV_FILE"
  fi

  echo "BRANCH_NAME=${BRANCH_NAME}" >>"$GITHUB_ENV"
fi

echo "BRANCH_NAME=${BRANCH_NAME}" >>"$ENV_FILE"
echo "Branch ${BRANCH_NAME} is ready."

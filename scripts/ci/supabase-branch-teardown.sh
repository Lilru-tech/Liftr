#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${ROOT_DIR}/Liftr"
ENV_FILE="${ROOT_DIR}/scripts/ci/.branch.env"
BRANCH_NAME="${BRANCH_NAME:-}"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [ -z "$BRANCH_NAME" ]; then
  echo "BRANCH_NAME is not set; skipping branch teardown."
  exit 0
fi

if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ] || [ -z "${SUPABASE_PROJECT_ID:-}" ]; then
  echo "Supabase credentials missing; skipping branch teardown for ${BRANCH_NAME}."
  exit 0
fi

export SUPABASE_ACCESS_TOKEN

echo "Deleting preview branch ${BRANCH_NAME}"
delete_branch() {
  supabase branches delete "$BRANCH_NAME" --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR"
}

if delete_branch; then
  echo "Deleted branch ${BRANCH_NAME}"
else
  if supabase --experimental branches delete "$BRANCH_NAME" --project-ref "$SUPABASE_PROJECT_ID" --workdir "$WORK_DIR"; then
    echo "Deleted branch ${BRANCH_NAME}"
  else
    echo "Branch delete returned non-zero for ${BRANCH_NAME}; it may already be removed."
  fi
fi

rm -f "$ENV_FILE"

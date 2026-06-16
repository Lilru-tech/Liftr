#!/usr/bin/env bash

branch_psql_url() {
  if [ -n "${POSTGRES_URL:-}" ]; then
    echo "$POSTGRES_URL"
    return 0
  fi

  if [ -n "${POSTGRES_URL_NON_POOLING:-}" ]; then
    echo "POSTGRES_URL is missing. supabase branches get must return the pooler URL for CI." >&2
    echo "db.<ref>.supabase.co is IPv6-only and branch tenants are not registered on the parent pooler host." >&2
    return 1
  fi

  echo "No branch database URL available." >&2
  return 1
}

wait_for_branch_db() {
  local max_wait="${BRANCH_DB_WAIT_SECONDS:-300}"
  local interval="${BRANCH_DB_POLL_SECONDS:-10}"
  local elapsed=0
  local db_url

  db_url="$(branch_psql_url)" || return 1

  echo "Waiting for branch database connectivity (timeout ${max_wait}s)..."
  while [ "$elapsed" -lt "$max_wait" ]; do
    if psql "$db_url" -v ON_ERROR_STOP=1 -c 'select 1 as branch_db_ok' >/dev/null 2>&1; then
      echo "Branch database is reachable."
      return 0
    fi
    echo "Branch database not ready yet (elapsed ${elapsed}s)"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "Timed out waiting for branch database."
  return 1
}

branch_psql() {
  local db_url
  db_url="$(branch_psql_url)" || return 1
  psql "$db_url" "$@"
}

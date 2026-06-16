#!/usr/bin/env bash

branch_psql_url() {
  local url="${1:-${POSTGRES_URL_NON_POOLING:-}}"
  local pooler_host="${SUPABASE_DB_HOST:-aws-1-eu-west-1.pooler.supabase.com}"
  local pooler_port="${SUPABASE_DB_PORT:-5432}"

  if [ -z "$url" ]; then
    echo "branch_psql_url: POSTGRES_URL_NON_POOLING is empty" >&2
    return 1
  fi

  python3 - "$url" "$pooler_host" "$pooler_port" <<'PY'
import sys
import urllib.parse

url, pooler_host, pooler_port = sys.argv[1:4]
parsed = urllib.parse.urlparse(url)
user = parsed.username or "postgres"
host = parsed.hostname or ""
password = parsed.password or ""
dbname = (parsed.path or "/postgres").lstrip("/") or "postgres"

if host.endswith("pooler.supabase.com"):
    print(url)
    sys.exit(0)

ref = ""
if host.startswith("db.") and host.endswith(".supabase.co"):
    ref = host[3 : -len(".supabase.co")]

if user == "postgres" and ref:
    user = f"postgres.{ref}"

netloc = (
    f"{urllib.parse.quote(user, safe='')}:"
    f"{urllib.parse.quote(password, safe='')}"
    f"@{pooler_host}:{pooler_port}"
)
rewritten = urllib.parse.urlunparse(
    (parsed.scheme or "postgresql", netloc, f"/{dbname}", "", "", "")
)
print(rewritten)
PY
}

branch_psql() {
  local db_url
  db_url="$(branch_psql_url)"
  psql "$db_url" "$@"
}

#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/settleit-auth-clone"
  echo "Example: $0 ~/Projects/settleit-auth"
  exit 1
fi

TARGET="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$TARGET/.git" ]]; then
  echo "Error: $TARGET is not a git repository (clone Lilru-tech/settleit-auth first)."
  exit 1
fi

mkdir -p "$TARGET/auth/callback"
cp "$SCRIPT_DIR/public/auth/callback/index.html" "$TARGET/auth/callback/index.html"
cp "$SCRIPT_DIR/vercel.json" "$TARGET/vercel.json"

echo "Synced Liftr bridge to $TARGET/auth/callback/ (existing SettleIt pages unchanged)"
echo "Next:"
echo "  cd $TARGET"
echo "  git add -A && git status"
echo "  git commit -m 'Sync Liftr password-reset callback bridge'"
echo "  git push origin main"

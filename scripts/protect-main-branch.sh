#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-Lilru-tech/Liftr}"
BRANCH="${BRANCH:-main}"

if ! command -v gh >/dev/null 2>&1; then
  echo "Install GitHub CLI: https://cli.github.com/"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Run: gh auth login"
  echo "You need Admin access on ${REPO} to set branch protection."
  exit 1
fi

echo "Applying branch protection on ${REPO}:${BRANCH} ..."
echo "  - Block force push"
echo "  - Block deletion"
echo "  - No required PR (keeps Auto-merge devel → main workflow working)"

gh api "repos/${REPO}/branches/${BRANCH}/protection" \
  --method PUT \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "block_creations": false,
  "allow_fork_syncing": false
}
EOF

echo "Done. Verify:"
gh api "repos/${REPO}/branches/${BRANCH}/protection" --jq '{
  allow_force_pushes: .allow_force_pushes.enabled,
  allow_deletions: .allow_deletions.enabled,
  enforce_admins: .enforce_admins.enabled,
  required_pr: .required_pull_request_reviews
}'

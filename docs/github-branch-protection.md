# GitHub branch protection (`main`)

GitHub shows **“Your main branch isn't protected”** when `main` allows force-push or deletion without rules. Protecting `main` is recommended for a production-style default branch.

## Liftr workflow constraint

[`.github/workflows/main.yml`](../.github/workflows/main.yml) fast-forwards `main` to `devel` on every `devel` push using `github-actions[bot]` (direct push, not a PR).

Protection must **not** require pull requests on `main`, or that workflow will fail unless you add a bypass for GitHub Actions and change the merge strategy.

## Recommended rules for `main`

| Rule | Setting | Why |
|------|---------|-----|
| Block force pushes | On | Prevents rewriting production history |
| Block branch deletion | On | Prevents accidental removal of `main` |
| Require pull request before merging | **Off** | Allows auto-merge `devel` → `main` |
| Require status checks | Off (for now) | No required checks configured for `main` today |
| Include administrators | On | Admins follow the same rules |

Optional later: protect `devel` with PR reviews while keeping `main` as a fast-forward mirror only.

## Apply protection (choose one)

### A — Script (fastest if you use GitHub CLI)

```bash
gh auth login
chmod +x scripts/protect-main-branch.sh
./scripts/protect-main-branch.sh
```

Requires **Admin** on `Lilru-tech/Liftr`.

### B — GitHub UI

1. Open [github.com/Lilru-tech/Liftr/settings/branches](https://github.com/Lilru-tech/Liftr/settings/branches).
2. **Add branch ruleset** or **Add classic branch protection rule**.
3. Branch name pattern: `main`.
4. Enable **Restrict force pushes** and **Restrict deletions** (or “Do not allow bypassing” for those).
5. Leave **Require a pull request before merging** **disabled** (see workflow constraint above).
6. Save.

Avoid clicking the repo banner’s **Protect this branch** if it enables required PRs without checking settings first.

## Verify

```bash
gh api repos/Lilru-tech/Liftr/branches/main/protection
```

Or in **Settings → Branches**, confirm a rule exists for `main`.

After the next push to `devel`, confirm the **Auto-merge devel → main** workflow still succeeds under **Actions**.

## If you want PR-only updates to `main` later

1. Stop direct pushes: remove or replace the auto-merge workflow.
2. Enable **Require pull request** on `main`.
3. Merge `devel` → `main` only via PR (or release process).

That is a separate process change, not required to fix the unprotected-branch warning safely today.

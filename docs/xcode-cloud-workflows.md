# Xcode Cloud workflows (Liftr iOS)

**Action required (App Store Connect / Xcode):** delete the **Default** workflow or remove its Push trigger on `devel`. Until that is done, every merge to `devel` still starts two builds. Steps are in [Remove the duplicate workflow](#remove-the-duplicate-workflow-required-once-per-team) below.

Xcode Cloud workflow definitions are **not** stored in this repository. They are managed in **Xcode** (Report navigator → Cloud) or [App Store Connect → Xcode Cloud](https://appstoreconnect.apple.com).

## Canonical setup

| Item | Value |
|------|--------|
| Workflow to keep | **Devel** |
| Workflow to remove | **Default** (duplicate) |
| Branch that triggers iOS CI | **`devel`** only (push) |
| GitHub integration branch | `devel` (same repo: `Lilru-tech/Liftr`) |

After cleanup, each merge or push to `devel` must produce **exactly one** Xcode Cloud build under **Devel**.

## Why two builds ran on every `devel` merge

Two workflows were configured with the same start condition:

- **Default** — Start Condition: **Pushed code changes** on branch `devel`
- **Devel** — Start Condition: **Pushed code changes** on branch `devel`

One git push matched both workflows, so Apple started two archives (e.g. Build 179 under Devel and Build 180 under Default for the same merge commit).

GitHub Actions in this repo do **not** start Xcode Cloud builds:

| Workflow | Triggers on `devel` push? | iOS build? |
|----------|---------------------------|------------|
| [`.github/workflows/main.yml`](../.github/workflows/main.yml) | Yes — fast-forwards `main` | No |
| [`.github/workflows/supabase-edge-territory.yml`](../.github/workflows/supabase-edge-territory.yml) | Only if territory edge paths change | No |
| [`.github/workflows/android.yml`](../.github/workflows/android.yml) | Only if `android/**` changes | No |

## Audit checklist (before deleting Default)

In Xcode → Report navigator (⌘9) → **Cloud**, open **Edit Workflow** for **Default** and **Devel** and compare:

1. **Start Conditions** — both should list Push on `devel` until Default is removed.
2. **Actions** — Archive scheme, test plans, analysis.
3. **Post-Actions** — TestFlight internal/external groups, App Store Connect distribution.
4. **Environment** — Xcode version, macOS image, custom env vars / secrets.

Copy any setting that exists only on **Default** into **Devel** before deleting Default.

Known from production builds (Devel workflow): action **Archive - iOS**, start condition **Pushed code changes**, environment **Xcode 15.3** / **macOS Sonoma 14.4** (upgrade in workflow settings when the team moves to a newer Xcode).

## Remove the duplicate workflow (required once per team)

Requires **Admin** or **App Manager** on the App Store Connect team.

1. Open `Liftr.xcodeproj` in Xcode.
2. Report navigator (⌘9) → **Cloud**.
3. Select workflow **Default** (sidebar group **Default**, branch `devel`).
4. **Edit Workflow** → **Delete Workflow** (or remove **Push** on `devel` under Start Conditions if you must keep the workflow name).
5. Confirm **Devel** remains with **Branch Changes → Push → `devel`** only.
6. Confirm **Default** no longer appears or no longer lists `devel` under push triggers.

Alternative: [App Store Connect](https://appstoreconnect.apple.com) → your app → **Xcode Cloud** → select **Default** → delete or edit start conditions.

## Verify a single build

1. Merge a PR into `devel` (or push a commit to `devel`).
2. In Cloud tab, expect **one** new build under **Devel** / `devel`.
3. **Default** must not start a new build.

## Avoid a second build from `main` (auto-merge)

[`.github/workflows/main.yml`](../.github/workflows/main.yml) pushes `main` after every `devel` push. If **Devel** (or any workflow) also has **Push → `main`**, you can get an extra build minutes later.

**Recommended:** **Devel** triggers only on **`devel`**, not on `main`, unless you intentionally want release builds from `main` only.

## Related docs

- [publishing.md](publishing.md) — App Store release overview
- [Liftr/readme.md](../Liftr/readme.md) — project CI summary

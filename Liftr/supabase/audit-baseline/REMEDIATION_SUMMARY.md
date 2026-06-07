# Liftr DB audit remediation summary

**Project:** `rjzhaafvkxmvlnpsikbi`  
**Date:** 2026-06-05

## Applied migrations (production)

| Migration | Change |
|-----------|--------|
| `db_audit_vacuum_v1` | Vacuum `net._http_response` (deferred marker + manual vacuum) |
| `db_audit_drop_duplicate_indexes_v1` | Removed 23 duplicate indexes/constraints |
| `db_audit_auth_rls_initplan_v1` | Wrapped `auth.uid()` in `(select auth.uid())` on 15 policies |
| `db_audit_spatial_ref_sys_rls_v1` + `db_audit_spatial_ref_sys_revoke_fix_v1` | Revoked API access to `spatial_ref_sys` |
| `db_audit_revoke_internal_rpcs_v1` | Revoked `EXECUTE` on internal `_`/`trg_` trigger functions |
| `db_audit_search_path_v1` | Pinned `search_path` on Liftr-owned security definer functions |
| `db_audit_with_check_policies_v1` | Tightened permissive `WITH CHECK (true)` policies |
| `db_audit_drop_backup_tables_v1` | Dropped 4 backup tables + `cnt` scratch table |
| `db_audit_idle_game_lockdown_v1` | Revoked API access to `idle_game` schema (not used in iOS app) |
| `db_audit_storage_avatars_v1` | Narrowed avatar read policy to UUID-timestamp filenames |

## Visibility regression

Before and after row counts for test users **match** (`visibility_baseline_prod.json` vs `visibility_post_remediation.json`).

## Branch status

Preview branch `db-audit-remediation` failed initial migration replay (PostGIS ordering). Remediation applied to production with per-migration snapshots instead. See `branch_status.json`.

## Manual follow-up

1. Enable auth hardening in dashboard — see `AUTH_HARDENING.md`.
2. **Deferred intentionally** (high breakage risk): RLS policy consolidation on `follows`/`workout_scores`/`profiles`, unused index drops, unindexed FK additions.

## Security advisor delta

- Before: **747** lints (1 ERROR)
- After: **703** lints (1 ERROR — `spatial_ref_sys` RLS still blocked by PostGIS ownership)

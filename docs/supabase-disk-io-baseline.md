# Supabase Disk IO baseline (2026-05-22)

Project: **Liftr** (`rjzhaafvkxmvlnpsikbi`, `eu-west-1`, Postgres 17, Free / NANO).

## Confirmed symptoms

- Email: Disk IO Budget depletion.
- Dashboard: resource exhaustion banner; Compute and Disk locked until **Pro+**.

## Top consumers (`pg_stat_statements`, by total time)

| Rank | Pattern | Calls | Total (ms) | Notes |
|------|---------|-------|------------|-------|
| 1 | `net._http_response` cleanup | 125k | ~20.4M | `pg_net` retention / vacuum pressure |
| 2 | Realtime WAL fan-out | 793k | ~5.3M | Chat / DB changes |
| 3 | `net.http_post` | 50k | ~1.3M | Outbound HTTP via `pg_net` |
| 4 | PostgREST RPC (`get_territory_map_v1`, city list, etc.) | 1–4k | 0.5–0.7M each | Territory + heavy RPCs |
| 5 | `vw_user_prs` selects | 3.5k | ~491k | Profile PR reads |
| 6 | `workouts` PostgREST reads/updates | 1–2k | 60–134k | Home feed + edits |

Territory map and home feed are in the top app-driven query families. Background `pg_net` maintenance is the single largest DB time sink.

## Performance advisor snapshot

- **398** lints total on `public` (+ `idle_game` schema on same instance).
- **178** `auth_rls_initplan` (WARN): `auth.uid()` evaluated per row in RLS.
- **91** `multiple_permissive_policies` (WARN).
- **27** unindexed foreign keys (INFO), including `territory_cells.last_workout_id`.

## Mitigations shipped in repo

See migration `Liftr/supabase/migrations/20260522140000_disk_io_optimizations_v1.sql`:

- Territory map SQL cap **5000** (was 20000).
- iOS/Android map client caps and debounce.
- RLS `(select auth.uid())` rewrite for all `public` policies.
- `get_home_feed_page_v1` single-RPC home feed.
- FK indexes on hot tables; duplicate notification policy removed; `VACUUM` on `net._http_response`.

## Monitoring (7 days)

See [supabase-disk-io-monitoring.md](./supabase-disk-io-monitoring.md).

**Upgrade trigger:** Disk IO daily usage still **>90%** for 3+ days after deploy → Pro + **Micro** or **Small** compute.

# Disk IO monitoring checklist (7 days post-deploy)

After applying `20260522140000_disk_io_optimizations_v1.sql` and client updates:

## Daily (Supabase Dashboard)

1. **Reports → Infrastructure** (or Usage): Disk IO budget % used (target **<80%** sustained).
2. **Database → Query Performance**: confirm `get_territory_map_v1` and `get_home_feed_page_v1` rank lower than before; watch `net._http_response` cleanup.
3. **Database → Advisors → Performance**: `auth_rls_initplan` count should drop to **0** on `public` policies.

## Weekly

- Compare p95 API latency from app logs / Supabase API metrics.
- Row count growth on `territory_cells` (large table increases IO per spatial scan).

## Upgrade decision (Phase D)

Upgrade to **Pro + Micro or Small** if **any** of:

- Disk IO budget **>90%** on **3+ days** in a week with normal traffic.
- User-visible feed/map timeouts persist after deploy.
- `pg_stat_statements` still shows `net._http_response` as #1 by total time after vacuum migration.

## Links

- [Compute and Disk](https://supabase.com/dashboard/project/rjzhaafvkxmvlnpsikbi/settings/compute-and-disk)
- [High Disk IO guide](https://supabase.com/docs/guides/platform/manage-your-usage/disk-io)
- Baseline: [supabase-disk-io-baseline.md](./supabase-disk-io-baseline.md)

-- Baseline checks for body weight history and latest-weight compatibility.

select
  to_regclass('public.body_weight_entries') is not null as body_weight_entries_exists,
  to_regclass('public.vw_latest_weight') is not null as vw_latest_weight_exists;

select
  conname
from pg_constraint
where conrelid = 'public.body_weight_entries'::regclass
  and contype = 'u';

select
  schemaname,
  tablename,
  policyname,
  cmd
from pg_policies
where schemaname = 'public'
  and tablename = 'body_weight_entries'
order by policyname;

select
  p.proname
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('upsert_body_weight_entry', 'refresh_profile_weight_kg');

select
  user_id,
  weight_kg
from public.vw_latest_weight
limit 5;

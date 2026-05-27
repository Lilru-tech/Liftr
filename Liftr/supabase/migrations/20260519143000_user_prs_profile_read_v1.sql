-- PRs on other users' profiles were empty because vw_user_prs runs as security_invoker
-- and personal/endurance/sport_records only allowed SELECT for auth.uid() = user_id.

drop policy if exists personal_records_select_profile on public.personal_records;
create policy personal_records_select_profile
  on public.personal_records
  as permissive
  for select
  to authenticated
  using (true);

drop policy if exists endurance_records_select_profile on public.endurance_records;
create policy endurance_records_select_profile
  on public.endurance_records
  as permissive
  for select
  to authenticated
  using (true);

drop policy if exists sport_records_select_profile on public.sport_records;
create policy sport_records_select_profile
  on public.sport_records
  as permissive
  for select
  to authenticated
  using (true);

create or replace function public.get_user_prs(
  p_user_id uuid,
  p_kind text default null,
  p_search text default null
)
returns table (
  kind text,
  user_id uuid,
  label text,
  metric text,
  value double precision,
  achieved_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_kind text;
  v_search text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22023';
  end if;

  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  v_search := nullif(btrim(coalesce(p_search, '')), '');

  return query
  select
    v.kind,
    v.user_id,
    v.label,
    v.metric,
    v.value,
    v.achieved_at
  from public.vw_user_prs v
  where v.user_id = p_user_id
    and (v_kind is null or v.kind = v_kind)
    and (
      v_search is null
      or v.label ilike '%' || v_search || '%'
      or v.metric ilike '%' || v_search || '%'
    )
  order by v.achieved_at desc nulls last;
end;
$$;

revoke all on function public.get_user_prs(uuid, text, text) from public;
grant execute on function public.get_user_prs(uuid, text, text) to authenticated;

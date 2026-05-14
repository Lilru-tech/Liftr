create table if not exists public.body_weight_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  measured_at timestamptz not null,
  weight_kg numeric not null check (weight_kg > 0),
  source text not null check (source in ('manual', 'apple_health', 'health_connect')),
  external_sample_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists body_weight_entries_user_source_external_uidx
  on public.body_weight_entries (user_id, source, external_sample_id)
  where external_sample_id is not null;

create index if not exists body_weight_entries_user_measured_at_idx
  on public.body_weight_entries (user_id, measured_at desc);

alter table public.body_weight_entries enable row level security;

drop policy if exists body_weight_entries_select_own on public.body_weight_entries;
create policy body_weight_entries_select_own
  on public.body_weight_entries
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists body_weight_entries_insert_own on public.body_weight_entries;
create policy body_weight_entries_insert_own
  on public.body_weight_entries
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists body_weight_entries_update_own on public.body_weight_entries;
create policy body_weight_entries_update_own
  on public.body_weight_entries
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists body_weight_entries_delete_own on public.body_weight_entries;
create policy body_weight_entries_delete_own
  on public.body_weight_entries
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.refresh_profile_weight_kg(p_user_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_weight numeric;
begin
  select b.weight_kg
  into v_weight
  from public.body_weight_entries b
  where b.user_id = p_user_id
  order by b.measured_at desc, b.created_at desc
  limit 1;

  update public.profiles p
  set
    weight_kg = v_weight,
    updated_at = now()
  where p.user_id = p_user_id;
end;
$$;

create or replace function public.upsert_body_weight_entry(
  p_measured_at timestamptz,
  p_weight_kg numeric,
  p_source text,
  p_external_sample_id text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_entry_id uuid;
  v_inserted boolean := false;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  if p_weight_kg is null or p_weight_kg <= 0 then
    raise exception 'weight_kg must be positive';
  end if;

  if p_source not in ('manual', 'apple_health', 'health_connect') then
    raise exception 'invalid source';
  end if;

  if p_external_sample_id is not null and btrim(p_external_sample_id) <> '' then
    select b.id
    into v_entry_id
    from public.body_weight_entries b
    where b.user_id = v_user_id
      and b.source = p_source
      and b.external_sample_id = p_external_sample_id
    limit 1;

    if v_entry_id is not null then
      return jsonb_build_object(
        'entry_id', v_entry_id,
        'inserted', false,
        'duplicate', true
      );
    end if;
  end if;

  insert into public.body_weight_entries (
    user_id,
    measured_at,
    weight_kg,
    source,
    external_sample_id
  )
  values (
    v_user_id,
    coalesce(p_measured_at, now()),
    p_weight_kg,
    p_source,
    nullif(btrim(coalesce(p_external_sample_id, '')), '')
  )
  returning id into v_entry_id;

  v_inserted := true;

  perform public.refresh_profile_weight_kg(v_user_id);

  return jsonb_build_object(
    'entry_id', v_entry_id,
    'inserted', v_inserted,
    'duplicate', false
  );
end;
$$;

create or replace function public.touch_body_weight_entry_updated_at()
  returns trigger
  language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists body_weight_entries_set_updated_at on public.body_weight_entries;
create trigger body_weight_entries_set_updated_at
  before update on public.body_weight_entries
  for each row
  execute function public.touch_body_weight_entry_updated_at();

create or replace function public.body_weight_entries_after_change()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_profile_weight_kg(old.user_id);
    return old;
  end if;

  perform public.refresh_profile_weight_kg(new.user_id);
  return new;
end;
$$;

drop trigger if exists body_weight_entries_refresh_profile on public.body_weight_entries;
create trigger body_weight_entries_refresh_profile
  after update or delete on public.body_weight_entries
  for each row
  execute function public.body_weight_entries_after_change();

drop view if exists public.vw_latest_weight;

create view public.vw_latest_weight
with (security_invoker = true)
as
select
  p.user_id,
  coalesce(latest.weight_kg, p.weight_kg)::numeric(6,3) as weight_kg,
  coalesce(latest.measured_at, p.updated_at, now()) as measured_at
from public.profiles p
left join lateral (
  select b.weight_kg, b.measured_at
  from public.body_weight_entries b
  where b.user_id = p.user_id
  order by b.measured_at desc, b.created_at desc
  limit 1
) latest on true;

insert into public.body_weight_entries (user_id, measured_at, weight_kg, source)
select
  p.user_id,
  coalesce(p.updated_at, now()),
  p.weight_kg,
  'manual'
from public.profiles p
where p.weight_kg is not null
  and p.weight_kg > 0
  and not exists (
    select 1
    from public.body_weight_entries b
    where b.user_id = p.user_id
  );

grant execute on function public.upsert_body_weight_entry(timestamptz, numeric, text, text) to authenticated;
grant execute on function public.refresh_profile_weight_kg(uuid) to authenticated;

set local check_function_bodies = off;

create table if not exists public.wearable_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null check (provider in ('garmin', 'fitbit', 'polar')),
  provider_user_id text,
  access_token text,
  refresh_token text,
  token_expires_at timestamptz,
  scopes text,
  status text not null default 'active' check (status in ('active', 'revoked', 'error')),
  connected_at timestamptz not null default now(),
  last_sync_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wearable_connections_user_provider_unique unique (user_id, provider)
);

create index if not exists wearable_connections_provider_user_idx
  on public.wearable_connections (provider, provider_user_id)
  where provider_user_id is not null;

create table if not exists public.external_workout_route_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null check (provider in ('garmin', 'fitbit', 'polar')),
  provider_activity_id text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_sec integer,
  activity_code text,
  route_points jsonb not null default '[]'::jsonb,
  healthkit_workout_uuid text,
  status text not null default 'pending' check (
    status in ('pending', 'applied_healthkit', 'applied_liftr', 'skipped', 'failed')
  ),
  skip_reason text,
  applied_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_workout_route_jobs_user_provider_activity_unique
    unique (user_id, provider, provider_activity_id)
);

create index if not exists external_workout_route_jobs_pending_idx
  on public.external_workout_route_jobs (user_id, status, started_at desc)
  where status = 'pending';

alter table public.wearable_connections enable row level security;
alter table public.external_workout_route_jobs enable row level security;

create policy wearable_connections_select_own
  on public.wearable_connections
  for select
  to authenticated
  using (user_id = auth.uid());

create policy external_workout_route_jobs_select_own
  on public.external_workout_route_jobs
  for select
  to authenticated
  using (user_id = auth.uid());

create policy external_workout_route_jobs_update_own
  on public.external_workout_route_jobs
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke insert, delete, update on public.wearable_connections from authenticated;
grant select on public.wearable_connections to authenticated;
grant select, update on public.external_workout_route_jobs to authenticated;

create or replace function public.apply_external_route_to_cardio_workout(
  p_healthkit_uuid text,
  p_route_geojson text,
  p_provider text default null,
  p_provider_activity_id text default null,
  p_started_at timestamptz default null,
  p_ended_at timestamptz default null,
  p_duration_sec integer default null,
  p_activity_code text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_workout_id bigint;
  v_session_id bigint;
  v_had_route boolean;
  v_route text := nullif(btrim(p_route_geojson), '');
begin
  if v_auth_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if v_route is null then
    raise exception 'route_geojson required' using errcode = '22023';
  end if;

  v_workout_id := public.find_cardio_workout_duplicate(
    v_auth_uid,
    p_activity_code,
    p_started_at,
    p_ended_at,
    p_duration_sec,
    p_healthkit_uuid
  );

  if v_workout_id is null then
    return null;
  end if;

  update public.workouts w
  set healthkit_uuid = coalesce(w.healthkit_uuid, nullif(btrim(p_healthkit_uuid), ''))
  where w.id = v_workout_id
    and w.user_id = v_auth_uid;

  select cs.id,
         nullif(btrim(coalesce(cs.route_geojson, '')), '') is not null
  into v_session_id, v_had_route
  from public.cardio_sessions cs
  where cs.workout_id = v_workout_id
  limit 1;

  if v_session_id is null then
    return v_workout_id;
  end if;

  if v_had_route then
    return v_workout_id;
  end if;

  update public.cardio_sessions cs
  set route_geojson = v_route
  where cs.id = v_session_id
    and nullif(btrim(coalesce(cs.route_geojson, '')), '') is null;

  return v_workout_id;
end;
$$;

revoke all on function public.apply_external_route_to_cardio_workout(
  text, text, text, text, timestamptz, timestamptz, integer, text
) from public;
grant execute on function public.apply_external_route_to_cardio_workout(
  text, text, text, text, timestamptz, timestamptz, integer, text
) to authenticated;

create or replace function public.update_external_route_job_status(
  p_job_id uuid,
  p_status text,
  p_skip_reason text default null,
  p_healthkit_workout_uuid text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
begin
  if v_auth_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_status not in ('pending', 'applied_healthkit', 'applied_liftr', 'skipped', 'failed') then
    raise exception 'invalid status' using errcode = '22023';
  end if;

  update public.external_workout_route_jobs j
  set
    status = p_status,
    skip_reason = nullif(btrim(p_skip_reason), ''),
    healthkit_workout_uuid = coalesce(
      nullif(btrim(p_healthkit_workout_uuid), ''),
      j.healthkit_workout_uuid
    ),
    applied_at = case
      when p_status in ('applied_healthkit', 'applied_liftr', 'skipped') then now()
      else j.applied_at
    end,
    updated_at = now()
  where j.id = p_job_id
    and j.user_id = v_auth_uid;
end;
$$;

revoke all on function public.update_external_route_job_status(uuid, text, text, text) from public;
grant execute on function public.update_external_route_job_status(uuid, text, text, text) to authenticated;

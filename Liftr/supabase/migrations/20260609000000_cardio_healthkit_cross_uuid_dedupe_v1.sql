set local check_function_bodies = off;

create table if not exists public.workout_healthkit_uuid_aliases (
  user_id uuid not null references auth.users (id) on delete cascade,
  healthkit_uuid text not null,
  workout_id bigint not null references public.workouts (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint workout_healthkit_uuid_aliases_pkey primary key (user_id, healthkit_uuid)
);

create index if not exists workout_healthkit_uuid_aliases_workout_idx
  on public.workout_healthkit_uuid_aliases (workout_id);

alter table public.workout_healthkit_uuid_aliases enable row level security;

create policy workout_healthkit_uuid_aliases_select_own
  on public.workout_healthkit_uuid_aliases
  for select
  to authenticated
  using (user_id = auth.uid());

revoke all on table public.workout_healthkit_uuid_aliases from public;
grant select on table public.workout_healthkit_uuid_aliases to authenticated;

create or replace function public.find_cardio_workout_duplicate(
  p_user_id uuid,
  p_activity_code text,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_duration_sec integer,
  p_healthkit_uuid text
)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_workout_id bigint;
  v_incoming_duration integer;
  v_healthkit_uuid text := nullif(btrim(p_healthkit_uuid), '');
begin
  if p_user_id is null or p_started_at is null then
    return null;
  end if;

  if v_healthkit_uuid is not null then
    select w.id
    into v_workout_id
    from public.workouts w
    where w.user_id = p_user_id
      and w.kind = 'cardio'
      and w.healthkit_uuid = v_healthkit_uuid
    limit 1;

    if v_workout_id is not null then
      return v_workout_id;
    end if;

    select a.workout_id
    into v_workout_id
    from public.workout_healthkit_uuid_aliases a
    where a.user_id = p_user_id
      and a.healthkit_uuid = v_healthkit_uuid
    limit 1;

    if v_workout_id is not null then
      return v_workout_id;
    end if;
  end if;

  v_incoming_duration := public.cardio_workout_effective_duration_sec(
    p_started_at,
    p_ended_at,
    p_duration_sec
  );

  if v_incoming_duration is null then
    return null;
  end if;

  select w.id
  into v_workout_id
  from public.workouts w
  join public.cardio_sessions cs on cs.workout_id = w.id
  where w.user_id = p_user_id
    and w.kind = 'cardio'
    and public.cardio_activity_codes_compatible(cs.activity_code, p_activity_code)
    and w.started_at is not null
    and abs(extract(epoch from (w.started_at - p_started_at))) <= 300
    and public.cardio_duration_sec_close(
      public.cardio_workout_effective_duration_sec(w.started_at, w.ended_at, cs.duration_sec),
      v_incoming_duration
    )
  order by
    case when w.healthkit_uuid is null then 0 else 1 end,
    abs(extract(epoch from (w.started_at - p_started_at)))
  limit 1;

  return v_workout_id;
end;
$$;

create or replace function public.merge_cardio_workout_from_import(
  p_workout_id bigint,
  p jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid := auth.uid();
  v_user_id uuid;
  v_activity_code text := nullif(p->>'p_activity_code', '');
  v_title text := nullif(p->>'p_title', '');
  v_started_at timestamptz := nullif(p->>'p_started_at', '')::timestamptz;
  v_ended_at timestamptz := nullif(p->>'p_ended_at', '')::timestamptz;
  v_notes text := nullif(p->>'p_notes', '');
  v_distance_km numeric := nullif(p->>'p_distance_km', '')::numeric;
  v_duration_sec integer := nullif(p->>'p_duration_sec', '')::integer;
  v_avg_hr integer := nullif(p->>'p_avg_hr', '')::integer;
  v_max_hr integer := nullif(p->>'p_max_hr', '')::integer;
  v_avg_pace_sec_per_km integer := nullif(p->>'p_avg_pace_sec_per_km', '')::integer;
  v_elevation_gain_m integer := nullif(p->>'p_elevation_gain_m', '')::integer;
  v_stats jsonb := coalesce(p->'p_stats', '{}'::jsonb);
  v_healthkit_uuid text := nullif(p->>'p_healthkit_uuid', '');
  v_route_geojson text := nullif(p->>'p_route_geojson', '');
  v_calories_kcal numeric := nullif(p->>'p_calories_kcal', '')::numeric;
  v_calories_method text := nullif(p->>'p_calories_method', '');
  v_session_id bigint;
  v_existing_stats jsonb;
  v_merged_stats jsonb;
  v_had_route boolean;
  v_existing_healthkit_uuid text;
begin
  if v_auth_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select w.user_id, w.healthkit_uuid
  into v_user_id, v_existing_healthkit_uuid
  from public.workouts w
  where w.id = p_workout_id
    and w.kind = 'cardio';

  if v_user_id is null then
    raise exception 'workout not found' using errcode = 'P0002';
  end if;

  if v_user_id is distinct from v_auth_uid then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  update public.workouts w
  set
    healthkit_uuid = coalesce(w.healthkit_uuid, v_healthkit_uuid),
    ended_at = coalesce(w.ended_at, v_ended_at),
    title = case
      when nullif(btrim(coalesce(w.title, '')), '') is null then v_title
      else w.title
    end,
    notes = case
      when nullif(btrim(coalesce(w.notes, '')), '') is null then v_notes
      else w.notes
    end
  where w.id = p_workout_id;

  if v_healthkit_uuid is not null then
    select w.healthkit_uuid
    into v_existing_healthkit_uuid
    from public.workouts w
    where w.id = p_workout_id;

    if v_existing_healthkit_uuid is not null
       and v_existing_healthkit_uuid <> v_healthkit_uuid then
      insert into public.workout_healthkit_uuid_aliases (user_id, healthkit_uuid, workout_id)
      values (v_user_id, v_healthkit_uuid, p_workout_id)
      on conflict (user_id, healthkit_uuid) do nothing;
    end if;
  end if;

  select cs.id,
         nullif(btrim(coalesce(cs.route_geojson, '')), '') is not null
  into v_session_id, v_had_route
  from public.cardio_sessions cs
  where cs.workout_id = p_workout_id
  limit 1;

  if v_session_id is null then
    insert into public.cardio_sessions(
      workout_id, modality, activity_code, distance_km, duration_sec, avg_hr, max_hr,
      avg_pace_sec_per_km, elevation_gain_m, notes, route_geojson
    )
    values (
      p_workout_id,
      'cardio',
      v_activity_code,
      v_distance_km, v_duration_sec, v_avg_hr, v_max_hr,
      v_avg_pace_sec_per_km, v_elevation_gain_m, v_notes, v_route_geojson
    )
    returning id into v_session_id;
    v_had_route := false;
  else
    update public.cardio_sessions cs
    set
      distance_km = coalesce(cs.distance_km, v_distance_km),
      duration_sec = coalesce(nullif(cs.duration_sec, 0), v_duration_sec),
      avg_hr = coalesce(cs.avg_hr, v_avg_hr),
      max_hr = coalesce(cs.max_hr, v_max_hr),
      avg_pace_sec_per_km = coalesce(cs.avg_pace_sec_per_km, v_avg_pace_sec_per_km),
      elevation_gain_m = coalesce(cs.elevation_gain_m, v_elevation_gain_m),
      route_geojson = case
        when nullif(btrim(coalesce(cs.route_geojson, '')), '') is null then v_route_geojson
        else cs.route_geojson
      end
    where cs.id = v_session_id;
  end if;

  if v_stats is not null and v_stats <> '{}'::jsonb then
    select css.stats
    into v_existing_stats
    from public.cardio_session_stats css
    where css.session_id = v_session_id;

    v_merged_stats := coalesce(v_existing_stats, '{}'::jsonb) || v_stats;

    insert into public.cardio_session_stats(session_id, stats)
    values (v_session_id, v_merged_stats)
    on conflict (session_id) do update
      set stats = excluded.stats;
  end if;

  if v_calories_method = 'healthkit_active_energy'
     and v_calories_kcal is not null
     and v_calories_kcal > 0 then
    update public.workouts w
    set calories_kcal = round(v_calories_kcal, 1),
        calories_method = 'healthkit_active_energy',
        calories_weight_kg = null,
        calories_updated_at = now()
    where w.id = p_workout_id
      and (
        w.calories_kcal is null
        or coalesce(w.calories_method, '') <> 'healthkit_active_energy'
      );
  else
    perform public.recalc_workout_calories(p_workout_id);
  end if;

  perform public.competition_attach_workout(p_workout_id);

  return p_workout_id;
end;
$$;

revoke all on function public.find_cardio_workout_duplicate(uuid, text, timestamptz, timestamptz, integer, text) from public;
revoke all on function public.merge_cardio_workout_from_import(bigint, jsonb) from public;
grant execute on function public.find_cardio_workout_duplicate(uuid, text, timestamptz, timestamptz, integer, text) to authenticated;
grant execute on function public.merge_cardio_workout_from_import(bigint, jsonb) to authenticated;

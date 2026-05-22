set local check_function_bodies = off;

create unique index if not exists workouts_user_healthkit_uuid_unique
  on public.workouts (user_id, healthkit_uuid)
  where healthkit_uuid is not null;

create or replace function public.cardio_activity_codes_compatible(
  p_a text,
  p_b text
)
returns boolean
language sql
immutable
as $$
  select
    p_a is not null
    and p_b is not null
    and (
      p_a = p_b
      or (p_a = 'run' and p_b = 'treadmill')
      or (p_a = 'treadmill' and p_b = 'run')
      or (p_a = 'walk' and p_b = 'treadmill')
      or (p_a = 'treadmill' and p_b = 'walk')
    );
$$;

create or replace function public.cardio_duration_sec_close(
  p_existing_sec integer,
  p_incoming_sec integer
)
returns boolean
language sql
immutable
as $$
  select
    p_existing_sec is not null
    and p_incoming_sec is not null
    and p_existing_sec > 0
    and p_incoming_sec > 0
    and abs(p_existing_sec - p_incoming_sec)
      <= greatest(90, (0.1 * greatest(p_existing_sec::numeric, p_incoming_sec::numeric))::integer);
$$;

create or replace function public.cardio_workout_effective_duration_sec(
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_session_duration_sec integer
)
returns integer
language sql
stable
as $$
  select coalesce(
    case
      when p_started_at is not null and p_ended_at is not null then
        greatest(1, floor(extract(epoch from (p_ended_at - p_started_at)))::integer)
      else null
    end,
    nullif(p_session_duration_sec, 0)
  );
$$;

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
begin
  if p_user_id is null or p_started_at is null then
    return null;
  end if;

  if nullif(btrim(p_healthkit_uuid), '') is not null then
    select w.id
    into v_workout_id
    from public.workouts w
    where w.user_id = p_user_id
      and w.kind = 'cardio'
      and w.healthkit_uuid = nullif(btrim(p_healthkit_uuid), '')
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
    and (
      nullif(btrim(p_healthkit_uuid), '') is null
      or w.healthkit_uuid is null
      or w.healthkit_uuid = nullif(btrim(p_healthkit_uuid), '')
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
begin
  if v_auth_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select w.user_id
  into v_user_id
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

create or replace function public.create_cardio_workout_v2(p jsonb)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid := nullif(p->>'p_user_id', '')::uuid;
  v_auth_uid uuid := auth.uid();
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
  v_perceived_intensity text := nullif(p->>'p_perceived_intensity', '');
  v_state workout_state := nullif(p->>'p_state', '')::workout_state;
  v_stats jsonb := coalesce(p->'p_stats', '{}'::jsonb);
  v_healthkit_uuid text := nullif(p->>'p_healthkit_uuid', '');
  v_route_geojson text := nullif(p->>'p_route_geojson', '');
  v_calories_kcal numeric := nullif(p->>'p_calories_kcal', '')::numeric;
  v_calories_method text := nullif(p->>'p_calories_method', '');
  v_workout_id bigint;
  v_session_id bigint;
  v_duplicate_id bigint;
begin
  if v_auth_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if v_user_id is null then
    v_user_id := v_auth_uid;
  elsif v_user_id is distinct from v_auth_uid then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  v_duplicate_id := public.find_cardio_workout_duplicate(
    v_user_id,
    v_activity_code,
    v_started_at,
    v_ended_at,
    v_duration_sec,
    v_healthkit_uuid
  );

  if v_duplicate_id is not null then
    perform public.merge_cardio_workout_from_import(v_duplicate_id, p);
    return v_duplicate_id::integer;
  end if;

  insert into public.workouts
    (user_id, title, started_at, ended_at, notes, perceived_intensity, state, kind, healthkit_uuid)
  values
    (v_user_id, v_title, v_started_at, v_ended_at, v_notes, v_perceived_intensity, coalesce(v_state, 'published'::public.workout_state), 'cardio', v_healthkit_uuid)
  returning id into v_workout_id;

  insert into public.cardio_sessions(
    workout_id, modality, activity_code, distance_km, duration_sec, avg_hr, max_hr,
    avg_pace_sec_per_km, elevation_gain_m, notes, route_geojson
  )
  values (
    v_workout_id,
    'cardio',
    v_activity_code,
    v_distance_km, v_duration_sec, v_avg_hr, v_max_hr,
    v_avg_pace_sec_per_km, v_elevation_gain_m, v_notes, v_route_geojson
  )
  returning id into v_session_id;

  if v_stats is not null and v_stats <> '{}'::jsonb then
    insert into public.cardio_session_stats(session_id, stats)
    values (v_session_id, v_stats);
  end if;

  if v_calories_method = 'healthkit_active_energy' and v_calories_kcal is not null and v_calories_kcal > 0 then
    update public.workouts
    set calories_kcal = round(v_calories_kcal, 1),
        calories_method = 'healthkit_active_energy',
        calories_weight_kg = null,
        calories_updated_at = now()
    where id = v_workout_id;
  else
    perform public.recalc_workout_calories(v_workout_id);
  end if;

  perform public.competition_attach_workout(v_workout_id);

  return v_workout_id::integer;
end;
$function$;

revoke all on function public.cardio_activity_codes_compatible(text, text) from public;
revoke all on function public.cardio_duration_sec_close(integer, integer) from public;
revoke all on function public.cardio_workout_effective_duration_sec(timestamptz, timestamptz, integer) from public;
revoke all on function public.find_cardio_workout_duplicate(uuid, text, timestamptz, timestamptz, integer, text) from public;
revoke all on function public.merge_cardio_workout_from_import(bigint, jsonb) from public;

grant execute on function public.find_cardio_workout_duplicate(uuid, text, timestamptz, timestamptz, integer, text) to authenticated;
grant execute on function public.merge_cardio_workout_from_import(bigint, jsonb) to authenticated;

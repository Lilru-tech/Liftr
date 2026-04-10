-- 1) Columna en workouts: deduplicar imports de Apple Health (HealthKit workout UUID).
--    NULL permitido; en PostgreSQL UNIQUE permite varias filas con NULL (no chocan).
alter table public.workouts
  add column if not exists healthkit_uuid text;

-- Índice único solo donde hay valor (evita duplicar el mismo entreno de Apple).
create unique index if not exists workouts_healthkit_uuid_unique
  on public.workouts (healthkit_uuid)
  where healthkit_uuid is not null;

comment on column public.workouts.healthkit_uuid is
  'UUID string del HKWorkout en Apple Health; importaciones desde Salud.';

-- 2) RPC ampliado: mismas claves JSON que antes + opcionales:
--    p_healthkit_uuid (text), p_route_geojson (text, GeoJSON LineString como en la app).
--    Si no van en el JSON, se tratan como NULL y el comportamiento es idéntico al anterior.

create or replace function public.create_cardio_workout_v2(p jsonb)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id              uuid            := nullif(p->>'p_user_id', '')::uuid;
  v_activity_code        text            := nullif(p->>'p_activity_code', '');
  v_title                text            := nullif(p->>'p_title', '');
  v_started_at           timestamptz     := nullif(p->>'p_started_at', '')::timestamptz;
  v_ended_at             timestamptz     := nullif(p->>'p_ended_at', '')::timestamptz;
  v_notes                text            := nullif(p->>'p_notes', '');
  v_distance_km          numeric         := nullif(p->>'p_distance_km', '')::numeric;
  v_duration_sec         integer         := nullif(p->>'p_duration_sec', '')::integer;
  v_avg_hr               integer         := nullif(p->>'p_avg_hr', '')::integer;
  v_max_hr               integer         := nullif(p->>'p_max_hr', '')::integer;
  v_avg_pace_sec_per_km  integer         := nullif(p->>'p_avg_pace_sec_per_km', '')::integer;
  v_elevation_gain_m     integer         := nullif(p->>'p_elevation_gain_m', '')::integer;
  v_perceived_intensity  text            := nullif(p->>'p_perceived_intensity', '');
  v_state                workout_state   := nullif(p->>'p_state', '')::workout_state;
  v_stats                jsonb           := coalesce(p->'p_stats', '{}'::jsonb);
  v_healthkit_uuid       text            := nullif(p->>'p_healthkit_uuid', '');
  v_route_geojson        text            := nullif(p->>'p_route_geojson', '');
  v_workout_id           bigint;
  v_session_id           bigint;
begin
  insert into public.workouts
    (user_id, title, started_at, ended_at, notes, perceived_intensity, state, kind, healthkit_uuid)
  values
    (v_user_id, v_title, v_started_at, v_ended_at, v_notes, v_perceived_intensity, v_state, 'cardio', v_healthkit_uuid)
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

  perform public.competition_attach_workout(v_workout_id);

  return v_workout_id;
end;
$function$;

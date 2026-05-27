create or replace function public._liftr_apply_territory_capture_for_workout (
  p_workout_id bigint,
  p_emit_notifications boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  w_user uuid;
  w_captured_at timestamptz;
  activity_code text;
  route_text text;
  route_geog geography;
  capture_geog geography;
  route_kind text;
  cells_gained integer := 0;
  cells_taken integer := 0;
  min_lat double precision;
  min_lon double precision;
  max_lat double precision;
  max_lon double precision;
  existing_event record;
  duration_sec integer;
  max_speed_mps double precision;
begin
  select
    e.*
  into existing_event
  from public.territory_capture_events e
  where e.workout_id = p_workout_id;

  if found then
    return public._liftr_territory_capture_summary_json(
      existing_event.route_kind,
      existing_event.cells_gained,
      existing_event.cells_taken,
      existing_event.bbox_min_lat,
      existing_event.bbox_min_lon,
      existing_event.bbox_max_lat,
      existing_event.bbox_max_lon,
      true
    );
  end if;

  select
    w.user_id,
    coalesce(w.ended_at, w.started_at, now())
  into w_user, w_captured_at
  from public.workouts w
  where w.id = p_workout_id;

  if w_user is null then
    raise exception 'workout_not_found';
  end if;

  select
    coalesce(nullif(trim(cs.activity_code), ''), nullif(trim(cs.modality), ''), '')
  into activity_code
  from public.cardio_sessions cs
  where cs.workout_id = p_workout_id
  order by cs.id nulls last
  limit 1;

  if not public._liftr_territory_outdoor_activity(activity_code) then
    return jsonb_build_object('ok', false, 'reason', 'activity_not_eligible');
  end if;

  route_text := public._liftr_workout_route_geojson_text(p_workout_id);
  route_geog := public._liftr_territory_route_geog_from_geojson(route_text);
  if route_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'missing_route');
  end if;

  if st_length(route_geog) < 500.0 then
    return jsonb_build_object('ok', false, 'reason', 'route_too_short');
  end if;

  select
    coalesce(cs.duration_sec, 0)
  into duration_sec
  from public.cardio_sessions cs
  where cs.workout_id = p_workout_id
  order by cs.id nulls last
  limit 1;

  if duration_sec > 0 then
    max_speed_mps := st_length(route_geog) / duration_sec::double precision;
    if max_speed_mps > 25.0 then
      return jsonb_build_object('ok', false, 'reason', 'speed_unrealistic');
    end if;
  end if;

  capture_geog := public._liftr_territory_capture_geom(route_geog);
  if capture_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'capture_geom_failed');
  end if;

  route_kind := public._liftr_territory_route_kind(route_geog);

  drop table if exists _liftr_capture_cells;
  create temp table _liftr_capture_cells on commit drop as
  select
    c.cell_id,
    c.cell_geog
  from public._liftr_territory_hex_cells_from_geog(capture_geog) c;

  select
    count(*)::integer
  into cells_gained
  from _liftr_capture_cells;

  if cells_gained = 0 then
    return jsonb_build_object('ok', false, 'reason', 'no_cells');
  end if;

  select
    count(*)::integer
  into cells_taken
  from _liftr_capture_cells nc
    join public.territory_cells tc on tc.cell_id = nc.cell_id
  where tc.owner_user_id <> w_user;

  drop table if exists _liftr_victim_takeover;
  create temp table _liftr_victim_takeover on commit drop as
  select
    tc.owner_user_id as victim_user_id,
    count(*)::integer as cells_taken_from_victim,
    (
      select count(*)::integer
      from public.territory_cells all_cells
      where all_cells.owner_user_id = tc.owner_user_id
    ) as victim_total_before
  from _liftr_capture_cells nc
    join public.territory_cells tc on tc.cell_id = nc.cell_id
  where tc.owner_user_id <> w_user
  group by tc.owner_user_id;

  select
    min(st_ymin(nc.cell_geog::geometry)),
    min(st_xmin(nc.cell_geog::geometry)),
    max(st_ymax(nc.cell_geog::geometry)),
    max(st_xmax(nc.cell_geog::geometry))
  into min_lat, min_lon, max_lat, max_lon
  from _liftr_capture_cells nc;

  insert into public.territory_cells (
    cell_id,
    cell_geog,
    owner_user_id,
    captured_at,
    last_workout_id,
    last_activity_code,
    city_key
  )
  select
    nc.cell_id,
    nc.cell_geog,
    w_user,
    w_captured_at,
    p_workout_id,
    activity_code,
    public._liftr_territory_city_key_for_point(
      st_y(st_centroid(nc.cell_geog::geometry)),
      st_x(st_centroid(nc.cell_geog::geometry))
    )
  from _liftr_capture_cells nc
  on conflict (cell_id) do update
    set
      owner_user_id = excluded.owner_user_id,
      captured_at = excluded.captured_at,
      last_workout_id = excluded.last_workout_id,
      last_activity_code = excluded.last_activity_code,
      city_key = excluded.city_key;

  insert into public.territory_capture_events (
    workout_id,
    user_id,
    route_kind,
    cells_gained,
    cells_taken,
    bbox_min_lat,
    bbox_min_lon,
    bbox_max_lat,
    bbox_max_lon,
    applied_at
  )
  values (
    p_workout_id,
    w_user,
    route_kind,
    cells_gained,
    cells_taken,
    min_lat,
    min_lon,
    max_lat,
    max_lon,
    w_captured_at
  );

  insert into public.territory_capture_takeovers (
    workout_id,
    victim_user_id,
    taker_user_id,
    cells_taken,
    victim_total_before,
    share_taken_pct
  )
  select
    p_workout_id,
    vt.victim_user_id,
    w_user,
    vt.cells_taken_from_victim,
    vt.victim_total_before,
    round(100.0 * vt.cells_taken_from_victim::numeric / greatest(vt.victim_total_before, 1), 1)
  from _liftr_victim_takeover vt
  on conflict (workout_id, victim_user_id) do nothing;

  if p_emit_notifications then
    perform public._liftr_emit_territory_takeover_notifications(
      p_workout_id,
      w_user,
      min_lat,
      min_lon,
      max_lat,
      max_lon
    );
  end if;

  return public._liftr_territory_capture_summary_json(
    route_kind,
    cells_gained,
    cells_taken,
    min_lat,
    min_lon,
    max_lat,
    max_lon,
    false
  );
end;
$$;

do $$
declare
  batch_processed integer := 1;
  total_processed integer := 0;
begin
  while batch_processed > 0 and total_processed < 10000 loop
    select public._liftr_backfill_territory_captures_global_batch(25)
    into batch_processed;
    total_processed := total_processed + batch_processed;
  end loop;
end;
$$;

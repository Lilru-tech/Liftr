alter table public.territory_capture_events
  add column if not exists cells_net_new integer not null default 0;

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
  cells_already_owned integer := 0;
  cells_net_new integer := 0;
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

  select
    count(*)::integer
  into cells_already_owned
  from _liftr_capture_cells nc
    join public.territory_cells tc on tc.cell_id = nc.cell_id
  where tc.owner_user_id = w_user;

  cells_net_new := greatest(cells_gained - cells_already_owned, 0);

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
    cells_net_new,
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
    cells_net_new,
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

create or replace function public._liftr_backfill_territory_cells_net_new_v1 ()
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  r record;
  route_text text;
  route_geog geography;
  capture_geog geography;
  cells_gained integer;
  cells_already_owned integer;
  v_cells_net_new integer;
  updated_count integer := 0;
begin
  create temp table _liftr_sim_cell_owner (
    cell_id text primary key,
    owner_user_id uuid not null
  ) on commit drop;

  truncate _liftr_sim_cell_owner;

  for r in
    select
      e.workout_id,
      e.user_id,
      e.cells_gained
    from public.territory_capture_events e
    order by e.applied_at asc, e.id asc
  loop
    route_text := public._liftr_workout_route_geojson_text(r.workout_id);
    route_geog := public._liftr_territory_route_geog_from_geojson(route_text);
    if route_geog is null then
      update public.territory_capture_events e
      set cells_net_new = greatest(e.cells_gained - e.cells_taken, 0)
      where e.workout_id = r.workout_id;
      updated_count := updated_count + 1;
      continue;
    end if;

    capture_geog := public._liftr_territory_capture_geom(route_geog);
    if capture_geog is null then
      update public.territory_capture_events e
      set cells_net_new = greatest(e.cells_gained - e.cells_taken, 0)
      where e.workout_id = r.workout_id;
      updated_count := updated_count + 1;
      continue;
    end if;

    drop table if exists _liftr_capture_cells;
    create temp table _liftr_capture_cells on commit drop as
    select
      c.cell_id,
      c.cell_geog
    from public._liftr_territory_hex_cells_from_geog(capture_geog) c;

    select count(*)::integer into cells_gained from _liftr_capture_cells;

    select count(*)::integer
    into cells_already_owned
    from _liftr_capture_cells nc
      join _liftr_sim_cell_owner s on s.cell_id = nc.cell_id
    where s.owner_user_id = r.user_id;

    v_cells_net_new := greatest(coalesce(cells_gained, r.cells_gained) - cells_already_owned, 0);

    update public.territory_capture_events e
    set cells_net_new = v_cells_net_new
    where e.workout_id = r.workout_id;

    insert into _liftr_sim_cell_owner (cell_id, owner_user_id)
    select nc.cell_id, r.user_id
    from _liftr_capture_cells nc
    on conflict (cell_id) do update
      set owner_user_id = excluded.owner_user_id;

    updated_count := updated_count + 1;
  end loop;

  return updated_count;
end;
$$;

select public._liftr_backfill_territory_cells_net_new_v1 ();

create or replace function public.get_territory_summary_v1 (
  p_user_id uuid default auth.uid()
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path = public
as $$
  with target as (
    select coalesce(p_user_id, auth.uid()) as user_id
  ),
  mine as (
    select count(*)::integer as total_cells
    from public.territory_cells tc
      join target t on tc.owner_user_id = t.user_id
  ),
  week as (
    select
      coalesce(sum(e.cells_net_new), 0)::integer as cells_gained_last_7d,
      count(*)::integer as capture_workouts_last_7d
    from public.territory_capture_events e
      join target t on e.user_id = t.user_id
    where e.applied_at >= now() - interval '7 days'
  )
  select jsonb_build_object(
    'total_cells', (select total_cells from mine),
    'cells_gained_last_7d', (select cells_gained_last_7d from week),
    'capture_workouts_last_7d', (select capture_workouts_last_7d from week),
    'cells_last_7d', (select capture_workouts_last_7d from week),
    'approx_area_m2', (select total_cells from mine) * 1623.8
  );
$$;

create or replace function public.get_my_territory_summary_v1 ()
  returns jsonb
  language sql
  stable
  security definer
  set search_path = public
as $$
  with mine as (
    select
      count(*)::integer as total_cells
    from public.territory_cells tc
    where tc.owner_user_id = auth.uid ()
  ),
  recent as (
    select
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'workout_id', e.workout_id,
            'route_kind', e.route_kind,
            'cells_gained', e.cells_gained,
            'cells_taken', e.cells_taken,
            'cells_net_new', e.cells_net_new,
            'applied_at', e.applied_at
          )
          order by e.applied_at desc
        ),
        '[]'::jsonb
      ) as events
    from (
      select
        *
      from public.territory_capture_events e
      where e.user_id = auth.uid ()
      order by e.applied_at desc
      limit 10
    ) e
  ),
  week as (
    select
      coalesce(sum(e.cells_net_new), 0)::integer as cells_gained_last_7d,
      count(*)::integer as capture_workouts_last_7d
    from public.territory_capture_events e
    where
      e.user_id = auth.uid ()
      and e.applied_at >= now() - interval '7 days'
  )
  select jsonb_build_object(
    'total_cells', (select total_cells from mine),
    'cells_gained_last_7d', (select cells_gained_last_7d from week),
    'capture_workouts_last_7d', (select capture_workouts_last_7d from week),
    'cells_last_7d', (select capture_workouts_last_7d from week),
    'approx_area_m2', (select total_cells from mine) * 1623.8,
    'recent_events', (select events from recent)
  );
$$;

update public.territory_municipalities m
set
  total_capture_cells = public._liftr_territory_count_hex_cells_for_geog(m.boundary_geom),
  updated_at = now()
where
  m.boundary_geom is not null
  and (
    m.total_capture_cells is null
    or m.total_capture_cells < 100
  );

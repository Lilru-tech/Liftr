drop function if exists public._liftr_territory_capture_geom(geography, double precision, double precision, double precision);
drop function if exists public._liftr_territory_route_kind(geography, double precision, double precision);

create or replace function public._liftr_territory_start_end_loop_polygon (
  p_route geography,
  p_loop_close_m double precision default 50.0,
  p_min_loop_area_m2 double precision default 5000.0
)
  returns geometry
  language plpgsql
  stable
  set search_path = public
as $$
declare
  start_end_m double precision;
  g_line geometry;
  g_poly geometry;
  area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return null;
  end if;

  g_line := st_force2d(p_route::geometry);
  start_end_m := st_distance(
    st_startpoint(g_line)::geography,
    st_endpoint(g_line)::geography
  );

  if start_end_m > p_loop_close_m then
    return null;
  end if;

  if not st_isclosed(g_line) then
    g_line := st_addpoint(g_line, st_startpoint(g_line));
  end if;

  begin
    g_poly := st_makevalid(st_makepolygon(g_line));
  exception
    when others then
      return null;
  end;

  if g_poly is null or st_isempty(g_poly) then
    return null;
  end if;

  area_m2 := st_area(g_poly::geography);
  if area_m2 is null or area_m2 < p_min_loop_area_m2 then
    return null;
  end if;

  return g_poly;
end;
$$;

create or replace function public._liftr_territory_polygonize_loop_faces (
  p_route geography,
  p_min_loop_area_m2 double precision default 5000.0,
  p_snap_m double precision default 12.0,
  p_max_loops integer default 20
)
  returns geometry
  language plpgsql
  stable
  set search_path = public
as $$
declare
  g_line geometry;
  g_3857 geometry;
  noded geometry;
  snapped geometry;
  poly_collection geometry;
  face record;
  face_4326 geometry;
  faces geometry[] := '{}';
  face_count integer := 0;
  area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return null;
  end if;

  g_line := st_force2d(p_route::geometry);
  if st_geometrytype(g_line) not in ('ST_LineString', 'ST_MultiLineString') then
    return null;
  end if;

  if st_geometrytype(g_line) = 'ST_MultiLineString' then
    g_line := st_linemerge(g_line);
  end if;

  if g_line is null or st_isempty(g_line) or st_geometrytype(g_line) <> 'ST_LineString' then
    return null;
  end if;

  g_3857 := st_transform(g_line, 3857);

  begin
    noded := st_node(g_3857);
    snapped := st_snap(g_3857, noded, greatest(p_snap_m, 1.0));
    noded := st_node(snapped);
  exception
    when others then
      return null;
  end;

  begin
    poly_collection := st_polygonize(noded);
  exception
    when others then
      return null;
  end;

  if poly_collection is null or st_isempty(poly_collection) then
    return null;
  end if;

  for face in
    select (st_dump(poly_collection)).geom as geom
  loop
    if face.geom is null or st_isempty(face.geom) then
      continue;
    end if;

    face_4326 := st_transform(st_makevalid(face.geom), 4326);
    area_m2 := st_area(face_4326::geography);
    if area_m2 is null or area_m2 < p_min_loop_area_m2 then
      continue;
    end if;

    face_count := face_count + 1;
    if face_count > greatest(p_max_loops, 1) then
      exit;
    end if;

    faces := array_append(faces, face_4326);
  end loop;

  if face_count = 0 then
    return null;
  end if;

  return st_collect(faces);
end;
$$;

create or replace function public._liftr_territory_capture_geom (
  p_route geography,
  p_edge_m double precision default 25.0,
  p_loop_close_m double precision default 50.0,
  p_min_loop_area_m2 double precision default 5000.0,
  p_snap_m double precision default 12.0,
  p_max_capture_area_m2 double precision default 2000000.0,
  p_max_loops integer default 20
)
  returns geography
  language plpgsql
  stable
  set search_path = public
as $$
declare
  route_len double precision;
  corridor_geog geography;
  loop_faces_geom geometry;
  start_end_poly geometry;
  parts geometry[] := '{}';
  merged_geom geometry;
  merged_geog geography;
  capture_area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return null;
  end if;

  route_len := st_length(p_route);
  if route_len is null or route_len < 500.0 then
    return null;
  end if;

  corridor_geog := st_buffer(p_route, greatest(p_edge_m / 2.0, 1.0));
  parts := array_append(parts, corridor_geog::geometry);

  loop_faces_geom := public._liftr_territory_polygonize_loop_faces(
    p_route,
    p_min_loop_area_m2,
    p_snap_m,
    p_max_loops
  );
  if loop_faces_geom is not null and not st_isempty(loop_faces_geom) then
    parts := array_append(parts, loop_faces_geom);
  end if;

  start_end_poly := public._liftr_territory_start_end_loop_polygon(
    p_route,
    p_loop_close_m,
    p_min_loop_area_m2
  );
  if start_end_poly is not null and not st_isempty(start_end_poly) then
    parts := array_append(parts, start_end_poly);
  end if;

  begin
    merged_geom := st_unaryunion(st_collect(parts));
  exception
    when others then
      merged_geom := st_collect(parts);
  end;

  if merged_geom is null or st_isempty(merged_geom) then
    return corridor_geog;
  end if;

  begin
    merged_geog := st_makevalid(merged_geom)::geography;
  exception
    when others then
      return corridor_geog;
  end;
  capture_area_m2 := st_area(merged_geog);
  if capture_area_m2 is not null and capture_area_m2 > p_max_capture_area_m2 then
    return corridor_geog;
  end if;

  return merged_geog;
end;
$$;

create or replace function public._liftr_territory_route_kind (
  p_route geography,
  p_loop_close_m double precision default 50.0,
  p_min_loop_area_m2 double precision default 5000.0,
  p_snap_m double precision default 12.0,
  p_max_loops integer default 20
)
  returns text
  language plpgsql
  stable
  set search_path = public
as $$
declare
  loop_faces_geom geometry;
  start_end_poly geometry;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return 'open';
  end if;

  start_end_poly := public._liftr_territory_start_end_loop_polygon(
    p_route,
    p_loop_close_m,
    p_min_loop_area_m2
  );
  if start_end_poly is not null then
    return 'closed';
  end if;

  loop_faces_geom := public._liftr_territory_polygonize_loop_faces(
    p_route,
    p_min_loop_area_m2,
    p_snap_m,
    p_max_loops
  );
  if loop_faces_geom is not null and not st_isempty(loop_faces_geom) then
    return 'closed';
  end if;

  return 'open';
end;
$$;

create or replace function public._liftr_reexpand_territory_capture_for_workout (
  p_workout_id bigint
)
  returns boolean
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
  v_route_kind text;
  v_cells_gained integer := 0;
  v_cells_taken integer := 0;
  v_cells_already_owned integer := 0;
  v_cells_net_new integer := 0;
  v_min_lat double precision;
  v_min_lon double precision;
  v_max_lat double precision;
  v_max_lon double precision;
  existing_event record;
begin
  select
    e.*
  into existing_event
  from public.territory_capture_events e
  where e.workout_id = p_workout_id;

  if not found then
    return false;
  end if;

  select
    w.user_id,
    coalesce(w.ended_at, w.started_at, existing_event.applied_at, now())
  into w_user, w_captured_at
  from public.workouts w
  where w.id = p_workout_id;

  if w_user is null or w_user <> existing_event.user_id then
    return false;
  end if;

  select
    coalesce(nullif(trim(cs.activity_code), ''), nullif(trim(cs.modality), ''), '')
  into activity_code
  from public.cardio_sessions cs
  where cs.workout_id = p_workout_id
  order by cs.id nulls last
  limit 1;

  route_text := public._liftr_workout_route_geojson_text(p_workout_id);
  route_geog := public._liftr_territory_route_geog_from_geojson(route_text);
  if route_geog is null then
    return false;
  end if;

  if st_length(route_geog) < 500.0 then
    return false;
  end if;

  begin
    capture_geog := public._liftr_territory_capture_geom(route_geog);
    v_route_kind := public._liftr_territory_route_kind(route_geog);
  exception
    when others then
      return false;
  end;

  if capture_geog is null then
    return false;
  end if;

  drop table if exists _liftr_capture_cells;
  create temp table _liftr_capture_cells on commit drop as
  select
    c.cell_id,
    c.cell_geog
  from public._liftr_territory_hex_cells_from_geog(capture_geog) c;

  select count(*)::integer into v_cells_gained from _liftr_capture_cells;
  if v_cells_gained = 0 then
    return false;
  end if;

  select count(*)::integer
  into v_cells_taken
  from _liftr_capture_cells nc
    join public.territory_cells tc on tc.cell_id = nc.cell_id
  where tc.owner_user_id <> w_user;

  select count(*)::integer
  into v_cells_already_owned
  from _liftr_capture_cells nc
    join public.territory_cells tc on tc.cell_id = nc.cell_id
  where tc.owner_user_id = w_user;

  v_cells_net_new := greatest(v_cells_gained - v_cells_already_owned, 0);

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
  into v_min_lat, v_min_lon, v_max_lat, v_max_lon
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

  delete from public.territory_capture_takeovers
  where workout_id = p_workout_id;

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
  on conflict (workout_id, victim_user_id) do update
    set
      cells_taken = excluded.cells_taken,
      victim_total_before = excluded.victim_total_before,
      share_taken_pct = excluded.share_taken_pct;

  update public.territory_capture_events e
  set
    route_kind = v_route_kind,
    cells_gained = v_cells_gained,
    cells_taken = v_cells_taken,
    cells_net_new = v_cells_net_new,
    bbox_min_lat = v_min_lat,
    bbox_min_lon = v_min_lon,
    bbox_max_lat = v_max_lat,
    bbox_max_lon = v_max_lon
  where e.workout_id = p_workout_id;

  return true;
end;
$$;

create or replace function public._liftr_backfill_territory_loop_capture_batch_v1 (
  p_limit integer default 25
)
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  r record;
  processed integer := 0;
begin
  for r in
    with picked as (
      delete from public._liftr_loop_backfill_queue q
      where q.workout_id in (
        select
          q2.workout_id
        from public._liftr_loop_backfill_queue q2
        limit greatest(least(coalesce(p_limit, 25), 500), 1)
      )
      returning q.workout_id
    )
    select
      workout_id
    from picked
  loop
    if public._liftr_reexpand_territory_capture_for_workout(r.workout_id) then
      processed := processed + 1;
    end if;
  end loop;

  return processed;
end;
$$;

create table if not exists public._liftr_loop_backfill_queue (
  workout_id bigint primary key
);

truncate public._liftr_loop_backfill_queue;

insert into public._liftr_loop_backfill_queue (workout_id)
select
  e.workout_id
from public.territory_capture_events e
where public._liftr_workout_route_geojson_text(e.workout_id) is not null;

do $$
declare
  batch_processed integer := 1;
  remaining integer := 0;
begin
  loop
    select count(*)::integer into remaining from public._liftr_loop_backfill_queue;
    exit when remaining = 0;

    select public._liftr_backfill_territory_loop_capture_batch_v1(25)
    into batch_processed;
    exit when batch_processed = 0;
  end loop;
end;
$$;

drop table public._liftr_loop_backfill_queue;

drop function if exists public._liftr_backfill_territory_loop_capture_batch_v1(integer);

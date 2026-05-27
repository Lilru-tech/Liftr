drop function if exists public._liftr_territory_polygonize_loop_faces(geography, double precision, double precision, integer);
drop function if exists public._liftr_territory_polygonize_loop_faces(geography, double precision, double precision, integer, double precision);
drop function if exists public._liftr_territory_start_end_loop_polygon(geography, double precision, double precision);
drop function if exists public._liftr_territory_start_end_loop_polygon(geography, double precision, double precision, double precision);
drop function if exists public._liftr_territory_capture_geom(geography, double precision, double precision, double precision);
drop function if exists public._liftr_territory_capture_geom(geography, double precision, double precision, double precision, double precision, double precision, integer);
drop function if exists public._liftr_territory_route_kind(geography, double precision, double precision);
drop function if exists public._liftr_territory_route_kind(geography, double precision, double precision, double precision, integer);

create or replace function public._liftr_territory_loop_close_m (
  p_route_len double precision
)
  returns double precision
  language sql
  immutable
  set search_path = public
as $$
  select least(250.0, greatest(50.0, coalesce(p_route_len, 0.0) * 0.025));
$$;

create or replace function public._liftr_territory_start_end_loop_polygon (
  p_route geography,
  p_loop_close_m double precision default null,
  p_min_loop_area_m2 double precision default null,
  p_max_interior_area_m2 double precision default 10000000.0
)
  returns geometry
  language plpgsql
  stable
  set search_path = public
as $$
declare
  route_len double precision;
  loop_close_m double precision;
  start_end_m double precision;
  g_line geometry;
  g_poly geometry;
  area_m2 double precision;
  min_area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return null;
  end if;

  route_len := st_length(p_route);
  loop_close_m := coalesce(p_loop_close_m, public._liftr_territory_loop_close_m(route_len));
  min_area_m2 := coalesce(p_min_loop_area_m2, public._liftr_territory_min_loop_area_m2());
  g_line := st_force2d(p_route::geometry);
  start_end_m := st_distance(
    st_startpoint(g_line)::geography,
    st_endpoint(g_line)::geography
  );

  if start_end_m > loop_close_m then
    return null;
  end if;

  if not st_isclosed(g_line) then
    g_line := st_addpoint(g_line, st_startpoint(g_line));
  end if;

  begin
    g_poly := st_makevalid(st_makepolygon(g_line));
  exception
    when others then
      g_poly := null;
  end;

  if (g_poly is null or st_isempty(g_poly)) and route_len >= 3000.0 then
    begin
      g_line := st_transform(g_line, 3857);
      g_line := st_snap(g_line, st_endpoint(g_line), 5.0);
      g_line := st_snap(g_line, st_startpoint(g_line), 5.0);
      g_line := st_transform(g_line, 4326);
      if not st_isclosed(g_line) then
        g_line := st_addpoint(g_line, st_startpoint(g_line));
      end if;
      g_poly := st_makevalid(st_makepolygon(g_line));
    exception
      when others then
        g_poly := null;
    end;
  end if;

  if g_poly is null or st_isempty(g_poly) then
    return null;
  end if;

  area_m2 := st_area(g_poly::geography);
  if area_m2 is null or area_m2 < min_area_m2 or area_m2 > p_max_interior_area_m2 then
    return null;
  end if;

  return g_poly;
end;
$$;

create or replace function public._liftr_territory_polygonize_loop_faces (
  p_route geography,
  p_min_loop_area_m2 double precision default null,
  p_snap_m double precision default 15.0,
  p_max_loops integer default 20,
  p_max_face_area_m2 double precision default 10000000.0
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
  min_area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return null;
  end if;

  min_area_m2 := coalesce(p_min_loop_area_m2, public._liftr_territory_min_loop_area_m2());

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

    begin
      face_4326 := st_transform(st_makevalid(face.geom), 4326);
      area_m2 := st_area(face_4326::geography);
    exception
      when others then
        continue;
    end;

    if area_m2 is null or area_m2 < min_area_m2 or area_m2 > p_max_face_area_m2 then
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
  p_min_loop_area_m2 double precision default null,
  p_snap_m double precision default 15.0,
  p_max_interior_area_m2 double precision default 10000000.0,
  p_max_loops integer default 20
)
  returns geography
  language plpgsql
  stable
  set search_path = public
as $$
declare
  route_len double precision;
  loop_close_m double precision;
  corridor_geog geography;
  loop_faces_geom geometry;
  start_end_poly geometry;
  parts geometry[] := '{}';
  merged_geom geometry;
  merged_geog geography;
  min_area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return null;
  end if;

  min_area_m2 := coalesce(p_min_loop_area_m2, public._liftr_territory_min_loop_area_m2(p_edge_m));

  route_len := st_length(p_route);
  if route_len is null or route_len < 500.0 then
    return null;
  end if;

  loop_close_m := public._liftr_territory_loop_close_m(route_len);

  corridor_geog := st_buffer(p_route, greatest(p_edge_m / 2.0, 1.0));
  parts := array_append(parts, corridor_geog::geometry);

  loop_faces_geom := public._liftr_territory_polygonize_loop_faces(
    p_route,
    min_area_m2,
    p_snap_m,
    p_max_loops,
    p_max_interior_area_m2
  );
  if loop_faces_geom is not null and not st_isempty(loop_faces_geom) then
    parts := array_append(parts, loop_faces_geom);
  end if;

  start_end_poly := public._liftr_territory_start_end_loop_polygon(
    p_route,
    loop_close_m,
    min_area_m2,
    p_max_interior_area_m2
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

  return merged_geog;
end;
$$;

create or replace function public._liftr_territory_route_kind (
  p_route geography,
  p_min_loop_area_m2 double precision default null,
  p_snap_m double precision default 15.0,
  p_max_loops integer default 20,
  p_max_interior_area_m2 double precision default 10000000.0
)
  returns text
  language plpgsql
  stable
  set search_path = public
as $$
declare
  route_len double precision;
  loop_close_m double precision;
  loop_faces_geom geometry;
  start_end_poly geometry;
  min_area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return 'open';
  end if;

  route_len := st_length(p_route);
  loop_close_m := public._liftr_territory_loop_close_m(route_len);
  min_area_m2 := coalesce(p_min_loop_area_m2, public._liftr_territory_min_loop_area_m2());

  start_end_poly := public._liftr_territory_start_end_loop_polygon(
    p_route,
    loop_close_m,
    min_area_m2,
    p_max_interior_area_m2
  );
  if start_end_poly is not null then
    return 'closed';
  end if;

  loop_faces_geom := public._liftr_territory_polygonize_loop_faces(
    p_route,
    min_area_m2,
    p_snap_m,
    p_max_loops,
    p_max_interior_area_m2
  );
  if loop_faces_geom is not null and not st_isempty(loop_faces_geom) then
    return 'closed';
  end if;

  return 'open';
end;
$$;

create or replace function public._liftr_backfill_territory_large_loop_capture_batch_v1 (
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
      delete from public._liftr_large_loop_backfill_queue q
      where q.workout_id in (
        select
          q2.workout_id
        from public._liftr_large_loop_backfill_queue q2
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

create table if not exists public._liftr_large_loop_backfill_queue (
  workout_id bigint primary key
);

truncate public._liftr_large_loop_backfill_queue;

insert into public._liftr_large_loop_backfill_queue (workout_id)
select distinct
  e.workout_id
from public.territory_capture_events e
where public._liftr_workout_route_geojson_text(e.workout_id) is not null
  and (
    e.workout_id in (1987, 1988)
    or (
      e.route_kind = 'open'
      and exists (
        select 1
        from (
          select
            public._liftr_territory_route_geog_from_geojson(
              public._liftr_workout_route_geojson_text(e.workout_id)
            ) as route_geog
        ) r
        where r.route_geog is not null
          and st_length(r.route_geog) >= 3000.0
          and st_distance(
            st_startpoint(r.route_geog::geometry)::geography,
            st_endpoint(r.route_geog::geometry)::geography
          ) <= public._liftr_territory_loop_close_m(st_length(r.route_geog))
      )
    )
  );

do $$
declare
  batch_processed integer := 1;
  remaining integer := 0;
begin
  loop
    select count(*)::integer into remaining from public._liftr_large_loop_backfill_queue;
    exit when remaining = 0;

    select public._liftr_backfill_territory_large_loop_capture_batch_v1(25)
    into batch_processed;
    exit when batch_processed = 0;
  end loop;
end;
$$;

drop table public._liftr_large_loop_backfill_queue;

drop function if exists public._liftr_backfill_territory_large_loop_capture_batch_v1(integer);

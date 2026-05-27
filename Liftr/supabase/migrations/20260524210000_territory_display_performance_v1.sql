create or replace function public._liftr_territory_capture_fill_geojson (
  p_capture_geog geography
)
  returns jsonb
  language plpgsql
  stable
  set search_path = public
as $$
declare
  g geometry;
  poly geometry;
  simplified geometry;
  area_m2 double precision;
  tol double precision;
begin
  if p_capture_geog is null or st_isempty(p_capture_geog::geometry) then
    return null;
  end if;

  g := st_makevalid(st_collectionextract(p_capture_geog::geometry, 3));
  if g is null or st_isempty(g) then
    g := st_makevalid(st_buffer(p_capture_geog::geometry, 0));
  end if;

  if g is null or st_isempty(g) then
    return null;
  end if;

  if st_geometrytype(g) = 'ST_MultiPolygon' then
    select
      f.geom
    into poly
    from st_dump(g) as f
    order by st_area(f.geom::geography) desc nulls last
    limit 1;
  elsif st_geometrytype(g) = 'ST_Polygon' then
    poly := g;
  else
    return null;
  end if;

  if poly is null or st_isempty(poly) then
    return null;
  end if;

  area_m2 := st_area(poly::geography);
  tol := greatest(0.00003, least(0.00015, sqrt(greatest(area_m2, 1.0)) / 500000.0));

  simplified := st_snaptogrid(
    st_simplifypreservetopology(poly, tol),
    0.00001
  );

  if simplified is null or st_isempty(simplified) then
    return null;
  end if;

  return st_asgeojson(simplified)::jsonb;
end;
$$;

drop function if exists public.preview_territory_capture_v1 (text);

create or replace function public.preview_territory_capture_v1 (
  p_route_geojson text,
  p_max_cells integer default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = public
as $$
declare
  route_geog geography;
  capture_geog geography;
  route_kind text;
  cell_count integer := 0;
  min_lat double precision;
  min_lon double precision;
  max_lat double precision;
  max_lon double precision;
  cells_json jsonb := '[]'::jsonb;
  fill_json jsonb;
  effective_max integer;
  cells_truncated boolean := false;
begin
  if auth.uid () is null then
    raise exception 'not_authenticated';
  end if;

  route_geog := public._liftr_territory_route_geog_from_geojson(p_route_geojson);
  if route_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid_route');
  end if;

  if st_length(route_geog) < 500.0 then
    return jsonb_build_object('ok', false, 'reason', 'route_too_short');
  end if;

  capture_geog := public._liftr_territory_capture_geom(route_geog);
  if capture_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'capture_geom_failed');
  end if;

  route_kind := public._liftr_territory_route_kind(route_geog);
  fill_json := public._liftr_territory_capture_fill_geojson(capture_geog);

  select
    count(*)::integer,
    coalesce(min(st_ymin(c.cell_geog::geometry)), 0),
    coalesce(min(st_xmin(c.cell_geog::geometry)), 0),
    coalesce(max(st_ymax(c.cell_geog::geometry)), 0),
    coalesce(max(st_xmax(c.cell_geog::geometry)), 0)
  into cell_count, min_lat, min_lon, max_lat, max_lon
  from public._liftr_territory_hex_cells_from_geog(capture_geog) c;

  effective_max := p_max_cells;

  if effective_max is not null and effective_max <= 0 then
    cells_json := '[]'::jsonb;
    cells_truncated := cell_count > 0;
  elsif effective_max is null or cell_count <= effective_max then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'cell_id', h.cell_id,
          'cell_geojson', st_asgeojson(h.cell_geog::geometry)::jsonb
        )
        order by h.cell_id
      ),
      '[]'::jsonb
    )
    into cells_json
    from public._liftr_territory_hex_cells_from_geog(capture_geog) h;
  else
    cells_truncated := true;
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'cell_id', s.cell_id,
          'cell_geojson', st_asgeojson(s.cell_geog::geometry)::jsonb
        )
        order by s.cell_id
      ),
      '[]'::jsonb
    )
    into cells_json
    from (
      select
        h.cell_id,
        h.cell_geog
      from public._liftr_territory_hex_cells_from_geog(capture_geog) h
      order by h.cell_id
      limit greatest(effective_max, 1)
    ) s;
  end if;

  return jsonb_build_object(
    'ok', true,
    'route_kind', route_kind,
    'cells_count', cell_count,
    'cells', cells_json,
    'capture_fill_geojson', fill_json,
    'cells_truncated', cells_truncated,
    'bbox', jsonb_build_object(
      'min_lat', min_lat,
      'min_lon', min_lon,
      'max_lat', max_lat,
      'max_lon', max_lon
    )
  );
end;
$$;

create or replace function public.get_workout_territory_display_v1 (
  p_workout_id bigint
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = public
as $$
declare
  route_text text;
  route_geog geography;
  capture_geog geography;
  route_kind text;
  cell_count integer := 0;
  fill_json jsonb;
  env geometry;
begin
  if auth.uid () is null then
    raise exception 'not_authenticated';
  end if;

  route_text := public._liftr_workout_route_geojson_text(p_workout_id);
  if route_text is null then
    return jsonb_build_object('ok', false, 'reason', 'missing_route');
  end if;

  select
    coalesce(e.cells_gained, 0)
  into cell_count
  from public.territory_capture_events e
  where e.workout_id = p_workout_id;

  route_geog := public._liftr_territory_route_geog_from_geojson(route_text);
  if route_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid_route');
  end if;

  if st_length(route_geog) < 500.0 then
    return jsonb_build_object('ok', false, 'reason', 'route_too_short');
  end if;

  capture_geog := public._liftr_territory_capture_geom(route_geog);
  if capture_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'capture_geom_failed');
  end if;

  route_kind := public._liftr_territory_route_kind(route_geog);
  fill_json := public._liftr_territory_capture_fill_geojson(capture_geog);
  env := st_envelope(capture_geog::geometry);

  return jsonb_build_object(
    'ok', true,
    'route_kind', route_kind,
    'cells_count', cell_count,
    'cells', '[]'::jsonb,
    'capture_fill_geojson', fill_json,
    'cells_truncated', cell_count > 0,
    'bbox', jsonb_build_object(
      'min_lat', st_ymin(env),
      'min_lon', st_xmin(env),
      'max_lat', st_ymax(env),
      'max_lon', st_xmax(env)
    )
  );
end;
$$;

grant execute on function public.preview_territory_capture_v1 (text, integer) to authenticated;
grant execute on function public.get_workout_territory_display_v1 (bigint) to authenticated;

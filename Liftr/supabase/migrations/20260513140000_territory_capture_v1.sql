create extension if not exists postgis;

create table if not exists public.territory_cells (
  cell_id text primary key,
  cell_geog geography (Polygon, 4326) not null,
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  captured_at timestamptz not null default now(),
  last_workout_id bigint references public.workouts (id) on delete set null,
  last_activity_code text
);

create index if not exists territory_cells_owner_user_id_idx on public.territory_cells (owner_user_id);

create index if not exists territory_cells_cell_geog_gist_idx on public.territory_cells using gist (cell_geog);

create table if not exists public.territory_capture_events (
  id bigserial primary key,
  workout_id bigint not null references public.workouts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  route_kind text not null check (route_kind in ('open', 'closed')),
  cells_gained integer not null default 0,
  cells_taken integer not null default 0,
  bbox_min_lat double precision,
  bbox_min_lon double precision,
  bbox_max_lat double precision,
  bbox_max_lon double precision,
  applied_at timestamptz not null default now(),
  unique (workout_id)
);

create index if not exists territory_capture_events_user_id_applied_at_idx
  on public.territory_capture_events (user_id, applied_at desc);

alter table public.territory_cells enable row level security;
alter table public.territory_capture_events enable row level security;

drop policy if exists territory_cells_select_authenticated on public.territory_cells;
create policy territory_cells_select_authenticated
  on public.territory_cells
  for select
  to authenticated
  using (true);

drop policy if exists territory_capture_events_select_authenticated on public.territory_capture_events;
create policy territory_capture_events_select_authenticated
  on public.territory_capture_events
  for select
  to authenticated
  using (true);

revoke insert, update, delete on public.territory_cells from anon, authenticated;
revoke insert, update, delete on public.territory_capture_events from anon, authenticated;

create or replace function public._liftr_territory_outdoor_activity (p_activity_code text)
  returns boolean
  language sql
  immutable
as $$
  select coalesce(lower(trim(p_activity_code)), '') in (
    'run',
    'walk',
    'hike',
    'bike',
    'e_bike',
    'mtb',
    'swim_open_water'
  );
$$;

create or replace function public._liftr_territory_route_geog_from_geojson (p_route_geojson text)
  returns geography
  language plpgsql
  stable
  set search_path = public
as $$
declare
  g geometry;
begin
  if p_route_geojson is null or length(trim(p_route_geojson)) = 0 then
    return null;
  end if;

  begin
    g := st_setsrid(st_geomfromgeojson(p_route_geojson), 4326);
  exception
    when others then
      return null;
  end;

  if g is null or st_isempty(g) then
    return null;
  end if;

  if st_geometrytype(g) = 'ST_MultiLineString' then
    g := st_linemerge(g);
  end if;

  if st_geometrytype(g) <> 'ST_LineString' then
    return null;
  end if;

  return g::geography;
end;
$$;

create or replace function public._liftr_territory_capture_geom (
  p_route geography,
  p_edge_m double precision default 25.0,
  p_loop_close_m double precision default 50.0,
  p_min_loop_area_m2 double precision default 5000.0
)
  returns geography
  language plpgsql
  stable
  set search_path = public
as $$
declare
  route_len double precision;
  start_end_m double precision;
  g_line geometry;
  g_poly geometry;
  area_m2 double precision;
begin
  if p_route is null or st_isempty(p_route::geometry) then
    return null;
  end if;

  route_len := st_length(p_route);
  if route_len is null or route_len < 500.0 then
    return null;
  end if;

  g_line := p_route::geometry;
  start_end_m := st_distance(
    st_startpoint(g_line)::geography,
    st_endpoint(g_line)::geography
  );

  if start_end_m <= p_loop_close_m then
    if not st_isclosed(g_line) then
      g_line := st_addpoint(g_line, st_startpoint(g_line));
    end if;

    begin
      g_poly := st_makevalid(st_makepolygon(g_line));
    exception
      when others then
        g_poly := null;
    end;

    if g_poly is not null and not st_isempty(g_poly) then
      area_m2 := st_area(g_poly::geography);
      if area_m2 is not null and area_m2 >= p_min_loop_area_m2 then
        return g_poly::geography;
      end if;
    end if;
  end if;

  return st_buffer(p_route, greatest(p_edge_m / 2.0, 1.0));
end;
$$;

create or replace function public._liftr_territory_route_kind (
  p_route geography,
  p_loop_close_m double precision default 50.0,
  p_min_loop_area_m2 double precision default 5000.0
)
  returns text
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
  if p_route is null then
    return 'open';
  end if;

  g_line := p_route::geometry;
  start_end_m := st_distance(
    st_startpoint(g_line)::geography,
    st_endpoint(g_line)::geography
  );

  if start_end_m > p_loop_close_m then
    return 'open';
  end if;

  if not st_isclosed(g_line) then
    g_line := st_addpoint(g_line, st_startpoint(g_line));
  end if;

  begin
    g_poly := st_makevalid(st_makepolygon(g_line));
  exception
    when others then
    return 'open';
  end;

  if g_poly is null or st_isempty(g_poly) then
    return 'open';
  end if;

  area_m2 := st_area(g_poly::geography);
  if area_m2 is null or area_m2 < p_min_loop_area_m2 then
    return 'open';
  end if;

  return 'closed';
end;
$$;

create or replace function public._liftr_territory_hex_cells_from_geog (
  p_target geography,
  p_edge_m double precision default 25.0
)
  returns table (
    cell_id text,
    cell_geog geography
  )
  language sql
  stable
  set search_path = public
as $$
  with
  target_3857 as (
    select st_transform(st_buffer(p_target, 0)::geometry, 3857) as geom
  ),
  bounds as (
    select st_envelope(st_buffer(t.geom, p_edge_m)) as bbox
    from target_3857 t
  ),
  grid as (
    select
      hex.geom as geom_3857,
      hex.i,
      hex.j
    from bounds b,
      lateral st_hexagongrid(p_edge_m, b.bbox) as hex (geom, i, j)
  ),
  matched as (
    select
      format('%s:%s', g.i, g.j) as cell_id,
      st_transform(g.geom_3857, 4326)::geography as cell_geog
    from grid g
      cross join target_3857 t
    where st_intersects(g.geom_3857, t.geom)
  )
  select distinct on (m.cell_id)
    m.cell_id,
    m.cell_geog
  from matched m
  order by m.cell_id;
$$;

create or replace function public._liftr_territory_capture_summary_json (
  p_route_kind text,
  p_cells_gained integer,
  p_cells_taken integer,
  p_bbox_min_lat double precision,
  p_bbox_min_lon double precision,
  p_bbox_max_lat double precision,
  p_bbox_max_lon double precision,
  p_already_applied boolean default false
)
  returns jsonb
  language sql
  immutable
as $$
  select jsonb_build_object(
    'ok', true,
    'route_kind', p_route_kind,
    'cells_gained', coalesce(p_cells_gained, 0),
    'cells_taken', coalesce(p_cells_taken, 0),
    'bbox', jsonb_build_object(
      'min_lat', p_bbox_min_lat,
      'min_lon', p_bbox_min_lon,
      'max_lat', p_bbox_max_lat,
      'max_lon', p_bbox_max_lon
    ),
    'already_applied', coalesce(p_already_applied, false)
  );
$$;

create or replace function public.preview_territory_capture_v1 (p_route_geojson text)
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

  select
    count(*)::integer,
    coalesce(min(st_ymin(c.cell_geog::geometry)), 0),
    coalesce(min(st_xmin(c.cell_geog::geometry)), 0),
    coalesce(max(st_ymax(c.cell_geog::geometry)), 0),
    coalesce(max(st_xmax(c.cell_geog::geometry)), 0)
  into cell_count, min_lat, min_lon, max_lat, max_lon
  from public._liftr_territory_hex_cells_from_geog(capture_geog) c;

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

  return jsonb_build_object(
    'ok', true,
    'route_kind', route_kind,
    'cells_count', cell_count,
    'cells', cells_json,
    'bbox', jsonb_build_object(
      'min_lat', min_lat,
      'min_lon', min_lon,
      'max_lat', max_lat,
      'max_lon', max_lon
    )
  );
end;
$$;

create or replace function public.apply_territory_capture_v1 (p_workout_id bigint)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  w_user uuid;
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
  if auth.uid () is null then
    raise exception 'not_authenticated';
  end if;

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
    w.user_id
  into w_user
  from public.workouts w
  where w.id = p_workout_id;

  if w_user is null then
    raise exception 'workout_not_found';
  end if;

  if w_user <> auth.uid () then
    raise exception 'not_owner';
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
  where tc.owner_user_id <> auth.uid ();

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
    last_activity_code
  )
  select
    nc.cell_id,
    nc.cell_geog,
    auth.uid (),
    now(),
    p_workout_id,
    activity_code
  from _liftr_capture_cells nc
  on conflict (cell_id) do update
    set
      owner_user_id = excluded.owner_user_id,
      captured_at = excluded.captured_at,
      last_workout_id = excluded.last_workout_id,
      last_activity_code = excluded.last_activity_code;

  insert into public.territory_capture_events (
    workout_id,
    user_id,
    route_kind,
    cells_gained,
    cells_taken,
    bbox_min_lat,
    bbox_min_lon,
    bbox_max_lat,
    bbox_max_lon
  )
  values (
    p_workout_id,
    auth.uid (),
    route_kind,
    cells_gained,
    cells_taken,
    min_lat,
    min_lon,
    max_lat,
    max_lon
  );

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

create or replace function public.get_territory_map_v1 (
  p_min_lat double precision,
  p_min_lon double precision,
  p_max_lat double precision,
  p_max_lon double precision,
  p_limit integer default 500
)
  returns table (
    cell_id text,
    cell_geojson jsonb,
    owner_user_id uuid,
    owner_username text,
    owner_avatar_url text,
    captured_at timestamptz,
    is_mine boolean
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  with bbox as (
    select st_makeenvelope(
      least(p_min_lon, p_max_lon),
      least(p_min_lat, p_max_lat),
      greatest(p_min_lon, p_max_lon),
      greatest(p_min_lat, p_max_lat),
      4326
    )::geography as geog
  )
  select
    tc.cell_id,
    st_asgeojson(tc.cell_geog::geometry)::jsonb as cell_geojson,
    tc.owner_user_id,
    p.username,
    p.avatar_url,
    tc.captured_at,
    tc.owner_user_id = auth.uid () as is_mine
  from public.territory_cells tc
    join bbox b on st_intersects(tc.cell_geog, b.geog)
    left join public.profiles p on p.user_id = tc.owner_user_id
  order by tc.captured_at desc
  limit greatest(least(coalesce(p_limit, 500), 2000), 1);
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
      count(*)::integer as cells_last_7d
    from public.territory_capture_events e
    where
      e.user_id = auth.uid ()
      and e.applied_at >= now() - interval '7 days'
  )
  select jsonb_build_object(
    'total_cells', (select total_cells from mine),
    'cells_last_7d', (select cells_last_7d from week),
    'approx_area_m2', (select total_cells from mine) * 1623.8,
    'recent_events', (select events from recent)
  );
$$;

grant execute on function public.preview_territory_capture_v1 (text) to authenticated;
grant execute on function public.apply_territory_capture_v1 (bigint) to authenticated;
grant execute on function public.get_territory_map_v1 (double precision, double precision, double precision, double precision, integer) to authenticated;
grant execute on function public.get_my_territory_summary_v1 () to authenticated;

analyze public.territory_cells;
analyze public.territory_capture_events;

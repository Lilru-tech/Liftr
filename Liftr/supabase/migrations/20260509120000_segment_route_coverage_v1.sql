-- Segment route overlap (axis coverage) + source workout persistence.
-- Requires PostGIS. Route GeoJSON: prefers public.workouts.route_geojson when the column
-- exists; otherwise public.cardio_sessions.route_geojson (first row per workout_id).
-- Adjust if your schema stores the line elsewhere.
--
-- After apply: run ANALYZE on affected tables; verify create_segment_from_workout_v1
-- if you already had a custom definition (merge source_* columns into your version).

create extension if not exists postgis;

-- ---------------------------------------------------------------------------
-- 1) Schema: source workout + route coverage
-- ---------------------------------------------------------------------------

alter table public.segments
  add column if not exists source_workout_id bigint references public.workouts (id);

alter table public.segments
  add column if not exists source_start_fraction double precision;

alter table public.segments
  add column if not exists source_end_fraction double precision;

alter table public.segments
  add column if not exists geog geography (LineString, 4326);

alter table public.segments
  add column if not exists geojson text;

create index if not exists segments_source_workout_id_idx on public.segments (source_workout_id)
where source_workout_id is not null;

alter table public.segment_efforts
  add column if not exists route_coverage double precision;

comment on column public.segment_efforts.route_coverage is
  'Fraction of segment axis length within buffer_m of the workout route (0–1). Source workout forced to 1.';

comment on column public.segments.source_workout_id is
  'Workout used to define this segment; its effort always qualifies at route_coverage = 1.';

-- Rellenar geog/geojson desde geom en segmentos legacy (mapa + cálculo de cobertura).
do $$
begin
  if exists (
    select 1
    from information_schema.columns c
    where
      c.table_schema = 'public'
      and c.table_name = 'segments'
      and c.column_name = 'geom'
  ) then
    update public.segments s
    set
      geog = coalesce(s.geog, s.geom::geography),
      geojson = coalesce(
        nullif(trim(s.geojson), ''),
        st_asgeojson(s.geom)::text
      )
    where
      s.geom is not null
      and (
        s.geog is null
        or btrim(coalesce(s.geojson, '')) = ''
      );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Helpers: geography from segment row / workout route
-- ---------------------------------------------------------------------------

-- Raw GeoJSON text for a workout (column layout varies by deployment).
create or replace function public._liftr_workout_route_geojson_text (p_workout_id bigint)
  returns text
  language plpgsql
  stable
  set search_path = public
as $$
declare
  gj text;
begin
  if exists (
    select 1
    from information_schema.columns c
    where
      c.table_schema = 'public'
      and c.table_name = 'workouts'
      and c.column_name = 'route_geojson'
  ) then
    execute $q$
      select nullif(trim(w.route_geojson::text), '')
      from public.workouts w
      where w.id = $1
    $q$
      into gj
    using p_workout_id;

    if gj is not null then
      return gj;
    end if;
  end if;

  if exists (
    select 1
    from information_schema.columns c
    where
      c.table_schema = 'public'
      and c.table_name = 'cardio_sessions'
      and c.column_name = 'route_geojson'
  ) then
    execute $q$
      select nullif(trim(cs.route_geojson::text), '')
      from public.cardio_sessions cs
      where cs.workout_id = $1
      order by cs.id nulls last
      limit 1
    $q$
      into gj
    using p_workout_id;
  end if;

  return gj;
end;
$$;

create or replace function public._liftr_workout_route_geog (p_workout_id bigint)
  returns geography
  language plpgsql
  stable
  set search_path = public
as $$
declare
  gj text;
  g geometry;
begin
  gj := public._liftr_workout_route_geojson_text(p_workout_id);

  if gj is null then
    return null;
  end if;

  begin
    g := st_setsrid(st_geomfromgeojson(gj), 4326);
  exception
    when others then
      return null;
  end;

  if g is null or st_isempty(g) then
    return null;
  end if;

  if st_geometrytype(g) = 'ST_LineString' then
    return g::geography;
  elsif st_geometrytype(g) = 'ST_MultiLineString' then
    return st_linemerge(g)::geography;
  end if;

  return null;
end;
$$;

create or replace function public._liftr_segment_line_geog (p_segment_id uuid)
  returns geography
  language plpgsql
  stable
  set search_path = public
as $$
declare
  gj text;
  g geometry;
  geog geography;
  g_geom geometry;
begin
  select
    nullif(trim(s.geojson), ''),
    s.geog,
    s.geom
  into gj, geog, g_geom
  from public.segments s
  where s.id = p_segment_id;

  if gj is not null and length(gj) > 0 then
    begin
      g := st_setsrid(st_geomfromgeojson(gj), 4326);
      if g is not null and not st_isempty(g) then
        if st_geometrytype(g) = 'ST_LineString' then
          return g::geography;
        elsif st_geometrytype(g) = 'ST_MultiLineString' then
          return st_linemerge(g)::geography;
        end if;
      end if;
    exception
      when others then
        null;
    end;
  end if;

  if geog is not null then
    return geog;
  end if;

  if g_geom is not null and not st_isempty(g_geom) then
    if st_geometrytype(g_geom) in ('ST_LineString', 'ST_MultiLineString') then
      return case
        when st_geometrytype(g_geom) = 'ST_MultiLineString' then st_linemerge(g_geom)::geography
        else g_geom::geography
      end;
    end if;
  end if;

  return null;
end;
$$;

-- Sample the segment axis at ~p_sample_step_m spacing; count samples within p_buffer_m of route.
create or replace function public._liftr_axis_route_coverage (
  p_segment_line geography,
  p_route_line geography,
  p_buffer_m double precision,
  p_sample_step_m double precision default 10.0
)
  returns double precision
  language plpgsql
  stable
as $$
declare
  seg_len double precision;
  n int;
  hits int := 0;
  i int;
  frac double precision;
  seg_geom geometry;
  route_geog geography;
begin
  if p_segment_line is null or p_route_line is null then
    return null;
  end if;

  seg_geom := p_segment_line::geometry;
  route_geog := p_route_line;

  if st_isempty(seg_geom) or st_isempty(route_geog::geometry) then
    return 0;
  end if;

  seg_len := st_length(p_segment_line::geography);

  if seg_len is null or seg_len <= 0 then
    return 0;
  end if;

  n := greatest(2, ceil(seg_len / greatest(p_sample_step_m, 1.0))::int);

  -- Radio > buffer_m del segmento para GPS (cobertura del eje; reduce falsos negativos frente a 0.95).
  for i in 0..(n - 1) loop
    frac := case
      when n <= 1 then 0.0
      else i::double precision / (n - 1)::double precision
    end;
    if st_dwithin(
      st_lineinterpolatepoint(seg_geom, frac)::geography,
      route_geog,
      greatest(p_buffer_m * 2.5, 40.0, p_buffer_m)
    ) then
      hits := hits + 1;
    end if;
  end loop;

  return hits::double precision / n::double precision;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) BEFORE INSERT/UPDATE: set route_coverage; reject rows below 0.95 (unless source workout)
-- ---------------------------------------------------------------------------

create or replace function public._liftr_segment_efforts_enforce_route_coverage ()
  returns trigger
  language plpgsql
as $$
declare
  seg_row record;
  seg geography;
  rt geography;
  cov double precision;
begin
  select
    *
  into seg_row
  from public.segments seg_src
  where seg_src.id = new.segment_id;

  if not found then
    return new;
  end if;

  if seg_row.source_workout_id is not null and new.workout_id = seg_row.source_workout_id then
    new.route_coverage := 1.0;
    return new;
  end if;

  seg := public._liftr_segment_line_geog(new.segment_id);
  rt := public._liftr_workout_route_geog(new.workout_id);

  if seg is null or rt is null then
    return null;
  end if;

  cov := public._liftr_axis_route_coverage(seg, rt, coalesce(seg_row.buffer_m, 25.0)::double precision, 10.0);
  new.route_coverage := cov;

  if cov is null or cov < 0.95 then
    return null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_liftr_segment_efforts_route_coverage on public.segment_efforts;

create trigger trg_liftr_segment_efforts_route_coverage
before insert or update of segment_id, workout_id on public.segment_efforts
for each row
execute procedure public._liftr_segment_efforts_enforce_route_coverage ();

-- ---------------------------------------------------------------------------
-- 4) Backfill + prune existing rows (legacy segments without source: coverage-only rule)
-- ---------------------------------------------------------------------------

create or replace function public.liftr_apply_segment_route_coverage_policy (p_segment_id uuid default null)
  returns bigint
  language plpgsql
as $$
declare
  n bigint;
begin
  update public.segment_efforts se
  set route_coverage = case
    when s.source_workout_id is not null
    and se.workout_id = s.source_workout_id then 1.0
    else coalesce(
      public._liftr_axis_route_coverage(
        public._liftr_segment_line_geog(se.segment_id),
        public._liftr_workout_route_geog(se.workout_id),
        coalesce(s.buffer_m, 25.0)::double precision,
        10.0
      ),
      0.0
    )
  end
  from public.segments s
  where se.segment_id = s.id
  and (
    p_segment_id is null
    or se.segment_id = p_segment_id
  );

  get diagnostics n = row_count;

  delete from public.segment_efforts se
  using public.segments s
  where se.segment_id = s.id
  and (
    p_segment_id is null
    or se.segment_id = p_segment_id
  )
  and (
    se.route_coverage is null
    or se.route_coverage < 0.95
  )
  and (
    s.source_workout_id is null
    or se.workout_id is distinct from s.source_workout_id
  );

  return coalesce(n, 0);
end;
$$;

-- Disable trigger during bulk refresh to avoid double logic
alter table public.segment_efforts disable trigger trg_liftr_segment_efforts_route_coverage;

select public.liftr_apply_segment_route_coverage_policy (null);

alter table public.segment_efforts enable trigger trg_liftr_segment_efforts_route_coverage;

-- ---------------------------------------------------------------------------
-- 5) create_segment_from_workout_v1 (minimal full body; merge with your duplicate checks if needed)
-- ---------------------------------------------------------------------------

drop function if exists public.create_segment_from_workout_v1 (bigint, text, double precision, double precision, double precision);

create or replace function public.create_segment_from_workout_v1 (
  p_workout_id bigint,
  p_name text,
  p_start_fraction double precision,
  p_end_fraction double precision,
  p_buffer_m double precision default 25.0
)
  returns uuid
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  w_user uuid;
  w_state text;
  rgeo text;
  seg_line geography;
  candidate record;
  new_id uuid;
  gj text;
  g_line geometry;
begin
  if p_start_fraction < 0
  or p_start_fraction > 1
  or p_end_fraction < 0
  or p_end_fraction > 1
  or p_start_fraction >= p_end_fraction then
    raise exception 'invalid_fraction_range';
  end if;

  select
    w.user_id,
    w.state::text
  into w_user, w_state
  from public.workouts w
  where w.id = p_workout_id;

  rgeo := public._liftr_workout_route_geojson_text(p_workout_id);

  if w_user is null then
    raise exception 'workout_not_found';
  end if;

  if w_user <> auth.uid () then
    raise exception 'not_owner';
  end if;

  if w_state is distinct from 'published' then
    raise exception 'workout_not_published';
  end if;

  if rgeo is null or length(rgeo) = 0 then
    raise exception 'missing_route_geojson';
  end if;

  begin
    g_line := st_setsrid(st_geomfromgeojson(rgeo), 4326);
  exception
    when others then
      raise exception 'invalid_route_geojson';
  end;

  if st_geometrytype(g_line) = 'ST_MultiLineString' then
    g_line := st_linemerge(g_line);
  end if;

  if st_geometrytype(g_line) <> 'ST_LineString' then
    raise exception 'route_not_linestring';
  end if;

  seg_line := st_linesubstring(g_line, p_start_fraction, p_end_fraction)::geography;

  if seg_line is null or st_length(seg_line) < 1 then
    raise exception 'segment_too_short';
  end if;

  gj := st_asgeojson(seg_line::geometry)::text;
  new_id := gen_random_uuid();

  insert into public.segments (
    id,
    name,
    buffer_m,
    status,
    created_by,
    created_at,
    geom,
    geog,
    geojson,
    source_workout_id,
    source_start_fraction,
    source_end_fraction
  )
  values (
    new_id,
    coalesce(nullif(trim(p_name), ''), 'Segment'),
    coalesce(p_buffer_m, 25.0),
    'published',
    auth.uid (),
    now(),
    seg_line::geometry,
    seg_line,
    gj,
    p_workout_id,
    p_start_fraction,
    p_end_fraction
  );

  if exists (
    select 1
    from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
    where
      n.nspname = 'public'
      and p.proname = '_match_segments_for_workout_internal'
  ) then
    -- Paridad con segments_mvp_v4: al crear segmento, re-matchear workouts publicados cercanos.
    for candidate in
      select w.id as workout_id
      from public.workouts w
      where w.state = 'published'
        and public._liftr_workout_route_geog(w.id) is not null
        and st_dwithin(
          seg_line,
          public._liftr_workout_route_geog(w.id),
          greatest(coalesce(p_buffer_m, 25.0) * 3.0, 200.0)
        )
    loop
      begin
        perform public._match_segments_for_workout_internal(candidate.workout_id);
      exception
        when others then
          -- No interrumpir creación de segmento por un workout individual problemático.
          null;
      end;
    end loop;
  elsif exists (
    select 1
    from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
    where
      n.nspname = 'public'
      and p.proname = 'match_segment_efforts_for_workout_v1'
  ) then
    -- Fallback: esta RPC suele estar limitada al dueño del workout.
    perform public.match_segment_efforts_for_workout_v1 (p_workout_id);
  end if;

  return new_id;
end;
$$;

grant execute on function public.create_segment_from_workout_v1 (bigint, text, double precision, double precision, double precision) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Leaderboard: only qualifying efforts; expose route_coverage + is_source_workout
-- ---------------------------------------------------------------------------

drop function if exists public.get_segment_leaderboard_v1 (uuid, int);

drop function if exists public.get_segment_leaderboard_v1 (uuid);

create or replace function public.get_segment_leaderboard_v1 (p_segment_id uuid, p_limit int default 50)
  returns table (
    rank bigint,
    user_id uuid,
    username text,
    avatar_url text,
    elapsed_sec int,
    workout_id bigint,
    matched_at timestamptz,
    effort_at timestamptz,
    confidence double precision,
    route_coverage double precision,
    is_source_workout boolean
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  with
  src as (
    select
      s.id as segment_id,
      s.source_workout_id
    from public.segments s
    where
      s.id = p_segment_id
  ),
  base as (
    select
      se.id as effort_id,
      se.user_id as uid,
      se.elapsed_sec as esec,
      se.workout_id as wid,
      se.matched_at as mat,
      coalesce(w.started_at, w.created_at) as eat,
      se.confidence as conf,
      se.route_coverage as rcov,
      (
        src.source_workout_id is not null
        and se.workout_id = src.source_workout_id
      ) as is_src
    from
      public.segment_efforts se
      join src on src.segment_id = se.segment_id
      join public.workouts w on w.id = se.workout_id
    where
      w.state = 'published'
      and (
        (
          src.source_workout_id is not null
          and se.workout_id = src.source_workout_id
        )
        or (
          se.route_coverage is not null
          and se.route_coverage >= 0.95
        )
      )
  ),
  capped as (
    select
      b.*,
      row_number() over (
        partition by
          b.uid
        order by
          b.esec asc
      ) as rn
    from
      base b
  ),
  ranked as (
    select
      c.*,
      row_number() over (
        order by
          c.esec asc
      ) as g_rank
    from
      capped c
    where
      c.rn <= 10
  )
  select
    r.g_rank as rank,
    r.uid as user_id,
    p.username,
    p.avatar_url,
    r.esec as elapsed_sec,
    r.wid as workout_id,
    r.mat as matched_at,
    r.eat as effort_at,
    r.conf,
    r.rcov as route_coverage,
    r.is_src as is_source_workout
  from
    ranked r
    left join public.profiles p on p.user_id = r.uid
  where
    r.g_rank <= coalesce(p_limit, 50)
  order by
    r.g_rank;
$$;

grant execute on function public.get_segment_leaderboard_v1 (uuid, int) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) Segment detail: stats from qualifying efforts only; geojson from geog/geojson column
-- ---------------------------------------------------------------------------

drop function if exists public.get_segment_detail_v1 (uuid);

create or replace function public.get_segment_detail_v1 (p_segment_id uuid)
  returns table (
    id uuid,
    name text,
    buffer_m double precision,
    status text,
    geojson text,
    created_by uuid,
    foreign_efforts_count bigint,
    segment_length_m double precision,
    center_lat double precision,
    center_lon double precision,
    leaderboard_effort_count bigint,
    leaderboard_athlete_count bigint,
    confidence_avg double precision,
    confidence_min double precision,
    confidence_max double precision,
    viewer_best_elapsed_sec int,
    viewer_best_workout_id bigint
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  with
  s as (
    select
      seg.*
    from
      public.segments seg
    where
      seg.id = p_segment_id
  ),
  qual as (
    select
      se.*
    from
      public.segment_efforts se
      join s on s.id = se.segment_id
      join public.workouts w on w.id = se.workout_id
    where
      w.state = 'published'
      and (
        (
          s.source_workout_id is not null
          and se.workout_id = s.source_workout_id
        )
        or (
          se.route_coverage is not null
          and se.route_coverage >= 0.95
        )
      )
  ),
  stats as (
    select
      avg(q.route_coverage) as rc_avg,
      min(q.route_coverage) as rc_min,
      max(q.route_coverage) as rc_max,
      count(*)::bigint as eff_cnt,
      count(distinct q.user_id)::bigint as ath_cnt
    from
      qual q
  )
  select
    s.id,
    coalesce(nullif(trim(s.name), ''), 'Segment') as name,
    coalesce(s.buffer_m, 25.0) as buffer_m,
    coalesce(nullif(trim(s.status), ''), 'published') as status,
    coalesce(
      nullif(trim(s.geojson), ''),
      case
        when s.geog is not null then st_asgeojson(s.geog::geometry)::text
        when s.geom is not null then st_asgeojson(s.geom)::text
        else null
      end,
      '{"type":"LineString","coordinates":[]}'::text
    ) as geojson,
    s.created_by,
    (
      select
        count(*)::bigint
      from
        qual q
      where
        q.user_id is distinct from s.created_by
    ) as foreign_efforts_count,
    case
      when s.geog is not null then st_length(s.geog::geography)
      when s.geom is not null then st_length(s.geom::geography)
      else st_length(public._liftr_segment_line_geog(s.id)::geography)
    end as segment_length_m,
    case
      when s.geog is not null then st_y(st_centroid(s.geog::geometry))::double precision
      -- segments.geom puede ser geography: st_centroid(geography)->geography y st_y no acepta geography.
      when s.geom is not null then st_y(st_centroid(s.geom::geometry))::double precision
      else st_y(st_centroid(public._liftr_segment_line_geog(s.id)::geometry))::double precision
    end as center_lat,
    case
      when s.geog is not null then st_x(st_centroid(s.geog::geometry))::double precision
      when s.geom is not null then st_x(st_centroid(s.geom::geometry))::double precision
      else st_x(st_centroid(public._liftr_segment_line_geog(s.id)::geometry))::double precision
    end as center_lon,
    st.eff_cnt as leaderboard_effort_count,
    st.ath_cnt as leaderboard_athlete_count,
    st.rc_avg as confidence_avg,
    st.rc_min as confidence_min,
    st.rc_max as confidence_max,
    (
      select
        q.elapsed_sec::int
      from
        qual q
      where
        auth.uid () is not null
        and q.user_id = auth.uid ()
      order by
        q.elapsed_sec asc
      limit 1
    ) as viewer_best_elapsed_sec,
    (
      select
        q.workout_id
      from
        qual q
      where
        auth.uid () is not null
        and q.user_id = auth.uid ()
      order by
        q.elapsed_sec asc
      limit 1
    )::bigint as viewer_best_workout_id
  from
    s
    cross join stats st;
$$;

grant execute on function public.get_segment_detail_v1 (uuid) to anon, authenticated;

grant execute on function public.liftr_apply_segment_route_coverage_policy (uuid) to service_role;

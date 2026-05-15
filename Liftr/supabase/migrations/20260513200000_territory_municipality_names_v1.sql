create table if not exists public.territory_municipalities (
  city_key text primary key,
  display_name text not null,
  display_name_override text,
  country_code text,
  admin_level integer,
  boundary_geom geography (MultiPolygon, 4326),
  center_lat double precision not null,
  center_lon double precision not null,
  total_capture_cells integer,
  geocode_source text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists territory_municipalities_boundary_gist_idx
  on public.territory_municipalities using gist (boundary_geom);

create index if not exists territory_municipalities_center_idx
  on public.territory_municipalities (center_lat, center_lon);

create table if not exists public.territory_city_geocode_cache (
  bucket_lat numeric(6, 2) not null,
  bucket_lon numeric(6, 2) not null,
  city_key text not null references public.territory_municipalities (city_key) on delete cascade,
  resolved_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  primary key (bucket_lat, bucket_lon)
);

create index if not exists territory_city_geocode_cache_city_key_idx
  on public.territory_city_geocode_cache (city_key);

create table if not exists public.territory_city_geocode_queue (
  bucket_lat numeric(6, 2) not null,
  bucket_lon numeric(6, 2) not null,
  sample_lat double precision not null,
  sample_lon double precision not null,
  attempts integer not null default 0,
  last_error text,
  queued_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (bucket_lat, bucket_lon)
);

alter table public.territory_municipalities enable row level security;
alter table public.territory_city_geocode_cache enable row level security;
alter table public.territory_city_geocode_queue enable row level security;

drop policy if exists territory_municipalities_select on public.territory_municipalities;
create policy territory_municipalities_select
  on public.territory_municipalities
  for select
  to authenticated
  using (true);

drop policy if exists territory_city_geocode_cache_select on public.territory_city_geocode_cache;
create policy territory_city_geocode_cache_select
  on public.territory_city_geocode_cache
  for select
  to authenticated
  using (true);

alter table public.territory_cells
  drop constraint if exists territory_cells_city_key_fkey;

create or replace function public._liftr_territory_city_geocode_bucket (
  p_lat double precision,
  p_lon double precision
)
  returns table (
    bucket_lat numeric,
    bucket_lon numeric
  )
  language sql
  immutable
as $$
  select
    round(p_lat::numeric, 2) as bucket_lat,
    round(p_lon::numeric, 2) as bucket_lon;
$$;

create or replace function public._liftr_territory_municipality_label (
  p_display_name text,
  p_display_name_override text
)
  returns text
  language sql
  immutable
as $$
  select coalesce(nullif(trim(p_display_name_override), ''), nullif(trim(p_display_name), ''), 'Unknown city');
$$;

create or replace function public._liftr_territory_count_hex_cells_for_geog (
  p_boundary geography,
  p_edge_m double precision default 25.0,
  p_max_cells integer default 500000
)
  returns integer
  language plpgsql
  stable
  set search_path = public
as $$
declare
  total integer;
begin
  if p_boundary is null then
    return null;
  end if;

  select count(*)::integer
  into total
  from (
    select distinct on (format('%s:%s', hex.i, hex.j))
      hex.i,
      hex.j
    from (
      select st_transform(st_buffer(p_boundary::geometry, 0), 3857) as geom_3857
    ) boundary_3857,
      lateral st_hexagongrid(
        p_edge_m,
        st_envelope(st_buffer(boundary_3857.geom_3857, p_edge_m))
      ) as hex (geom, i, j)
    where st_intersects(hex.geom, boundary_3857.geom_3857)
    limit p_max_cells + 1
  ) q;

  if total > p_max_cells then
    return null;
  end if;

  return total;
end;
$$;

create or replace function public._liftr_territory_boundary_from_geojson (
  p_geojson text
)
  returns geography
  language plpgsql
  immutable
  set search_path = public
as $$
declare
  g geometry;
begin
  if coalesce(trim(p_geojson), '') = '' then
    return null;
  end if;

  g := st_setsrid(st_geomfromgeojson(p_geojson), 4326);
  if g is null or st_isempty(g) then
    return null;
  end if;

  if st_geometrytype(g) = 'ST_Polygon' then
    return st_multi(g)::geography;
  elsif st_geometrytype(g) = 'ST_MultiPolygon' then
    return g::geography;
  end if;

  return null;
end;
$$;

create or replace function public._liftr_territory_boundary_from_bbox (
  p_min_lat double precision,
  p_min_lon double precision,
  p_max_lat double precision,
  p_max_lon double precision
)
  returns geography
  language sql
  immutable
as $$
  select st_multi(
    st_makepolygon(
      st_makeline(array[
        st_makepoint(p_min_lon, p_min_lat),
        st_makepoint(p_max_lon, p_min_lat),
        st_makepoint(p_max_lon, p_max_lat),
        st_makepoint(p_min_lon, p_max_lat),
        st_makepoint(p_min_lon, p_min_lat)
      ])
    )
  )::geography;
$$;

create or replace function public._liftr_enqueue_territory_geocode_point (
  p_lat double precision,
  p_lon double precision
)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  bucket record;
begin
  select *
  into bucket
  from public._liftr_territory_city_geocode_bucket(p_lat, p_lon);

  insert into public.territory_city_geocode_queue (
    bucket_lat,
    bucket_lon,
    sample_lat,
    sample_lon
  )
  values (
    bucket.bucket_lat,
    bucket.bucket_lon,
    p_lat,
    p_lon
  )
  on conflict (bucket_lat, bucket_lon) do update
    set
      sample_lat = excluded.sample_lat,
      sample_lon = excluded.sample_lon,
      updated_at = now();
end;
$$;

create or replace function public._liftr_territory_city_key_for_point (
  p_lat double precision,
  p_lon double precision
)
  returns text
  language plpgsql
  stable
  security definer
  set search_path = public
as $$
declare
  bucket record;
  cached_key text;
  matched_key text;
begin
  select *
  into bucket
  from public._liftr_territory_city_geocode_bucket(p_lat, p_lon);

  select c.city_key
  into cached_key
  from public.territory_city_geocode_cache c
  where
    c.bucket_lat = bucket.bucket_lat
    and c.bucket_lon = bucket.bucket_lon
    and c.expires_at > now();

  if cached_key is not null then
    return cached_key;
  end if;

  select m.city_key
  into matched_key
  from public.territory_municipalities m
  where
    m.boundary_geom is not null
    and st_covers(
      m.boundary_geom::geometry,
      st_setsrid(st_makepoint(p_lon, p_lat), 4326)
    )
  order by st_area(m.boundary_geom::geography)
  limit 1;

  if matched_key is not null then
    insert into public.territory_city_geocode_cache (
      bucket_lat,
      bucket_lon,
      city_key
    )
    values (
      bucket.bucket_lat,
      bucket.bucket_lon,
      matched_key
    )
    on conflict (bucket_lat, bucket_lon) do update
      set
        city_key = excluded.city_key,
        resolved_at = now(),
        expires_at = now() + interval '30 days';

    return matched_key;
  end if;

  perform public._liftr_enqueue_territory_geocode_point(p_lat, p_lon);
  return null;
end;
$$;

create or replace function public.ingest_territory_municipality_v1 (
  p_city_key text,
  p_display_name text,
  p_country_code text,
  p_admin_level integer,
  p_boundary_geojson text,
  p_min_lat double precision,
  p_min_lon double precision,
  p_max_lat double precision,
  p_max_lon double precision,
  p_center_lat double precision,
  p_center_lon double precision,
  p_geocode_source text,
  p_display_name_override text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  boundary geography;
  total_cells integer;
begin
  if coalesce(trim(p_city_key), '') = '' then
    raise exception 'city_key_required';
  end if;

  boundary := public._liftr_territory_boundary_from_geojson(p_boundary_geojson);
  if boundary is null then
    boundary := public._liftr_territory_boundary_from_bbox(
      p_min_lat,
      p_min_lon,
      p_max_lat,
      p_max_lon
    );
  end if;

  if boundary is null then
    raise exception 'boundary_required';
  end if;

  total_cells := public._liftr_territory_count_hex_cells_for_geog(boundary);

  insert into public.territory_municipalities (
    city_key,
    display_name,
    display_name_override,
    country_code,
    admin_level,
    boundary_geom,
    center_lat,
    center_lon,
    total_capture_cells,
    geocode_source,
    resolved_at,
    updated_at
  )
  values (
    p_city_key,
    coalesce(nullif(trim(p_display_name), ''), 'Unknown city'),
    nullif(trim(p_display_name_override), ''),
    nullif(trim(p_country_code), ''),
    p_admin_level,
    boundary,
    p_center_lat,
    p_center_lon,
    total_cells,
    coalesce(nullif(trim(p_geocode_source), ''), 'nominatim'),
    now(),
    now()
  )
  on conflict (city_key) do update
    set
      display_name = excluded.display_name,
      display_name_override = coalesce(excluded.display_name_override, public.territory_municipalities.display_name_override),
      country_code = coalesce(excluded.country_code, public.territory_municipalities.country_code),
      admin_level = coalesce(excluded.admin_level, public.territory_municipalities.admin_level),
      boundary_geom = excluded.boundary_geom,
      center_lat = excluded.center_lat,
      center_lon = excluded.center_lon,
      total_capture_cells = coalesce(excluded.total_capture_cells, public.territory_municipalities.total_capture_cells),
      geocode_source = excluded.geocode_source,
      resolved_at = now(),
      updated_at = now();

  insert into public.territory_city_geocode_cache (
    bucket_lat,
    bucket_lon,
    city_key
  )
  select
    bucket.bucket_lat,
    bucket.bucket_lon,
    p_city_key
  from public._liftr_territory_city_geocode_bucket(p_center_lat, p_center_lon) bucket
  on conflict (bucket_lat, bucket_lon) do update
    set
      city_key = excluded.city_key,
      resolved_at = now(),
      expires_at = now() + interval '30 days';

  delete from public.territory_city_geocode_queue q
  using public._liftr_territory_city_geocode_bucket(p_center_lat, p_center_lon) bucket
  where
    q.bucket_lat = bucket.bucket_lat
    and q.bucket_lon = bucket.bucket_lon;

  update public.territory_cells tc
  set city_key = p_city_key
  where
    (
      tc.city_key is null
      or tc.city_key like 'grid:%'
    )
    and st_covers(
      boundary::geometry,
      st_centroid(tc.cell_geog::geometry)
    );

  return jsonb_build_object(
    'ok', true,
    'city_key', p_city_key,
    'display_name', public._liftr_territory_municipality_label(p_display_name, p_display_name_override),
    'total_capture_cells', total_cells
  );
end;
$$;

create or replace function public.list_territory_geocode_queue_v1 (
  p_limit integer default 25
)
  returns table (
    bucket_lat numeric,
    bucket_lon numeric,
    sample_lat double precision,
    sample_lon double precision,
    attempts integer
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  select
    q.bucket_lat,
    q.bucket_lon,
    q.sample_lat,
    q.sample_lon,
    q.attempts
  from public.territory_city_geocode_queue q
  order by q.queued_at
  limit greatest(least(coalesce(p_limit, 25), 100), 1);
$$;

create or replace function public.mark_territory_geocode_queue_error_v1 (
  p_bucket_lat numeric,
  p_bucket_lon numeric,
  p_error text
)
  returns void
  language sql
  security definer
  set search_path = public
as $$
  update public.territory_city_geocode_queue
  set
    attempts = attempts + 1,
    last_error = left(coalesce(p_error, 'unknown'), 500),
    updated_at = now()
  where
    bucket_lat = p_bucket_lat
    and bucket_lon = p_bucket_lon;
$$;

create or replace function public.backfill_territory_municipality_assignments_v1 (
  p_limit integer default 500
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  updated_count integer := 0;
begin
  with candidates as (
    select
      tc.cell_id,
      public._liftr_territory_city_key_for_point(
        st_y(st_centroid(tc.cell_geog::geometry)),
        st_x(st_centroid(tc.cell_geog::geometry))
      ) as resolved_city_key
    from public.territory_cells tc
    where
      tc.city_key is null
      or tc.city_key like 'grid:%'
    limit greatest(least(coalesce(p_limit, 500), 5000), 1)
  ),
  applied as (
    update public.territory_cells tc
    set city_key = c.resolved_city_key
    from candidates c
    where
      tc.cell_id = c.cell_id
      and c.resolved_city_key is not null
    returning tc.cell_id
  )
  select count(*)::integer
  into updated_count
  from applied;

  return jsonb_build_object(
    'ok', true,
    'updated', updated_count
  );
end;
$$;

drop function if exists public.list_territory_city_regions_v1();

create or replace function public.list_territory_city_regions_v1 ()
returns table (
  city_key text,
  display_name text,
  center_lat double precision,
  center_lon double precision,
  captured_cells integer,
  total_capture_cells integer
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    m.city_key,
    public._liftr_territory_municipality_label(m.display_name, m.display_name_override) as display_name,
    m.center_lat,
    m.center_lon,
    count(tc.cell_id)::integer as captured_cells,
    m.total_capture_cells
  from public.territory_municipalities m
    inner join public.territory_cells tc on tc.city_key = m.city_key
  group by
    m.city_key,
    m.display_name,
    m.display_name_override,
    m.center_lat,
    m.center_lon,
    m.total_capture_cells
  order by captured_cells desc, display_name;
$$;

create or replace function public.get_territory_city_share_leaderboard_v1 (
  p_city_key text,
  p_scope text,
  p_limit integer default 100
)
returns table (
  rank integer,
  user_id uuid,
  username text,
  avatar_url text,
  owned_cells integer,
  territory_share_pct numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  city_total numeric;
begin
  select coalesce(m.total_capture_cells, 0)::numeric
  into city_total
  from public.territory_municipalities m
  where m.city_key = p_city_key;

  if city_total is null or city_total <= 0 then
    select count(*)::numeric
    into city_total
    from public.territory_cells tc
    where tc.city_key = p_city_key;
  end if;

  return query
  with owned as (
    select
      tc.owner_user_id as uid,
      count(*)::integer as owned_cells
    from public.territory_cells tc
    where tc.city_key = p_city_key
    group by tc.owner_user_id
  ),
  scoped as (
    select
      o.uid,
      o.owned_cells,
      greatest(city_total, 1) as total_cells
    from owned o
    inner join public.profiles pr on pr.user_id = o.uid
    where
      coalesce(p_scope, 'global') = 'global'
      or pr.user_id = auth.uid()
      or exists (
        select 1
        from public.follows f
        where f.follower_id = auth.uid()
          and f.followee_id = pr.user_id
      )
  ),
  ordered as (
    select
      s.uid,
      s.owned_cells,
      round(100.0 * s.owned_cells::numeric / s.total_cells, 2) as territory_share_pct,
      row_number() over (
        order by s.owned_cells desc, s.uid
      ) as rnk
    from scoped s
  )
  select
    o.rnk::integer as rank,
    o.uid as user_id,
    pr.username,
    pr.avatar_url,
    o.owned_cells,
    o.territory_share_pct
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  order by o.rnk
  limit greatest(least(coalesce(p_limit, 100), 200), 1);
end;
$$;

insert into public.territory_city_geocode_queue (
  bucket_lat,
  bucket_lon,
  sample_lat,
  sample_lon
)
select distinct on (bucket.bucket_lat, bucket.bucket_lon)
  bucket.bucket_lat,
  bucket.bucket_lon,
  st_y(st_centroid(tc.cell_geog::geometry)) as sample_lat,
  st_x(st_centroid(tc.cell_geog::geometry)) as sample_lon
from public.territory_cells tc
  cross join lateral public._liftr_territory_city_geocode_bucket(
    st_y(st_centroid(tc.cell_geog::geometry)),
    st_x(st_centroid(tc.cell_geog::geometry))
  ) bucket
where
  tc.city_key is null
  or tc.city_key like 'grid:%'
on conflict (bucket_lat, bucket_lon) do nothing;

revoke all on function public.ingest_territory_municipality_v1 (
  text,
  text,
  text,
  integer,
  text,
  double precision,
  double precision,
  double precision,
  double precision,
  double precision,
  double precision,
  text,
  text
) from public, anon, authenticated;

revoke all on function public.list_territory_geocode_queue_v1 (integer) from public, anon, authenticated;
revoke all on function public.mark_territory_geocode_queue_error_v1 (numeric, numeric, text) from public, anon, authenticated;

grant execute on function public.ingest_territory_municipality_v1 (
  text,
  text,
  text,
  integer,
  text,
  double precision,
  double precision,
  double precision,
  double precision,
  double precision,
  double precision,
  text,
  text
) to service_role;

grant execute on function public.list_territory_geocode_queue_v1 (integer) to service_role;
grant execute on function public.mark_territory_geocode_queue_error_v1 (numeric, numeric, text) to service_role;
grant execute on function public.backfill_territory_municipality_assignments_v1 (integer) to authenticated, service_role;
grant execute on function public.list_territory_city_regions_v1 () to authenticated;
grant execute on function public.get_territory_city_share_leaderboard_v1 (text, text, integer) to authenticated;

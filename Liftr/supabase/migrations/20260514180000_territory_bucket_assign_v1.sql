create or replace function public.assign_territory_cells_for_geocode_bucket_v1 (
  p_bucket_lat numeric,
  p_bucket_lon numeric,
  p_city_key text
)
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  updated_count integer;
begin
  if coalesce(trim(p_city_key), '') = '' then
    raise exception 'city_key_required';
  end if;

  with candidates as (
    select
      tc.cell_id
    from public.territory_cells tc
      cross join lateral public._liftr_territory_city_geocode_bucket(
        st_y(st_centroid(tc.cell_geog::geometry)),
        st_x(st_centroid(tc.cell_geog::geometry))
      ) bucket
    where
      (
        tc.city_key is null
        or tc.city_key like 'grid:%'
      )
      and bucket.bucket_lat = p_bucket_lat
      and bucket.bucket_lon = p_bucket_lon
  )
  update public.territory_cells tc
  set city_key = p_city_key
  from candidates c
  where tc.cell_id = c.cell_id;

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

grant execute on function public.assign_territory_cells_for_geocode_bucket_v1 (
  numeric,
  numeric,
  text
) to authenticated, service_role;

create or replace function public.backfill_territory_municipality_assignments_v1 (
  p_limit integer default 200
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  batch_size integer;
  batch_updated integer;
  has_more boolean;
begin
  batch_size := greatest(least(coalesce(p_limit, 200), 5000), 1);

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
    limit batch_size
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
  into batch_updated
  from applied;

  select exists (
    select 1
    from public.territory_cells tc
    where
      tc.city_key is null
      or tc.city_key like 'grid:%'
    limit 1
  )
  into has_more;

  return jsonb_build_object(
    'ok', true,
    'updated', batch_updated,
    'has_more', has_more
  );
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
  p_display_name_override text default null,
  p_bucket_lat numeric default null,
  p_bucket_lon numeric default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  boundary geography;
  total_cells integer;
  target_bucket_lat numeric;
  target_bucket_lon numeric;
  bucket_assigned_cells integer := 0;
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

  begin
    total_cells := public._liftr_territory_count_hex_cells_for_geog(boundary);
  exception
    when others then
      total_cells := null;
  end;

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

  select
    coalesce(p_bucket_lat, bucket.bucket_lat),
    coalesce(p_bucket_lon, bucket.bucket_lon)
  into target_bucket_lat, target_bucket_lon
  from public._liftr_territory_city_geocode_bucket(p_center_lat, p_center_lon) bucket;

  insert into public.territory_city_geocode_cache (
    bucket_lat,
    bucket_lon,
    city_key
  )
  values (
    target_bucket_lat,
    target_bucket_lon,
    p_city_key
  )
  on conflict (bucket_lat, bucket_lon) do update
    set
      city_key = excluded.city_key,
      resolved_at = now(),
      expires_at = now() + interval '30 days';

  delete from public.territory_city_geocode_queue q
  where
    q.bucket_lat = target_bucket_lat
    and q.bucket_lon = target_bucket_lon;

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

  bucket_assigned_cells := public.assign_territory_cells_for_geocode_bucket_v1(
    target_bucket_lat,
    target_bucket_lon,
    p_city_key
  );

  return jsonb_build_object(
    'ok', true,
    'city_key', p_city_key,
    'display_name', public._liftr_territory_municipality_label(p_display_name, p_display_name_override),
    'total_capture_cells', total_cells,
    'bucket_lat', target_bucket_lat,
    'bucket_lon', target_bucket_lon,
    'bucket_assigned_cells', bucket_assigned_cells
  );
end;
$$;

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
  text,
  numeric,
  numeric
) to authenticated, service_role;

grant execute on function public.backfill_territory_municipality_assignments_v1 (integer) to authenticated, service_role;

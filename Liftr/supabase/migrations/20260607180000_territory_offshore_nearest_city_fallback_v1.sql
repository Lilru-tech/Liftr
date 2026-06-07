create or replace function public._liftr_territory_city_key_for_point (
  p_lat double precision,
  p_lon double precision
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  bucket record;
  cached_key text;
  matched_key text;
  point_geog geography;
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

  point_geog := st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography;

  select m.city_key
  into matched_key
  from public.territory_municipalities m
  where
    m.boundary_geom is not null
    and st_covers(
      m.boundary_geom::geometry,
      point_geog::geometry
    )
  order by st_area(m.boundary_geom::geography)
  limit 1;

  if matched_key is null then
    select m.city_key
    into matched_key
    from public.territory_municipalities m
    where
      m.boundary_geom is not null
      and st_dwithin(m.boundary_geom::geography, point_geog, 15000)
    order by st_distance(m.boundary_geom::geography, point_geog)
    limit 1;
  end if;

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

create or replace function public.reconcile_unassigned_territory_cells_v1 (
  p_limit integer default 500
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
  batch_size := greatest(least(coalesce(p_limit, 500), 5000), 1);

  with candidates as (
    select
      tc.cell_id,
      public._liftr_territory_city_key_for_point(
        st_y(st_centroid(tc.cell_geog::geometry)),
        st_x(st_centroid(tc.cell_geog::geometry))
      ) as resolved_city_key
    from public.territory_cells tc
    where
      (
        tc.city_key is null
        or tc.city_key like 'grid:%'
      )
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
  )
  into has_more;

  delete from public.territory_city_geocode_queue q
  where not exists (
    select 1
    from public.territory_cells tc
      cross join lateral public._liftr_territory_city_geocode_bucket(
        st_y(st_centroid(tc.cell_geog::geometry)),
        st_x(st_centroid(tc.cell_geog::geometry))
      ) bucket
    where
      bucket.bucket_lat = q.bucket_lat
      and bucket.bucket_lon = q.bucket_lon
      and (
        tc.city_key is null
        or tc.city_key like 'grid:%'
      )
  );

  return jsonb_build_object(
    'ok', true,
    'updated', batch_updated,
    'has_more', has_more
  );
end;
$$;

grant execute on function public.reconcile_unassigned_territory_cells_v1(integer) to authenticated;

select public.reconcile_unassigned_territory_cells_v1(5000) as reconcile_unassigned_cells;

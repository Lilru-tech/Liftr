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

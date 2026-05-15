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
  with
  effective_limit as (
    select greatest(least(coalesce(p_limit, 500), 2000), 1) as n
  ),
  bbox as (
    select st_makeenvelope(
      least(p_min_lon, p_max_lon),
      least(p_min_lat, p_max_lat),
      greatest(p_min_lon, p_max_lon),
      greatest(p_min_lat, p_max_lat),
      4326
    )::geography as geog
  ),
  mine as (
    select
      tc.cell_id,
      st_asgeojson(tc.cell_geog::geometry)::jsonb as cell_geojson,
      tc.owner_user_id,
      p.username as owner_username,
      p.avatar_url as owner_avatar_url,
      tc.captured_at,
      true as is_mine
    from public.territory_cells tc
      join bbox b on st_intersects(tc.cell_geog, b.geog)
      left join public.profiles p on p.user_id = tc.owner_user_id
    where tc.owner_user_id = auth.uid ()
  ),
  mine_count as (
    select count(*)::integer as n
    from mine
  ),
  others_ranked as (
    select
      tc.cell_id,
      st_asgeojson(tc.cell_geog::geometry)::jsonb as cell_geojson,
      tc.owner_user_id,
      p.username as owner_username,
      p.avatar_url as owner_avatar_url,
      tc.captured_at,
      false as is_mine,
      row_number() over (order by tc.captured_at desc) as rn
    from public.territory_cells tc
      join bbox b on st_intersects(tc.cell_geog, b.geog)
      left join public.profiles p on p.user_id = tc.owner_user_id
    where tc.owner_user_id is distinct from auth.uid ()
  ),
  others as (
    select
      o.cell_id,
      o.cell_geojson,
      o.owner_user_id,
      o.owner_username,
      o.owner_avatar_url,
      o.captured_at,
      o.is_mine
    from others_ranked o
      cross join effective_limit el
      cross join mine_count mc
    where o.rn <= greatest(el.n - mc.n, 0)
  )
  select * from mine
  union all
  select * from others;
$$;

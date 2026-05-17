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
  budget_targets as (
    select
      ceil(n * 0.60)::integer as mine_target,
      (n - ceil(n * 0.60)::integer) as others_target,
      n
    from effective_limit
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
  mine_total as (
    select count(*)::integer as n
    from public.territory_cells tc
      join bbox b on st_intersects(tc.cell_geog, b.geog)
    where tc.owner_user_id = auth.uid ()
  ),
  others_total as (
    select count(*)::integer as n
    from public.territory_cells tc
      join bbox b on st_intersects(tc.cell_geog, b.geog)
    where tc.owner_user_id is distinct from auth.uid ()
  ),
  mine_budget as (
    select least(
      mt.n,
      case
        when ot.n < bt.others_target then greatest(bt.n - ot.n, 0)
        else bt.mine_target
      end
    )::integer as n
    from budget_targets bt
      cross join mine_total mt
      cross join others_total ot
  ),
  others_budget as (
    select least(
      ot.n,
      greatest(bt.n - mb.n, 0)
    )::integer as n
    from budget_targets bt
      cross join mine_budget mb
      cross join others_total ot
  ),
  mine_ranked as (
    select
      tc.cell_id,
      st_asgeojson(tc.cell_geog::geometry)::jsonb as cell_geojson,
      tc.owner_user_id,
      p.username as owner_username,
      p.avatar_url as owner_avatar_url,
      tc.captured_at,
      true as is_mine,
      row_number() over (order by tc.captured_at desc) as rn
    from public.territory_cells tc
      join bbox b on st_intersects(tc.cell_geog, b.geog)
      left join public.profiles p on p.user_id = tc.owner_user_id
    where tc.owner_user_id = auth.uid ()
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
  )
  select
    m.cell_id,
    m.cell_geojson,
    m.owner_user_id,
    m.owner_username,
    m.owner_avatar_url,
    m.captured_at,
    m.is_mine
  from mine_ranked m
    cross join mine_budget mb
  where m.rn <= mb.n
  union all
  select
    o.cell_id,
    o.cell_geojson,
    o.owner_user_id,
    o.owner_username,
    o.owner_avatar_url,
    o.captured_at,
    o.is_mine
  from others_ranked o
    cross join others_budget ob
  where o.rn <= ob.n;
$$;

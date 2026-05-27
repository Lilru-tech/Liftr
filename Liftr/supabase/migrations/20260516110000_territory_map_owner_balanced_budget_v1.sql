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
  spatial_candidates as materialized (
    select
      tc.cell_id,
      tc.cell_geog,
      tc.owner_user_id,
      tc.captured_at,
      (tc.owner_user_id = auth.uid ()) as is_mine
    from public.territory_cells tc
      join bbox b on st_intersects(tc.cell_geog, b.geog)
  ),
  candidate_totals as (
    select
      count(*) filter (where is_mine)::integer as mine_count,
      count(*) filter (where not is_mine)::integer as others_count
    from spatial_candidates
  ),
  mine_budget as (
    select least(
      ct.mine_count,
      case
        when ct.others_count < bt.others_target then greatest(bt.n - ct.others_count, 0)
        else bt.mine_target
      end
    )::integer as n
    from budget_targets bt
      cross join candidate_totals ct
  ),
  others_budget as (
    select least(
      ct.others_count,
      greatest(bt.n - mb.n, 0)
    )::integer as n
    from budget_targets bt
      cross join mine_budget mb
      cross join candidate_totals ct
  ),
  mine_ranked as (
    select
      sc.cell_id,
      sc.cell_geog,
      sc.owner_user_id,
      sc.captured_at,
      sc.is_mine,
      row_number() over (
        order by sc.captured_at desc, sc.cell_id
      ) as rank_in_budget
    from spatial_candidates sc
    where sc.is_mine
  ),
  others_ranked_by_owner as (
    select
      sc.cell_id,
      sc.cell_geog,
      sc.owner_user_id,
      sc.captured_at,
      sc.is_mine,
      row_number() over (
        partition by sc.owner_user_id
        order by sc.captured_at desc, sc.cell_id
      ) as owner_rank
    from spatial_candidates sc
    where not sc.is_mine
  ),
  others_balanced as (
    select
      oro.cell_id,
      oro.cell_geog,
      oro.owner_user_id,
      oro.captured_at,
      oro.is_mine,
      row_number() over (
        order by oro.owner_rank, oro.captured_at desc, oro.owner_user_id, oro.cell_id
      ) as rank_in_budget
    from others_ranked_by_owner oro
  ),
  selected_cells as (
    select
      m.cell_id,
      m.cell_geog,
      m.owner_user_id,
      m.captured_at,
      m.is_mine
    from mine_ranked m
      cross join mine_budget mb
    where m.rank_in_budget <= mb.n
    union all
    select
      o.cell_id,
      o.cell_geog,
      o.owner_user_id,
      o.captured_at,
      o.is_mine
    from others_balanced o
      cross join others_budget ob
    where o.rank_in_budget <= ob.n
  )
  select
    sc.cell_id,
    st_asgeojson(sc.cell_geog::geometry)::jsonb as cell_geojson,
    sc.owner_user_id,
    p.username as owner_username,
    p.avatar_url as owner_avatar_url,
    sc.captured_at,
    sc.is_mine
  from selected_cells sc
    left join public.profiles p on p.user_id = sc.owner_user_id
  order by sc.is_mine desc, sc.captured_at desc, sc.cell_id;
$$;

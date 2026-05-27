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
    last_workout_id bigint,
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
    select greatest(least(coalesce(p_limit, 500), 5000), 1) as n
  ),
  bounds as (
    select
      p_min_lat <= -90
        and p_min_lon <= -180
        and p_max_lat >= 90
        and p_max_lon >= 180 as fetch_all,
      greatest(p_max_lat - p_min_lat, p_max_lon - p_min_lon) as span_deg,
      case
        when p_min_lat <= -90
          and p_min_lon <= -180
          and p_max_lat >= 90
          and p_max_lon >= 180
        then null::geography
        else st_makeenvelope(
          least(p_min_lon, p_max_lon),
          least(p_min_lat, p_max_lat),
          greatest(p_min_lon, p_max_lon),
          greatest(p_min_lat, p_max_lat),
          4326
        )::geography
      end as geog
  ),
  spatial_candidates as materialized (
    select
      tc.cell_id,
      tc.cell_geog,
      tc.owner_user_id,
      tc.last_workout_id,
      tc.captured_at,
      ((tc.owner_user_id = auth.uid ()) is true) as is_mine
    from public.territory_cells tc
      cross join bounds b
    where b.fetch_all or st_intersects(tc.cell_geog, b.geog)
  ),
  mine_count as (
    select count(*)::integer as n
    from spatial_candidates sc
    where sc.is_mine
  ),
  other_route_groups as (
    select
      sc.owner_user_id,
      coalesce(sc.last_workout_id::text, sc.cell_id) as route_key,
      max(sc.captured_at) as route_captured_at,
      count(*)::integer as route_size
    from spatial_candidates sc
    where not sc.is_mine
    group by sc.owner_user_id, coalesce(sc.last_workout_id::text, sc.cell_id)
  ),
  other_route_groups_ranked as (
    select
      org.*,
      row_number() over (
        partition by org.owner_user_id
        order by org.route_captured_at desc, org.route_key
      ) as owner_route_rank
    from other_route_groups org
  ),
  other_route_groups_budgeted as (
    select
      orgr.*,
      sum(orgr.route_size) over (
        order by orgr.owner_route_rank, orgr.route_captured_at desc, orgr.owner_user_id, orgr.route_key
      ) as running_cells
    from other_route_groups_ranked orgr
  ),
  selected_other_route_groups as (
    select orgb.owner_user_id, orgb.route_key
    from other_route_groups_budgeted orgb
      cross join effective_limit el
    where orgb.running_cells <= el.n
  ),
  selected_others_from_routes as (
    select
      sc.cell_id,
      sc.cell_geog,
      sc.owner_user_id,
      sc.last_workout_id,
      sc.captured_at,
      sc.is_mine
    from spatial_candidates sc
      join selected_other_route_groups sorg
        on sorg.owner_user_id = sc.owner_user_id
       and sorg.route_key = coalesce(sc.last_workout_id::text, sc.cell_id)
    where not sc.is_mine
  ),
  selected_others_from_routes_count as (
    select count(*)::integer as n
    from selected_others_from_routes
  ),
  other_cells_ranked as (
    select
      sc.cell_id,
      sc.cell_geog,
      sc.owner_user_id,
      sc.last_workout_id,
      sc.captured_at,
      sc.is_mine,
      row_number() over (
        order by sc.captured_at desc, sc.cell_id
      ) as rank_in_budget
    from spatial_candidates sc
    where not sc.is_mine
  ),
  selected_others_fallback as (
    select
      o.cell_id,
      o.cell_geog,
      o.owner_user_id,
      o.last_workout_id,
      o.captured_at,
      o.is_mine
    from other_cells_ranked o
      cross join effective_limit el
      cross join mine_count mc
      cross join selected_others_from_routes_count soc
    where soc.n = 0
      and o.rank_in_budget <= greatest(el.n - least(mc.n, el.n / 3), el.n / 2)
  ),
  selected_others as (
    select * from selected_others_from_routes
    union all
    select * from selected_others_fallback
  ),
  selected_others_count as (
    select count(*)::integer as n
    from selected_others
  ),
  mine_ranked as (
    select
      sc.cell_id,
      sc.cell_geog,
      sc.owner_user_id,
      sc.last_workout_id,
      sc.captured_at,
      sc.is_mine,
      row_number() over (
        order by sc.captured_at desc, sc.cell_id
      ) as rank_in_budget
    from spatial_candidates sc
    where sc.is_mine
  ),
  selected_mine as (
    select
      m.cell_id,
      m.cell_geog,
      m.owner_user_id,
      m.last_workout_id,
      m.captured_at,
      m.is_mine
    from mine_ranked m
      cross join selected_others_count soc
      cross join effective_limit el
    where m.rank_in_budget <= greatest(el.n - soc.n, 0)
  ),
  selected_cells as (
    select * from selected_others
    union all
    select * from selected_mine
  ),
  geo_tolerance as (
    select greatest(
      0.000006,
      least(0.00004, (b.span_deg / 180.0))
    ) as tol
    from bounds b
  )
  select
    sc.cell_id,
    st_asgeojson(
      st_simplifypreservetopology(
        sc.cell_geog::geometry,
        gt.tol
      )
    )::jsonb as cell_geojson,
    sc.owner_user_id,
    p.username as owner_username,
    p.avatar_url as owner_avatar_url,
    sc.last_workout_id,
    sc.captured_at,
    sc.is_mine
  from selected_cells sc
    cross join geo_tolerance gt
    left join public.profiles p on p.user_id = sc.owner_user_id
  order by sc.is_mine asc, sc.captured_at desc, sc.cell_id;
$$;

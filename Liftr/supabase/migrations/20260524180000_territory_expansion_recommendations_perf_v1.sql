create or replace function public.get_recommended_expansion_cells_v1 (
  p_user_id uuid,
  p_current_lat double precision,
  p_current_lng double precision,
  p_radius_meters double precision default 5000
)
  returns table (
    cell_id text,
    cell_geojson jsonb,
    weight_priority integer
  )
  language plpgsql
  stable
  security definer
  set search_path = public
as $$
declare
  v_radius double precision;
  v_user_point geography;
begin
  if auth.uid() is null or p_user_id is distinct from auth.uid() then
    return;
  end if;

  v_radius := least(greatest(coalesce(p_radius_meters, 5000), 100), 15000);
  v_user_point := st_setsrid(st_makepoint(p_current_lng, p_current_lat), 4326)::geography;

  return query
  with
  user_cells as (
    select
      tc.cell_id,
      tc.cell_geog,
      tc.city_key,
      st_distance(st_centroid(tc.cell_geog::geometry), v_user_point::geometry) as dist_m
    from public.territory_cells tc
    where tc.owner_user_id = p_user_id
      and st_dwithin(tc.cell_geog, v_user_point, v_radius)
  ),
  user_cells_frontier as (
    select
      uc.cell_id,
      uc.cell_geog,
      uc.city_key,
      uc.dist_m
    from user_cells uc
    order by uc.dist_m asc, uc.cell_id asc
    limit 60
  ),
  user_cities as (
    select distinct uc.city_key
    from user_cells uc
    where uc.city_key is not null
      and uc.city_key not like 'grid:%'
      and uc.city_key not like 'pending:%'
  ),
  city_owned as (
    select
      tc.city_key,
      tc.owner_user_id,
      count(*)::integer as owned_cells
    from public.territory_cells tc
      inner join user_cities c on c.city_key = tc.city_key
    group by tc.city_key, tc.owner_user_id
  ),
  city_ranked as (
    select
      co.city_key,
      co.owner_user_id,
      co.owned_cells,
      row_number() over (
        partition by co.city_key
        order by co.owned_cells desc, co.owner_user_id
      ) as rnk
    from city_owned co
  ),
  city_leader as (
    select
      cr.city_key,
      cr.owner_user_id as leader_id
    from city_ranked cr
    where cr.rnk = 1
  ),
  user_city_rank as (
    select
      cr.city_key,
      cr.rnk
    from city_ranked cr
    where cr.owner_user_id = p_user_id
  ),
  chase_cities as (
    select uc.city_key
    from user_cities uc
      left join user_city_rank ucr on ucr.city_key = uc.city_key
    where coalesce(ucr.rnk, 999) > 1
  ),
  p1_candidates as (
    select
      tc.cell_id,
      tc.cell_geog,
      1 as weight_priority,
      case when tc.owner_user_id = cl.leader_id then 0 else 1 end as leader_sort,
      st_distance(st_centroid(tc.cell_geog::geometry), v_user_point::geometry) as dist_m
    from public.territory_cells tc
      inner join chase_cities cc on cc.city_key = tc.city_key
      left join city_leader cl on cl.city_key = tc.city_key
    where tc.owner_user_id <> p_user_id
      and st_dwithin(tc.cell_geog, v_user_point, v_radius)
  ),
  adjacent_contested as (
    select distinct on (tc2.cell_id)
      tc2.cell_id,
      tc2.cell_geog,
      st_distance(st_centroid(tc2.cell_geog::geometry), v_user_point::geometry) as dist_m
    from user_cells_frontier uc
      inner join public.territory_cells tc2
        on tc2.cell_id <> uc.cell_id
        and st_dwithin(uc.cell_geog, tc2.cell_geog, 30)
    where tc2.owner_user_id <> p_user_id
      and st_dwithin(tc2.cell_geog, v_user_point, v_radius)
    order by tc2.cell_id, st_distance(st_centroid(tc2.cell_geog::geometry), v_user_point::geometry)
  ),
  neighbor_uncaptured as (
    select distinct on (nh.cell_id)
      nh.cell_id,
      nh.cell_geog,
      st_distance(st_centroid(nh.cell_geog::geometry), v_user_point::geometry) as dist_m
    from user_cells_frontier uc
      cross join lateral public._liftr_territory_hex_cells_from_geog(
        st_buffer(uc.cell_geog::geometry, 50)::geography,
        25.0
      ) nh
      left join public.territory_cells tc on tc.cell_id = nh.cell_id
    where nh.cell_id <> uc.cell_id
      and st_touches(uc.cell_geog::geometry, nh.cell_geog::geometry)
      and tc.cell_id is null
      and st_dwithin(nh.cell_geog, v_user_point, v_radius)
    order by nh.cell_id
  ),
  p2_candidates as (
    select
      ac.cell_id,
      ac.cell_geog,
      2 as weight_priority,
      0 as leader_sort,
      ac.dist_m
    from adjacent_contested ac
    union all
    select
      nu.cell_id,
      nu.cell_geog,
      2 as weight_priority,
      0 as leader_sort,
      nu.dist_m
    from neighbor_uncaptured nu
  ),
  combined as (
    select
      p1.cell_id,
      p1.cell_geog,
      p1.weight_priority,
      p1.leader_sort,
      p1.dist_m
    from p1_candidates p1
    union all
    select
      p2.cell_id,
      p2.cell_geog,
      p2.weight_priority,
      p2.leader_sort,
      p2.dist_m
    from p2_candidates p2
  ),
  deduped as (
    select distinct on (c.cell_id)
      c.cell_id,
      c.cell_geog,
      c.weight_priority
    from combined c
    order by c.cell_id, c.weight_priority asc, c.leader_sort asc, c.dist_m asc
  )
  select
    d.cell_id,
    st_asgeojson(d.cell_geog::geometry)::jsonb as cell_geojson,
    d.weight_priority
  from deduped d
  order by
    d.weight_priority asc,
    st_distance(st_centroid(d.cell_geog::geometry), v_user_point::geometry) asc,
    d.cell_id asc
  limit 10;
end;
$$;

grant execute on function public.get_recommended_expansion_cells_v1 (
  uuid,
  double precision,
  double precision,
  double precision
) to authenticated;

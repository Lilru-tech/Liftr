create or replace function public.get_recommended_expansion_cells_v1 (
  p_user_id uuid,
  p_current_lat double precision,
  p_current_lng double precision,
  p_radius_meters double precision default 12000
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

  if not exists (
    select 1
    from public.territory_cells tc
    where tc.owner_user_id = p_user_id
  ) then
    return;
  end if;

  v_radius := least(greatest(coalesce(p_radius_meters, 12000), 500), 25000);
  v_user_point := st_setsrid(st_makepoint(p_current_lng, p_current_lat), 4326)::geography;

  return query
  with
  user_owned_ranked as (
    select
      tc.cell_id,
      tc.cell_geog,
      tc.city_key,
      st_distance(st_centroid(tc.cell_geog::geometry), v_user_point::geometry) as dist_m
    from public.territory_cells tc
    where tc.owner_user_id = p_user_id
  ),
  user_cells_in_radius as (
    select uor.cell_id, uor.cell_geog, uor.city_key, uor.dist_m
    from user_owned_ranked uor
    where uor.dist_m <= v_radius
  ),
  user_cells_frontier as (
    select uor.cell_id, uor.cell_geog, uor.city_key, uor.dist_m
    from user_owned_ranked uor
    order by uor.dist_m asc, uor.cell_id asc
    limit 60
  ),
  user_cities as (
    select distinct src.city_key
    from (
      select ucr.city_key
      from user_cells_in_radius ucr
      union all
      select ucf.city_key
      from user_cells_frontier ucf
    ) src
    where src.city_key is not null
      and src.city_key not like 'grid:%'
      and src.city_key not like 'pending:%'
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
    select cr.city_key, cr.owner_user_id as leader_id
    from city_ranked cr
    where cr.rnk = 1
  ),
  user_city_rank as (
    select cr.city_key, cr.rnk
    from city_ranked cr
    where cr.owner_user_id = p_user_id
  ),
  chase_cities as (
    select uc.city_key
    from user_cities uc
      left join user_city_rank ucr on ucr.city_key = uc.city_key
    where coalesce(ucr.rnk, 999) > 1
  ),
  p1_chase as (
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
  p1_contested as (
    select
      tc.cell_id,
      tc.cell_geog,
      1 as weight_priority,
      1 as leader_sort,
      st_distance(st_centroid(tc.cell_geog::geometry), v_user_point::geometry) as dist_m
    from public.territory_cells tc
      inner join user_cities uc on uc.city_key = tc.city_key
    where tc.owner_user_id <> p_user_id
      and st_dwithin(tc.cell_geog, v_user_point, v_radius)
      and not exists (select 1 from chase_cities cc where cc.city_key = tc.city_key)
  ),
  p2_adjacent as (
    select distinct on (tc2.cell_id)
      tc2.cell_id,
      tc2.cell_geog,
      2 as weight_priority,
      0 as leader_sort,
      st_distance(st_centroid(tc2.cell_geog::geometry), v_user_point::geometry) as dist_m
    from user_cells_frontier uc
      inner join public.territory_cells tc2
        on tc2.cell_id <> uc.cell_id
        and (
          st_touches(uc.cell_geog::geometry, tc2.cell_geog::geometry)
          or st_dwithin(uc.cell_geog, tc2.cell_geog, 36)
        )
    where tc2.owner_user_id <> p_user_id
      and st_dwithin(tc2.cell_geog, v_user_point, v_radius)
    order by tc2.cell_id
  ),
  combined as (
    select * from p1_chase
    union all
    select * from p1_contested
    union all
    select * from p2_adjacent
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

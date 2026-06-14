create or replace function public.list_territory_city_regions_v1 (
  p_query text default null,
  p_limit integer default 200,
  p_owned_first boolean default true
)
returns table (
  city_key text,
  display_name text,
  center_lat double precision,
  center_lon double precision,
  captured_cells integer,
  total_capture_cells integer,
  my_owned_cells integer
)
language sql
stable
security definer
set search_path = public
as $$
  with cities as (
    select
      m.city_key,
      public._liftr_territory_municipality_label(m.display_name, m.display_name_override) as display_name,
      m.center_lat,
      m.center_lon,
      count(tc.cell_id)::integer as captured_cells,
      greatest(coalesce(m.total_capture_cells, 0), count(tc.cell_id)::integer) as total_capture_cells,
      count(*) filter (where tc.owner_user_id = auth.uid())::integer as my_owned_cells
    from public.territory_municipalities m
      inner join public.territory_cells tc on tc.city_key = m.city_key
    group by
      m.city_key,
      m.display_name,
      m.display_name_override,
      m.center_lat,
      m.center_lon,
      m.total_capture_cells
    union all
    select
      format('pending:%s:%s', bucket.bucket_lat, bucket.bucket_lon) as city_key,
      format(
        'Resolving area · %s, %s',
        bucket.bucket_lat::text,
        bucket.bucket_lon::text
      ) as display_name,
      avg(st_y(st_centroid(tc.cell_geog::geometry)))::double precision as center_lat,
      avg(st_x(st_centroid(tc.cell_geog::geometry)))::double precision as center_lon,
      count(*)::integer as captured_cells,
      count(*)::integer as total_capture_cells,
      count(*) filter (where tc.owner_user_id = auth.uid())::integer as my_owned_cells
    from public.territory_cells tc
      cross join lateral public._liftr_territory_city_geocode_bucket(
        st_y(st_centroid(tc.cell_geog::geometry)),
        st_x(st_centroid(tc.cell_geog::geometry))
      ) bucket
    where
      tc.city_key is null
      or tc.city_key like 'grid:%'
    group by
      bucket.bucket_lat,
      bucket.bucket_lon
  )
  select
    c.city_key,
    c.display_name,
    c.center_lat,
    c.center_lon,
    c.captured_cells,
    c.total_capture_cells,
    c.my_owned_cells
  from cities c
  where
    coalesce(trim(p_query), '') = ''
    or c.display_name ilike '%' || trim(p_query) || '%'
    or c.city_key ilike '%' || trim(p_query) || '%'
  order by
    case when coalesce(p_owned_first, true) then c.my_owned_cells end desc nulls last,
    c.captured_cells desc,
    c.display_name
  limit greatest(least(coalesce(p_limit, 200), 500), 1);
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
security definer
set search_path = public
as $$
declare
  city_total numeric;
  pending_bucket_lat numeric;
  pending_bucket_lon numeric;
  pending_parts text[];
begin
  if coalesce(p_city_key, '') like 'pending:%' then
    pending_parts := string_to_array(p_city_key, ':');
    if coalesce(array_length(pending_parts, 1), 0) < 3 then
      return;
    end if;

    pending_bucket_lat := pending_parts[2]::numeric;
    pending_bucket_lon := pending_parts[3]::numeric;

    select count(*)::numeric
    into city_total
    from public.territory_cells tc
      cross join lateral public._liftr_territory_city_geocode_bucket(
        st_y(st_centroid(tc.cell_geog::geometry)),
        st_x(st_centroid(tc.cell_geog::geometry))
      ) bucket
    where
      bucket.bucket_lat = pending_bucket_lat
      and bucket.bucket_lon = pending_bucket_lon
      and (
        tc.city_key is null
        or tc.city_key like 'grid:%'
      );

    return query
    with owned as (
      select
        tc.owner_user_id as uid,
        count(*)::integer as owned_cells
      from public.territory_cells tc
        cross join lateral public._liftr_territory_city_geocode_bucket(
          st_y(st_centroid(tc.cell_geog::geometry)),
          st_x(st_centroid(tc.cell_geog::geometry))
        ) bucket
      where
        bucket.bucket_lat = pending_bucket_lat
        and bucket.bucket_lon = pending_bucket_lon
        and (
          tc.city_key is null
          or tc.city_key like 'grid:%'
        )
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

    return;
  end if;

  select greatest(coalesce(m.total_capture_cells, 0), count(tc.cell_id))::numeric
  into city_total
  from public.territory_municipalities m
    left join public.territory_cells tc on tc.city_key = m.city_key
  where m.city_key = p_city_key
  group by m.total_capture_cells;

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

create or replace function public.list_user_territory_top_cities_v1 (
  p_user_id uuid,
  p_limit integer default 3
)
returns table (
  city_key text,
  display_name text,
  center_lat double precision,
  center_lon double precision,
  captured_cells integer,
  total_capture_cells integer,
  owned_cells integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
  grouped.city_key,
  grouped.display_name,
  grouped.center_lat,
  grouped.center_lon,
  grouped.captured_cells,
  grouped.total_capture_cells,
  grouped.owned_cells
  from (
    select
      tc.city_key,
      coalesce(
        public._liftr_territory_municipality_label(m.display_name, m.display_name_override),
        tc.city_key
      ) as display_name,
      m.center_lat,
      m.center_lon,
      count(tc.cell_id)::integer as captured_cells,
      m.total_capture_cells,
      count(tc.cell_id)::integer as owned_cells
    from public.territory_cells tc
      left join public.territory_municipalities m on m.city_key = tc.city_key
    where tc.owner_user_id = p_user_id
    group by
      tc.city_key,
      m.display_name,
      m.display_name_override,
      m.center_lat,
      m.center_lon,
      m.total_capture_cells
    order by count(tc.cell_id) desc, coalesce(
      public._liftr_territory_municipality_label(m.display_name, m.display_name_override),
      tc.city_key
    )
    limit greatest(least(coalesce(p_limit, 3), 20), 1)
  ) grouped;
$$;

grant execute on function public.list_territory_city_regions_v1(text, integer, boolean) to authenticated;
grant execute on function public.get_territory_city_share_leaderboard_v1(text, text, integer) to authenticated;
grant execute on function public.list_user_territory_top_cities_v1(uuid, integer) to authenticated;

grant execute on function public.get_territory_map_v1(
  double precision, double precision, double precision, double precision, integer
) to authenticated;

do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'list_territory_city_regions_v1',
        'get_territory_city_share_leaderboard_v1',
        'list_user_territory_top_cities_v1'
      )
  loop
    if not exists (
      select 1
      from pg_proc p2
      where p2.oid = fn.signature::oid
        and p2.prosecdef
    ) then
      raise exception 'expected security definer on %', fn.signature;
    end if;
  end loop;

  if not has_function_privilege(
    'authenticated',
    'public.list_territory_city_regions_v1(text,integer,boolean)',
    'execute'
  ) then
    raise exception 'authenticated missing execute on list_territory_city_regions_v1';
  end if;
end
$$;

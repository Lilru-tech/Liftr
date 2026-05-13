create or replace function public.get_territory_summary_v1 (
  p_user_id uuid default auth.uid()
)
  returns jsonb
  language sql
  stable
  security definer
  set search_path = public
as $$
  with target as (
    select coalesce(p_user_id, auth.uid()) as user_id
  ),
  mine as (
    select count(*)::integer as total_cells
    from public.territory_cells tc
      join target t on tc.owner_user_id = t.user_id
  ),
  week as (
    select count(*)::integer as cells_last_7d
    from public.territory_capture_events e
      join target t on e.user_id = t.user_id
    where e.applied_at >= now() - interval '7 days'
  )
  select jsonb_build_object(
    'total_cells', (select total_cells from mine),
    'cells_last_7d', (select cells_last_7d from week),
    'approx_area_m2', (select total_cells from mine) * 1623.8
  );
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
  security invoker
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

create or replace function public.list_territory_recent_takeovers_v1 (
  p_user_id uuid default auth.uid(),
  p_limit integer default 5
)
  returns table (
    workout_id bigint,
    other_user_id uuid,
    other_username text,
    cells_taken integer,
    share_taken_pct numeric,
    created_at timestamptz
  )
  language sql
  stable
  security invoker
  set search_path = public
as $$
  select
    t.workout_id,
    t.victim_user_id,
    coalesce(p.username, 'user') as other_username,
    t.cells_taken,
    t.share_taken_pct,
    t.created_at
  from public.territory_capture_takeovers t
    join public.profiles p on p.user_id = t.victim_user_id
  where t.taker_user_id = coalesce(p_user_id, auth.uid())
  order by t.created_at desc
  limit greatest(least(coalesce(p_limit, 5), 20), 1);
$$;

grant execute on function public.get_territory_summary_v1 (uuid) to authenticated;
grant execute on function public.list_user_territory_top_cities_v1 (uuid, integer) to authenticated;
grant execute on function public.list_territory_recent_takeovers_v1 (uuid, integer) to authenticated;

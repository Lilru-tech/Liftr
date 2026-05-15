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
    select
      coalesce(sum(e.cells_gained), 0)::integer as cells_gained_last_7d,
      count(*)::integer as capture_workouts_last_7d
    from public.territory_capture_events e
      join target t on e.user_id = t.user_id
    where e.applied_at >= now() - interval '7 days'
  )
  select jsonb_build_object(
    'total_cells', (select total_cells from mine),
    'cells_gained_last_7d', (select cells_gained_last_7d from week),
    'capture_workouts_last_7d', (select capture_workouts_last_7d from week),
    'cells_last_7d', (select capture_workouts_last_7d from week),
    'approx_area_m2', (select total_cells from mine) * 1623.8
  );
$$;

create or replace function public.get_my_territory_summary_v1 ()
  returns jsonb
  language sql
  stable
  security definer
  set search_path = public
as $$
  with mine as (
    select
      count(*)::integer as total_cells
    from public.territory_cells tc
    where tc.owner_user_id = auth.uid ()
  ),
  recent as (
    select
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'workout_id', e.workout_id,
            'route_kind', e.route_kind,
            'cells_gained', e.cells_gained,
            'cells_taken', e.cells_taken,
            'applied_at', e.applied_at
          )
          order by e.applied_at desc
        ),
        '[]'::jsonb
      ) as events
    from (
      select
        *
      from public.territory_capture_events e
      where e.user_id = auth.uid ()
      order by e.applied_at desc
      limit 10
    ) e
  ),
  week as (
    select
      coalesce(sum(e.cells_gained), 0)::integer as cells_gained_last_7d,
      count(*)::integer as capture_workouts_last_7d
    from public.territory_capture_events e
    where
      e.user_id = auth.uid ()
      and e.applied_at >= now() - interval '7 days'
  )
  select jsonb_build_object(
    'total_cells', (select total_cells from mine),
    'cells_gained_last_7d', (select cells_gained_last_7d from week),
    'capture_workouts_last_7d', (select capture_workouts_last_7d from week),
    'cells_last_7d', (select capture_workouts_last_7d from week),
    'approx_area_m2', (select total_cells from mine) * 1623.8,
    'recent_events', (select events from recent)
  );
$$;

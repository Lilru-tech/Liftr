create or replace function public._liftr_backfill_territory_captures_global_batch (p_limit integer default 5)
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  workout_row record;
  processed integer := 0;
begin
  for workout_row in
    select
      w.id
    from public.workouts w
    where
      lower(coalesce(w.kind::text, '')) = 'cardio'
      and w.ended_at is not null
      and public._liftr_workout_route_geojson_text(w.id) is not null
      and not exists (
        select 1
        from public.territory_capture_events e
        where e.workout_id = w.id
      )
    order by coalesce(w.ended_at, w.started_at), w.id
    limit greatest(least(coalesce(p_limit, 5), 25), 1)
  loop
    begin
      perform public._liftr_apply_territory_capture_for_workout(workout_row.id);
      processed := processed + 1;
    exception
      when others then
        null;
    end;
  end loop;

  return processed;
end;
$$;

create or replace function public.backfill_my_territory_captures_v1 (p_limit integer default 5)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  workout_row record;
  processed integer := 0;
  cells_gained_total integer := 0;
  cells_taken_total integer := 0;
  apply_result jsonb;
  has_more boolean := false;
begin
  if auth.uid () is null then
    raise exception 'not_authenticated';
  end if;

  for workout_row in
    select
      w.id
    from public.workouts w
    where
      w.user_id = auth.uid ()
      and lower(coalesce(w.kind::text, '')) = 'cardio'
      and w.ended_at is not null
      and public._liftr_workout_route_geojson_text(w.id) is not null
      and not exists (
        select 1
        from public.territory_capture_events e
        where e.workout_id = w.id
      )
    order by coalesce(w.ended_at, w.started_at), w.id
    limit greatest(least(coalesce(p_limit, 5), 25), 1)
  loop
    begin
      apply_result := public._liftr_apply_territory_capture_for_workout(workout_row.id);
      processed := processed + 1;
      if coalesce((apply_result ->> 'ok')::boolean, false) then
        cells_gained_total := cells_gained_total + coalesce((apply_result ->> 'cells_gained')::integer, 0);
        cells_taken_total := cells_taken_total + coalesce((apply_result ->> 'cells_taken')::integer, 0);
      end if;
    exception
      when others then
        null;
    end;
  end loop;

  select
    exists (
      select 1
      from public.workouts w
      where
        w.user_id = auth.uid ()
        and lower(coalesce(w.kind::text, '')) = 'cardio'
        and w.ended_at is not null
        and public._liftr_workout_route_geojson_text(w.id) is not null
        and not exists (
          select 1
          from public.territory_capture_events e
          where e.workout_id = w.id
        )
    )
  into has_more;

  return jsonb_build_object(
    'ok', true,
    'processed', processed,
    'cells_gained', cells_gained_total,
    'cells_taken', cells_taken_total,
    'has_more', has_more
  );
end;
$$;

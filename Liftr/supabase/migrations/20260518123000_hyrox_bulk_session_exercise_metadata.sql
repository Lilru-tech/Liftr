create or replace function public.patch_hyrox_session_exercise_metadata(
  p_workout_id bigint,
  p_exercises jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id bigint;
begin
  select s.id
  into v_session_id
  from public.sport_sessions s
  join public.workouts w on w.id = s.workout_id
  where w.id = p_workout_id
    and w.user_id = auth.uid()
    and lower(s.sport) = 'hyrox'
  limit 1;

  if v_session_id is null then
    raise exception 'No Hyrox sport session for workout_id %', p_workout_id using errcode = 'P0002';
  end if;

  if p_exercises is null or jsonb_typeof(p_exercises) <> 'array' then
    return;
  end if;

  with rows as (
    select
      coalesce(nullif(value->>'exercise_order', '')::integer, ordinality::integer) as exercise_order,
      nullif(value->>'exercise_display_name', '') as exercise_display_name,
      nullif(value->>'zone_order', '')::integer as zone_order
    from jsonb_array_elements(p_exercises) with ordinality as items(value, ordinality)
  )
  update public.hyrox_session_exercises hse
  set
    exercise_display_name = rows.exercise_display_name,
    zone_order = rows.zone_order
  from rows
  where hse.session_id = v_session_id
    and hse.exercise_order = rows.exercise_order;
end;
$$;

grant execute on function public.patch_hyrox_session_exercise_metadata(bigint, jsonb) to authenticated;

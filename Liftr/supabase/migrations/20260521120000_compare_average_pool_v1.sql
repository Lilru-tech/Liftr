begin;

create or replace function public._workout_primary_muscles(p_workout_id bigint)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    array_agg(distinct m order by m),
    '{}'::text[]
  )
  from (
    select lower(btrim(e.muscle_primary)) as m
    from public.workout_exercises we
    join public.exercises e on e.id = we.exercise_id
    where we.workout_id = p_workout_id
      and e.muscle_primary is not null
      and btrim(e.muscle_primary) <> ''
      and lower(btrim(e.muscle_primary)) <> 'cardio'
  ) s;
$$;

create or replace function public._workout_cardio_activity_key(p_workout_id bigint)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(btrim(coalesce(
    nullif(btrim(cs.activity_code), ''),
    nullif(btrim(cs.modality), ''),
    ''
  )))
  from public.cardio_sessions cs
  where cs.workout_id = p_workout_id
  limit 1;
$$;

create or replace function public._workout_sport_key(p_workout_id bigint)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(btrim(ss.sport))
  from public.sport_sessions ss
  where ss.workout_id = p_workout_id
  limit 1;
$$;

create or replace function public.list_compare_average_pool_v1(
  p_baseline_workout bigint,
  p_scope text,
  p_limit int default 10
)
returns table (
  workout_id bigint,
  started_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_viewer uuid;
  v_kind text;
  v_baseline_muscles text[];
  v_cardio_key text;
  v_sport_key text;
  v_scope text;
  v_limit int;
begin
  v_viewer := auth.uid();
  if v_viewer is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_baseline_workout is null then
    raise exception 'p_baseline_workout is required' using errcode = '22023';
  end if;

  v_scope := lower(btrim(coalesce(p_scope, '')));
  if v_scope not in ('mine', 'global') then
    raise exception 'p_scope must be mine or global' using errcode = '22023';
  end if;

  v_limit := greatest(1, least(coalesce(p_limit, 10), 100));

  select lower(btrim(w.kind::text))
  into v_kind
  from public.workouts w
  where w.id = p_baseline_workout
    and w.state = 'published';

  if v_kind is null then
    return;
  end if;

  if v_kind = 'strength' then
    v_baseline_muscles := public._workout_primary_muscles(p_baseline_workout);
    if coalesce(array_length(v_baseline_muscles, 1), 0) = 0 then
      return;
    end if;
  elsif v_kind = 'cardio' then
    v_cardio_key := public._workout_cardio_activity_key(p_baseline_workout);
    if coalesce(v_cardio_key, '') = '' then
      return;
    end if;
  elsif v_kind = 'sport' then
    v_sport_key := public._workout_sport_key(p_baseline_workout);
    if coalesce(v_sport_key, '') = '' then
      return;
    end if;
  else
    return;
  end if;

  return query
  select w.id::bigint, w.started_at
  from public.workouts w
  where w.id <> p_baseline_workout
    and w.state = 'published'
    and lower(btrim(w.kind::text)) = v_kind
    and (
      v_scope = 'global'
      or w.user_id = v_viewer
      or exists (
        select 1
        from public.workout_participants wp
        where wp.workout_id = w.id
          and wp.user_id = v_viewer
      )
    )
    and (
      v_kind <> 'strength'
      or public._workout_primary_muscles(w.id) = v_baseline_muscles
    )
    and (
      v_kind <> 'cardio'
      or public._workout_cardio_activity_key(w.id) = v_cardio_key
    )
    and (
      v_kind <> 'sport'
      or public._workout_sport_key(w.id) = v_sport_key
    )
  order by w.started_at desc nulls last, w.id desc
  limit v_limit;
end;
$$;

revoke all on function public.list_compare_average_pool_v1(bigint, text, int) from public;
grant execute on function public.list_compare_average_pool_v1(bigint, text, int) to authenticated;

revoke all on function public._workout_primary_muscles(bigint) from public;
revoke all on function public._workout_cardio_activity_key(bigint) from public;
revoke all on function public._workout_sport_key(bigint) from public;

commit;

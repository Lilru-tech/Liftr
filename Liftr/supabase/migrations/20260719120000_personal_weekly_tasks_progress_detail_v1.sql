begin;

create or replace function public._user_tasks_workout_contribution_value(
  p_task public.user_tasks,
  p_workout_id bigint
)
returns numeric
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_w public.workouts%rowtype;
  v_distance numeric;
  v_pace numeric;
  v_volume numeric;
  v_max_weight numeric;
  v_duration_sec numeric;
  v_calories numeric;
  v_total_reps numeric;
  v_total_sets numeric;
  v_routes_sent int;
  v_problems_sent int;
  v_ts timestamptz;
begin
  select * into v_w
  from public.workouts w
  where w.id = p_workout_id
    and w.user_id = p_task.user_id
    and w.state = 'published'::public.workout_state;

  if not found then
    return 0;
  end if;

  v_ts := coalesce(v_w.started_at, v_w.created_at);
  if v_ts < p_task.week_start or v_ts >= p_task.expires_at then
    return 0;
  end if;

  if p_task.target_metric in ('sport_weekly_minutes', 'hyrox_weekly_minutes') then
    if v_w.kind <> 'sport'::public.workout_kind then
      return 0;
    end if;
    select coalesce(ss.duration_sec, 0) / 60.0 into v_duration_sec
    from public.sport_sessions ss
    where ss.workout_id = p_workout_id
      and (
        p_task.target_metric = 'hyrox_weekly_minutes' and ss.sport = 'hyrox'
        or p_task.target_metric = 'sport_weekly_minutes'
          and (p_task.scope_sport is null or ss.sport = p_task.scope_sport)
      );
    return coalesce(v_duration_sec, 0);
  end if;

  if p_task.target_metric = 'sport_sessions_weekly' then
    if v_w.kind <> 'sport'::public.workout_kind then
      return 0;
    end if;
    if exists (
      select 1 from public.sport_sessions ss
      where ss.workout_id = p_workout_id
        and (p_task.scope_sport is null or ss.sport = p_task.scope_sport)
    ) then
      return 1;
    end if;
    return 0;
  end if;

  if p_task.category = 'cardio' and v_w.kind <> 'cardio'::public.workout_kind then
    return 0;
  elsif p_task.category = 'strength' and v_w.kind <> 'strength'::public.workout_kind then
    return 0;
  elsif p_task.category = 'sport' and v_w.kind <> 'sport'::public.workout_kind then
    return 0;
  end if;

  if p_task.target_metric = 'distance_km' then
    select cs.distance_km into v_distance
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
      and (p_task.scope_activity_code is null
        or cs.activity_code = p_task.scope_activity_code
        or cs.modality = p_task.scope_activity_code);
    return greatest(coalesce(v_distance, 0), 0);
  elsif p_task.target_metric = 'pace_sec_per_km' then
    select cs.distance_km, cs.avg_pace_sec_per_km
    into v_distance, v_pace
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
      and (p_task.scope_activity_code is null
        or cs.activity_code = p_task.scope_activity_code
        or cs.modality = p_task.scope_activity_code);
    if coalesce(v_distance, 0) < coalesce(p_task.target_secondary, 3) then
      return 0;
    end if;
    if coalesce(v_pace, 0) <= 0 or coalesce(p_task.target_value, 0) <= 0 then
      return 0;
    end if;
    return least(p_task.target_value, p_task.target_value * (p_task.target_value / v_pace));
  elsif p_task.target_metric = 'max_weight_kg' then
    select max(es.weight_kg) into v_max_weight
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where we.workout_id = p_workout_id
      and coalesce(es.is_completed, true)
      and (
        p_task.scope_muscle_primary is null
        or e.muscle_primary = p_task.scope_muscle_primary
        or e.muscle_primary = replace(p_task.scope_muscle_primary, 'pecho', 'chest')
      );
    return greatest(coalesce(v_max_weight, 0), 0);
  elsif p_task.target_metric = 'volume_kg' then
    select coalesce(sum(es.reps * es.weight_kg), 0) into v_volume
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where we.workout_id = p_workout_id
      and coalesce(es.is_completed, true)
      and (
        p_task.scope_muscle_primary is null
        or e.muscle_primary = p_task.scope_muscle_primary
        or e.muscle_primary = replace(p_task.scope_muscle_primary, 'pecho', 'chest')
      );
    return greatest(v_volume, 0);
  elsif p_task.target_metric = 'total_reps' then
    select coalesce(sum(es.reps), 0) into v_total_reps
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where we.workout_id = p_workout_id
      and coalesce(es.is_completed, true)
      and (
        p_task.scope_muscle_primary is null
        or e.muscle_primary = p_task.scope_muscle_primary
        or e.muscle_primary = replace(p_task.scope_muscle_primary, 'pecho', 'chest')
      );
    return greatest(v_total_reps, 0);
  elsif p_task.target_metric = 'total_sets' then
    select count(*)::numeric into v_total_sets
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where we.workout_id = p_workout_id
      and coalesce(es.is_completed, true)
      and (
        p_task.scope_muscle_primary is null
        or e.muscle_primary = p_task.scope_muscle_primary
        or e.muscle_primary = replace(p_task.scope_muscle_primary, 'pecho', 'chest')
      );
    return greatest(v_total_sets, 0);
  elsif p_task.target_metric in ('routes_sent', 'problems_sent') then
    select cls.routes_sent, cls.problems_sent
    into v_routes_sent, v_problems_sent
    from public.sport_sessions ss
    left join public.climbing_session_stats cls on cls.session_id = ss.id
    where ss.workout_id = p_workout_id
      and ss.sport = 'climbing'
      and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    if p_task.target_metric = 'routes_sent' then
      return greatest(coalesce(v_routes_sent, 0), 0);
    end if;
    return greatest(coalesce(v_problems_sent, 0), 0);
  elsif p_task.target_metric = 'duration_sec' then
    if p_task.category = 'sport' then
      select coalesce(ss.duration_sec, 0) into v_duration_sec
      from public.sport_sessions ss
      where ss.workout_id = p_workout_id
        and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    else
      v_duration_sec := coalesce(v_w.duration_min, 0) * 60;
    end if;
    return greatest(coalesce(v_duration_sec, 0), 0);
  elsif p_task.target_metric = 'calories_kcal' then
    return greatest(coalesce(v_w.calories_kcal, 0), 0);
  end if;

  return 0;
end;
$$;

create or replace function public._user_tasks_is_weekly_cumulative_metric(p_metric text)
returns boolean
language sql
immutable
as $$
  select p_metric in ('sport_weekly_minutes', 'hyrox_weekly_minutes', 'sport_sessions_weekly');
$$;

create or replace function public._user_tasks_progress_value(
  p_task public.user_tasks
)
returns numeric
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_progress numeric := 0;
begin
  if p_task.status not in ('accepted', 'completed') then
    return null;
  end if;

  if p_task.status = 'completed' then
    return greatest(coalesce(p_task.target_value, 0), 0);
  end if;

  if public._user_tasks_is_weekly_cumulative_metric(p_task.target_metric) then
    select coalesce(sum(public._user_tasks_workout_contribution_value(p_task, w.id)), 0)
    into v_progress
    from public.workouts w
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at;
  else
    select coalesce(max(public._user_tasks_workout_contribution_value(p_task, w.id)), 0)
    into v_progress
    from public.workouts w
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at;
  end if;

  return greatest(v_progress, 0);
end;
$$;

create or replace function public._user_tasks_contribution_label(
  p_metric text,
  p_value numeric
)
returns text
language plpgsql
stable
as $$
declare
  v_fmt text;
begin
  if coalesce(p_value, 0) <= 0 then
    return '0';
  end if;

  v_fmt := public._user_tasks_format_value(p_metric, p_value, null);

  return case p_metric
    when 'calories_kcal' then v_fmt || ' kcal'
    when 'distance_km' then v_fmt || ' km'
    when 'duration_sec' then v_fmt || ' min'
    when 'sport_weekly_minutes' then v_fmt || ' min'
    when 'hyrox_weekly_minutes' then v_fmt || ' min'
    when 'sport_sessions_weekly' then v_fmt || case when p_value = 1 then ' session' else ' sessions' end
    when 'volume_kg' then v_fmt || ' kg'
    when 'max_weight_kg' then v_fmt || ' kg'
    when 'total_reps' then v_fmt || ' reps'
    when 'total_sets' then v_fmt || ' sets'
    when 'routes_sent' then v_fmt || case when p_value = 1 then ' route' else ' routes' end
    when 'problems_sent' then v_fmt || case when p_value = 1 then ' problem' else ' problems' end
    when 'pace_sec_per_km' then v_fmt || ' min/km'
    else v_fmt
  end;
end;
$$;

create or replace function public._user_tasks_workout_matches_task_scope(
  p_task public.user_tasks,
  p_workout_id bigint
)
returns boolean
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_w public.workouts%rowtype;
begin
  if public._user_tasks_workout_contribution_value(p_task, p_workout_id) > 0 then
    return true;
  end if;

  select * into v_w
  from public.workouts w
  where w.id = p_workout_id
    and w.user_id = p_task.user_id
    and w.state = 'published'::public.workout_state;

  if not found then
    return false;
  end if;

  if coalesce(v_w.started_at, v_w.created_at) < p_task.week_start
    or coalesce(v_w.started_at, v_w.created_at) >= p_task.expires_at then
    return false;
  end if;

  if p_task.category = 'cardio' and v_w.kind = 'cardio'::public.workout_kind then
    if p_task.scope_activity_code is null then
      return true;
    end if;
    return exists (
      select 1 from public.cardio_sessions cs
      where cs.workout_id = p_workout_id
        and (cs.activity_code = p_task.scope_activity_code
          or cs.modality = p_task.scope_activity_code)
    );
  elsif p_task.category = 'strength' and v_w.kind = 'strength'::public.workout_kind then
    if p_task.scope_muscle_primary is null then
      return true;
    end if;
    return exists (
      select 1
      from public.workout_exercises we
      join public.exercises e on e.id = we.exercise_id
      where we.workout_id = p_workout_id
        and (e.muscle_primary = p_task.scope_muscle_primary
          or e.muscle_primary = replace(p_task.scope_muscle_primary, 'pecho', 'chest'))
    );
  elsif p_task.category = 'sport' and v_w.kind = 'sport'::public.workout_kind then
    if p_task.scope_sport is null then
      return true;
    end if;
    return exists (
      select 1 from public.sport_sessions ss
      where ss.workout_id = p_workout_id
        and ss.sport = p_task.scope_sport
    );
  end if;

  return false;
end;
$$;

drop function if exists public.get_user_task_detail_v1(uuid);

create or replace function public.get_user_task_detail_v1(p_task_id uuid)
returns table (
  task_id uuid,
  title text,
  description text,
  category text,
  target_metric text,
  target_value numeric,
  target_secondary numeric,
  reward_xp int,
  reward_coins int,
  reward_task_points int,
  difficulty_band text,
  scope_activity_code text,
  scope_sport text,
  scope_muscle_primary text,
  status text,
  progress_value numeric,
  progress_percent int,
  progress_current_label text,
  progress_target_label text,
  generated_at timestamptz,
  accepted_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz,
  completed_workout_id bigint,
  week_start timestamptz,
  week_end timestamptz
)
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  v_task public.user_tasks%rowtype;
  v_progress numeric;
  we timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_task
  from public.user_tasks ut
  where ut.id = p_task_id
    and ut.user_id = v_uid;

  if not found then
    raise exception 'user_task_not_found';
  end if;

  select b.w_end into we from public._challenge_week_bounds_utc(v_task.week_start) as b;

  v_progress := coalesce(public._user_tasks_progress_value(v_task), 0);

  return query
  select
    v_task.id,
    v_task.title,
    v_task.description,
    v_task.category,
    v_task.target_metric,
    v_task.target_value,
    v_task.target_secondary,
    v_task.reward_xp,
    v_task.reward_coins,
    v_task.reward_task_points,
    v_task.difficulty_band,
    v_task.scope_activity_code,
    v_task.scope_sport,
    v_task.scope_muscle_primary,
    v_task.status,
    v_progress,
    case
      when coalesce(v_task.target_value, 0) <= 0 then 0
      when v_task.status = 'completed' then 100
      else least(100, greatest(0, round((v_progress / v_task.target_value) * 100)::int))
    end,
    public._user_tasks_contribution_label(v_task.target_metric, v_progress),
    public._user_tasks_contribution_label(v_task.target_metric, v_task.target_value),
    v_task.generated_at,
    v_task.accepted_at,
    v_task.completed_at,
    v_task.expires_at,
    v_task.completed_workout_id,
    v_task.week_start,
    we;
end;
$$;

create or replace function public.list_user_task_workouts_v1(p_task_id uuid)
returns table (
  workout_id bigint,
  kind text,
  title text,
  started_at timestamptz,
  state text,
  calories_kcal numeric,
  contribution_value numeric,
  qualifies boolean,
  contribution_label text
)
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  v_task public.user_tasks%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_task
  from public.user_tasks ut
  where ut.id = p_task_id
    and ut.user_id = v_uid;

  if not found then
    raise exception 'user_task_not_found';
  end if;

  return query
  select
    w.id,
    w.kind::text,
    w.title,
    coalesce(w.started_at, w.created_at),
    w.state::text,
    w.calories_kcal,
    public._user_tasks_workout_contribution_value(v_task, w.id),
    public._user_task_workout_satisfies(v_task, w.id),
    public._user_tasks_contribution_label(
      v_task.target_metric,
      public._user_tasks_workout_contribution_value(v_task, w.id)
    )
  from public.workouts w
  where w.user_id = v_uid
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= v_task.week_start
    and coalesce(w.started_at, w.created_at) < v_task.expires_at
    and public._user_tasks_workout_matches_task_scope(v_task, w.id)
  order by coalesce(w.started_at, w.created_at) desc;
end;
$$;

revoke all on function public._user_tasks_workout_contribution_value(public.user_tasks, bigint) from public, anon;
revoke all on function public.list_user_task_workouts_v1(uuid) from public, anon;
grant execute on function public.list_user_task_workouts_v1(uuid) to authenticated;

revoke all on function public.get_user_task_detail_v1(uuid) from public, anon;
grant execute on function public.get_user_task_detail_v1(uuid) to authenticated;

commit;

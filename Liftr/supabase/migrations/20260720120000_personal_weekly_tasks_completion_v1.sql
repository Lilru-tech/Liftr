begin;

create or replace function public._user_task_is_satisfied(
  p_task public.user_tasks
)
returns boolean
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_progress numeric;
  v_found boolean;
begin
  if p_task.status <> 'accepted' then
    return false;
  end if;

  if p_task.target_metric = 'pace_sec_per_km' then
    select exists (
      select 1
      from public.workouts w
      join public.cardio_sessions cs on cs.workout_id = w.id
      where w.user_id = p_task.user_id
        and w.state = 'published'::public.workout_state
        and coalesce(w.started_at, w.created_at) >= p_task.week_start
        and coalesce(w.started_at, w.created_at) < p_task.expires_at
        and (
          p_task.scope_activity_code is null
          or cs.activity_code = p_task.scope_activity_code
          or cs.modality = p_task.scope_activity_code
        )
        and coalesce(cs.distance_km, 0) >= coalesce(p_task.target_secondary, 3)
        and coalesce(cs.avg_pace_sec_per_km, 1e9) <= p_task.target_value
    ) into v_found;
    return coalesce(v_found, false);
  end if;

  v_progress := public._user_tasks_progress_value(p_task);
  return coalesce(v_progress, 0) >= coalesce(p_task.target_value, 0);
end;
$$;

create or replace function public._user_tasks_pick_completion_workout(
  p_task public.user_tasks
)
returns bigint
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_wid bigint;
begin
  select w.id into v_wid
  from public.workouts w
  where w.user_id = p_task.user_id
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= p_task.week_start
    and coalesce(w.started_at, w.created_at) < p_task.expires_at
    and public._user_tasks_workout_contribution_value(p_task, w.id) > 0
  order by coalesce(w.started_at, w.created_at) desc
  limit 1;

  if v_wid is not null then
    return v_wid;
  end if;

  select w.id into v_wid
  from public.workouts w
  where w.user_id = p_task.user_id
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= p_task.week_start
    and coalesce(w.started_at, w.created_at) < p_task.expires_at
  order by coalesce(w.started_at, w.created_at) desc
  limit 1;

  return v_wid;
end;
$$;

create or replace function public.complete_user_task(
  p_task_id uuid,
  p_user_id uuid,
  p_workout_id bigint
)
returns boolean
language plpgsql
security definer
set search_path to public
as $$
declare
  v_task public.user_tasks%rowtype;
  v_workout_id bigint := p_workout_id;
begin
  select * into v_task
  from public.user_tasks ut
  where ut.id = p_task_id
    and ut.user_id = p_user_id
    and ut.status = 'accepted'
  for update;

  if not found then
    return false;
  end if;

  if v_workout_id is null then
    v_workout_id := public._user_tasks_pick_completion_workout(v_task);
  end if;

  update public.user_tasks
  set status = 'completed',
      completed_at = now(),
      completed_workout_id = v_workout_id
  where id = p_task_id;

  perform public.apply_liftr_xp_reward(p_user_id, v_task.reward_xp, p_task_id, v_workout_id);

  perform public.apply_liftr_coin_reward(
    p_user_id,
    v_task.reward_coins,
    'user_task_completed',
    p_task_id
  );

  perform public.allow_profiles_task_points_update();
  update public.profiles
  set task_points_total = coalesce(task_points_total, 0) + v_task.reward_task_points
  where user_id = p_user_id;

  if to_regprocedure('public.create_notification(uuid,text,text,text,jsonb)') is not null then
    perform public.create_notification(
      p_user_id,
      'user_task_completed',
      'Weekly task complete',
      v_task.title,
      jsonb_build_object(
        'task_id', p_task_id::text,
        'reward_xp', v_task.reward_xp,
        'reward_coins', v_task.reward_coins,
        'reward_task_points', v_task.reward_task_points
      )
    );
  end if;

  return true;
end;
$$;

create or replace function public.evaluate_user_tasks_for_user(
  p_user_id uuid,
  p_workout_id bigint default null
)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_task public.user_tasks%rowtype;
  v_workout_id bigint;
begin
  if p_user_id is null then
    return;
  end if;

  perform public._user_tasks_ensure_weekly_for_user(p_user_id);

  for v_task in
    select ut.*
    from public.user_tasks ut
    where ut.user_id = p_user_id
      and ut.status = 'accepted'
      and now() >= ut.week_start
      and now() < ut.expires_at
    for update
  loop
    if public._user_task_is_satisfied(v_task) then
      v_workout_id := coalesce(
        p_workout_id,
        public._user_tasks_pick_completion_workout(v_task)
      );
      perform public.complete_user_task(v_task.id, p_user_id, v_workout_id);
    end if;
  end loop;
end;
$$;

create or replace function public.accept_user_task_v1(p_task_id uuid)
returns public.user_tasks
language plpgsql
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  ws timestamptz;
  v_accepted int;
  v_task public.user_tasks%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  perform public._user_tasks_ensure_weekly_for_user(v_uid);

  select b.w_start into ws from public._challenge_week_bounds_utc(now()) as b;

  select count(*)::int into v_accepted
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status = 'accepted';

  if v_accepted >= 3 then
    raise exception 'user_task_accept_cap_reached';
  end if;

  update public.user_tasks ut
  set status = 'accepted',
      accepted_at = now()
  where ut.id = p_task_id
    and ut.user_id = v_uid
    and ut.status = 'generated'
    and ut.week_start = ws
    and now() < ut.expires_at
  returning * into v_task;

  if not found then
    raise exception 'user_task_not_acceptable';
  end if;

  perform public.evaluate_user_tasks_for_user(v_uid);

  select * into v_task from public.user_tasks where id = p_task_id;

  return v_task;
end;
$$;

drop function if exists public.list_my_weekly_tasks_v1();

create or replace function public.list_my_weekly_tasks_v1()
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
  status text,
  generated_at timestamptz,
  expires_at timestamptz,
  accepted_at timestamptz,
  completed_at timestamptz,
  progress_value numeric,
  week_start timestamptz,
  week_end timestamptz,
  accepted_count int,
  accept_slots_remaining int,
  refresh_count int,
  free_refresh_available boolean,
  next_refresh_cost_coins int
)
language plpgsql
volatile
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  ws timestamptz;
  we timestamptz;
  v_accepted int;
  v_refresh_count int;
  v_free_refresh boolean;
  v_next_cost int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  perform public._user_tasks_ensure_weekly_for_user(v_uid);
  perform public.evaluate_user_tasks_for_user(v_uid);

  select b.w_start, b.w_end into ws, we
  from public._challenge_week_bounds_utc(now()) as b;

  select count(*)::int into v_accepted
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status = 'accepted';

  select m.refresh_count, m.free_refresh_available, m.next_refresh_cost_coins
  into v_refresh_count, v_free_refresh, v_next_cost
  from public._user_tasks_refresh_meta_for_user(v_uid, ws) as m;

  return query
  select
    ut.id,
    ut.title,
    ut.description,
    ut.category,
    ut.target_metric,
    ut.target_value,
    ut.target_secondary,
    ut.reward_xp,
    ut.reward_coins,
    ut.reward_task_points,
    ut.difficulty_band,
    ut.status,
    ut.generated_at,
    ut.expires_at,
    ut.accepted_at,
    ut.completed_at,
    public._user_tasks_progress_value(ut),
    ws,
    we,
    v_accepted,
    greatest(0, 3 - v_accepted),
    v_refresh_count,
    v_free_refresh,
    v_next_cost
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status <> 'expired'
  order by
    case ut.status
      when 'accepted' then 0
      when 'completed' then 1
      when 'generated' then 2
      else 3
    end,
    ut.generated_at;
end;
$$;

do $$
declare
  r record;
begin
  for r in
    select distinct ut.user_id
    from public.user_tasks ut
    where ut.status = 'accepted'
  loop
    perform public.evaluate_user_tasks_for_user(r.user_id);
  end loop;
end;
$$;

revoke all on function public._user_task_is_satisfied(public.user_tasks) from public, anon;
grant execute on function public._user_task_is_satisfied(public.user_tasks) to authenticated;

revoke all on function public._user_tasks_pick_completion_workout(public.user_tasks) from public, anon;
grant execute on function public._user_tasks_pick_completion_workout(public.user_tasks) to authenticated;

revoke all on function public.list_my_weekly_tasks_v1() from public, anon;
grant execute on function public.list_my_weekly_tasks_v1() to authenticated;

revoke all on function public.accept_user_task_v1(uuid) from public, anon;
grant execute on function public.accept_user_task_v1(uuid) to authenticated;

commit;

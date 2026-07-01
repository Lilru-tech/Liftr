do $$
declare
  v_user uuid;
  v_task public.user_tasks%rowtype;
  v_accepted int;
begin
  select user_id into v_user from public.profiles where username = 'Lilru' limit 1;

  if v_user is null then
    raise notice 'personal_weekly_tasks_completion_v1 verify skipped (no Lilru)';
    return;
  end if;

  select * into v_task
  from public.user_tasks ut
  where ut.user_id = v_user
    and ut.status = 'accepted'
    and ut.target_metric = 'sport_sessions_weekly'
    and public._user_task_is_satisfied(ut)
  limit 1;

  if v_task.id is not null then
    perform public.evaluate_user_tasks_for_user(v_user);
    select * into v_task from public.user_tasks where id = v_task.id;
    if v_task.status <> 'completed' then
      raise exception 'satisfied sport_sessions_weekly task should complete after evaluate, got %', v_task.status;
    end if;
  end if;

  select count(*)::int into v_accepted
  from public.user_tasks ut
  join lateral (
    select b.w_start as ws from public._challenge_week_bounds_utc(now()) as b
  ) wb on ut.week_start = wb.ws
  where ut.user_id = v_user
    and ut.status = 'accepted';

  if v_accepted > 3 then
    raise exception 'accepted cap should be at most 3, got %', v_accepted;
  end if;

        if to_regprocedure('public.get_my_weekly_tasks_history_v1(integer,integer)') is null then
    raise exception 'get_my_weekly_tasks_history_v1(int,int) missing';
  end if;

  raise notice 'personal_weekly_tasks_completion_v1 verify ok';
end;
$$;

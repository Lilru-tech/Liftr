do $$
declare
  v_user uuid;
  v_task_id uuid;
  v_progress numeric;
  v_detail record;
  v_count int;
begin
  select user_id into v_user from public.profiles where username = 'Lilru' limit 1;

  if v_user is null then
    raise notice 'personal_weekly_tasks_progress_detail_v1 verify skipped (no Lilru)';
    return;
  end if;

  select ut.id, public._user_tasks_progress_value(ut)
  into v_task_id, v_progress
  from public.user_tasks ut
  where ut.user_id = v_user
    and ut.status = 'accepted'
    and ut.target_metric = 'calories_kcal'
  order by ut.generated_at desc
  limit 1;

  if v_task_id is not null then
    if v_progress is null then
      raise exception 'accepted cardio calories task should return progress_value, got null';
    end if;
  end if;

  select ut.id into v_task_id
  from public.user_tasks ut
  where ut.user_id = v_user
    and ut.status = 'accepted'
    and ut.target_metric = 'sport_sessions_weekly'
  limit 1;

  if v_task_id is not null then
    select public._user_tasks_progress_value(ut) into v_progress
    from public.user_tasks ut where ut.id = v_task_id;

    if v_progress is null then
      raise exception 'hyrox sessions task should return progress_value';
    end if;
  end if;

  raise notice 'personal_weekly_tasks_progress_detail_v1 verify ok';
end;
$$;

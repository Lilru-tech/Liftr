do $$
declare
  v_user uuid;
  v_payload jsonb;
  v_count int;
begin
  select user_id into v_user from public.profiles where username = 'Lilru' limit 1;

  if v_user is null then
    raise notice 'personal_weekly_tasks_history_v2 verify skipped (no Lilru)';
    return;
  end if;

  if to_regprocedure('public.get_my_weekly_tasks_history_v1(integer,integer)') is null then
    raise exception 'get_my_weekly_tasks_history_v1(int,int) missing';
  end if;

  select count(*)::int into v_count
  from public.user_tasks ut
  where ut.user_id = v_user and ut.status = 'completed';

  if v_count > 0 then
    raise notice 'Lilru has % completed tasks for history smoke', v_count;
  end if;

  raise notice 'personal_weekly_tasks_history_v2 verify ok';
end;
$$;

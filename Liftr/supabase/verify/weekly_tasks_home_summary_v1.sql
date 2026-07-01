do $$
begin
  if to_regprocedure('public.get_my_weekly_tasks_home_summary_v1()') is null then
    raise exception 'get_my_weekly_tasks_home_summary_v1() missing';
  end if;

  raise notice 'weekly_tasks_home_summary_v1 verify ok';
end;
$$;

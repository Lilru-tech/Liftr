begin;

create or replace function public.get_my_weekly_tasks_home_summary_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  ws timestamptz;
  v_accepted int;
  v_available int;
  v_completed int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  perform public._user_tasks_ensure_weekly_for_user(v_uid);
  perform public.evaluate_user_tasks_for_user(v_uid);

  select b.w_start into ws
  from public._challenge_week_bounds_utc(now()) as b;

  select count(*)::int into v_accepted
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status = 'accepted';

  select count(*)::int into v_available
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status = 'generated';

  select count(*)::int into v_completed
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status = 'completed';

  return jsonb_build_object(
    'week_start', ws,
    'accepted_count', v_accepted,
    'accept_slots_remaining', greatest(0, 3 - v_accepted),
    'available_count', v_available,
    'completed_count_this_week', v_completed
  );
end;
$$;

revoke all on function public.get_my_weekly_tasks_home_summary_v1() from public, anon;
grant execute on function public.get_my_weekly_tasks_home_summary_v1() to authenticated;

commit;

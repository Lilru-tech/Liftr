begin;

drop function if exists public.get_my_weekly_tasks_history_v1(int);

create or replace function public.get_my_weekly_tasks_history_v1(
  p_tasks_limit int default 10,
  p_tasks_offset int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  v_ws timestamptz;
  v_stats jsonb;
  v_completed_tasks jsonb;
  v_total int;
  v_limit int := greatest(1, least(coalesce(p_tasks_limit, 10), 50));
  v_offset int := greatest(0, coalesce(p_tasks_offset, 0));
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select b.w_start into v_ws
  from public._challenge_week_bounds_utc(now()) as b;

  select jsonb_build_object(
    'total_accepted',
      (select count(*)::int from public.user_tasks ut where ut.user_id = v_uid and ut.accepted_at is not null),
    'total_completed',
      (select count(*)::int from public.user_tasks ut where ut.user_id = v_uid and ut.status = 'completed'),
    'total_expired',
      (select count(*)::int from public.user_tasks ut
       where ut.user_id = v_uid and ut.status = 'expired' and ut.accepted_at is not null),
    'completion_rate_percent',
      coalesce((
        select round(
          count(*) filter (where ut.status = 'completed')::numeric
          / nullif(count(*) filter (where ut.accepted_at is not null), 0) * 100.0,
          0
        )::int
        from public.user_tasks ut
        where ut.user_id = v_uid
      ), 0),
    'total_xp_earned',
      coalesce((select sum(ut.reward_xp)::int from public.user_tasks ut
        where ut.user_id = v_uid and ut.status = 'completed'), 0),
    'total_coins_earned',
      coalesce((select sum(ut.reward_coins)::int from public.user_tasks ut
        where ut.user_id = v_uid and ut.status = 'completed'), 0),
    'total_task_points_earned',
      coalesce((select sum(ut.reward_task_points)::int from public.user_tasks ut
        where ut.user_id = v_uid and ut.status = 'completed'), 0),
    'current_week_accepted',
      (select count(*)::int from public.user_tasks ut
       where ut.user_id = v_uid and ut.week_start = v_ws and ut.status = 'accepted'),
    'current_week_completed',
      (select count(*)::int from public.user_tasks ut
       where ut.user_id = v_uid and ut.week_start = v_ws and ut.status = 'completed')
  ) into v_stats;

  select count(*)::int into v_total
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.status = 'completed';

  select coalesce(jsonb_agg(row_data order by sort_completed_at desc), '[]'::jsonb)
  into v_completed_tasks
  from (
    select
      ut.completed_at as sort_completed_at,
      jsonb_build_object(
        'task_id', ut.id,
        'title', ut.title,
        'category', ut.category,
        'difficulty_band', ut.difficulty_band,
        'status', ut.status,
        'accepted_at', ut.accepted_at,
        'completed_at', ut.completed_at,
        'week_start', ut.week_start,
        'target_metric', ut.target_metric,
        'target_value', ut.target_value,
        'reward_xp', ut.reward_xp,
        'reward_coins', ut.reward_coins,
        'reward_task_points', ut.reward_task_points
      ) as row_data
    from public.user_tasks ut
    where ut.user_id = v_uid
      and ut.status = 'completed'
    order by ut.completed_at desc nulls last, ut.generated_at desc
    limit v_limit
    offset v_offset
  ) sub;

  return jsonb_build_object(
    'stats', v_stats,
    'completed_tasks', v_completed_tasks,
    'total_completed_tasks', v_total,
    'has_more', v_total > v_offset + v_limit
  );
end;
$$;

revoke all on function public.get_my_weekly_tasks_history_v1(int, int) from public, anon;
grant execute on function public.get_my_weekly_tasks_history_v1(int, int) to authenticated;

commit;

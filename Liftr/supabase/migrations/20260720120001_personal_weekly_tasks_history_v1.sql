begin;

create or replace function public.get_my_weekly_tasks_history_v1(
  p_weeks_limit int default 16
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
  v_we timestamptz;
  v_stats jsonb;
  v_weeks jsonb;
  v_limit int := greatest(1, least(coalesce(p_weeks_limit, 16), 52));
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select b.w_start, b.w_end into v_ws, v_we
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

  select coalesce(jsonb_agg(wk order by wk_week_start desc), '[]'::jsonb)
  into v_weeks
  from (
    select
      ut.week_start as wk_week_start,
      jsonb_build_object(
        'week_start', ut.week_start,
        'week_end', max(ut.expires_at),
        'tasks', jsonb_agg(
          jsonb_build_object(
            'task_id', ut.id,
            'title', ut.title,
            'category', ut.category,
            'difficulty_band', ut.difficulty_band,
            'status', ut.status,
            'accepted_at', ut.accepted_at,
            'completed_at', ut.completed_at,
            'target_metric', ut.target_metric,
            'target_value', ut.target_value,
            'progress_value', public._user_tasks_progress_value(ut),
            'reward_xp', ut.reward_xp,
            'reward_coins', ut.reward_coins,
            'reward_task_points', ut.reward_task_points
          )
          order by
            case ut.status
              when 'completed' then 0
              when 'accepted' then 1
              when 'expired' then 2
              else 3
            end,
            ut.generated_at desc
        )
      ) as wk
    from public.user_tasks ut
    where ut.user_id = v_uid
      and ut.week_start < v_ws
      and ut.accepted_at is not null
    group by ut.week_start
    order by ut.week_start desc
    limit v_limit
  ) sub;

  return jsonb_build_object('stats', v_stats, 'weeks', v_weeks);
end;
$$;

revoke all on function public.get_my_weekly_tasks_history_v1(int) from public, anon;
grant execute on function public.get_my_weekly_tasks_history_v1(int) to authenticated;

commit;

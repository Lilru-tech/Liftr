select count(*) as body_weight_achievement_rows
from public.achievements
where category = 'health';

select code, name, category, requirement_value, coin_reward_tier
from public.achievements
where category = 'health'
order by code;

select
  to_regprocedure('public.unlock_body_weight_achievements(uuid)') is not null as has_unlock_body_weight,
  to_regprocedure('public.liftr_user_body_weight_metrics(uuid)') is not null as has_metrics_fn,
  to_regprocedure('public.liftr_achievement_progress_current(uuid, text, text)') is not null as has_progress_fn;

select pg_get_functiondef(p.oid) like '%unlock_body_weight_achievements%' as orchestrator_wired
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'check_and_unlock_achievements_for';

select tgname, tgrelid::regclass as table_name
from pg_trigger
where tgname = 'trg_achievements_on_body_weight_entry';

select
  total_entries,
  distinct_months,
  span_days,
  has_manual,
  has_health_sync
from public.liftr_user_body_weight_metrics(auth.uid());

select
  code,
  is_unlocked,
  progress_current,
  requirement_value
from public.get_user_achievements(auth.uid())
where category = 'health'
order by code;

select public.liftr_achievement_progress_current(auth.uid(), 'body_weight_first_log', 'count') as progress_first_log,
       public.liftr_achievement_progress_current(auth.uid(), 'body_weight_logs_10', 'count') as progress_logs_10,
       public.liftr_achievement_progress_current(auth.uid(), 'body_weight_span_90d', 'count') as progress_span_90d;

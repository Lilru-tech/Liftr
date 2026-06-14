select count(*) as pet_coin_achievement_rows
from public.achievements
where category in ('pet', 'coins');

select code, name, category, requirement_value, coin_reward_tier
from public.achievements
where category in ('pet', 'coins')
order by category, code;

select
  to_regprocedure('public.unlock_pet_achievements(uuid)') is not null as has_unlock_pet,
  to_regprocedure('public.unlock_coin_achievements(uuid)') is not null as has_unlock_coin,
  to_regprocedure('public.liftr_achievement_progress_current(uuid, text, text)') is not null as has_progress_fn;

select pg_get_functiondef(p.oid) like '%unlock_pet_achievements%' as orchestrator_wired
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'check_and_unlock_achievements_for';

select tgname, tgrelid::regclass as table_name
from pg_trigger
where tgname in (
  'trg_achievements_on_coin_tx',
  'trg_achievements_on_pet_log',
  'trg_achievements_on_pet_instance',
  'trg_achievements_on_pet_combat_stats',
  'trg_achievements_on_profile_energy'
)
order by tgname;

select
  code,
  is_unlocked,
  progress_current,
  requirement_value
from public.get_user_achievements(auth.uid())
where category in ('pet', 'coins')
order by category, code;

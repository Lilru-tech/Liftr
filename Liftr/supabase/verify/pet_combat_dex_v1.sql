select
  to_regclass('public.pet_combat_dex_species') is not null as has_dex_species,
  to_regclass('public.pet_combat_dex_rarities') is not null as has_dex_rarities,
  to_regclass('public.pet_combat_dex_stages') is not null as has_dex_stages,
  to_regclass('public.pet_user_discovered_stages') is not null as has_discovered_stages;

select
  to_regprocedure('public.get_my_pet_dex_v1()') is not null as has_get_my_pet_dex,
  to_regprocedure('public.get_pet_species_detail_v1(text)') is not null as has_get_pet_species_detail,
  to_regprocedure('public.liftr_user_pet_dex_metrics(uuid)') is not null as has_dex_metrics;

select tgname, tgrelid::regclass as table_name
from pg_trigger
where tgname in (
  'trg_pet_combat_dex_from_history',
  'trg_pet_own_stage_discovery'
)
order by tgname;

select code, name, requirement_value, coin_reward_tier
from public.achievements
where code in (
  'pet_combat_all_rarities',
  'pet_combat_all_species',
  'pet_combat_all_stages'
)
order by code;

select pg_get_functiondef(p.oid) like '%pet_combat_all_rarities%' as unlock_has_dex_achievements
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'unlock_pet_achievements';

select pg_get_functiondef(p.oid) like '%pet_combat_all_species%' as progress_has_dex_achievements
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'liftr_achievement_progress_current';

select public.get_my_pet_dex_v1() -> 'total_species' as dex_total_species;

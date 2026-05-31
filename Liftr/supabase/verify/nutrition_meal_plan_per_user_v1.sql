select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'nutrition_meal_plan_targets'
  and column_name in ('ingredient_id', 'recipe_id')
order by column_name;

select
  conname,
  pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.nutrition_meal_plan_targets'::regclass
  and conname = 'nutrition_meal_plan_targets_source_xor';

select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'update_meal_plan_target',
    'reject_meal_plan',
    'complete_meal_plan_as_eaten',
    'nutrition_meal_plan_targets_auto_accept_creator'
  )
order by p.proname;

select
  tgname,
  tgrelid::regclass as table_name
from pg_trigger
where tgrelid = 'public.nutrition_meal_plan_targets'::regclass
  and not tgisinternal
  and tgname in (
    'nutrition_meal_plan_targets_auto_accept_creator',
    'nutrition_meal_plan_targets_guard_columns'
  )
order by tgname;

select
  has_function_privilege('authenticated', 'public.update_meal_plan_target(uuid, numeric, text)', 'execute') as update_meal_plan_target_granted;

select
  p.proname,
  pg_get_functiondef(p.oid) like '%INVITEE_MAY_ONLY_UPDATE_STATUS%' as guard_blocks_quantity_not_status,
  pg_get_functiondef(p.oid) like '%liftr.meal_plan_target_rpc%' as guard_rpc_bypass
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'nutrition_meal_plan_targets_guard_columns';

select
  pg_get_functiondef(p.oid) like '%set_config(''liftr.meal_plan_target_rpc''%' as update_meal_plan_target_sets_bypass
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'update_meal_plan_target';

select
  to_regclass('public.nutrition_meal_plans') is not null as nutrition_meal_plans_exists,
  to_regclass('public.nutrition_meal_plan_targets') is not null as nutrition_meal_plan_targets_exists;

select
  conname,
  pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.nutrition_meal_plans'::regclass
  and contype = 'c'
order by conname;

select
  conname,
  pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.nutrition_meal_plan_targets'::regclass
  and contype in ('c', 'u')
order by conname;

select
  indexname
from pg_indexes
where schemaname = 'public'
  and tablename in ('nutrition_meal_plans', 'nutrition_meal_plan_targets')
order by tablename, indexname;

select
  tablename,
  policyname,
  cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('nutrition_meal_plans', 'nutrition_meal_plan_targets')
order by tablename, policyname;

select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'accept_meal_plan',
    'reject_meal_plan',
    'complete_meal_plan_as_eaten',
    'trg_nutrition_meal_plan_targets_after_insert_notify',
    'nutrition_meal_plan_targets_guard_columns',
    'touch_nutrition_meal_plan_target_updated_at'
  )
order by p.proname;

select
  tgname,
  tgrelid::regclass as table_name
from pg_trigger
where tgrelid in (
  'public.nutrition_meal_plan_targets'::regclass
)
  and not tgisinternal
order by tgname;

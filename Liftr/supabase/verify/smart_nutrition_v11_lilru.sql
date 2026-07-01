select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'nutrition_log_metrics_v1',
    'nutrition_top_food_contributors_v1',
    'nutrition_meal_slot_summary_v1',
    'nutrition_training_rest_split_v1',
    'nutrition_weight_trend_v1',
    'nutrition_logging_quality_v1',
    'nutrition_smart_recommendation_compute_v2',
    'get_smart_nutrition_recommendation_v2',
    'get_daily_nutrition_insights_v1'
  )
order by p.proname;

select
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'profiles'
  and column_name in ('nutrition_goal', 'nutrition_goal_rate_kg_per_week')
order by column_name;

with lilru as (
  select '4f009d0b-547e-4090-aa7e-1c70197e9e99'::uuid as user_id
),
result as (
  select public.nutrition_smart_recommendation_compute_v2(
    (select user_id from lilru),
    '2026-05-19'::date,
    '2026-06-28'::date
  ) as payload
)
select
  jsonb_array_length(payload->'insights') as insight_count,
  (payload->>'archetype') as archetype,
  (payload->>'nutrition_goal') as nutrition_goal
from result;

select
  x->>'id' as insight_id,
  x->>'category' as category,
  x->>'sentiment' as sentiment,
  x->>'title' as title
from (
  select public.nutrition_smart_recommendation_compute_v2(
    '4f009d0b-547e-4090-aa7e-1c70197e9e99'::uuid,
    '2026-05-19'::date,
    '2026-06-28'::date
  )->'insights' as insights
) r,
jsonb_array_elements(r.insights) x;

select
  jsonb_array_length(payload->'insights') >= 6 as passes_minimum_insight_count
from (
  select public.nutrition_smart_recommendation_compute_v2(
    '4f009d0b-547e-4090-aa7e-1c70197e9e99'::uuid,
    '2026-05-19'::date,
    '2026-06-28'::date
  ) as payload
) q;

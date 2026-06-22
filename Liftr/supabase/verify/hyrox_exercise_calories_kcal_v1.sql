select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'hyrox_session_exercises'
  and column_name = 'calories_kcal';

select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'hyrox_routine_exercises'
  and column_name = 'calories_kcal';

select p.proname,
       pg_get_functiondef(p.oid) ilike '%calories_kcal%' as mentions_calories_kcal
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_sport_workout_v2', 'update_sport_workout_v2');

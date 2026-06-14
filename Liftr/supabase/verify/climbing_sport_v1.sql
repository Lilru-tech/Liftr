-- Climbing sport v1 verification
select 'climbing_session_stats' as obj, to_regclass('public.climbing_session_stats')::text as ok;
select 'climbing_session_routes' as obj, to_regclass('public.climbing_session_routes')::text as ok;

select proname from pg_proc
where proname in (
  'apply_climbing_sport_stats',
  'climbing_grade_normalize',
  'score_climbing_v1',
  'get_climbing_routes_sent_leaderboard_v1',
  'unlock_climbing_achievements'
)
order by 1;

select count(*) as climbing_achievements
from public.achievements
where code like 'climbing_%';

select public.climbing_grade_normalize('v_scale', 'V5') as v5_norm;
select public.climbing_grade_normalize('french', '7a') as french_7a_norm;
select public.climbing_grade_normalize('yds', '5.11c') as yds_511c_norm;

select pg_get_functiondef(p.oid) like '%climbing%' as create_rpc_has_climbing
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_sport_workout_v2';

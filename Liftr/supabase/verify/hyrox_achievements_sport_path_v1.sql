select
  (
    select count(*)
    from public.sport_sessions ss
    join public.workouts w on w.id = ss.workout_id
    where w.state = 'published'
      and lower(ss.sport) = 'hyrox'
  ) as published_sport_hyrox_sessions,
  (
    select count(*)
    from public.cardio_sessions cs
    where lower(coalesce(cs.activity_type, '')) = 'hyrox'
       or lower(coalesce(cs.activity_code, '')) = 'hyrox'
  ) as cardio_hyrox_sessions;

select
  to_regprocedure('public.unlock_hyrox_achievements(uuid)') is not null as has_unlock_hyrox;

select pg_get_functiondef(p.oid) like '%sport_sessions%' as unlock_hyrox_uses_sport_path
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'unlock_hyrox_achievements';

select
  a.code,
  count(*)::bigint as times_unlocked
from public.user_achievements ua
join public.achievements a on a.id = ua.achievement_id
where a.code like 'hyrox_%'
group by a.code
order by a.code;

select
  pr.username,
  g.code,
  g.is_unlocked,
  g.progress_current,
  g.requirement_value
from public.profiles pr
cross join lateral (
  select code, is_unlocked, progress_current, requirement_value
  from public.get_user_achievements(pr.user_id)
  where code like 'hyrox_%'
) g
where pr.username in ('Lilru', 'Lauratrix', 'Elborbla')
order by pr.username, g.code;

select
  code,
  is_unlocked,
  progress_current,
  requirement_value
from public.get_user_achievements('4f009d0b-547e-4090-aa7e-1c70197e9e99'::uuid)
where code like 'hyrox_%'
order by code;

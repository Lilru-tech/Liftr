select count(*)::bigint as orphan_user_achievements
from public.user_achievements ua
where not exists (
  select 1 from public.profiles p where p.user_id = ua.user_id
);

select count(*)::bigint as publishing_users_with_profile
from (
  select distinct w.user_id
  from public.workouts w
  inner join public.profiles p on p.user_id = w.user_id
  where w.state = 'published'
) pu;

with publishing_users as (
  select distinct w.user_id
  from public.workouts w
  inner join public.profiles p on p.user_id = w.user_id
  where w.state = 'published'
),
active_community as (
  select count(*)::bigint as n from publishing_users
),
unlocks_by_achievement as (
  select ua.achievement_id,
         count(distinct ua.user_id)::bigint as unlocked_n
  from public.user_achievements ua
  inner join publishing_users pu on pu.user_id = ua.user_id
  group by ua.achievement_id
),
community_stats as (
  select
    a.code,
    least(
      100.0,
      round(
        (100.0 * coalesce(u.unlocked_n, 0)::numeric / nullif(ac.n, 0)::numeric),
        1
      )
    )::double precision as pct_unlocked,
    ac.n::integer as sample_size
  from public.achievements a
  cross join active_community ac
  left join unlocks_by_achievement u on u.achievement_id = a.id
)
select code, pct_unlocked, sample_size
from community_stats
where pct_unlocked > 100
order by pct_unlocked desc;

select
  code,
  community_pct_unlocked,
  community_sample_size
from public.get_user_achievements(
  (select user_id from public.profiles where username = 'Taniam' limit 1)
)
where code = 'achievements_1'
   or community_pct_unlocked > 100
order by community_pct_unlocked desc nulls last
limit 20;

select pg_get_functiondef(p.oid) like '%publishing_users%' as uses_publishing_users_cte
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_user_achievements';

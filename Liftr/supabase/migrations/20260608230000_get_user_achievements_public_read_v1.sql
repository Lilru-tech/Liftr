create or replace function public.get_user_achievements(p_user_id uuid)
returns table(
  achievement_id bigint,
  code text,
  title text,
  description text,
  category text,
  requirement_type text,
  requirement_value integer,
  icon_url text,
  user_id uuid,
  unlocked_at timestamp with time zone,
  is_unlocked boolean,
  progress_current double precision,
  community_pct_unlocked double precision,
  community_sample_size integer
)
language sql
stable
security definer
set search_path = public
as $function$
  with published_cardio_workouts as (
    select count(distinct w.id)::double precision as n
    from public.workouts w
    join public.cardio_sessions cs on cs.workout_id = w.id
    where w.user_id = p_user_id
      and w.state = 'published'
  ),
  active_community as (
    select count(distinct w.user_id)::bigint as n
    from public.workouts w
    where w.state = 'published'
  ),
  unlocks_by_achievement as (
    select ua.achievement_id,
           count(distinct ua.user_id)::bigint as unlocked_n
    from public.user_achievements ua
    group by ua.achievement_id
  ),
  achievement_community_threshold as (
    select 1::bigint as min_publishing_users
  ),
  community_stats as (
    select
      a.id as achievement_id,
      case
        when ac.n < th.min_publishing_users then null::double precision
        else round(
          (100.0 * coalesce(u.unlocked_n, 0)::numeric / nullif(ac.n, 0)::numeric),
          1
        )::double precision
      end as pct_unlocked,
      case
        when ac.n < th.min_publishing_users then null::integer
        else ac.n::integer
      end as sample_size
    from public.achievements a
    cross join active_community ac
    cross join achievement_community_threshold th
    left join unlocks_by_achievement u on u.achievement_id = a.id
  )
  select
    a.id as achievement_id,
    a.code,
    a.name as title,
    a.description,
    a.category,
    a.requirement_type,
    a.requirement_value,
    a.icon_url,
    ua.user_id,
    ua.unlocked_at,
    (ua.user_id is not null) as is_unlocked,
    case
        when ua.user_id is not null then a.requirement_value::double precision
        when a.requirement_type = 'count'
         and a.code like 'cardio_sessions_%'
        then (select n from published_cardio_workouts)
        else null::double precision
    end as progress_current,
    c.pct_unlocked as community_pct_unlocked,
    c.sample_size as community_sample_size
  from public.achievements a
  left join public.user_achievements ua
    on ua.achievement_id = a.id
   and ua.user_id = p_user_id
  left join community_stats c on c.achievement_id = a.id
  order by (ua.user_id is not null) desc, a.category, title
$function$;

revoke all on function public.get_user_achievements(uuid) from public;
grant execute on function public.get_user_achievements(uuid) to authenticated;
grant execute on function public.get_user_achievements(uuid) to service_role;

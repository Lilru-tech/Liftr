set local check_function_bodies = off;

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
  community_sample_size integer,
  is_tracked boolean
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
  published_hyrox_workouts as (
    select distinct w.id, w.started_at
    from public.sport_sessions ss
    join public.workouts w on w.id = ss.workout_id
    where w.user_id = p_user_id
      and w.state = 'published'
      and lower(ss.sport) = 'hyrox'
    union
    select distinct w.id, w.started_at
    from public.workouts w
    join public.cardio_sessions cs on cs.workout_id = w.id
    where w.user_id = p_user_id
      and w.state = 'published'
      and (
        lower(coalesce(cs.activity_type, '')) = 'hyrox'
        or lower(coalesce(cs.activity_code, '')) = 'hyrox'
      )
  ),
  published_hyrox_sessions as (
    select count(*)::double precision as n
    from published_hyrox_workouts
  ),
  published_hyrox_days as (
    select count(distinct (started_at at time zone 'UTC')::date)::double precision as n
    from published_hyrox_workouts
  ),
  publishing_users as (
    select distinct w.user_id
    from public.workouts w
    inner join public.profiles p on p.user_id = w.user_id
    where w.state = 'published'
  ),
  active_community as (
    select count(*)::bigint as n
    from publishing_users
  ),
  unlocks_by_achievement as (
    select ua.achievement_id,
           count(distinct ua.user_id)::bigint as unlocked_n
    from public.user_achievements ua
    inner join publishing_users pu on pu.user_id = ua.user_id
    group by ua.achievement_id
  ),
  achievement_community_threshold as (
    select 3::bigint as min_publishing_users
  ),
  community_stats as (
    select
      a.id as achievement_id,
      case
        when ac.n < th.min_publishing_users then null::double precision
        else least(
          100.0,
          round(
            (100.0 * coalesce(u.unlocked_n, 0)::numeric / nullif(ac.n, 0)::numeric),
            1
          )
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
      when a.requirement_type = 'count'
       and a.code like 'hyrox_sessions_%'
      then (select n from published_hyrox_sessions)
      when a.requirement_type = 'count'
       and a.code like 'hyrox_days_%'
      then (select n from published_hyrox_days)
      when a.requirement_type = 'count'
       and (a.code like 'pet_%' or a.code like 'coins_%')
      then public.liftr_achievement_progress_current(p_user_id, a.code, a.requirement_type)
      else null::double precision
    end as progress_current,
    c.pct_unlocked as community_pct_unlocked,
    c.sample_size as community_sample_size,
    (ut.user_id is not null) as is_tracked
  from public.achievements a
  left join public.user_achievements ua
    on ua.achievement_id = a.id
   and ua.user_id = p_user_id
  left join public.user_tracked_achievements ut
    on ut.achievement_id = a.id
   and ut.user_id = p_user_id
  left join community_stats c on c.achievement_id = a.id
  order by (ua.user_id is not null) desc, a.category, title
$function$;

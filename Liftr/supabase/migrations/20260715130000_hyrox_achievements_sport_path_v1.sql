set local check_function_bodies = off;

create or replace function public.unlock_hyrox_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_sessions int := 0;
  v_days int := 0;
begin
  with hyrox_workouts as (
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
  )
  select
    count(*)::int,
    count(distinct (started_at at time zone 'UTC')::date)::int
  into v_sessions, v_days
  from hyrox_workouts;

  if v_sessions >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'hyrox_sessions_1'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_sessions >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'hyrox_sessions_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_sessions >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'hyrox_sessions_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_days >= 7 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'hyrox_days_7'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_days >= 30 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'hyrox_days_30'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

drop function if exists public.get_user_achievements(uuid);

create function public.get_user_achievements(p_user_id uuid)
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

create or replace function public.get_tracked_achievement_count_v1(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_count integer := 0;
  v_top_progress_pct integer := 0;
begin
  select count(*)::integer
  into v_count
  from public.user_tracked_achievements ut
  where ut.user_id = p_user_id;

  if v_count > 0 then
    select coalesce(
      max(
        case
          when a.requirement_value is null or a.requirement_value <= 0 then 0
          when ua.user_id is not null then 100
          else least(
            100,
            greatest(
              0,
              floor(
                (
                  coalesce(
                    case
                      when a.requirement_type = 'count'
                       and a.code like 'cardio_sessions_%'
                      then (
                        select count(distinct w.id)::double precision
                        from public.workouts w
                        join public.cardio_sessions cs on cs.workout_id = w.id
                        where w.user_id = p_user_id
                          and w.state = 'published'
                      )
                      when a.requirement_type = 'count'
                       and a.code like 'hyrox_sessions_%'
                      then (
                        select count(*)::double precision
                        from (
                          select distinct w.id
                          from public.sport_sessions ss
                          join public.workouts w on w.id = ss.workout_id
                          where w.user_id = p_user_id
                            and w.state = 'published'
                            and lower(ss.sport) = 'hyrox'
                          union
                          select distinct w.id
                          from public.workouts w
                          join public.cardio_sessions cs on cs.workout_id = w.id
                          where w.user_id = p_user_id
                            and w.state = 'published'
                            and (
                              lower(coalesce(cs.activity_type, '')) = 'hyrox'
                              or lower(coalesce(cs.activity_code, '')) = 'hyrox'
                            )
                        ) hyrox_workouts
                      )
                      when a.requirement_type = 'count'
                       and a.code like 'hyrox_days_%'
                      then (
                        select count(distinct (started_at at time zone 'UTC')::date)::double precision
                        from (
                          select w.started_at
                          from public.sport_sessions ss
                          join public.workouts w on w.id = ss.workout_id
                          where w.user_id = p_user_id
                            and w.state = 'published'
                            and lower(ss.sport) = 'hyrox'
                          union all
                          select w.started_at
                          from public.workouts w
                          join public.cardio_sessions cs on cs.workout_id = w.id
                          where w.user_id = p_user_id
                            and w.state = 'published'
                            and (
                              lower(coalesce(cs.activity_type, '')) = 'hyrox'
                              or lower(coalesce(cs.activity_code, '')) = 'hyrox'
                            )
                        ) hyrox_days
                      )
                      when a.requirement_type = 'count'
                       and (a.code like 'pet_%' or a.code like 'coins_%')
                      then public.liftr_achievement_progress_current(
                        p_user_id,
                        a.code,
                        a.requirement_type
                      )
                      else 0::double precision
                    end,
                    0::double precision
                  ) / a.requirement_value::double precision
                ) * 100.0
              )
            )::integer
          )
        end
      ),
      0
    )
    into v_top_progress_pct
    from public.user_tracked_achievements ut
    join public.achievements a on a.id = ut.achievement_id
    left join public.user_achievements ua
      on ua.user_id = p_user_id
     and ua.achievement_id = a.id;
  end if;

  return jsonb_build_object(
    'count', v_count,
    'top_progress_pct', v_top_progress_pct
  );
end;
$function$;

do $backfill$
declare
  r record;
begin
  for r in
    select distinct w.user_id
    from public.sport_sessions ss
    join public.workouts w on w.id = ss.workout_id
    where w.state = 'published'
      and lower(ss.sport) = 'hyrox'
  loop
    perform public.check_and_unlock_achievements_for(r.user_id);
  end loop;
end $backfill$;

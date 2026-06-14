set local check_function_bodies = off;

create table if not exists public.user_tracked_achievements (
  user_id uuid not null references auth.users (id) on delete cascade,
  achievement_id bigint not null references public.achievements (id) on delete cascade,
  tracked_at timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

create index if not exists user_tracked_achievements_user_id_idx
  on public.user_tracked_achievements (user_id);

alter table public.user_tracked_achievements enable row level security;

drop policy if exists user_tracked_achievements_select_own on public.user_tracked_achievements;
create policy user_tracked_achievements_select_own
  on public.user_tracked_achievements
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists user_tracked_achievements_insert_own on public.user_tracked_achievements;
create policy user_tracked_achievements_insert_own
  on public.user_tracked_achievements
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_tracked_achievements_delete_own on public.user_tracked_achievements;
create policy user_tracked_achievements_delete_own
  on public.user_tracked_achievements
  for delete
  to authenticated
  using (user_id = auth.uid());

create or replace function public.trg_fn_untrack_achievement_on_unlock()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  delete from public.user_tracked_achievements
  where user_id = new.user_id
    and achievement_id = new.achievement_id;
  return new;
end;
$function$;

drop trigger if exists trg_untrack_achievement_on_unlock on public.user_achievements;
create trigger trg_untrack_achievement_on_unlock
  after insert on public.user_achievements
  for each row
  execute function public.trg_fn_untrack_achievement_on_unlock();

create or replace function public.toggle_tracked_achievement_v1(p_achievement_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_tracked boolean;
  v_count integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1 from public.achievements a where a.id = p_achievement_id
  ) then
    raise exception 'achievement_not_found';
  end if;

  if exists (
    select 1
    from public.user_achievements ua
    where ua.user_id = v_user_id
      and ua.achievement_id = p_achievement_id
  ) then
    raise exception 'already_unlocked';
  end if;

  if exists (
    select 1
    from public.user_tracked_achievements ut
    where ut.user_id = v_user_id
      and ut.achievement_id = p_achievement_id
  ) then
    delete from public.user_tracked_achievements
    where user_id = v_user_id
      and achievement_id = p_achievement_id;
    v_tracked := false;
  else
    select count(*)::integer
    into v_count
    from public.user_tracked_achievements ut
    where ut.user_id = v_user_id;

    if v_count >= 5 then
      raise exception 'tracked_limit_reached';
    end if;

    insert into public.user_tracked_achievements (user_id, achievement_id)
    values (v_user_id, p_achievement_id);
    v_tracked := true;
  end if;

  select count(*)::integer
  into v_count
  from public.user_tracked_achievements ut
  where ut.user_id = v_user_id;

  return jsonb_build_object(
    'tracked', v_tracked,
    'tracked_count', v_count
  );
end;
$function$;

revoke all on function public.toggle_tracked_achievement_v1(bigint) from public;
grant execute on function public.toggle_tracked_achievement_v1(bigint) to authenticated;

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

revoke all on function public.get_tracked_achievement_count_v1(uuid) from public;
grant execute on function public.get_tracked_achievement_count_v1(uuid) to authenticated;

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

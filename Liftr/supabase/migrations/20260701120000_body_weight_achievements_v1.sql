begin;

alter table public.achievements
  drop constraint if exists achievements_category_check;

alter table public.achievements
  add constraint achievements_category_check
  check (
    category = any (
      array[
        'general', 'strength', 'cardio', 'sport', 'social', 'streak', 'ranking', 'pet', 'coins', 'health'
      ]::text[]
    )
  );

insert into public.achievements (
  code, name, description, category, requirement_type, requirement_value, coin_reward_tier, created_at
)
values
  (
    'body_weight_first_log',
    'First Reading',
    'Log your first body weight entry.',
    'health',
    'count',
    1,
    'bronze',
    now()
  ),
  (
    'body_weight_logs_10',
    'Steady Tracker',
    'Log body weight on 10 separate occasions.',
    'health',
    'count',
    10,
    'silver',
    now()
  ),
  (
    'body_weight_logs_50',
    'Long-Term Tracker',
    'Log body weight on 50 separate occasions.',
    'health',
    'count',
    50,
    'gold',
    now()
  ),
  (
    'body_weight_health_sync_first',
    'Connected',
    'Import your first body weight from Apple Health or Health Connect.',
    'health',
    'count',
    1,
    'bronze',
    now()
  ),
  (
    'body_weight_months_3',
    'Three Months',
    'Log body weight in 3 different calendar months.',
    'health',
    'count',
    3,
    'silver',
    now()
  ),
  (
    'body_weight_months_6',
    'Half-Year Habit',
    'Log body weight in 6 different calendar months.',
    'health',
    'count',
    6,
    'gold',
    now()
  ),
  (
    'body_weight_span_90d',
    'Over Time',
    'Keep weight entries spanning at least 90 days with 3 or more readings.',
    'health',
    'count',
    90,
    'gold',
    now()
  ),
  (
    'body_weight_sources_both',
    'Two Sources',
    'Log body weight both manually and via a health app.',
    'health',
    'count',
    2,
    'silver',
    now()
  )
on conflict (code) do nothing;

create or replace function public.liftr_user_body_weight_metrics(p_user_id uuid)
returns table (
  total_entries bigint,
  distinct_months integer,
  span_days integer,
  has_manual boolean,
  has_health_sync boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(*)::bigint as total_entries,
    count(distinct date_trunc('month', measured_at at time zone 'UTC'))::integer as distinct_months,
    case
      when count(*) >= 2 then
        greatest(
          0,
          floor(extract(epoch from (max(measured_at) - min(measured_at))) / 86400.0)
        )::integer
      else 0
    end as span_days,
    coalesce(bool_or(source = 'manual'), false) as has_manual,
    coalesce(bool_or(source in ('apple_health', 'health_connect')), false) as has_health_sync
  from public.body_weight_entries
  where user_id = p_user_id;
$$;

create or replace function public.unlock_body_weight_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  m record;
begin
  select * into m from public.liftr_user_body_weight_metrics(p_user_id);

  if m.total_entries >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_first_log'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_entries >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_logs_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_entries >= 50 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_logs_50'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.has_health_sync then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_health_sync_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.distinct_months >= 3 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_months_3'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.distinct_months >= 6 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_months_6'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_entries >= 3 and m.span_days >= 90 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_span_90d'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.has_manual and m.has_health_sync then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'body_weight_sources_both'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

create or replace function public.liftr_achievement_progress_current(
  p_user_id uuid,
  p_code text,
  p_requirement_type text
)
returns double precision
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  m record;
  d record;
  bw record;
  v_lifetime bigint;
  v_pet_sources bigint;
  v_source_progress double precision;
begin
  if p_requirement_type is distinct from 'count' then
    return null;
  end if;

  if p_code like 'coins_%' then
    v_lifetime := public.liftr_user_lifetime_coins_earned(p_user_id);
    v_pet_sources :=
      public.liftr_user_coin_source_total(p_user_id, 'pet_coins')
      + public.liftr_user_coin_source_total(p_user_id, 'pet_combat')
      + public.liftr_user_coin_source_total(p_user_id, 'pet_workout_bonus');
    return case p_code
      when 'coins_earned_first' then v_lifetime::double precision
      when 'coins_earned_100' then v_lifetime::double precision
      when 'coins_earned_500' then v_lifetime::double precision
      when 'coins_earned_1000' then v_lifetime::double precision
      when 'coins_earned_5000' then v_lifetime::double precision
      when 'coins_earned_10000' then v_lifetime::double precision
      when 'coins_earned_25000' then v_lifetime::double precision
      when 'coins_earned_50000' then v_lifetime::double precision
      when 'coins_workouts_1000' then public.liftr_user_coin_source_total(p_user_id, 'workouts')::double precision
      when 'coins_social_500' then public.liftr_user_coin_source_total(p_user_id, 'social')::double precision
      when 'coins_nutrition_500' then public.liftr_user_coin_source_total(p_user_id, 'nutrition')::double precision
      when 'coins_pet_sources_1000' then v_pet_sources::double precision
      else null
    end;
  end if;

  if p_code like 'pet_%' then
    select * into m from public.liftr_user_pet_metrics(p_user_id);
    select * into d from public.liftr_user_pet_dex_metrics(p_user_id);
    return case p_code
      when 'pet_incubation_first' then m.incubations::double precision
      when 'pet_hatched_first' then greatest(m.hatches, case when m.max_stage_rank >= 1 then 1 else 0 end)::double precision
      when 'pet_feed_10' then m.total_feedings::double precision
      when 'pet_feed_100' then m.total_feedings::double precision
      when 'pet_evolve_kid' then case when m.max_stage_rank >= 2 then 1 else 0 end::double precision
      when 'pet_evolve_teen' then case when m.max_stage_rank >= 3 then 1 else 0 end::double precision
      when 'pet_evolve_adult' then case when m.max_stage_rank >= 4 then 1 else 0 end::double precision
      when 'pet_evolve_elder' then case when m.max_stage_rank >= 5 then 1 else 0 end::double precision
      when 'pet_level_50' then m.current_level::double precision
      when 'pet_level_100' then m.current_level::double precision
      when 'pet_rarity_rare' then case when m.max_rarity_sort >= 3 then 1 else 0 end::double precision
      when 'pet_rarity_epic' then case when m.max_rarity_sort >= 4 then 1 else 0 end::double precision
      when 'pet_rarity_mythic' then case when m.max_rarity_sort >= 6 then 1 else 0 end::double precision
      when 'pet_combat_first' then m.total_battles::double precision
      when 'pet_combat_wins_10' then m.wins::double precision
      when 'pet_combat_streak_5' then m.best_win_streak::double precision
      when 'pet_combat_all_rarities' then d.rarities_discovered::double precision
      when 'pet_combat_all_species' then d.species_discovered::double precision
      when 'pet_combat_all_stages' then d.stages_discovered::double precision
      when 'pet_coins_passive_1000' then m.passive_pet_coins::double precision
      when 'pet_workout_bonus_10' then m.workout_bonus_count::double precision
      when 'pet_egg_reroll_5' then m.reroll_count::double precision
      when 'pet_energy_max_7' then m.max_energy::double precision
      else null
    end;
  end if;

  if p_code like 'body_weight_%' then
    select * into bw from public.liftr_user_body_weight_metrics(p_user_id);
    v_source_progress :=
      (case when bw.has_manual then 1 else 0 end
      + case when bw.has_health_sync then 1 else 0 end)::double precision;
    return case p_code
      when 'body_weight_first_log' then bw.total_entries::double precision
      when 'body_weight_logs_10' then bw.total_entries::double precision
      when 'body_weight_logs_50' then bw.total_entries::double precision
      when 'body_weight_health_sync_first' then case when bw.has_health_sync then 1 else 0 end::double precision
      when 'body_weight_months_3' then bw.distinct_months::double precision
      when 'body_weight_months_6' then bw.distinct_months::double precision
      when 'body_weight_span_90d' then
        case when bw.total_entries >= 3 then bw.span_days::double precision else 0 end
      when 'body_weight_sources_both' then v_source_progress
      else null
    end;
  end if;

  return null;
end;
$function$;

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
       and (a.code like 'pet_%' or a.code like 'coins_%' or a.code like 'body_weight_%')
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
                       and (a.code like 'pet_%' or a.code like 'coins_%' or a.code like 'body_weight_%')
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

do $patch$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'check_and_unlock_achievements_for'
    and pg_get_function_identity_arguments(p.oid) = 'p_user_id uuid';

  if v_def is null then
    raise notice 'check_and_unlock_achievements_for not found; wire unlock_body_weight manually';
    return;
  end if;

  if v_def like '%unlock_body_weight_achievements%' then
    return;
  end if;

  if v_def like '%unlock_ranking_achievements%' then
    v_def := replace(
      v_def,
      $needle$  sig  := 'public.unlock_ranking_achievements(uuid)';$needle$,
      $needle$  sig  := 'public.unlock_body_weight_achievements(uuid)';
  call := 'SELECT public.unlock_body_weight_achievements($1)';
  if to_regprocedure(sig) is not null then execute call using p_user_id; end if;

  sig  := 'public.unlock_ranking_achievements(uuid)';$needle$
    );
  elsif v_def like '%unlock_coin_achievements%' then
    v_def := replace(
      v_def,
      $needle$  sig  := 'public.unlock_coin_achievements(uuid)';$needle$,
      $needle$  sig  := 'public.unlock_body_weight_achievements(uuid)';
  call := 'SELECT public.unlock_body_weight_achievements($1)';
  if to_regprocedure(sig) is not null then execute call using p_user_id; end if;

  sig  := 'public.unlock_coin_achievements(uuid)';$needle$
    );
  else
    v_def := replace(
      v_def,
      E'  return;\nend;\n$function$',
      E'  sig  := ''public.unlock_body_weight_achievements(uuid)'';\n  call := ''SELECT public.unlock_body_weight_achievements($1)'';\n  if to_regprocedure(sig) is not null then execute call using p_user_id; end if;\n\n  return;\nend;\n$function$'
    );
  end if;

  if v_def not like '%unlock_body_weight_achievements%' then
    raise warning 'check_and_unlock_achievements_for was not patched; add unlock_body_weight manually';
    return;
  end if;

  execute v_def;
end;
$patch$;

create or replace function public.trg_fn_recheck_achievements_for_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user_id uuid;
begin
  v_user_id := case tg_table_name
    when 'coin_transactions' then new.user_id
    when 'pet_logs' then new.user_id
    when 'pet_instances' then new.user_id
    when 'pet_combat_user_stats' then new.user_id
    when 'profiles' then new.user_id
    when 'body_weight_entries' then new.user_id
    else null
  end;

  if v_user_id is not null then
    perform public.check_and_unlock_achievements_for(v_user_id);
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_achievements_on_body_weight_entry on public.body_weight_entries;
create trigger trg_achievements_on_body_weight_entry
  after insert on public.body_weight_entries
  for each row
  execute function public.trg_fn_recheck_achievements_for_user();

do $backfill$
declare
  r record;
begin
  for r in
    select distinct user_id
    from public.body_weight_entries
  loop
    perform public.check_and_unlock_achievements_for(r.user_id);
  end loop;
end;
$backfill$;

revoke all on function public.liftr_user_body_weight_metrics(uuid) from public;
revoke all on function public.unlock_body_weight_achievements(uuid) from public;
grant execute on function public.liftr_user_body_weight_metrics(uuid) to authenticated;
grant execute on function public.unlock_body_weight_achievements(uuid) to service_role;

commit;

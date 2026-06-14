begin;

alter table public.achievements
  drop constraint if exists achievements_category_check;

alter table public.achievements
  add constraint achievements_category_check
  check (
    category = any (
      array[
        'general', 'strength', 'cardio', 'sport', 'social', 'streak', 'ranking', 'pet', 'coins'
      ]::text[]
    )
  );

insert into public.achievements (
  code, name, description, category, requirement_type, requirement_value, coin_reward_tier, created_at
)
values
  (
    'pet_incubation_first',
    'First Incubator',
    'Start incubating your first pet egg.',
    'pet',
    'count',
    1,
    'bronze',
    now()
  ),
  (
    'pet_hatched_first',
    'Welcome to the World',
    'Hatch your first pet.',
    'pet',
    'count',
    1,
    'bronze',
    now()
  ),
  (
    'pet_feed_10',
    'Snack Time',
    'Feed your pet 10 times.',
    'pet',
    'count',
    10,
    'bronze',
    now()
  ),
  (
    'pet_feed_100',
    'Dedicated Trainer',
    'Feed your pet 100 times.',
    'pet',
    'count',
    100,
    'silver',
    now()
  ),
  (
    'pet_evolve_kid',
    'Growing Up',
    'Evolve a pet to the Kid stage.',
    'pet',
    'count',
    1,
    'bronze',
    now()
  ),
  (
    'pet_evolve_teen',
    'Teen Spirit',
    'Evolve a pet to the Teen stage.',
    'pet',
    'count',
    1,
    'silver',
    now()
  ),
  (
    'pet_evolve_adult',
    'Fully Grown',
    'Evolve a pet to the Adult stage.',
    'pet',
    'count',
    1,
    'silver',
    now()
  ),
  (
    'pet_evolve_elder',
    'Wise Elder',
    'Evolve a pet to the Elder stage.',
    'pet',
    'count',
    1,
    'gold',
    now()
  ),
  (
    'pet_level_50',
    'Halfway Hero',
    'Reach pet level 50.',
    'pet',
    'count',
    50,
    'silver',
    now()
  ),
  (
    'pet_level_100',
    'Century Companion',
    'Reach pet level 100.',
    'pet',
    'count',
    100,
    'gold',
    now()
  ),
  (
    'pet_rarity_rare',
    'Rare Find',
    'Own a pet with Rare rarity or higher.',
    'pet',
    'count',
    1,
    'silver',
    now()
  ),
  (
    'pet_rarity_epic',
    'Epic Companion',
    'Own a pet with Epic rarity or higher.',
    'pet',
    'count',
    1,
    'silver',
    now()
  ),
  (
    'pet_rarity_mythic',
    'Mythic Master',
    'Own a Mythic pet.',
    'pet',
    'count',
    1,
    'gold',
    now()
  ),
  (
    'pet_combat_first',
    'Arena Debut',
    'Complete your first pet arena battle.',
    'pet',
    'count',
    1,
    'bronze',
    now()
  ),
  (
    'pet_combat_wins_10',
    'Battle Veteran',
    'Win 10 pet arena battles.',
    'pet',
    'count',
    10,
    'silver',
    now()
  ),
  (
    'pet_combat_streak_5',
    'Unstoppable',
    'Win 5 pet arena battles in a row.',
    'pet',
    'count',
    5,
    'gold',
    now()
  ),
  (
    'pet_coins_passive_1000',
    'Passive Income',
    'Earn 1,000 Liftr Coins from passive pet generation.',
    'pet',
    'count',
    1000,
    'silver',
    now()
  ),
  (
    'pet_workout_bonus_10',
    'Training Partner',
    'Earn 10 workout pet training coin bonuses.',
    'pet',
    'count',
    10,
    'silver',
    now()
  ),
  (
    'pet_egg_reroll_5',
    'Picky Parent',
    'Reroll a pet egg 5 times.',
    'pet',
    'count',
    5,
    'silver',
    now()
  ),
  (
    'pet_energy_max_7',
    'Endurance Trainer',
    'Upgrade your arena energy capacity to at least 7.',
    'pet',
    'count',
    7,
    'gold',
    now()
  ),
  (
    'coins_earned_first',
    'First Coin',
    'Earn your first Liftr Coin.',
    'coins',
    'count',
    1,
    'bronze',
    now()
  ),
  (
    'coins_earned_100',
    'Pocket Change',
    'Earn 100 Liftr Coins in total.',
    'coins',
    'count',
    100,
    'bronze',
    now()
  ),
  (
    'coins_earned_500',
    'Coin Collector',
    'Earn 500 Liftr Coins in total.',
    'coins',
    'count',
    500,
    'bronze',
    now()
  ),
  (
    'coins_earned_1000',
    'Thousand Club',
    'Earn 1,000 Liftr Coins in total.',
    'coins',
    'count',
    1000,
    'silver',
    now()
  ),
  (
    'coins_earned_5000',
    'Serious Saver',
    'Earn 5,000 Liftr Coins in total.',
    'coins',
    'count',
    5000,
    'silver',
    now()
  ),
  (
    'coins_earned_10000',
    'Coin Vault',
    'Earn 10,000 Liftr Coins in total.',
    'coins',
    'count',
    10000,
    'gold',
    now()
  ),
  (
    'coins_earned_25000',
    'Treasure Hunter',
    'Earn 25,000 Liftr Coins in total.',
    'coins',
    'count',
    25000,
    'gold',
    now()
  ),
  (
    'coins_earned_50000',
    'Liftr Tycoon',
    'Earn 50,000 Liftr Coins in total.',
    'coins',
    'count',
    50000,
    'gold',
    now()
  ),
  (
    'coins_workouts_1000',
    'Workout Payoff',
    'Earn 1,000 Liftr Coins from published workouts.',
    'coins',
    'count',
    1000,
    'silver',
    now()
  ),
  (
    'coins_social_500',
    'Social Earner',
    'Earn 500 Liftr Coins from social actions.',
    'coins',
    'count',
    500,
    'silver',
    now()
  ),
  (
    'coins_nutrition_500',
    'Nutrition Rewards',
    'Earn 500 Liftr Coins from nutrition logging and creation.',
    'coins',
    'count',
    500,
    'silver',
    now()
  ),
  (
    'coins_pet_sources_1000',
    'Pet Economy',
    'Earn 1,000 Liftr Coins from pet coin sources.',
    'coins',
    'count',
    1000,
    'silver',
    now()
  )
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  category = excluded.category,
  requirement_type = excluded.requirement_type,
  requirement_value = excluded.requirement_value,
  coin_reward_tier = excluded.coin_reward_tier;

create or replace function public.liftr_user_lifetime_coins_earned(p_user_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(ct.amount), 0)::bigint
  from public.coin_transactions ct
  where ct.user_id = p_user_id
    and ct.amount > 0
    and public.liftr_coin_source_key(ct.action_type) is not null;
$$;

create or replace function public.liftr_user_coin_source_total(p_user_id uuid, p_source_key text)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(ct.amount), 0)::bigint
  from public.coin_transactions ct
  where ct.user_id = p_user_id
    and ct.amount > 0
    and public.liftr_coin_source_key(ct.action_type) = p_source_key;
$$;

create or replace function public.liftr_pet_stage_rank(p_stage text)
returns integer
language sql
immutable
as $$
  select case lower(coalesce(p_stage, 'egg'))
    when 'egg' then 0
    when 'baby' then 1
    when 'kid' then 2
    when 'teen' then 3
    when 'adult' then 4
    when 'elder' then 5
    else 0
  end;
$$;

create or replace function public.liftr_user_pet_metrics(p_user_id uuid)
returns table (
  incubations bigint,
  hatches bigint,
  total_feedings bigint,
  current_level integer,
  max_stage_rank integer,
  max_rarity_sort integer,
  reroll_count integer,
  max_energy integer,
  passive_pet_coins bigint,
  workout_bonus_count bigint,
  total_battles integer,
  wins integer,
  best_win_streak integer
)
language sql
stable
security definer
set search_path = public
as $$
  with active_pet as (
    select pi.*
    from public.pet_instances pi
    where pi.user_id = p_user_id
      and pi.is_active = true
    limit 1
  ),
  pet_agg as (
    select
      coalesce(max(public.liftr_pet_stage_rank(pi.evolution_stage)), 0) as max_stage_rank,
      coalesce(max(rc.sort_order), 0) as max_rarity_sort
    from public.pet_instances pi
    left join public.pet_rarity_config rc on rc.rarity = pi.rarity
    where pi.user_id = p_user_id
  )
  select
    (
      select count(*)::bigint
      from public.pet_logs pl
      where pl.user_id = p_user_id
        and pl.event_type = 'incubation_started'
    ) as incubations,
    (
      select count(*)::bigint
      from public.pet_logs pl
      where pl.user_id = p_user_id
        and pl.event_type = 'hatched'
    ) as hatches,
    coalesce((select ap.total_feedings from active_pet ap), 0)::bigint as total_feedings,
    coalesce((select ap.current_level from active_pet ap), 0) as current_level,
    pa.max_stage_rank,
    pa.max_rarity_sort,
    coalesce((select ap.reroll_count from active_pet ap), 0) as reroll_count,
    coalesce((
      select p.max_energy
      from public.profiles p
      where p.user_id = p_user_id
    ), 5) as max_energy,
    coalesce((
      select sum(ct.amount)::bigint
      from public.coin_transactions ct
      where ct.user_id = p_user_id
        and ct.amount > 0
        and ct.action_type = 'pet_coins_generated'
    ), 0) as passive_pet_coins,
    coalesce((
      select count(*)::bigint
      from public.coin_transactions ct
      where ct.user_id = p_user_id
        and ct.amount > 0
        and ct.action_type = 'workout_pet_training_bonus'
    ), 0) as workout_bonus_count,
    coalesce(cs.total_battles, 0) as total_battles,
    coalesce(cs.wins, 0) as wins,
    coalesce(cs.best_win_streak, 0) as best_win_streak
  from pet_agg pa
  left join public.pet_combat_user_stats cs on cs.user_id = p_user_id;
$$;

create or replace function public.unlock_pet_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  m record;
begin
  select * into m from public.liftr_user_pet_metrics(p_user_id);

  if m.incubations >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_incubation_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.hatches >= 1 or m.max_stage_rank >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_hatched_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_feedings >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_feed_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_feedings >= 100 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_feed_100'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 2 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_kid'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 3 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_teen'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 4 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_adult'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_elder'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.current_level >= 50 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_level_50'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.current_level >= 100 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_level_100'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_rarity_sort >= 3 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_rarity_rare'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_rarity_sort >= 4 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_rarity_epic'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_rarity_sort >= 6 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_rarity_mythic'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_battles >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.wins >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_wins_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.best_win_streak >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_streak_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.passive_pet_coins >= 1000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_coins_passive_1000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.workout_bonus_count >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_workout_bonus_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.reroll_count >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_egg_reroll_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_energy >= 7 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_energy_max_7'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

create or replace function public.unlock_coin_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_lifetime bigint := 0;
  v_workouts bigint := 0;
  v_social bigint := 0;
  v_nutrition bigint := 0;
  v_pet_sources bigint := 0;
begin
  v_lifetime := public.liftr_user_lifetime_coins_earned(p_user_id);
  v_workouts := public.liftr_user_coin_source_total(p_user_id, 'workouts');
  v_social := public.liftr_user_coin_source_total(p_user_id, 'social');
  v_nutrition := public.liftr_user_coin_source_total(p_user_id, 'nutrition');
  v_pet_sources :=
    public.liftr_user_coin_source_total(p_user_id, 'pet_coins')
    + public.liftr_user_coin_source_total(p_user_id, 'pet_combat')
    + public.liftr_user_coin_source_total(p_user_id, 'pet_workout_bonus');

  if v_lifetime >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_lifetime >= 100 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_100'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_lifetime >= 500 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_500'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_lifetime >= 1000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_1000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_lifetime >= 5000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_5000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_lifetime >= 10000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_10000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_lifetime >= 25000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_25000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_lifetime >= 50000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_earned_50000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_workouts >= 1000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_workouts_1000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_social >= 500 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_social_500'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_nutrition >= 500 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_nutrition_500'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_pet_sources >= 1000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'coins_pet_sources_1000'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

do $patch$
declare
  v_def text;
  v_insert text := E'  sig  := ''public.unlock_pet_achievements(uuid)'';\n  call := ''SELECT public.unlock_pet_achievements($1)'';\n  if to_regprocedure(sig) is not null then execute call using p_user_id; end if;\n\n  sig  := ''public.unlock_coin_achievements(uuid)'';\n  call := ''SELECT public.unlock_coin_achievements($1)'';\n  if to_regprocedure(sig) is not null then execute call using p_user_id; end if;\n\n';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'check_and_unlock_achievements_for'
    and pg_get_function_identity_arguments(p.oid) = 'p_user_id uuid';

  if v_def is null then
    raise notice 'check_and_unlock_achievements_for not found; wire unlock_pet/coin manually';
    return;
  end if;

  if v_def like '%unlock_pet_achievements%' then
    return;
  end if;

  v_def := replace(
    v_def,
    E'  return;\nend;\n$function$',
    v_insert || E'  return;\nend;\n$function$'
  );

  if v_def not like '%unlock_pet_achievements%' then
    raise warning 'check_and_unlock_achievements_for was not patched; add unlock_pet/coin manually';
    return;
  end if;

  execute v_def;
end;
$patch$;

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
  v_lifetime bigint;
  v_pet_sources bigint;
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
      when 'pet_coins_passive_1000' then m.passive_pet_coins::double precision
      when 'pet_workout_bonus_10' then m.workout_bonus_count::double precision
      when 'pet_egg_reroll_5' then m.reroll_count::double precision
      when 'pet_energy_max_7' then m.max_energy::double precision
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
      when a.requirement_type = 'count'
       and (a.code like 'pet_%' or a.code like 'coins_%')
      then public.liftr_achievement_progress_current(p_user_id, a.code, a.requirement_type)
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
    else null
  end;

  if v_user_id is not null then
    perform public.check_and_unlock_achievements_for(v_user_id);
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_achievements_on_coin_tx on public.coin_transactions;
create trigger trg_achievements_on_coin_tx
  after insert on public.coin_transactions
  for each row
  when (new.amount > 0)
  execute function public.trg_fn_recheck_achievements_for_user();

drop trigger if exists trg_achievements_on_pet_log on public.pet_logs;
create trigger trg_achievements_on_pet_log
  after insert on public.pet_logs
  for each row
  execute function public.trg_fn_recheck_achievements_for_user();

drop trigger if exists trg_achievements_on_pet_instance on public.pet_instances;
create trigger trg_achievements_on_pet_instance
  after insert or update of total_feedings, current_level, evolution_stage, rarity, reroll_count
  on public.pet_instances
  for each row
  execute function public.trg_fn_recheck_achievements_for_user();

drop trigger if exists trg_achievements_on_pet_combat_stats on public.pet_combat_user_stats;
create trigger trg_achievements_on_pet_combat_stats
  after insert or update on public.pet_combat_user_stats
  for each row
  execute function public.trg_fn_recheck_achievements_for_user();

drop trigger if exists trg_achievements_on_profile_energy on public.profiles;
create trigger trg_achievements_on_profile_energy
  after update of max_energy on public.profiles
  for each row
  when (new.max_energy is distinct from old.max_energy)
  execute function public.trg_fn_recheck_achievements_for_user();

do $backfill$
declare
  r record;
begin
  for r in select p.user_id from public.profiles p loop
    perform public.check_and_unlock_achievements_for(r.user_id);
  end loop;
end;
$backfill$;

revoke all on function public.liftr_user_lifetime_coins_earned(uuid) from public;
revoke all on function public.liftr_user_coin_source_total(uuid, text) from public;
revoke all on function public.liftr_pet_stage_rank(text) from public;
revoke all on function public.liftr_user_pet_metrics(uuid) from public;
revoke all on function public.unlock_pet_achievements(uuid) from public;
revoke all on function public.unlock_coin_achievements(uuid) from public;
revoke all on function public.liftr_achievement_progress_current(uuid, text, text) from public;
grant execute on function public.liftr_user_lifetime_coins_earned(uuid) to authenticated;
grant execute on function public.liftr_user_coin_source_total(uuid, text) to authenticated;
grant execute on function public.liftr_user_pet_metrics(uuid) to authenticated;
grant execute on function public.unlock_pet_achievements(uuid) to service_role;
grant execute on function public.unlock_coin_achievements(uuid) to service_role;
grant execute on function public.liftr_achievement_progress_current(uuid, text, text) to authenticated;

commit;

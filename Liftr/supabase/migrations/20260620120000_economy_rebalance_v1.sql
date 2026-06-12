begin;

create table if not exists public.pet_training_bonus_config (
  stage text not null,
  rarity public.pet_rarity not null,
  bonus_pct numeric(5, 2) not null,
  primary key (stage, rarity)
);

alter table public.pet_training_bonus_config enable row level security;

drop policy if exists pet_training_bonus_config_read on public.pet_training_bonus_config;
create policy pet_training_bonus_config_read on public.pet_training_bonus_config
  for select using (true);

insert into public.pet_training_bonus_config (stage, rarity, bonus_pct) values
  ('baby', 'common', 1.00),
  ('baby', 'uncommon', 2.00),
  ('baby', 'rare', 3.00),
  ('baby', 'epic', 4.00),
  ('baby', 'legendary', 5.00),
  ('baby', 'mythic', 8.00),
  ('kid', 'common', 3.00),
  ('kid', 'uncommon', 4.00),
  ('kid', 'rare', 6.00),
  ('kid', 'epic', 8.00),
  ('kid', 'legendary', 12.00),
  ('kid', 'mythic', 15.00),
  ('teen', 'common', 5.00),
  ('teen', 'uncommon', 7.00),
  ('teen', 'rare', 10.00),
  ('teen', 'epic', 14.00),
  ('teen', 'legendary', 18.00),
  ('teen', 'mythic', 22.00),
  ('adult', 'common', 10.00),
  ('adult', 'uncommon', 12.00),
  ('adult', 'rare', 16.00),
  ('adult', 'epic', 22.00),
  ('adult', 'legendary', 28.00),
  ('adult', 'mythic', 35.00),
  ('elder', 'common', 15.00),
  ('elder', 'uncommon', 18.00),
  ('elder', 'rare', 24.00),
  ('elder', 'epic', 32.00),
  ('elder', 'legendary', 42.00),
  ('elder', 'mythic', 50.00)
on conflict (stage, rarity) do update set bonus_pct = excluded.bonus_pct;

update public.pet_stage_rewards
set
  coins_min_per_hour = case lower(stage)
    when 'baby' then 3
    when 'kid' then 6
    when 'teen' then 9
    when 'adult' then 12
    when 'elder' then 15
    when 'egg' then 0
    else coins_min_per_hour
  end,
  coins_max_per_hour = case lower(stage)
    when 'baby' then 7
    when 'kid' then 11
    when 'teen' then 14
    when 'adult' then 18
    when 'elder' then 28
    when 'egg' then 0
    else coins_max_per_hour
  end;

create or replace function public.liftr_workout_coin_scale_factor()
returns numeric
language sql
immutable
as $$
  select 8.5::numeric;
$$;

create or replace function public.get_pet_training_bonus_pct_for_pet(p_stage text, p_rarity text)
returns numeric
language sql
stable
security definer
set search_path to public
as $$
  select coalesce((
    select btc.bonus_pct
    from public.pet_training_bonus_config btc
    where lower(btc.stage) = lower(p_stage)
      and lower(btc.rarity::text) = lower(p_rarity)
    limit 1
  ), 0::numeric);
$$;

create or replace function public.get_pet_training_bonus_pct(p_user_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_stage text;
  v_rarity text;
begin
  if p_user_id is null then
    return 0;
  end if;

  select pi.evolution_stage, pi.rarity::text
  into v_stage, v_rarity
  from public.pet_instances pi
  where pi.user_id = p_user_id
    and pi.is_active = true
  limit 1;

  if v_stage is null or lower(v_stage) = 'egg' then
    return 0;
  end if;

  return public.get_pet_training_bonus_pct_for_pet(v_stage, v_rarity);
end;
$$;

create or replace function public.resolve_pet_bonus_at_time(p_user_id uuid, p_at timestamptz)
returns numeric
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_instance_id uuid;
  v_stage text;
  v_rarity text;
  v_hatch_at timestamptz;
  v_bonus numeric;
begin
  if p_user_id is null or p_at is null then
    return 0;
  end if;

  select pi.id
  into v_instance_id
  from public.pet_instances pi
  where pi.user_id = p_user_id
    and pi.is_active = true
  limit 1;

  if v_instance_id is null then
    select pi.id
    into v_instance_id
    from public.pet_instances pi
    where pi.user_id = p_user_id
    order by pi.created_at desc
    limit 1;
  end if;

  if v_instance_id is null then
    return 0;
  end if;

  select min(pl.created_at)
  into v_hatch_at
  from public.pet_logs pl
  where pl.pet_instance_id = v_instance_id
    and pl.event_type = 'hatched';

  if v_hatch_at is null then
    select pi.hatch_at
    into v_hatch_at
    from public.pet_instances pi
    where pi.id = v_instance_id;
  end if;

  if v_hatch_at is null or v_hatch_at > p_at then
    return 0;
  end if;

  select coalesce(
    (
      select pl.details->>'to_stage'
      from public.pet_logs pl
      where pl.pet_instance_id = v_instance_id
        and pl.event_type = 'evolution'
        and pl.created_at <= p_at
      order by pl.created_at desc
      limit 1
    ),
    'baby'
  )
  into v_stage;

  select coalesce(
    (
      select pl.details->>'to_rarity'
      from public.pet_logs pl
      where pl.pet_instance_id = v_instance_id
        and pl.event_type = 'rarity_upgrade'
        and pl.created_at <= p_at
      order by pl.created_at desc
      limit 1
    ),
    (
      select pl.details->>'rarity'
      from public.pet_logs pl
      where pl.pet_instance_id = v_instance_id
        and pl.event_type = 'incubation_started'
        and pl.created_at <= p_at
      order by pl.created_at desc
      limit 1
    )
  )
  into v_rarity;

  if v_rarity is null then
    select pi.rarity::text
    into v_rarity
    from public.pet_instances pi
    where pi.id = v_instance_id;
  end if;

  v_bonus := public.get_pet_training_bonus_pct_for_pet(v_stage, v_rarity);

  if coalesce(v_bonus, 0) = 0 then
    return coalesce(public.get_pet_training_bonus_pct(p_user_id), 0);
  end if;

  return v_bonus;
end;
$$;

create or replace function public.compute_workout_coin_reward(p_workout_id bigint)
returns integer
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_kind text;
  v_duration_min integer;
  v_duration_sec integer;
  v_distance_km numeric;
  v_set_count integer;
  v_base integer := 10;
begin
  select w.kind, w.duration_min
  into v_kind, v_duration_min
  from public.workouts w
  where w.id = p_workout_id;

  if v_kind is null then
    return 0;
  end if;

  if v_kind = 'strength' then
    select count(*)::integer
    into v_set_count
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    where we.workout_id = p_workout_id;

    v_base := 10 + coalesce(v_set_count, 0);
    return round(greatest(v_base, 0) * public.liftr_workout_coin_scale_factor())::integer;
  end if;

  if v_kind = 'cardio' then
    select cs.duration_sec, cs.distance_km
    into v_duration_sec, v_distance_km
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
    limit 1;

    if v_duration_sec is null and v_duration_min is not null then
      v_duration_sec := v_duration_min * 60;
    end if;

    if coalesce(v_duration_sec, 0) >= 1800 then
      v_base := v_base + 5;
    end if;
    if coalesce(v_duration_sec, 0) >= 3600 then
      v_base := v_base + 5;
    end if;
    if coalesce(v_distance_km, 0) >= 5 then
      v_base := v_base + 5;
    end if;
    if coalesce(v_distance_km, 0) >= 10 then
      v_base := v_base + 10;
    end if;

    return round(greatest(v_base, 0) * public.liftr_workout_coin_scale_factor())::integer;
  end if;

  return round(greatest(v_base, 0) * public.liftr_workout_coin_scale_factor())::integer;
end;
$$;

create or replace function public.compute_workout_coin_reward_with_pet_bonus(
  p_workout_id bigint,
  p_user_id uuid default null,
  p_at timestamptz default null
)
returns integer
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_user_id uuid;
  v_at timestamptz;
  v_base integer;
  v_bonus_pct numeric;
  v_bonus_amount integer;
begin
  v_base := public.compute_workout_coin_reward(p_workout_id);
  if v_base <= 0 then
    return 0;
  end if;

  if p_user_id is not null then
    v_user_id := p_user_id;
  else
    select w.user_id
    into v_user_id
    from public.workouts w
    where w.id = p_workout_id;
  end if;

  if p_at is not null then
    v_at := p_at;
  else
    select coalesce(w.ended_at, w.started_at, now())
    into v_at
    from public.workouts w
    where w.id = p_workout_id;
  end if;

  if v_user_id is null then
    return v_base;
  end if;

  if p_at is not null then
    v_bonus_pct := public.resolve_pet_bonus_at_time(v_user_id, v_at);
  else
    v_bonus_pct := public.get_pet_training_bonus_pct(v_user_id);
  end if;

  v_bonus_amount := round(v_base * coalesce(v_bonus_pct, 0) / 100.0)::integer;
  return v_base + greatest(v_bonus_amount, 0);
end;
$$;

create or replace function public.trg_coins_on_workout_publish()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
declare
  v_amount integer;
  v_day date;
  v_event_at timestamptz;
begin
  if tg_op = 'INSERT' then
    if new.state <> 'published'::public.workout_state then
      return new;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.state <> 'published'::public.workout_state
       or old.state is not distinct from 'published'::public.workout_state then
      return new;
    end if;
  else
    return new;
  end if;

  v_event_at := coalesce(new.ended_at, new.started_at, now());
  v_amount := public.compute_workout_coin_reward_with_pet_bonus(new.id, new.user_id, v_event_at);
  if v_amount > 0 then
    perform public.apply_liftr_coin_reward(
      new.user_id,
      v_amount,
      'workout_logged',
      public.liftr_coin_ref_bigint(new.id),
      v_event_at
    );
  end if;

  v_day := (v_event_at at time zone 'utc')::date;
  perform public.evaluate_workout_consistency_streak_coins(new.user_id, v_day);

  return new;
end;
$$;

create unique index if not exists coin_tx_once_workout_economy_rebalance_v1
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'workout_economy_rebalance_v1' and amount > 0;

create unique index if not exists coin_tx_once_pet_passive_economy_rebalance_v1
  on public.coin_transactions (user_id, action_type)
  where action_type = 'pet_passive_economy_rebalance_v1';

create or replace function public.apply_economy_rebalance_clawback_v1(
  p_user_id uuid,
  p_desired_delta integer,
  p_action_type text,
  p_reference_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path to public
as $$
declare
  v_balance integer;
  v_adjustment integer;
begin
  if p_user_id is null or p_desired_delta is null or p_desired_delta >= 0 or p_action_type is null then
    return 0;
  end if;

  select coalesce(p.coins_balance, 0)
  into v_balance
  from public.profiles p
  where p.user_id = p_user_id
  for update;

  if not found then
    return 0;
  end if;

  v_adjustment := greatest(p_desired_delta, -v_balance);
  if v_adjustment = 0 then
    return 0;
  end if;

  begin
    insert into public.coin_transactions (user_id, amount, action_type, reference_id, created_at)
    values (
      p_user_id,
      v_adjustment,
      p_action_type,
      p_reference_id,
      now()
    );
    return v_adjustment;
  exception
    when unique_violation then
      return 0;
  end;
end;
$$;

create or replace function public.backfill_economy_rebalance_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
  u record;
  v_ref uuid;
  v_paid integer;
  v_new integer;
  v_delta integer;
  v_clawback integer;
  v_passive_paid integer;
begin
  for r in
    select
      w.id,
      w.user_id,
      coalesce(w.ended_at, w.started_at, now()) as event_at
    from public.workouts w
    where w.state = 'published'::public.workout_state
    order by w.id
  loop
    v_ref := public.liftr_coin_ref_bigint(r.id);
    v_new := public.compute_workout_coin_reward_with_pet_bonus(r.id, r.user_id, r.event_at);

    select coalesce(sum(ct.amount), 0)
    into v_paid
    from public.coin_transactions ct
    where ct.user_id = r.user_id
      and ct.reference_id = v_ref
      and ct.action_type in ('workout_logged', 'workout_coin_doubling_v1')
      and ct.amount > 0;

    v_delta := v_new - coalesce(v_paid, 0);
    if v_delta > 0 then
      perform public.apply_liftr_coin_reward(
        r.user_id,
        v_delta,
        'workout_economy_rebalance_v1',
        v_ref,
        r.event_at
      );
    end if;
  end loop;

  for u in
    select
      ct.user_id,
      coalesce(sum(ct.amount), 0)::integer as passive_paid
    from public.coin_transactions ct
    where ct.action_type = 'pet_coins_generated'
      and ct.amount > 0
    group by ct.user_id
    having coalesce(sum(ct.amount), 0) > 0
  loop
    v_passive_paid := u.passive_paid;
    v_clawback := round(v_passive_paid * 0.75)::integer;
    if v_clawback > 0 then
      perform public.apply_economy_rebalance_clawback_v1(
        u.user_id,
        -v_clawback,
        'pet_passive_economy_rebalance_v1',
        public.liftr_coin_ref_uuid(u.user_id)
      );
    end if;
  end loop;
end;
$$;

revoke all on function public.liftr_workout_coin_scale_factor() from public;
revoke all on function public.get_pet_training_bonus_pct_for_pet(text, text) from public;
revoke all on function public.get_pet_training_bonus_pct(uuid) from public;
revoke all on function public.resolve_pet_bonus_at_time(uuid, timestamptz) from public;
revoke all on function public.compute_workout_coin_reward_with_pet_bonus(bigint, uuid, timestamptz) from public;
revoke all on function public.apply_economy_rebalance_clawback_v1(uuid, integer, text, uuid) from public;
revoke all on function public.backfill_economy_rebalance_v1() from public;

revoke all on function public.get_pet_training_bonus_pct_for_pet(text, text) from anon, authenticated;
revoke all on function public.get_pet_training_bonus_pct(uuid) from anon, authenticated;
revoke all on function public.resolve_pet_bonus_at_time(uuid, timestamptz) from anon, authenticated;
revoke all on function public.compute_workout_coin_reward_with_pet_bonus(bigint, uuid, timestamptz) from anon, authenticated;
revoke all on function public.apply_economy_rebalance_clawback_v1(uuid, integer, text, uuid) from anon, authenticated;
revoke all on function public.backfill_economy_rebalance_v1() from anon, authenticated;

select public.backfill_economy_rebalance_v1();

commit;

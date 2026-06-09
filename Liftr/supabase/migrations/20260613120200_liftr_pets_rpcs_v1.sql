begin;

create or replace function public.roll_pet_rarity()
returns public.pet_rarity
language plpgsql
stable
set search_path to public
as $$
declare
  v_roll integer;
  v_cumulative integer := 0;
  r record;
begin
  v_roll := floor(random() * 1000)::integer;
  for r in
    select c.rarity, c.drop_weight
    from public.pet_rarity_config c
    order by c.sort_order asc
  loop
    v_cumulative := v_cumulative + r.drop_weight;
    if v_roll < v_cumulative then
      return r.rarity;
    end if;
  end loop;
  return 'common'::public.pet_rarity;
end;
$$;

create or replace function public.liftr_pet_active_instance_id(p_user_id uuid)
returns uuid
language sql
stable
set search_path to public
as $$
  select id
  from public.pet_instances
  where user_id = p_user_id
    and is_active = true
  limit 1;
$$;

create or replace function public.get_pet_stat_multiplier(p_user_id uuid)
returns numeric
language sql
stable
set search_path to public
as $$
  select coalesce(c.stat_multiplier, 1.00)
  from public.pet_instances pi
  left join public.pet_rarity_config c on c.rarity = pi.rarity
  where pi.user_id = p_user_id
    and pi.is_active = true
  limit 1;
$$;

create or replace function public.get_pet_coin_multiplier(p_user_id uuid)
returns numeric
language sql
stable
set search_path to public
as $$
  select coalesce(c.coin_multiplier, 1.00)
  from public.pet_instances pi
  left join public.pet_rarity_config c on c.rarity = pi.rarity
  where pi.user_id = p_user_id
    and pi.is_active = true
  limit 1;
$$;

create or replace function public.liftr_inventory_add(
  p_user_id uuid,
  p_item_type text,
  p_quantity integer
)
returns void
language plpgsql
set search_path to public
as $$
begin
  insert into public.user_inventory (user_id, item_type, quantity)
  values (p_user_id, p_item_type, p_quantity)
  on conflict (user_id, item_type)
  do update set quantity = public.user_inventory.quantity + excluded.quantity;
end;
$$;

create or replace function public.liftr_inventory_consume(
  p_user_id uuid,
  p_item_type text,
  p_quantity integer default 1
)
returns boolean
language plpgsql
set search_path to public
as $$
declare
  v_qty integer;
begin
  select quantity into v_qty
  from public.user_inventory
  where user_id = p_user_id
    and item_type = p_item_type
  for update;

  if v_qty is null or v_qty < p_quantity then
    return false;
  end if;

  if v_qty = p_quantity then
    delete from public.user_inventory
    where user_id = p_user_id
      and item_type = p_item_type;
  else
    update public.user_inventory
    set quantity = quantity - p_quantity
    where user_id = p_user_id
      and item_type = p_item_type;
  end if;

  return true;
end;
$$;

create or replace function public.generate_initial_pet_stats(p_pet_instance_id uuid)
returns void
language plpgsql
set search_path to public
as $$
declare
  v_pet_type text;
  v_user_id uuid;
  weights record;
  stat_keys text[] := array[
    'health', 'strength', 'defense', 'speed', 'intelligence',
    'agility', 'stamina', 'critical_rate', 'resistance',
    'exploration', 'happiness'
  ];
  base_points integer := 50;
  total_weight integer;
  allocations jsonb := '{}'::jsonb;
  stat text;
  value integer;
  v_stat_mult numeric;
begin
  select pi.pet_type, pi.user_id
  into v_pet_type, v_user_id
  from public.pet_instances pi
  where pi.id = p_pet_instance_id
    and pi.evolution_stage = 'baby';

  if v_pet_type is null then
    return;
  end if;

  v_stat_mult := public.get_pet_stat_multiplier(v_user_id);
  base_points := greatest(1, round(base_points * v_stat_mult)::integer);

  select * into weights
  from public.pet_type_stat_weights
  where pet_type = v_pet_type;

  if weights is null then
    return;
  end if;

  total_weight :=
    weights.health_weight + weights.strength_weight + weights.defense_weight +
    weights.speed_weight + weights.intelligence_weight + weights.agility_weight +
    weights.stamina_weight + weights.critical_rate_weight + weights.resistance_weight +
    weights.exploration_weight + weights.happiness_weight;

  foreach stat in array stat_keys loop
    value := round(base_points *
      case stat
        when 'health' then weights.health_weight
        when 'strength' then weights.strength_weight
        when 'defense' then weights.defense_weight
        when 'speed' then weights.speed_weight
        when 'intelligence' then weights.intelligence_weight
        when 'agility' then weights.agility_weight
        when 'stamina' then weights.stamina_weight
        when 'critical_rate' then weights.critical_rate_weight
        when 'resistance' then weights.resistance_weight
        when 'exploration' then weights.exploration_weight
        when 'happiness' then weights.happiness_weight
      end::float / total_weight
    )::integer;
    allocations := jsonb_set(allocations, array[stat], to_jsonb(value));
  end loop;

  insert into public.pet_instance_stats (
    pet_instance_id, health, strength, defense, speed, intelligence,
    agility, stamina, critical_rate, resistance, exploration, happiness
  )
  values (
    p_pet_instance_id,
    (allocations->>'health')::integer,
    (allocations->>'strength')::integer,
    (allocations->>'defense')::integer,
    (allocations->>'speed')::integer,
    (allocations->>'intelligence')::integer,
    (allocations->>'agility')::integer,
    (allocations->>'stamina')::integer,
    (allocations->>'critical_rate')::integer,
    (allocations->>'resistance')::integer,
    (allocations->>'exploration')::integer,
    (allocations->>'happiness')::integer
  )
  on conflict (pet_instance_id) do update set
    health = excluded.health,
    strength = excluded.strength,
    defense = excluded.defense,
    speed = excluded.speed,
    intelligence = excluded.intelligence,
    agility = excluded.agility,
    stamina = excluded.stamina,
    critical_rate = excluded.critical_rate,
    resistance = excluded.resistance,
    exploration = excluded.exploration,
    happiness = excluded.happiness;
end;
$$;

create or replace function public.distribute_pet_stats(p_pet_instance_id uuid, p_level_up boolean default true)
returns void
language plpgsql
set search_path to public
as $$
declare
  p_type text;
  p_stage text;
  v_user_id uuid;
  total_points integer;
  min_points integer;
  max_points integer;
  total_weight integer;
  new_level integer;
  v_stat_mult numeric;
  w_health int; w_strength int; w_defense int; w_speed int; w_intelligence int;
  w_agility int; w_stamina int; w_critical_rate int; w_resistance int;
  w_exploration int; w_happiness int;
  r_health int; r_strength int; r_defense int; r_speed int; r_intelligence int;
  r_agility int; r_stamina int; r_critical_rate int; r_resistance int;
  r_exploration int; r_happiness int;
begin
  insert into public.pet_instance_stats (pet_instance_id)
  values (p_pet_instance_id)
  on conflict (pet_instance_id) do nothing;

  select pi.pet_type, pi.evolution_stage, pi.user_id
  into p_type, p_stage, v_user_id
  from public.pet_instances pi
  where pi.id = p_pet_instance_id;

  select stats_min_per_level, stats_max_per_level
  into min_points, max_points
  from public.pet_stage_rewards
  where stage = p_stage;

  total_points := floor(random() * (max_points - min_points + 1))::integer + min_points;
  v_stat_mult := public.get_pet_stat_multiplier(v_user_id);
  total_points := greatest(1, round(total_points * v_stat_mult)::integer);

  select
    health_weight, strength_weight, defense_weight, speed_weight, intelligence_weight,
    agility_weight, stamina_weight, critical_rate_weight, resistance_weight,
    exploration_weight, happiness_weight
  into
    w_health, w_strength, w_defense, w_speed, w_intelligence,
    w_agility, w_stamina, w_critical_rate, w_resistance,
    w_exploration, w_happiness
  from public.pet_type_stat_weights
  where pet_type = p_type;

  total_weight := w_health + w_strength + w_defense + w_speed + w_intelligence +
                  w_agility + w_stamina + w_critical_rate + w_resistance +
                  w_exploration + w_happiness;

  r_health := round(total_points * w_health::numeric / total_weight);
  r_strength := round(total_points * w_strength::numeric / total_weight);
  r_defense := round(total_points * w_defense::numeric / total_weight);
  r_speed := round(total_points * w_speed::numeric / total_weight);
  r_intelligence := round(total_points * w_intelligence::numeric / total_weight);
  r_agility := round(total_points * w_agility::numeric / total_weight);
  r_stamina := round(total_points * w_stamina::numeric / total_weight);
  r_critical_rate := round(total_points * w_critical_rate::numeric / total_weight);
  r_resistance := round(total_points * w_resistance::numeric / total_weight);
  r_exploration := round(total_points * w_exploration::numeric / total_weight);
  r_happiness := round(total_points * w_happiness::numeric / total_weight);

  update public.pet_instance_stats
  set
    health = coalesce(health, 0) + r_health,
    strength = coalesce(strength, 0) + r_strength,
    defense = coalesce(defense, 0) + r_defense,
    speed = coalesce(speed, 0) + r_speed,
    intelligence = coalesce(intelligence, 0) + r_intelligence,
    agility = coalesce(agility, 0) + r_agility,
    stamina = coalesce(stamina, 0) + r_stamina,
    critical_rate = coalesce(critical_rate, 0) + r_critical_rate,
    resistance = coalesce(resistance, 0) + r_resistance,
    exploration = coalesce(exploration, 0) + r_exploration,
    happiness = coalesce(happiness, 0) + r_happiness
  where pet_instance_id = p_pet_instance_id;

  if p_level_up then
    update public.pet_instances
    set current_level = current_level + 1,
        updated_at = now()
    where id = p_pet_instance_id
    returning current_level into new_level;

    insert into public.pet_logs (user_id, pet_instance_id, event_type, new_level, stats_delta)
    values (
      v_user_id,
      p_pet_instance_id,
      'level_up',
      new_level,
      jsonb_build_object(
        'health', r_health, 'strength', r_strength, 'defense', r_defense,
        'speed', r_speed, 'intelligence', r_intelligence, 'agility', r_agility,
        'stamina', r_stamina, 'critical_rate', r_critical_rate, 'resistance', r_resistance,
        'exploration', r_exploration, 'happiness', r_happiness
      )
    );
  end if;
end;
$$;

create or replace function public.check_pet_level_up(p_pet_instance_id uuid)
returns void
language plpgsql
set search_path to public
as $$
declare
  current_exp integer;
  current_level integer;
  next_required_exp integer;
  v_user_id uuid;
begin
  loop
    select pi.current_xp, pi.current_level, pi.user_id
    into current_exp, current_level, v_user_id
    from public.pet_instances pi
    where pi.id = p_pet_instance_id
      and pi.is_active = true
    for update;

    select required_exp into next_required_exp
    from public.pet_levels
    where level = current_level;

    exit when current_exp < next_required_exp or next_required_exp is null;

    update public.pet_instances
    set current_xp = current_xp - next_required_exp,
        updated_at = now()
    where id = p_pet_instance_id;

    perform public.distribute_pet_stats(p_pet_instance_id, true);
  end loop;
end;
$$;

create or replace function public.apply_evolution_stat_bonus(p_pet_instance_id uuid, p_current_stage text)
returns jsonb
language plpgsql
set search_path to public
as $$
declare
  v_pet_type text;
  v_user_id uuid;
  v_next_stage text;
  v_bonus_points integer;
  v_stat_mult numeric;
  w record;
  v_total_weight integer;
  v_stats_delta jsonb := '{}'::jsonb;
  stat_key text;
  v_share numeric;
  v_base integer;
  v_overflow integer;
  i integer;
  v_rand_stat text;
begin
  v_next_stage := case lower(p_current_stage)
    when 'baby' then 'kid'
    when 'kid' then 'teen'
    when 'teen' then 'adult'
    when 'adult' then 'elder'
    else null
  end;

  if v_next_stage is null then
    raise exception 'invalid_evolution_stage';
  end if;

  v_bonus_points := case v_next_stage
    when 'kid' then 15
    when 'teen' then 20
    when 'adult' then 25
    when 'elder' then 35
    else 0
  end;

  select pi.pet_type, pi.user_id
  into v_pet_type, v_user_id
  from public.pet_instances pi
  where pi.id = p_pet_instance_id;

  select * into w
  from public.pet_type_stat_weights
  where pet_type = v_pet_type;

  if w is null then
    raise exception 'unknown_pet_type';
  end if;

  v_stat_mult := public.get_pet_stat_multiplier(v_user_id);
  v_bonus_points := greatest(1, round(v_bonus_points * v_stat_mult)::integer);

  v_total_weight :=
    w.health_weight + w.strength_weight + w.defense_weight + w.speed_weight +
    w.intelligence_weight + w.agility_weight + w.stamina_weight + w.critical_rate_weight +
    w.resistance_weight + w.exploration_weight + w.happiness_weight;

  for stat_key in select unnest(array[
    'health', 'strength', 'defense', 'speed', 'intelligence', 'agility',
    'stamina', 'critical_rate', 'resistance', 'exploration', 'happiness'
  ]) loop
    v_share := case stat_key
      when 'health' then w.health_weight::numeric / v_total_weight
      when 'strength' then w.strength_weight::numeric / v_total_weight
      when 'defense' then w.defense_weight::numeric / v_total_weight
      when 'speed' then w.speed_weight::numeric / v_total_weight
      when 'intelligence' then w.intelligence_weight::numeric / v_total_weight
      when 'agility' then w.agility_weight::numeric / v_total_weight
      when 'stamina' then w.stamina_weight::numeric / v_total_weight
      when 'critical_rate' then w.critical_rate_weight::numeric / v_total_weight
      when 'resistance' then w.resistance_weight::numeric / v_total_weight
      when 'exploration' then w.exploration_weight::numeric / v_total_weight
      when 'happiness' then w.happiness_weight::numeric / v_total_weight
    end;
    v_base := round(v_bonus_points * v_share)::integer;
    v_stats_delta := jsonb_set(v_stats_delta, array[stat_key], to_jsonb(v_base), true);
  end loop;

  for i in 1..3 loop
    select key into v_rand_stat
    from jsonb_each_text(v_stats_delta)
    order by random()
    limit 1;
    v_stats_delta := jsonb_set(
      v_stats_delta,
      array[v_rand_stat],
      to_jsonb((v_stats_delta ->> v_rand_stat)::integer + 1),
      true
    );
  end loop;

  select coalesce(sum((value)::integer), 0) into v_overflow
  from jsonb_each_text(v_stats_delta);

  while v_overflow > v_bonus_points loop
    select key into v_rand_stat
    from jsonb_each_text(v_stats_delta)
    where (value)::integer > 0
    order by random()
    limit 1;
    exit when v_rand_stat is null;
    v_stats_delta := jsonb_set(
      v_stats_delta,
      array[v_rand_stat],
      to_jsonb(greatest(0, (v_stats_delta ->> v_rand_stat)::integer - 1)),
      true
    );
    v_overflow := v_overflow - 1;
  end loop;

  insert into public.pet_instance_stats (pet_instance_id)
  values (p_pet_instance_id)
  on conflict (pet_instance_id) do nothing;

  update public.pet_instance_stats ps
  set
    health = coalesce(ps.health, 0) + coalesce((v_stats_delta ->> 'health')::integer, 0),
    strength = coalesce(ps.strength, 0) + coalesce((v_stats_delta ->> 'strength')::integer, 0),
    defense = coalesce(ps.defense, 0) + coalesce((v_stats_delta ->> 'defense')::integer, 0),
    speed = coalesce(ps.speed, 0) + coalesce((v_stats_delta ->> 'speed')::integer, 0),
    intelligence = coalesce(ps.intelligence, 0) + coalesce((v_stats_delta ->> 'intelligence')::integer, 0),
    agility = coalesce(ps.agility, 0) + coalesce((v_stats_delta ->> 'agility')::integer, 0),
    stamina = coalesce(ps.stamina, 0) + coalesce((v_stats_delta ->> 'stamina')::integer, 0),
    critical_rate = coalesce(ps.critical_rate, 0) + coalesce((v_stats_delta ->> 'critical_rate')::integer, 0),
    resistance = coalesce(ps.resistance, 0) + coalesce((v_stats_delta ->> 'resistance')::integer, 0),
    exploration = coalesce(ps.exploration, 0) + coalesce((v_stats_delta ->> 'exploration')::integer, 0),
    happiness = coalesce(ps.happiness, 0) + coalesce((v_stats_delta ->> 'happiness')::integer, 0)
  where ps.pet_instance_id = p_pet_instance_id;

  insert into public.pet_logs (user_id, pet_instance_id, event_type, stats_delta, details, created_at)
  values (
    v_user_id,
    p_pet_instance_id,
    'evolution',
    v_stats_delta,
    jsonb_build_object('from_stage', p_current_stage, 'to_stage', v_next_stage),
    now()
  );

  return v_stats_delta;
end;
$$;

create or replace function public.buy_pet_market_item_v1(
  p_item_type text,
  p_quantity integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_item record;
  v_total integer;
  v_purchase_id uuid := gen_random_uuid();
  v_has_active_pet boolean;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity';
  end if;

  select * into v_item
  from public.pet_market_items
  where item_type = p_item_type
    and is_active = true;

  if v_item is null then
    raise exception 'item_not_found';
  end if;

  if p_item_type = 'pet_egg' then
    select exists (
      select 1 from public.pet_instances
      where user_id = v_user_id and is_active = true
    ) into v_has_active_pet;
    if v_has_active_pet then
      raise exception 'already_has_pet';
    end if;
  end if;

  v_total := v_item.price * p_quantity;

  if not public.apply_liftr_coin_transaction(
    v_user_id,
    -v_total,
    'pet_market_purchase',
    v_purchase_id
  ) then
    raise exception 'insufficient_coins';
  end if;

  perform public.liftr_inventory_add(v_user_id, p_item_type, p_quantity);

  return jsonb_build_object(
    'item_type', p_item_type,
    'quantity', p_quantity,
    'total_spent', v_total,
    'purchase_id', v_purchase_id
  );
end;
$$;

create or replace function public.start_pet_incubation_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_pet_type text;
  v_hatch_at timestamptz;
  v_rarity public.pet_rarity;
  v_instance_id uuid;
  v_has_egg boolean;
  v_has_incubator boolean;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select coalesce(quantity, 0) > 0 into v_has_egg
  from public.user_inventory
  where user_id = v_user_id and item_type = 'pet_egg';

  select coalesce(quantity, 0) > 0 into v_has_incubator
  from public.user_inventory
  where user_id = v_user_id and item_type = 'incubator';

  if not coalesce(v_has_egg, false) then
    raise exception 'no_pet_egg';
  end if;

  if not coalesce(v_has_incubator, false) then
    raise exception 'no_incubator';
  end if;

  if exists (
    select 1 from public.pet_instances
    where user_id = v_user_id and is_active = true
  ) then
    raise exception 'already_has_pet';
  end if;

  if not public.liftr_inventory_consume(v_user_id, 'pet_egg', 1) then
    raise exception 'no_pet_egg';
  end if;

  select pt.name into v_pet_type
  from public.pet_types pt
  order by random()
  limit 1;

  if v_pet_type is null then
    raise exception 'no_pet_types';
  end if;

  v_rarity := public.roll_pet_rarity();
  v_hatch_at := now() + interval '6 hours' + (random() * interval '10 hours');

  insert into public.pet_instances (
    user_id, pet_type, evolution_stage, current_xp, current_level,
    hatch_at, is_active, is_equipped, reroll_count, rarity
  )
  values (
    v_user_id, v_pet_type, 'egg', 0, 1,
    v_hatch_at, true, true, 0, v_rarity
  )
  returning id into v_instance_id;

  insert into public.pet_logs (user_id, pet_instance_id, event_type, details)
  values (
    v_user_id,
    v_instance_id,
    'incubation_started',
    jsonb_build_object('pet_type', v_pet_type, 'rarity', v_rarity::text, 'hatch_at', v_hatch_at)
  );

  return jsonb_build_object(
    'pet_instance_id', v_instance_id,
    'pet_type', v_pet_type,
    'rarity', v_rarity::text,
    'hatch_at', v_hatch_at
  );
end;
$$;

create or replace function public.check_and_hatch_pet_eggs_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
begin
  for r in
    select id, user_id
    from public.pet_instances
    where evolution_stage = 'egg'
      and hatch_at is not null
      and hatch_at <= now()
      and is_active = true
  loop
    update public.pet_instances
    set evolution_stage = 'baby',
        updated_at = now()
    where id = r.id
      and evolution_stage = 'egg';

    perform public.generate_initial_pet_stats(r.id);

    insert into public.pet_logs (user_id, pet_instance_id, event_type, details)
    values (r.user_id, r.id, 'hatched', jsonb_build_object('stage', 'baby'));
  end loop;
end;
$$;

create or replace function public.feed_pet_v1(p_item_type text)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance_id uuid;
  v_stage text;
  v_min_exp integer;
  v_max_exp integer;
  v_gained_exp integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  v_instance_id := public.liftr_pet_active_instance_id(v_user_id);
  if v_instance_id is null then
    raise exception 'no_active_pet';
  end if;

  select evolution_stage into v_stage
  from public.pet_instances
  where id = v_instance_id
  for update;

  if v_stage is null or lower(v_stage) = 'egg' then
    raise exception 'pet_not_hatched';
  end if;

  if not public.liftr_inventory_consume(v_user_id, p_item_type, 1) then
    raise exception 'no_food_item';
  end if;

  select pfe.min_exp, pfe.max_exp
  into v_min_exp, v_max_exp
  from public.pet_food_experience pfe
  where pfe.item_type = p_item_type
    and lower(pfe.pet_stage) = lower(v_stage);

  if v_min_exp is null or v_max_exp is null then
    raise exception 'no_exp_config';
  end if;

  v_gained_exp := floor(random() * (v_max_exp - v_min_exp + 1))::integer + v_min_exp;

  update public.pet_instances
  set current_xp = current_xp + v_gained_exp,
      total_feedings = total_feedings + 1,
      updated_at = now()
  where id = v_instance_id;

  insert into public.pet_logs (user_id, pet_instance_id, event_type, item_type, exp_gained, details)
  values (
    v_user_id,
    v_instance_id,
    'fed',
    p_item_type,
    v_gained_exp,
    jsonb_build_object('pet_stage', v_stage)
  );

  perform public.check_pet_level_up(v_instance_id);

  return jsonb_build_object('exp_gained', v_gained_exp);
end;
$$;

create or replace function public.confirm_pet_evolution_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance_id uuid;
  v_stage text;
  v_level integer;
  v_required_level integer;
  v_next_stage text;
  v_stats_delta jsonb;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  v_instance_id := public.liftr_pet_active_instance_id(v_user_id);

  select evolution_stage, current_level
  into v_stage, v_level
  from public.pet_instances
  where id = v_instance_id
  for update;

  if v_stage is null then
    raise exception 'no_active_pet';
  end if;

  v_required_level := case lower(v_stage)
    when 'baby' then 25
    when 'kid' then 50
    when 'teen' then 75
    when 'adult' then 100
    else null
  end;

  v_next_stage := case lower(v_stage)
    when 'baby' then 'kid'
    when 'kid' then 'teen'
    when 'teen' then 'adult'
    when 'adult' then 'elder'
    else null
  end;

  if v_required_level is null or v_next_stage is null then
    raise exception 'cannot_evolve';
  end if;

  if v_level < v_required_level then
    raise exception 'level_too_low';
  end if;

  v_stats_delta := public.apply_evolution_stat_bonus(v_instance_id, v_stage);

  update public.pet_instances
  set evolution_stage = v_next_stage,
      updated_at = now()
  where id = v_instance_id;

  return jsonb_build_object(
    'pet_stage', v_next_stage,
    'stats_delta', v_stats_delta
  );
end;
$$;

create or replace function public.update_pet_custom_name_v1(p_name text)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  v_instance_id := public.liftr_pet_active_instance_id(v_user_id);
  if v_instance_id is null then
    raise exception 'no_active_pet';
  end if;

  update public.pet_instances
  set custom_name = nullif(trim(p_name), ''),
      updated_at = now()
  where id = v_instance_id;
end;
$$;

create or replace function public.reroll_pet_egg_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance_id uuid;
  v_rerolls integer;
  v_cost integer;
  v_pet_type text;
  v_hatch_at timestamptz;
  v_rarity public.pet_rarity;
  v_purchase_id uuid := gen_random_uuid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  v_instance_id := public.liftr_pet_active_instance_id(v_user_id);

  select coalesce(reroll_count, 0)
  into v_rerolls
  from public.pet_instances
  where id = v_instance_id
    and evolution_stage = 'egg'
  for update;

  if v_rerolls is null then
    raise exception 'no_active_egg';
  end if;

  v_cost := floor(50 * power(1.1, v_rerolls))::integer;

  if not public.apply_liftr_coin_transaction(
    v_user_id,
    -v_cost,
    'pet_egg_reroll',
    v_purchase_id
  ) then
    raise exception 'insufficient_coins';
  end if;

  select name into v_pet_type
  from public.pet_types
  order by random()
  limit 1;

  v_rarity := public.roll_pet_rarity();
  v_hatch_at := now() + ((6 + floor(random() * 11)::integer) || ' hours')::interval;

  update public.pet_instances
  set pet_type = v_pet_type,
      hatch_at = v_hatch_at,
      reroll_count = v_rerolls + 1,
      rarity = v_rarity,
      updated_at = now()
  where id = v_instance_id;

  return jsonb_build_object(
    'pet_type', v_pet_type,
    'rarity', v_rarity::text,
    'hatch_at', v_hatch_at,
    'reroll_count', v_rerolls + 1,
    'cost', v_cost
  );
end;
$$;

create or replace function public.get_my_pet_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_pet jsonb;
  v_stats jsonb;
  v_inventory jsonb;
  v_required_exp integer;
  v_can_evolve boolean := false;
  v_stage text;
  v_level integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select to_jsonb(pi.*) into v_pet
  from public.pet_instances pi
  where pi.user_id = v_user_id
    and pi.is_active = true
  limit 1;

  if v_pet is null then
    return jsonb_build_object(
      'pet', null,
      'stats', null,
      'inventory', '[]'::jsonb,
      'xp_required', 0,
      'can_evolve', false
    );
  end if;

  select to_jsonb(ps.*) into v_stats
  from public.pet_instance_stats ps
  where ps.pet_instance_id = (v_pet->>'id')::uuid;

  select coalesce(jsonb_agg(to_jsonb(ui.*)), '[]'::jsonb) into v_inventory
  from public.user_inventory ui
  where ui.user_id = v_user_id
    and ui.quantity > 0;

  select required_exp into v_required_exp
  from public.pet_levels
  where level = (v_pet->>'current_level')::integer;

  v_stage := v_pet->>'evolution_stage';
  v_level := (v_pet->>'current_level')::integer;

  v_can_evolve := case lower(v_stage)
    when 'baby' then v_level >= 25
    when 'kid' then v_level >= 50
    when 'teen' then v_level >= 75
    when 'adult' then v_level >= 100
    else false
  end;

  return jsonb_build_object(
    'pet', v_pet,
    'stats', v_stats,
    'inventory', v_inventory,
    'xp_required', coalesce(v_required_exp, 0),
    'can_evolve', v_can_evolve
  );
end;
$$;

create or replace function public.list_pet_market_items_v1()
returns setof public.pet_market_items
language sql
security definer
stable
set search_path to public
as $$
  select *
  from public.pet_market_items
  where is_active = true
  order by category, price;
$$;

revoke all on function public.buy_pet_market_item_v1(text, integer) from public;
revoke all on function public.start_pet_incubation_v1() from public;
revoke all on function public.feed_pet_v1(text) from public;
revoke all on function public.confirm_pet_evolution_v1() from public;
revoke all on function public.update_pet_custom_name_v1(text) from public;
revoke all on function public.reroll_pet_egg_v1() from public;
revoke all on function public.get_my_pet_v1() from public;
revoke all on function public.list_pet_market_items_v1() from public;
revoke all on function public.check_and_hatch_pet_eggs_v1() from public;

grant execute on function public.buy_pet_market_item_v1(text, integer) to authenticated;
grant execute on function public.start_pet_incubation_v1() to authenticated;
grant execute on function public.feed_pet_v1(text) to authenticated;
grant execute on function public.confirm_pet_evolution_v1() to authenticated;
grant execute on function public.update_pet_custom_name_v1(text) to authenticated;
grant execute on function public.reroll_pet_egg_v1() to authenticated;
grant execute on function public.get_my_pet_v1() to authenticated;
grant execute on function public.list_pet_market_items_v1() to authenticated;
grant execute on function public.check_and_hatch_pet_eggs_v1() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'liftr_hatch_pet_eggs_job') then
      perform cron.schedule(
        'liftr_hatch_pet_eggs_job',
        '*/10 * * * *',
        'select public.check_and_hatch_pet_eggs_v1();'
      );
    end if;
  end if;
end $$;

commit;

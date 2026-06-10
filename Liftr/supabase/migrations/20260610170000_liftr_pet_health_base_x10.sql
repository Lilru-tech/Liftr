begin;

-- 1. Hatch: health stored at battle scale (x20 of weighted share = old x2 doubling x10 battle scale)
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
    if stat = 'health' then
      value := value * 20;
    end if;
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

-- 2. Level-up: health gain at battle scale (x20)
create or replace function public.distribute_pet_stats(p_pet_instance_id uuid, p_level_up boolean default true)
returns void
language plpgsql
set search_path to public
as $$
declare
  p_type text;
  p_stage text;
  v_user_id uuid;
  min_points int;
  max_points int;
  total_points int;
  v_stat_mult numeric;
  new_level int;
  total_weight int;
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

  r_health := round(total_points * w_health::numeric / total_weight) * 20;
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

-- 3. Evolution bonus: health share at battle scale (x20 after overflow trimming)
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

  v_stats_delta := jsonb_set(
    v_stats_delta,
    array['health'],
    to_jsonb(coalesce((v_stats_delta ->> 'health')::integer, 0) * 20),
    true
  );

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

-- 4. One-time: scale existing active, hatched pets' health to battle scale
update public.pet_instance_stats ps
set health = coalesce(ps.health, 0) * 10
from public.pet_instances pi
where pi.id = ps.pet_instance_id
  and pi.is_active = true
  and lower(pi.evolution_stage) <> 'egg';

-- 5. Combat: use the stored health directly as the battle HP pool
create or replace function public.execute_pet_combat_v1(p_target_opponent_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_attacker_id uuid := auth.uid();
  v_attacker record;
  v_defender record;
  v_attacker_username text;
  v_current_energy integer;
  v_attacker_hp integer;
  v_defender_hp integer;
  v_attacker_max_hp integer;
  v_defender_max_hp integer;
  v_turn_num integer := 0;
  v_max_rounds integer := 50;
  v_round integer := 0;
  v_turns jsonb := '[]'::jsonb;
  v_actor text;
  v_actor_name text;
  v_target_name text;
  v_strike record;
  v_damage integer;
  v_is_critical boolean;
  v_is_dodged boolean;
  v_attacker_first boolean;
  v_action_idx integer;
  v_winner text := null;
  v_winner_user_id uuid := null;
  v_is_draw boolean := false;
  v_scaled_rewards jsonb;
  v_attacker_rewards jsonb := '{"xp":0,"coins":0}'::jsonb;
  v_defender_rewards jsonb := '{"xp":0,"coins":0}'::jsonb;
  v_combat_id uuid := gen_random_uuid();
  v_battle_log jsonb;
  v_attacker_name text;
  v_defender_name text;
  v_attacker_snapshot jsonb;
  v_defender_snapshot jsonb;
  v_cooldown timestamptz;
  v_defender_won boolean := false;
  v_defender_xp integer := 0;
  v_defender_username text;
  v_message text;
  v_attacker_moves text[];
  v_defender_moves text[];
  v_move text;
  v_a_max_dealt integer; v_a_total_dealt integer; v_a_crits integer; v_a_dodges integer;
  v_d_max_dealt integer; v_d_total_dealt integer; v_d_crits integer; v_d_dodges integer;
begin
  if v_attacker_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_target_opponent_user_id is null then
    raise exception 'invalid_target';
  end if;

  if p_target_opponent_user_id = v_attacker_id then
    raise exception 'self_challenge';
  end if;

  perform public.liftr_refresh_profile_energy(v_attacker_id);

  select username, current_energy
  into v_attacker_username, v_current_energy
  from public.profiles
  where user_id = v_attacker_id
  for update;

  if coalesce(v_current_energy, 0) <= 0 then
    raise exception 'no_energy';
  end if;

  v_cooldown := public.liftr_combat_cooldown_expires_at(v_attacker_id, p_target_opponent_user_id);
  if v_cooldown is not null and v_cooldown > now() then
    raise exception 'cooldown_active';
  end if;

  select * into v_attacker
  from public.pet_instances pi
  join public.pet_instance_stats ps on ps.pet_instance_id = pi.id
  where pi.user_id = v_attacker_id
    and pi.is_active = true
    and pi.is_equipped = true
  for update of pi;

  if v_attacker.id is null then
    raise exception 'attacker_no_pet';
  end if;

  if lower(v_attacker.evolution_stage) = 'egg' then
    raise exception 'attacker_egg';
  end if;

  select * into v_defender
  from public.pet_instances pi
  join public.pet_instance_stats ps on ps.pet_instance_id = pi.id
  where pi.user_id = p_target_opponent_user_id
    and pi.is_active = true
    and pi.is_equipped = true
  for update of pi;

  if v_defender.id is null then
    raise exception 'defender_no_pet';
  end if;

  if lower(v_defender.evolution_stage) = 'egg' then
    raise exception 'defender_egg';
  end if;

  select username into v_defender_username
  from public.profiles
  where user_id = p_target_opponent_user_id;

  perform public.allow_profiles_energy_update();
  update public.profiles
  set current_energy = current_energy - 1
  where user_id = v_attacker_id;

  v_attacker_name := coalesce(nullif(trim(v_attacker.custom_name), ''), initcap(replace(v_attacker.pet_type, '_', ' ')));
  v_defender_name := coalesce(nullif(trim(v_defender.custom_name), ''), initcap(replace(v_defender.pet_type, '_', ' ')));

  select coalesce(array_agg(move_name), array['Strike'])
  into v_attacker_moves
  from public.pet_type_combat_moves
  where pet_type = v_attacker.pet_type;

  select coalesce(array_agg(move_name), array['Strike'])
  into v_defender_moves
  from public.pet_type_combat_moves
  where pet_type = v_defender.pet_type;

  v_attacker_max_hp := greatest(v_attacker.health, 1);
  v_defender_max_hp := greatest(v_defender.health, 1);
  v_attacker_hp := v_attacker_max_hp;
  v_defender_hp := v_defender_max_hp;

  v_attacker_snapshot := jsonb_build_object(
    'user_id', v_attacker_id,
    'pet_instance_id', v_attacker.id,
    'name', v_attacker_name,
    'pet_type', v_attacker.pet_type,
    'evolution_stage', v_attacker.evolution_stage,
    'level', v_attacker.current_level,
    'rarity', v_attacker.rarity::text,
    'image_url', public.liftr_pet_image_url_for_stage(v_attacker.pet_type, v_attacker.evolution_stage),
    'max_hp', v_attacker_max_hp
  );

  v_defender_snapshot := jsonb_build_object(
    'user_id', p_target_opponent_user_id,
    'pet_instance_id', v_defender.id,
    'name', v_defender_name,
    'pet_type', v_defender.pet_type,
    'evolution_stage', v_defender.evolution_stage,
    'level', v_defender.current_level,
    'rarity', v_defender.rarity::text,
    'image_url', public.liftr_pet_image_url_for_stage(v_defender.pet_type, v_defender.evolution_stage),
    'max_hp', v_defender_max_hp
  );

  while v_attacker_hp > 0 and v_defender_hp > 0 and v_round < v_max_rounds loop
    v_round := v_round + 1;

    v_attacker_first := v_attacker.speed > v_defender.speed
      or (v_attacker.speed = v_defender.speed and v_attacker.agility > v_defender.agility)
      or (v_attacker.speed = v_defender.speed and v_attacker.agility = v_defender.agility and random() >= 0.5);

    for v_action_idx in 1..2 loop
      exit when v_attacker_hp <= 0 or v_defender_hp <= 0;

      if v_action_idx = 1 then
        v_actor := case when v_attacker_first then 'attacker' else 'defender' end;
      else
        v_actor := case when v_attacker_first then 'defender' else 'attacker' end;
      end if;

      if v_actor = 'attacker' then
        v_actor_name := v_attacker_name;
        v_target_name := v_defender_name;
        v_move := v_attacker_moves[1 + floor(random() * array_length(v_attacker_moves, 1))::integer];
        select * into v_strike from public.liftr_combat_strike_v3(
          v_attacker.strength,
          v_attacker.intelligence,
          v_attacker.critical_rate,
          v_attacker.happiness,
          v_attacker.exploration,
          v_defender.defense,
          v_defender.resistance,
          v_defender.agility,
          v_defender.stamina,
          v_round,
          v_turn_num = 0
        );
        v_damage := v_strike.damage;
        v_is_critical := v_strike.is_critical;
        v_is_dodged := v_strike.is_dodged;
        if not v_is_dodged then
          v_defender_hp := greatest(0, v_defender_hp - v_damage);
        end if;
      else
        v_actor_name := v_defender_name;
        v_target_name := v_attacker_name;
        v_move := v_defender_moves[1 + floor(random() * array_length(v_defender_moves, 1))::integer];
        select * into v_strike from public.liftr_combat_strike_v3(
          v_defender.strength,
          v_defender.intelligence,
          v_defender.critical_rate,
          v_defender.happiness,
          v_defender.exploration,
          v_attacker.defense,
          v_attacker.resistance,
          v_attacker.agility,
          v_attacker.stamina,
          v_round,
          v_turn_num = 0
        );
        v_damage := v_strike.damage;
        v_is_critical := v_strike.is_critical;
        v_is_dodged := v_strike.is_dodged;
        if not v_is_dodged then
          v_attacker_hp := greatest(0, v_attacker_hp - v_damage);
        end if;
      end if;

      if v_is_dodged then
        v_message := format('%s dodged %s''s %s!', v_target_name, v_actor_name, v_move);
      else
        v_message := format(
          '%s used %s%s dealing %s damage!',
          v_actor_name,
          case when v_is_critical then 'a critical ' else '' end,
          v_move,
          v_damage
        );
      end if;

      v_turn_num := v_turn_num + 1;
      v_turns := v_turns || jsonb_build_array(
        jsonb_build_object(
          'turn', v_turn_num,
          'actor', v_actor,
          'action', case when v_is_dodged then 'dodge' else 'strike' end,
          'move', v_move,
          'damage', v_damage,
          'is_critical', v_is_critical,
          'attacker_hp_after', v_attacker_hp,
          'defender_hp_after', v_defender_hp,
          'message', v_message
        )
      );
    end loop;
  end loop;

  if v_attacker_hp > 0 and v_defender_hp > 0 then
    v_is_draw := true;
    v_winner := null;
    v_winner_user_id := null;
  elsif v_attacker_hp > v_defender_hp then
    v_winner := 'attacker';
    v_winner_user_id := v_attacker_id;
  elsif v_defender_hp > v_attacker_hp then
    v_winner := 'defender';
    v_winner_user_id := p_target_opponent_user_id;
    v_defender_won := true;
  else
    v_is_draw := true;
  end if;

  v_scaled_rewards := public.liftr_combat_scaled_rewards(v_attacker.current_level, v_defender.current_level);

  if v_is_draw then
    v_attacker_rewards := '{"xp":10,"coins":5}'::jsonb;
    v_defender_rewards := '{"xp":10,"coins":5}'::jsonb;
  elsif v_winner = 'attacker' then
    v_attacker_rewards := v_scaled_rewards;
    v_defender_rewards := '{"xp":0,"coins":0}'::jsonb;
  else
    v_attacker_rewards := '{"xp":0,"coins":0}'::jsonb;
    v_defender_rewards := v_scaled_rewards;
  end if;

  v_battle_log := jsonb_build_object(
    'version', 1,
    'attacker_pet', v_attacker_snapshot,
    'defender_pet', v_defender_snapshot,
    'turns', v_turns,
    'result', jsonb_build_object(
      'winner', v_winner,
      'winner_user_id', v_winner_user_id,
      'total_turns', v_turn_num,
      'is_draw', v_is_draw
    )
  );

  insert into public.pet_combat_history (
    id,
    attacker_user_id,
    defender_user_id,
    winner_user_id,
    battle_log,
    attacker_rewards,
    defender_rewards
  )
  values (
    v_combat_id,
    v_attacker_id,
    p_target_opponent_user_id,
    v_winner_user_id,
    v_battle_log,
    v_attacker_rewards,
    v_defender_rewards
  );

  select
    coalesce(max(case when t->>'actor' = 'attacker' and t->>'action' = 'strike' then (t->>'damage')::integer end), 0),
    coalesce(sum(case when t->>'actor' = 'attacker' and t->>'action' = 'strike' then (t->>'damage')::integer else 0 end), 0),
    coalesce(count(*) filter (where t->>'actor' = 'attacker' and (t->>'is_critical')::boolean), 0),
    coalesce(count(*) filter (where t->>'actor' = 'defender' and t->>'action' = 'dodge'), 0),
    coalesce(max(case when t->>'actor' = 'defender' and t->>'action' = 'strike' then (t->>'damage')::integer end), 0),
    coalesce(sum(case when t->>'actor' = 'defender' and t->>'action' = 'strike' then (t->>'damage')::integer else 0 end), 0),
    coalesce(count(*) filter (where t->>'actor' = 'defender' and (t->>'is_critical')::boolean), 0),
    coalesce(count(*) filter (where t->>'actor' = 'attacker' and t->>'action' = 'dodge'), 0)
  into
    v_a_max_dealt, v_a_total_dealt, v_a_crits, v_a_dodges,
    v_d_max_dealt, v_d_total_dealt, v_d_crits, v_d_dodges
  from jsonb_array_elements(v_turns) t;

  perform public.liftr_combat_record_user_stats(
    v_attacker_id,
    v_a_max_dealt, v_d_max_dealt, v_a_total_dealt, v_d_total_dealt,
    v_a_crits, v_a_dodges,
    v_winner = 'attacker', v_is_draw, v_turn_num
  );

  perform public.liftr_combat_record_user_stats(
    p_target_opponent_user_id,
    v_d_max_dealt, v_a_max_dealt, v_d_total_dealt, v_a_total_dealt,
    v_d_crits, v_d_dodges,
    v_winner = 'defender', v_is_draw, v_turn_num
  );

  if (v_attacker_rewards->>'xp')::integer > 0 then
    update public.pet_instances
    set current_xp = current_xp + (v_attacker_rewards->>'xp')::integer,
        updated_at = now()
    where id = v_attacker.id;
    perform public.check_pet_level_up(v_attacker.id);
  end if;

  if (v_attacker_rewards->>'coins')::integer > 0 then
    perform public.apply_liftr_coin_transaction(
      v_attacker_id,
      (v_attacker_rewards->>'coins')::integer,
      'pet_combat_reward',
      v_combat_id
    );
  end if;

  if (v_defender_rewards->>'xp')::integer > 0 then
    update public.pet_instances
    set current_xp = current_xp + (v_defender_rewards->>'xp')::integer,
        updated_at = now()
    where id = v_defender.id;
    perform public.check_pet_level_up(v_defender.id);
  end if;

  if (v_defender_rewards->>'coins')::integer > 0 then
    perform public.apply_liftr_coin_transaction(
      p_target_opponent_user_id,
      (v_defender_rewards->>'coins')::integer,
      'pet_combat_reward',
      v_combat_id
    );
  end if;

  v_defender_xp := coalesce((v_defender_rewards->>'xp')::integer, 0);

  insert into public.pet_logs (user_id, pet_instance_id, event_type, exp_gained, details)
  values
    (
      v_attacker_id,
      v_attacker.id,
      'combat',
      coalesce((v_attacker_rewards->>'xp')::integer, 0),
      jsonb_build_object(
        'combat_id', v_combat_id,
        'role', 'attacker',
        'opponent_user_id', p_target_opponent_user_id,
        'won', v_winner = 'attacker',
        'is_draw', v_is_draw,
        'opponent_username', coalesce(v_defender_username, ''),
        'coins_gained', coalesce((v_attacker_rewards->>'coins')::integer, 0),
        'rewards', v_attacker_rewards
      )
    ),
    (
      p_target_opponent_user_id,
      v_defender.id,
      'combat',
      v_defender_xp,
      jsonb_build_object(
        'combat_id', v_combat_id,
        'role', 'defender',
        'opponent_user_id', v_attacker_id,
        'won', v_winner = 'defender',
        'is_draw', v_is_draw,
        'opponent_username', coalesce(v_attacker_username, ''),
        'coins_gained', coalesce((v_defender_rewards->>'coins')::integer, 0),
        'rewards', v_defender_rewards
      )
    );

  insert into public.notifications (user_id, type, title, body, data)
  values (
    p_target_opponent_user_id,
    'pet_combat_challenged',
    'Pet Arena Challenge',
    format(
      'Your pet was challenged by %s! Your pet %s the match and accumulated +%s XP!',
      coalesce(v_attacker_username, 'Someone'),
      case
        when v_is_draw then 'tied in'
        when v_defender_won then 'won'
        else 'lost'
      end,
      v_defender_xp
    ),
    jsonb_build_object(
      'combat_id', v_combat_id::text,
      'attacker_user_id', v_attacker_id::text,
      'attacker_username', coalesce(v_attacker_username, ''),
      'defender_won', v_defender_won,
      'xp_gained', v_defender_xp
    )
  );

  return jsonb_build_object(
    'combat_id', v_combat_id,
    'winner_user_id', v_winner_user_id,
    'attacker_rewards', v_attacker_rewards,
    'defender_rewards', v_defender_rewards,
    'battle_log', v_battle_log,
    'energy', public.liftr_profile_energy_json(v_attacker_id)
  );
end;
$$;

commit;

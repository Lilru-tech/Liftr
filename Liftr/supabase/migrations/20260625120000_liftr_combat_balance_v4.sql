begin;

create or replace function public.liftr_combat_battle_hp_v1(p_health integer)
returns integer
language sql
immutable
as $$
  select (greatest(coalesce(p_health, 0), 1) * 8 + 9) / 10;
$$;

create or replace function public.liftr_combat_strike_v4(
  p_attacker_strength integer,
  p_attacker_agility integer,
  p_attacker_intelligence integer,
  p_attacker_critical_rate integer,
  p_attacker_happiness integer,
  p_attacker_exploration integer,
  p_defender_defense integer,
  p_defender_resistance integer,
  p_defender_agility integer,
  p_defender_stamina integer,
  p_round integer,
  p_is_first_strike boolean,
  out damage integer,
  out is_critical boolean,
  out is_dodged boolean
)
returns record
language plpgsql
volatile
as $$
declare
  v_dodge_chance numeric;
  v_crit_mult numeric := 1.0;
  v_mitigation numeric;
  v_variance_floor numeric;
  v_variance numeric;
  v_fatigue numeric;
  v_first_strike numeric := 1.0;
  v_strength numeric;
begin
  damage := 0;
  is_critical := false;
  is_dodged := false;

  v_dodge_chance := least(0.28, greatest(0.03,
    (greatest(p_defender_agility, 0) - greatest(p_attacker_intelligence, 0) / 2.0) * 0.02
  ));
  if random() < v_dodge_chance then
    is_dodged := true;
    return;
  end if;

  is_critical := random() < least(0.5, greatest(p_attacker_critical_rate, 0)::numeric / 100.0);
  if is_critical then
    v_crit_mult := least(2.25, 1.75 + greatest(p_attacker_intelligence, 0) * 0.005);
  end if;

  v_strength := greatest(p_attacker_strength, 1)::numeric
    + greatest(p_attacker_agility, 0)::numeric * 0.22
    + greatest(p_attacker_intelligence, 0)::numeric * 0.10;

  v_mitigation := v_strength / (
    v_strength + (greatest(p_defender_defense, 0) + greatest(p_defender_resistance, 0)) / 2.0
  );

  v_variance_floor := 0.85 + least(0.05, greatest(p_attacker_happiness, 0) * 0.002);
  v_variance := v_variance_floor + random() * (1.15 - v_variance_floor);

  v_fatigue := 1.0 + greatest(0, p_round - 12)
    * greatest(0.01, 0.04 - greatest(p_defender_stamina, 0) * 0.001);

  if p_is_first_strike then
    v_first_strike := 1.0 + least(0.03, greatest(p_attacker_exploration, 0) * 0.002);
  end if;

  damage := greatest(1, floor(
    1.22
      * v_strength
      * v_mitigation
      * v_variance
      * v_crit_mult
      * v_fatigue
      * v_first_strike
  )::integer);
end;
$$;

update public.pet_type_stat_weights
set
  health_weight = 3,
  happiness_weight = case
    when happiness_weight > 1 then happiness_weight - 1
    when exploration_weight > 1 then happiness_weight
    else happiness_weight
  end,
  exploration_weight = case
    when happiness_weight > 1 then exploration_weight
    when exploration_weight > 1 then exploration_weight - 1
    else exploration_weight
  end
where health_weight <= 2;

update public.pet_type_stat_weights
set
  strength_weight = strength_weight - 1,
  happiness_weight = happiness_weight + 1
where health_weight >= 5
  and strength_weight >= 5;

update public.pet_type_stat_weights
set
  health_weight = 4,
  strength_weight = 4,
  intelligence_weight = 4,
  agility_weight = 5,
  exploration_weight = 4,
  happiness_weight = 4
where pet_type = 'monkey';

update public.pet_type_stat_weights
set
  health_weight = 4,
  strength_weight = 4,
  resistance_weight = 5,
  happiness_weight = 4
where pet_type = 'griffin';

do $$
declare
  v_bad_count integer;
begin
  select count(*)
  into v_bad_count
  from public.pet_type_stat_weights
  where
    health_weight + strength_weight + defense_weight + speed_weight
    + intelligence_weight + agility_weight + stamina_weight
    + critical_rate_weight + resistance_weight + exploration_weight
    + happiness_weight <> 40
    or least(
      health_weight, strength_weight, defense_weight, speed_weight,
      intelligence_weight, agility_weight, stamina_weight,
      critical_rate_weight, resistance_weight, exploration_weight, happiness_weight
    ) < 1;

  if v_bad_count > 0 then
    raise exception 'pet_type_stat_weights combat balance normalization failed: % invalid rows', v_bad_count;
  end if;
end;
$$;

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

  v_attacker_max_hp := public.liftr_combat_battle_hp_v1(v_attacker.health);
  v_defender_max_hp := public.liftr_combat_battle_hp_v1(v_defender.health);
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
        select * into v_strike from public.liftr_combat_strike_v4(
          v_attacker.strength,
          v_attacker.agility,
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
        select * into v_strike from public.liftr_combat_strike_v4(
          v_defender.strength,
          v_defender.agility,
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
    coalesce(count(*) filter (where t->>'actor' = 'attacker' and t->>'action' = 'dodge'), 0),
    coalesce(max(case when t->>'actor' = 'defender' and t->>'action' = 'strike' then (t->>'damage')::integer end), 0),
    coalesce(sum(case when t->>'actor' = 'defender' and t->>'action' = 'strike' then (t->>'damage')::integer else 0 end), 0),
    coalesce(count(*) filter (where t->>'actor' = 'defender' and (t->>'is_critical')::boolean), 0),
    coalesce(count(*) filter (where t->>'actor' = 'defender' and t->>'action' = 'dodge'), 0)
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

revoke all on function public.liftr_combat_battle_hp_v1(integer) from public;
revoke all on function public.liftr_combat_strike_v4(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, boolean) from public;
revoke all on function public.execute_pet_combat_v1(uuid) from public;
grant execute on function public.execute_pet_combat_v1(uuid) to authenticated;

commit;

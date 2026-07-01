begin;

create or replace function public.liftr_combat_effective_power_v1(
  p_health integer,
  p_strength integer,
  p_defense integer,
  p_speed integer,
  p_agility integer,
  p_stamina integer,
  p_resistance integer,
  p_critical_rate integer,
  p_intelligence integer,
  p_exploration integer
)
returns numeric
language sql
immutable
as $$
  select
    (
      greatest(coalesce(p_strength, 0), 1)::numeric
      + greatest(coalesce(p_agility, 0), 0)::numeric * 0.22
      + greatest(coalesce(p_intelligence, 0), 0)::numeric * 0.10
    ) * 3.0
    + (
      (greatest(coalesce(p_defense, 0), 0) + greatest(coalesce(p_resistance, 0), 0)) / 2.0
    ) * 2.0
    + greatest(coalesce(p_speed, 0), 0)::numeric * 0.8
    + greatest(coalesce(p_agility, 0), 0)::numeric * 0.5
    + greatest(coalesce(p_health, 0), 0)::numeric * 0.15
    + greatest(coalesce(p_critical_rate, 0), 0)::numeric * 0.3
    + greatest(coalesce(p_stamina, 0), 0)::numeric * 0.2
    + greatest(coalesce(p_exploration, 0), 0)::numeric * 0.15;
$$;

create or replace function public.liftr_combat_handicap_pool_multiplier_v1()
returns numeric
language sql
immutable
as $$
  select 1.05::numeric;
$$;

drop function if exists public.liftr_combat_nerf_stats_to_target_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer);

create or replace function public.liftr_combat_nerf_stats_to_target_v1(
  p_weaker_health integer,
  p_weaker_strength integer,
  p_weaker_defense integer,
  p_weaker_speed integer,
  p_weaker_agility integer,
  p_weaker_stamina integer,
  p_weaker_resistance integer,
  p_weaker_critical_rate integer,
  p_weaker_intelligence integer,
  p_weaker_exploration integer,
  p_health integer,
  p_strength integer,
  p_defense integer,
  p_speed integer,
  p_agility integer,
  p_stamina integer,
  p_resistance integer,
  p_critical_rate integer,
  p_intelligence integer,
  p_exploration integer,
  p_happiness integer default null
)
returns table (
  health integer,
  strength integer,
  defense integer,
  speed integer,
  agility integer,
  stamina integer,
  resistance integer,
  critical_rate integer,
  intelligence integer,
  exploration integer
)
language plpgsql
immutable
as $$
declare
  v_weaker_power numeric;
  v_stronger_power numeric;
  v_target_power numeric;
  v_factor numeric;
  v_health integer;
  v_strength integer;
  v_defense integer;
  v_speed integer;
  v_agility integer;
  v_stamina integer;
  v_resistance integer;
  v_critical_rate integer;
  v_intelligence integer;
  v_exploration integer;
begin
  v_weaker_power := public.liftr_combat_effective_power_v1(
    p_weaker_health, p_weaker_strength, p_weaker_defense, p_weaker_speed,
    p_weaker_agility, p_weaker_stamina, p_weaker_resistance,
    p_weaker_critical_rate, p_weaker_intelligence, p_weaker_exploration
  );
  v_stronger_power := public.liftr_combat_effective_power_v1(
    p_health, p_strength, p_defense, p_speed,
    p_agility, p_stamina, p_resistance,
    p_critical_rate, p_intelligence, p_exploration
  );
  v_target_power := v_weaker_power * public.liftr_combat_handicap_pool_multiplier_v1();

  if v_stronger_power <= v_target_power then
    health := greatest(1, coalesce(p_health, 0));
    strength := greatest(1, coalesce(p_strength, 0));
    defense := greatest(0, coalesce(p_defense, 0));
    speed := greatest(0, coalesce(p_speed, 0));
    agility := greatest(0, coalesce(p_agility, 0));
    stamina := greatest(0, coalesce(p_stamina, 0));
    resistance := greatest(0, coalesce(p_resistance, 0));
    critical_rate := greatest(0, coalesce(p_critical_rate, 0));
    intelligence := greatest(0, coalesce(p_intelligence, 0));
    exploration := greatest(0, coalesce(p_exploration, 0));
    return next;
    return;
  end if;

  v_factor := v_target_power / v_stronger_power;

  v_health := greatest(1, floor(coalesce(p_health, 0) * v_factor)::integer);
  v_strength := greatest(1, floor(coalesce(p_strength, 0) * v_factor)::integer);
  v_defense := greatest(0, floor(coalesce(p_defense, 0) * v_factor)::integer);
  v_speed := greatest(0, floor(coalesce(p_speed, 0) * v_factor)::integer);
  v_agility := greatest(0, floor(coalesce(p_agility, 0) * v_factor)::integer);
  v_stamina := greatest(0, floor(coalesce(p_stamina, 0) * v_factor)::integer);
  v_resistance := greatest(0, floor(coalesce(p_resistance, 0) * v_factor)::integer);
  v_critical_rate := greatest(0, floor(coalesce(p_critical_rate, 0) * v_factor)::integer);
  v_intelligence := greatest(0, floor(coalesce(p_intelligence, 0) * v_factor)::integer);
  v_exploration := greatest(0, floor(coalesce(p_exploration, 0) * v_factor)::integer);

  health := v_health;
  strength := v_strength;
  defense := v_defense;
  speed := v_speed;
  agility := v_agility;
  stamina := v_stamina;
  resistance := v_resistance;
  critical_rate := v_critical_rate;
  intelligence := v_intelligence;
  exploration := v_exploration;
  return next;
end;
$$;

create or replace function public.liftr_combat_stat_balancing_json(
  p_attacker_health integer,
  p_attacker_strength integer,
  p_attacker_defense integer,
  p_attacker_speed integer,
  p_attacker_agility integer,
  p_attacker_stamina integer,
  p_attacker_resistance integer,
  p_attacker_critical_rate integer,
  p_attacker_intelligence integer,
  p_attacker_exploration integer,
  p_defender_health integer,
  p_defender_strength integer,
  p_defender_defense integer,
  p_defender_speed integer,
  p_defender_agility integer,
  p_defender_stamina integer,
  p_defender_resistance integer,
  p_defender_critical_rate integer,
  p_defender_intelligence integer,
  p_defender_exploration integer
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_attacker_pool integer;
  v_defender_pool integer;
  v_attacker_pool_full integer;
  v_defender_pool_full integer;
  v_is_unbalanced boolean;
  v_stronger_side text := null;
  v_attacker_battle_pool integer;
  v_defender_battle_pool integer;
  v_nerf record;
  v_stronger_pool integer;
  v_weaker_pool integer;
  v_hardcore_buff_multiplier numeric := null;
  v_hardcore_bonus_percent integer := null;
begin
  v_attacker_pool := public.liftr_combat_comparison_pool_v1(
    p_attacker_health, p_attacker_strength, p_attacker_defense, p_attacker_speed,
    p_attacker_agility, p_attacker_stamina, p_attacker_resistance,
    p_attacker_critical_rate, p_attacker_intelligence, p_attacker_exploration
  );
  v_defender_pool := public.liftr_combat_comparison_pool_v1(
    p_defender_health, p_defender_strength, p_defender_defense, p_defender_speed,
    p_defender_agility, p_defender_stamina, p_defender_resistance,
    p_defender_critical_rate, p_defender_intelligence, p_defender_exploration
  );
  v_attacker_pool_full := public.liftr_combat_stat_pool_v1(
    p_attacker_health, p_attacker_strength, p_attacker_defense, p_attacker_speed,
    p_attacker_agility, p_attacker_stamina, p_attacker_resistance,
    p_attacker_critical_rate, p_attacker_intelligence, p_attacker_exploration
  );
  v_defender_pool_full := public.liftr_combat_stat_pool_v1(
    p_defender_health, p_defender_strength, p_defender_defense, p_defender_speed,
    p_defender_agility, p_defender_stamina, p_defender_resistance,
    p_defender_critical_rate, p_defender_intelligence, p_defender_exploration
  );

  v_is_unbalanced := public.liftr_combat_is_stat_unbalanced_v1(v_attacker_pool, v_defender_pool);
  v_attacker_battle_pool := v_attacker_pool_full;
  v_defender_battle_pool := v_defender_pool_full;

  if v_is_unbalanced then
    v_stronger_pool := greatest(v_attacker_pool, v_defender_pool);
    v_weaker_pool := least(v_attacker_pool, v_defender_pool);
    v_hardcore_buff_multiplier := v_stronger_pool::numeric / greatest(v_weaker_pool, 1)::numeric;
    v_hardcore_bonus_percent := round((v_hardcore_buff_multiplier - 1.0) * 100.0)::integer;

    if v_attacker_pool >= v_defender_pool then
      v_stronger_side := 'attacker';
      select * into v_nerf from public.liftr_combat_nerf_stats_to_target_v1(
        p_defender_health, p_defender_strength, p_defender_defense, p_defender_speed,
        p_defender_agility, p_defender_stamina, p_defender_resistance,
        p_defender_critical_rate, p_defender_intelligence, p_defender_exploration,
        p_attacker_health, p_attacker_strength, p_attacker_defense, p_attacker_speed,
        p_attacker_agility, p_attacker_stamina, p_attacker_resistance,
        p_attacker_critical_rate, p_attacker_intelligence, p_attacker_exploration
      );
      v_attacker_battle_pool := public.liftr_combat_stat_pool_v1(
        v_nerf.health, v_nerf.strength, v_nerf.defense, v_nerf.speed,
        v_nerf.agility, v_nerf.stamina, v_nerf.resistance,
        v_nerf.critical_rate, v_nerf.intelligence, v_nerf.exploration
      );
    else
      v_stronger_side := 'defender';
      select * into v_nerf from public.liftr_combat_nerf_stats_to_target_v1(
        p_attacker_health, p_attacker_strength, p_attacker_defense, p_attacker_speed,
        p_attacker_agility, p_attacker_stamina, p_attacker_resistance,
        p_attacker_critical_rate, p_attacker_intelligence, p_attacker_exploration,
        p_defender_health, p_defender_strength, p_defender_defense, p_defender_speed,
        p_defender_agility, p_defender_stamina, p_defender_resistance,
        p_defender_critical_rate, p_defender_intelligence, p_defender_exploration
      );
      v_defender_battle_pool := public.liftr_combat_stat_pool_v1(
        v_nerf.health, v_nerf.strength, v_nerf.defense, v_nerf.speed,
        v_nerf.agility, v_nerf.stamina, v_nerf.resistance,
        v_nerf.critical_rate, v_nerf.intelligence, v_nerf.exploration
      );
    end if;
  end if;

  return jsonb_build_object(
    'is_unbalanced', v_is_unbalanced,
    'attacker_stat_pool', v_attacker_pool,
    'defender_stat_pool', v_defender_pool,
    'attacker_pool_battle', v_attacker_battle_pool,
    'defender_pool_battle', v_defender_battle_pool,
    'stronger_side', v_stronger_side,
    'hardcore_buff_multiplier', v_hardcore_buff_multiplier,
    'hardcore_bonus_percent', v_hardcore_bonus_percent
  );
end;
$$;

drop function if exists public.execute_pet_combat_v1(uuid);
create or replace function public.execute_pet_combat_v1(
  p_target_opponent_user_id uuid,
  p_disable_nerf_choice boolean default false
)
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
  v_winner_rewards jsonb;
  v_loser_rewards jsonb;
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
  v_defender_coins integer := 0;
  v_defender_username text;
  v_message text;
  v_attacker_moves text[];
  v_defender_moves text[];
  v_move text;
  v_a_max_dealt integer; v_a_total_dealt integer; v_a_crits integer; v_a_dodges integer;
  v_d_max_dealt integer; v_d_total_dealt integer; v_d_crits integer; v_d_dodges integer;
  v_a_health integer;
  v_a_strength integer;
  v_a_defense integer;
  v_a_speed integer;
  v_a_agility integer;
  v_a_stamina integer;
  v_a_resistance integer;
  v_a_critical_rate integer;
  v_a_intelligence integer;
  v_a_exploration integer;
  v_a_happiness integer;
  v_d_health integer;
  v_d_strength integer;
  v_d_defense integer;
  v_d_speed integer;
  v_d_agility integer;
  v_d_stamina integer;
  v_d_resistance integer;
  v_d_critical_rate integer;
  v_d_intelligence integer;
  v_d_exploration integer;
  v_d_happiness integer;
  v_attacker_pool_original integer;
  v_defender_pool_original integer;
  v_attacker_pool_comparison integer;
  v_defender_pool_comparison integer;
  v_attacker_pool_battle integer;
  v_defender_pool_battle integer;
  v_handicap_applied_to text := null;
  v_combat_mode text := null;
  v_is_handicapped boolean := false;
  v_hardcore_buff_multiplier numeric := null;
  v_disable_nerf_effective boolean := false;
  v_nerf record;
  v_stat_balancing jsonb;
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

  v_a_health := v_attacker.health;
  v_a_strength := v_attacker.strength;
  v_a_defense := v_attacker.defense;
  v_a_speed := v_attacker.speed;
  v_a_agility := v_attacker.agility;
  v_a_stamina := v_attacker.stamina;
  v_a_resistance := v_attacker.resistance;
  v_a_critical_rate := v_attacker.critical_rate;
  v_a_intelligence := v_attacker.intelligence;
  v_a_exploration := v_attacker.exploration;
  v_a_happiness := v_attacker.happiness;

  v_d_health := v_defender.health;
  v_d_strength := v_defender.strength;
  v_d_defense := v_defender.defense;
  v_d_speed := v_defender.speed;
  v_d_agility := v_defender.agility;
  v_d_stamina := v_defender.stamina;
  v_d_resistance := v_defender.resistance;
  v_d_critical_rate := v_defender.critical_rate;
  v_d_intelligence := v_defender.intelligence;
  v_d_exploration := v_defender.exploration;
  v_d_happiness := v_defender.happiness;

  v_attacker_pool_original := public.liftr_combat_stat_pool_v1(
    v_a_health, v_a_strength, v_a_defense, v_a_speed, v_a_agility, v_a_stamina,
    v_a_resistance, v_a_critical_rate, v_a_intelligence, v_a_exploration
  );
  v_defender_pool_original := public.liftr_combat_stat_pool_v1(
    v_d_health, v_d_strength, v_d_defense, v_d_speed, v_d_agility, v_d_stamina,
    v_d_resistance, v_d_critical_rate, v_d_intelligence, v_d_exploration
  );
  v_attacker_pool_comparison := public.liftr_combat_comparison_pool_v1(
    v_a_health, v_a_strength, v_a_defense, v_a_speed, v_a_agility, v_a_stamina,
    v_a_resistance, v_a_critical_rate, v_a_intelligence, v_a_exploration
  );
  v_defender_pool_comparison := public.liftr_combat_comparison_pool_v1(
    v_d_health, v_d_strength, v_d_defense, v_d_speed, v_d_agility, v_d_stamina,
    v_d_resistance, v_d_critical_rate, v_d_intelligence, v_d_exploration
  );

  v_is_handicapped := public.liftr_combat_is_stat_unbalanced_v1(
    v_attacker_pool_comparison,
    v_defender_pool_comparison
  );

  if v_is_handicapped then
    v_hardcore_buff_multiplier := greatest(v_attacker_pool_comparison, v_defender_pool_comparison)::numeric
      / greatest(least(v_attacker_pool_comparison, v_defender_pool_comparison), 1)::numeric;

    v_disable_nerf_effective := coalesce(p_disable_nerf_choice, false)
      and v_attacker_pool_comparison < v_defender_pool_comparison;

    if v_disable_nerf_effective then
      v_combat_mode := 'hardcore';
      v_handicap_applied_to := null;
    else
      v_combat_mode := 'balanced';
      if v_attacker_pool_comparison >= v_defender_pool_comparison then
        v_handicap_applied_to := 'attacker';
        select * into v_nerf from public.liftr_combat_nerf_stats_to_target_v1(
          v_d_health, v_d_strength, v_d_defense, v_d_speed, v_d_agility, v_d_stamina,
          v_d_resistance, v_d_critical_rate, v_d_intelligence, v_d_exploration,
          v_a_health, v_a_strength, v_a_defense, v_a_speed, v_a_agility, v_a_stamina,
          v_a_resistance, v_a_critical_rate, v_a_intelligence, v_a_exploration
        );
        v_a_health := v_nerf.health;
        v_a_strength := v_nerf.strength;
        v_a_defense := v_nerf.defense;
        v_a_speed := v_nerf.speed;
        v_a_agility := v_nerf.agility;
        v_a_stamina := v_nerf.stamina;
        v_a_resistance := v_nerf.resistance;
        v_a_critical_rate := v_nerf.critical_rate;
        v_a_intelligence := v_nerf.intelligence;
        v_a_exploration := v_nerf.exploration;
      else
        v_handicap_applied_to := 'defender';
        select * into v_nerf from public.liftr_combat_nerf_stats_to_target_v1(
          v_a_health, v_a_strength, v_a_defense, v_a_speed, v_a_agility, v_a_stamina,
          v_a_resistance, v_a_critical_rate, v_a_intelligence, v_a_exploration,
          v_d_health, v_d_strength, v_d_defense, v_d_speed, v_d_agility, v_d_stamina,
          v_d_resistance, v_d_critical_rate, v_d_intelligence, v_d_exploration
        );
        v_d_health := v_nerf.health;
        v_d_strength := v_nerf.strength;
        v_d_defense := v_nerf.defense;
        v_d_speed := v_nerf.speed;
        v_d_agility := v_nerf.agility;
        v_d_stamina := v_nerf.stamina;
        v_d_resistance := v_nerf.resistance;
        v_d_critical_rate := v_nerf.critical_rate;
        v_d_intelligence := v_nerf.intelligence;
        v_d_exploration := v_nerf.exploration;
      end if;
    end if;
  end if;

  v_attacker_pool_battle := public.liftr_combat_stat_pool_v1(
    v_a_health, v_a_strength, v_a_defense, v_a_speed, v_a_agility, v_a_stamina,
    v_a_resistance, v_a_critical_rate, v_a_intelligence, v_a_exploration
  );
  v_defender_pool_battle := public.liftr_combat_stat_pool_v1(
    v_d_health, v_d_strength, v_d_defense, v_d_speed, v_d_agility, v_d_stamina,
    v_d_resistance, v_d_critical_rate, v_d_intelligence, v_d_exploration
  );

  v_stat_balancing := jsonb_build_object(
    'mode', v_combat_mode,
    'applied_to', v_handicap_applied_to,
    'buff_multiplier', v_hardcore_buff_multiplier,
    'attacker_pool_original', v_attacker_pool_original,
    'defender_pool_original', v_defender_pool_original,
    'attacker_pool_comparison', v_attacker_pool_comparison,
    'defender_pool_comparison', v_defender_pool_comparison,
    'attacker_pool_battle', v_attacker_pool_battle,
    'defender_pool_battle', v_defender_pool_battle
  );

  v_attacker_max_hp := public.liftr_combat_arena_max_hp_v1(v_a_health, v_handicap_applied_to = 'attacker');
  v_defender_max_hp := public.liftr_combat_arena_max_hp_v1(v_d_health, v_handicap_applied_to = 'defender');
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

    v_attacker_first := v_a_speed > v_d_speed
      or (v_a_speed = v_d_speed and v_a_agility > v_d_agility)
      or (v_a_speed = v_d_speed and v_a_agility = v_d_agility and random() >= 0.5);

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
          v_a_strength,
          v_a_agility,
          v_a_intelligence,
          v_a_critical_rate,
          v_a_happiness,
          v_a_exploration,
          v_d_defense,
          v_d_resistance,
          v_d_agility,
          v_d_stamina,
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
          v_d_strength,
          v_d_agility,
          v_d_intelligence,
          v_d_critical_rate,
          v_d_happiness,
          v_d_exploration,
          v_a_defense,
          v_a_resistance,
          v_a_agility,
          v_a_stamina,
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
    if v_combat_mode = 'hardcore' then
      v_winner_rewards := public.liftr_combat_hardcore_rewards(
        v_attacker.current_level,
        v_defender.current_level,
        v_defender_pool_comparison,
        v_attacker_pool_comparison
      );
    elsif v_handicap_applied_to = 'attacker' then
      v_winner_rewards := public.liftr_combat_handicap_minimum_rewards();
    elsif v_handicap_applied_to = 'defender' then
      v_winner_rewards := public.liftr_combat_premium_rewards(v_attacker.current_level, v_defender.current_level);
    else
      v_winner_rewards := v_scaled_rewards;
    end if;
    v_attacker_rewards := v_winner_rewards;
    v_loser_rewards := public.liftr_combat_loser_rewards(v_winner_rewards);
    v_defender_rewards := v_loser_rewards;
  else
    if v_combat_mode = 'hardcore' then
      v_winner_rewards := public.liftr_combat_handicap_minimum_rewards();
    elsif v_handicap_applied_to = 'defender' then
      v_winner_rewards := public.liftr_combat_handicap_minimum_rewards();
    elsif v_handicap_applied_to = 'attacker' then
      v_winner_rewards := public.liftr_combat_premium_rewards(v_attacker.current_level, v_defender.current_level);
    else
      v_winner_rewards := v_scaled_rewards;
    end if;
    v_loser_rewards := public.liftr_combat_loser_rewards(v_winner_rewards);
    v_attacker_rewards := v_loser_rewards;
    v_defender_rewards := v_winner_rewards;
  end if;

  v_battle_log := jsonb_build_object(
    'version', 1,
    'attacker_pet', v_attacker_snapshot,
    'defender_pet', v_defender_snapshot,
    'turns', v_turns,
    'stat_balancing', v_stat_balancing,
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
    defender_rewards,
    is_handicapped
  )
  values (
    v_combat_id,
    v_attacker_id,
    p_target_opponent_user_id,
    v_winner_user_id,
    v_battle_log,
    v_attacker_rewards,
    v_defender_rewards,
    v_is_handicapped
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
  v_defender_coins := coalesce((v_defender_rewards->>'coins')::integer, 0);

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
      'Your pet was challenged by %s! Your pet %s the match and accumulated %s!',
      coalesce(v_attacker_username, 'Someone'),
      case
        when v_is_draw then 'tied in'
        when v_defender_won then 'won'
        else 'lost'
      end,
      case
        when v_defender_xp > 0 and v_defender_coins > 0 then format('+%s XP and +%s coins', v_defender_xp, v_defender_coins)
        when v_defender_xp > 0 then format('+%s XP', v_defender_xp)
        when v_defender_coins > 0 then format('+%s coins', v_defender_coins)
        else 'no rewards'
      end
    ),
    jsonb_build_object(
      'combat_id', v_combat_id::text,
      'attacker_user_id', v_attacker_id::text,
      'attacker_username', coalesce(v_attacker_username, ''),
      'defender_won', v_defender_won,
      'xp_gained', v_defender_xp,
      'coins_gained', v_defender_coins
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

revoke all on function public.liftr_combat_handicap_health_weight_v1() from public;
revoke all on function public.liftr_combat_handicap_threshold_pct_v1() from public;
revoke all on function public.liftr_combat_comparison_pool_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer) from public;
revoke all on function public.liftr_combat_is_stat_unbalanced_v1(integer, integer) from public;
revoke all on function public.liftr_combat_stat_balancing_json(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer) from public;
revoke all on function public.execute_pet_combat_v1(uuid, boolean) from public;
grant execute on function public.execute_pet_combat_v1(uuid, boolean) to authenticated;


drop function if exists public.execute_pet_combat_v1(uuid);

revoke all on function public.liftr_combat_effective_power_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer) from public;
revoke all on function public.liftr_combat_nerf_stats_to_target_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer) from public;
revoke all on function public.liftr_combat_stat_balancing_json(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer) from public;

commit;

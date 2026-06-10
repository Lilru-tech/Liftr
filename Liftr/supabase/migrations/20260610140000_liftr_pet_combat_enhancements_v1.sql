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
  v_turn_num integer := 0;
  v_max_rounds integer := 50;
  v_round integer := 0;
  v_turns jsonb := '[]'::jsonb;
  v_actor text;
  v_actor_name text;
  v_strike record;
  v_damage integer;
  v_is_critical boolean;
  v_attacker_first boolean;
  v_actions integer;
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

  v_attacker_hp := v_attacker.health;
  v_defender_hp := v_defender.health;

  v_attacker_snapshot := jsonb_build_object(
    'user_id', v_attacker_id,
    'pet_instance_id', v_attacker.id,
    'name', v_attacker_name,
    'pet_type', v_attacker.pet_type,
    'evolution_stage', v_attacker.evolution_stage,
    'level', v_attacker.current_level,
    'rarity', v_attacker.rarity::text,
    'image_url', public.liftr_pet_image_url_for_stage(v_attacker.pet_type, v_attacker.evolution_stage),
    'max_hp', v_attacker.health
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
    'max_hp', v_defender.health
  );

  while v_attacker_hp > 0 and v_defender_hp > 0 and v_round < v_max_rounds loop
    v_round := v_round + 1;

    v_attacker_first := v_attacker.speed > v_defender.speed
      or (v_attacker.speed = v_defender.speed and v_attacker.agility > v_defender.agility)
      or (v_attacker.speed = v_defender.speed and v_attacker.agility = v_defender.agility and random() >= 0.5);

    v_actions := case when v_attacker_hp > 0 and v_defender_hp > 0 then 2 else 1 end;

    for v_action_idx in 1..2 loop
      exit when v_attacker_hp <= 0 or v_defender_hp <= 0;

      if v_action_idx = 1 then
        v_actor := case when v_attacker_first then 'attacker' else 'defender' end;
      else
        v_actor := case when v_attacker_first then 'defender' else 'attacker' end;
      end if;

      if v_actor = 'attacker' then
        v_actor_name := v_attacker_name;
        select * into v_strike from public.liftr_combat_strike_damage(
          v_attacker.strength,
          v_defender.defense,
          v_defender.resistance,
          v_attacker.critical_rate
        );
        v_damage := v_strike.damage;
        v_is_critical := v_strike.is_critical;
        v_defender_hp := greatest(0, v_defender_hp - v_damage);
      else
        v_actor_name := v_defender_name;
        select * into v_strike from public.liftr_combat_strike_damage(
          v_defender.strength,
          v_attacker.defense,
          v_attacker.resistance,
          v_defender.critical_rate
        );
        v_damage := v_strike.damage;
        v_is_critical := v_strike.is_critical;
        v_attacker_hp := greatest(0, v_attacker_hp - v_damage);
      end if;

      v_turn_num := v_turn_num + 1;
      v_turns := v_turns || jsonb_build_array(
        jsonb_build_object(
          'turn', v_turn_num,
          'actor', v_actor,
          'action', 'strike',
          'damage', v_damage,
          'is_critical', v_is_critical,
          'attacker_hp_after', v_attacker_hp,
          'defender_hp_after', v_defender_hp,
          'message', format(
            '%s used a %s dealing %s damage!',
            v_actor_name,
            case when v_is_critical then 'critical strike' else 'heavy strike' end,
            v_damage
          )
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


create or replace function public.get_pet_combat_head_to_head_v1(p_opponent_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_me uuid := auth.uid();
  v_wins integer := 0;
  v_losses integer := 0;
  v_draws integer := 0;
  v_total integer := 0;
  v_win_rate numeric := 0;
  v_last_created timestamptz;
  v_last_winner uuid;
  v_last_attacker uuid;
  v_last_is_draw boolean := false;
  v_last_rewards jsonb;
begin
  if v_me is null then
    raise exception 'not_authenticated';
  end if;

  if p_opponent_user_id is null then
    raise exception 'invalid_target';
  end if;

  select
    count(*) filter (where h.winner_user_id = v_me),
    count(*) filter (where h.winner_user_id is not null and h.winner_user_id <> v_me),
    count(*) filter (where h.winner_user_id is null),
    count(*)
  into v_wins, v_losses, v_draws, v_total
  from public.pet_combat_history h
  where (h.attacker_user_id = v_me and h.defender_user_id = p_opponent_user_id)
     or (h.attacker_user_id = p_opponent_user_id and h.defender_user_id = v_me);

  if v_total > 0 then
    v_win_rate := round(v_wins::numeric / v_total::numeric, 4);
  end if;

  select
    h.created_at,
    h.winner_user_id,
    h.attacker_user_id,
    coalesce((h.battle_log->'result'->>'is_draw')::boolean, false),
    case when h.attacker_user_id = v_me then h.attacker_rewards else h.defender_rewards end
  into v_last_created, v_last_winner, v_last_attacker, v_last_is_draw, v_last_rewards
  from public.pet_combat_history h
  where (h.attacker_user_id = v_me and h.defender_user_id = p_opponent_user_id)
     or (h.attacker_user_id = p_opponent_user_id and h.defender_user_id = v_me)
  order by h.created_at desc
  limit 1;

  return jsonb_build_object(
    'wins', v_wins,
    'losses', v_losses,
    'draws', v_draws,
    'total_battles', v_total,
    'win_rate', v_win_rate,
    'last_battle', case
      when v_total = 0 then null
      else jsonb_build_object(
        'created_at', v_last_created,
        'won', v_last_winner = v_me and not v_last_is_draw,
        'is_draw', v_last_is_draw,
        'your_role', case when v_last_attacker = v_me then 'attacker' else 'defender' end,
        'rewards', coalesce(v_last_rewards, '{"xp":0,"coins":0}'::jsonb)
      )
    end
  );
end;
$$;

grant execute on function public.get_pet_combat_head_to_head_v1(uuid) to authenticated;

update public.pet_market_items set price = case item_type
  when 'food_baby' then 250
  when 'food_kid' then 500
  when 'food_teen' then 1000
  when 'food_adult' then 1750
  when 'food_elder' then 2500
end
where item_type in ('food_baby', 'food_kid', 'food_teen', 'food_adult', 'food_elder');

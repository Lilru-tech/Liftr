begin;

alter table public.profiles
  add column if not exists current_energy int not null default 5,
  add column if not exists max_energy int not null default 5,
  add column if not exists last_energy_refresh timestamptz not null default now();

alter table public.profiles
  drop constraint if exists profiles_energy_bounds_chk;

alter table public.profiles
  add constraint profiles_energy_bounds_chk
    check (current_energy >= 0 and max_energy >= 5 and current_energy <= max_energy);

create or replace function public.allow_profiles_energy_update()
returns void
language sql
security definer
set search_path to public
as $$
  select set_config('app.allow_energy_update', 'true', true);
$$;

create or replace function public.protect_profiles_energy_fields()
returns trigger
language plpgsql
set search_path to public
as $$
begin
  if (
    old.current_energy is distinct from new.current_energy
    or old.max_energy is distinct from new.max_energy
    or old.last_energy_refresh is distinct from new.last_energy_refresh
  ) and current_setting('app.allow_energy_update', true) is distinct from 'true' then
    raise exception 'energy_fields_are_server_managed';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_profiles_energy_fields on public.profiles;
create trigger trg_protect_profiles_energy_fields
  before update on public.profiles
  for each row
  execute function public.protect_profiles_energy_fields();

create table if not exists public.pet_combat_history (
  id uuid primary key default gen_random_uuid(),
  attacker_user_id uuid not null references public.profiles (user_id) on delete cascade,
  defender_user_id uuid not null references public.profiles (user_id) on delete cascade,
  winner_user_id uuid references public.profiles (user_id) on delete set null,
  battle_log jsonb not null,
  attacker_rewards jsonb not null default '{"xp":0,"coins":0}'::jsonb,
  defender_rewards jsonb not null default '{"xp":0,"coins":0}'::jsonb,
  created_at timestamptz not null default now(),
  constraint pet_combat_history_distinct_users_chk check (attacker_user_id <> defender_user_id)
);

create index if not exists pet_combat_history_attacker_defender_created_idx
  on public.pet_combat_history (attacker_user_id, defender_user_id, created_at desc);

create index if not exists pet_combat_history_defender_created_idx
  on public.pet_combat_history (defender_user_id, created_at desc);

alter table public.pet_combat_history enable row level security;

drop policy if exists pet_combat_history_select_own on public.pet_combat_history;
create policy pet_combat_history_select_own on public.pet_combat_history
  for select
  using (auth.uid() = attacker_user_id or auth.uid() = defender_user_id);

revoke insert, update, delete on public.pet_combat_history from authenticated;

alter table public.user_notification_settings
  add column if not exists push_pet_combat_challenged boolean not null default true;

insert into public.pet_market_items (
  item_type, display_name, description, price, category, image_path, is_active
)
values (
  'pet_energy_capacity',
  'Expand Energy Capacity',
  'Increase your daily pet arena energy by one slot. Cost doubles with each purchase.',
  5000,
  'pet_upgrades',
  'market/energy_capacity.png',
  true
)
on conflict (item_type) do update set
  display_name = excluded.display_name,
  description = excluded.description,
  price = excluded.price,
  category = excluded.category,
  image_path = excluded.image_path,
  is_active = excluded.is_active;

create unique index if not exists coin_tx_once_pet_combat_reward
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'pet_combat_reward' and amount > 0;

create unique index if not exists coin_tx_once_pet_energy_capacity_upgrade
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'pet_energy_capacity_upgrade' and amount < 0;

create or replace function public.liftr_refresh_profile_energy(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to public
as $$
begin
  perform public.allow_profiles_energy_update();

  update public.profiles
  set current_energy = max_energy,
      last_energy_refresh = now()
  where user_id = p_user_id
    and date_trunc('day', last_energy_refresh at time zone 'utc')
      < date_trunc('day', now() at time zone 'utc');
end;
$$;

create or replace function public.get_pet_energy_capacity_upgrade_cost(p_max_energy integer)
returns integer
language sql
immutable
set search_path to public
as $$
  select (5000 * power(2, greatest(p_max_energy, 5) - 5))::integer;
$$;

create or replace function public.liftr_profile_energy_json(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to public
as $$
  select jsonb_build_object(
    'current', p.current_energy,
    'max', p.max_energy,
    'last_refresh', p.last_energy_refresh
  )
  from public.profiles p
  where p.user_id = p_user_id;
$$;

create or replace function public.upgrade_pet_energy_capacity_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_max_energy integer;
  v_cost integer;
  v_purchase_id uuid := gen_random_uuid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  perform public.liftr_refresh_profile_energy(v_user_id);

  select max_energy
  into v_max_energy
  from public.profiles
  where user_id = v_user_id
  for update;

  if v_max_energy is null then
    raise exception 'profile_not_found';
  end if;

  if v_max_energy >= 15 then
    raise exception 'max_energy_capacity_reached';
  end if;

  v_cost := public.get_pet_energy_capacity_upgrade_cost(v_max_energy);

  if not public.apply_liftr_coin_transaction(
    v_user_id,
    -v_cost,
    'pet_energy_capacity_upgrade',
    v_purchase_id
  ) then
    raise exception 'insufficient_coins';
  end if;

  perform public.allow_profiles_energy_update();

  update public.profiles
  set max_energy = max_energy + 1,
      current_energy = max_energy + 1,
      last_energy_refresh = now()
  where user_id = v_user_id
  returning max_energy into v_max_energy;

  return jsonb_build_object(
    'max_energy', v_max_energy,
    'current_energy', v_max_energy,
    'cost', v_cost,
    'purchase_id', v_purchase_id
  );
end;
$$;

create or replace function public.liftr_combat_pet_side_json(
  p_user_id uuid,
  p_username text,
  p_instance_id uuid,
  p_pet_type text,
  p_custom_name text,
  p_evolution_stage text,
  p_current_level integer,
  p_rarity text,
  p_health integer,
  p_strength integer,
  p_defense integer,
  p_speed integer,
  p_critical_rate integer,
  p_resistance integer
)
returns jsonb
language plpgsql
stable
set search_path to public
as $$
declare
  v_image_url text;
  v_name text;
begin
  v_image_url := public.liftr_pet_image_url_for_stage(p_pet_type, p_evolution_stage);
  v_name := coalesce(nullif(trim(p_custom_name), ''), initcap(replace(p_pet_type, '_', ' ')));

  return jsonb_build_object(
    'user_id', p_user_id,
    'username', p_username,
    'pet', jsonb_build_object(
      'id', p_instance_id,
      'custom_name', p_custom_name,
      'pet_type', p_pet_type,
      'evolution_stage', p_evolution_stage,
      'current_level', p_current_level,
      'rarity', p_rarity,
      'image_url', v_image_url,
      'name', v_name
    ),
    'stats', jsonb_build_object(
      'health', p_health,
      'strength', p_strength,
      'defense', p_defense,
      'speed', p_speed,
      'critical_rate', p_critical_rate,
      'resistance', p_resistance
    )
  );
end;
$$;

create or replace function public.liftr_combat_reward_multiplier(p_level_diff integer)
returns numeric
language sql
immutable
as $$
  select case
    when p_level_diff <= 5 then 1.0
    when p_level_diff <= 10 then 0.5
    else 0.15
  end;
$$;

create or replace function public.liftr_combat_scaled_rewards(
  p_attacker_level integer,
  p_defender_level integer
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_avg_level numeric;
  v_level_diff integer;
  v_multiplier numeric;
  v_base_xp integer;
  v_base_coins integer;
  v_xp integer;
  v_coins integer;
begin
  v_avg_level := (p_attacker_level + p_defender_level) / 2.0;
  v_level_diff := abs(p_attacker_level - p_defender_level);
  v_multiplier := public.liftr_combat_reward_multiplier(v_level_diff);
  v_base_xp := 30 + floor(v_avg_level * 8)::integer;
  v_base_coins := 15 + floor(v_avg_level * 4)::integer;
  v_xp := greatest(10, floor(v_base_xp * v_multiplier)::integer);
  v_coins := greatest(5, floor(v_base_coins * v_multiplier)::integer);
  return jsonb_build_object('xp', v_xp, 'coins', v_coins);
end;
$$;

create or replace function public.liftr_combat_strike_damage(
  p_strength integer,
  p_defense integer,
  p_resistance integer,
  p_critical_rate integer,
  out damage integer,
  out is_critical boolean
)
returns record
language plpgsql
volatile
as $$
declare
  v_raw numeric;
  v_mitigated numeric;
  v_variance numeric;
  v_crit_mult numeric := 1.0;
begin
  is_critical := random() < (greatest(p_critical_rate, 0)::numeric / 100.0);
  if is_critical then
    v_crit_mult := 1.75;
  end if;

  v_raw := greatest(p_strength, 1)::numeric * (100.0 / (100.0 + greatest(p_defense, 0)));
  v_mitigated := v_raw * (100.0 / (100.0 + greatest(p_resistance, 0)));
  v_variance := 0.85 + (random() * 0.30);
  damage := greatest(1, floor(v_mitigated * v_variance * v_crit_mult)::integer);
end;
$$;

create or replace function public.liftr_combat_cooldown_expires_at(
  p_attacker_user_id uuid,
  p_defender_user_id uuid
)
returns timestamptz
language sql
stable
set search_path to public
as $$
  select h.created_at + interval '24 hours'
  from public.pet_combat_history h
  where h.attacker_user_id = p_attacker_user_id
    and h.defender_user_id = p_defender_user_id
    and h.created_at > now() - interval '24 hours'
  order by h.created_at desc
  limit 1;
$$;

create or replace function public.liftr_combat_load_side(
  p_user_id uuid,
  out instance_id uuid,
  out username text,
  out pet_type text,
  out custom_name text,
  out evolution_stage text,
  out current_level integer,
  out rarity text,
  out health integer,
  out strength integer,
  out defense integer,
  out speed integer,
  out agility integer,
  out critical_rate integer,
  out resistance integer
)
returns record
language plpgsql
stable
set search_path to public
as $$
begin
  select p.username
  into username
  from public.profiles p
  where p.user_id = p_user_id;

  select
    pi.id,
    pi.pet_type,
    pi.custom_name,
    pi.evolution_stage,
    pi.current_level,
    pi.rarity::text,
    ps.health,
    ps.strength,
    ps.defense,
    ps.speed,
    ps.agility,
    ps.critical_rate,
    ps.resistance
  into
    instance_id,
    pet_type,
    custom_name,
    evolution_stage,
    current_level,
    rarity,
    health,
    strength,
    defense,
    speed,
    agility,
    critical_rate,
    resistance
  from public.pet_instances pi
  join public.pet_instance_stats ps on ps.pet_instance_id = pi.id
  where pi.user_id = p_user_id
    and pi.is_active = true
    and pi.is_equipped = true
  limit 1;
end;
$$;

create or replace function public.get_pet_combat_preview_v1(p_target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_attacker_id uuid := auth.uid();
  v_attacker record;
  v_defender record;
  v_can_challenge boolean := false;
  v_block_reason text := null;
  v_cooldown timestamptz;
  v_current_energy integer;
  v_max_energy integer;
begin
  if v_attacker_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_target_user_id is null then
    raise exception 'invalid_target';
  end if;

  perform public.liftr_refresh_profile_energy(v_attacker_id);

  select current_energy, max_energy
  into v_current_energy, v_max_energy
  from public.profiles
  where user_id = v_attacker_id;

  select * into v_attacker from public.liftr_combat_load_side(v_attacker_id);
  select * into v_defender from public.liftr_combat_load_side(p_target_user_id);

  if p_target_user_id = v_attacker_id then
    v_block_reason := 'self_challenge';
  elsif v_attacker.instance_id is null then
    v_block_reason := 'attacker_no_pet';
  elsif v_defender.instance_id is null then
    v_block_reason := 'defender_no_pet';
  elsif lower(coalesce(v_attacker.evolution_stage, 'egg')) = 'egg' then
    v_block_reason := 'attacker_egg';
  elsif lower(coalesce(v_defender.evolution_stage, 'egg')) = 'egg' then
    v_block_reason := 'defender_egg';
  elsif coalesce(v_current_energy, 0) <= 0 then
    v_block_reason := 'no_energy';
  else
    v_cooldown := public.liftr_combat_cooldown_expires_at(v_attacker_id, p_target_user_id);
    if v_cooldown is not null and v_cooldown > now() then
      v_block_reason := 'cooldown_active';
    else
      v_can_challenge := true;
    end if;
  end if;

  return jsonb_build_object(
    'can_challenge', v_can_challenge,
    'block_reason', v_block_reason,
    'cooldown_expires_at', v_cooldown,
    'attacker', case
      when v_attacker.instance_id is null then null
      else public.liftr_combat_pet_side_json(
        v_attacker_id,
        v_attacker.username,
        v_attacker.instance_id,
        v_attacker.pet_type,
        v_attacker.custom_name,
        v_attacker.evolution_stage,
        v_attacker.current_level,
        v_attacker.rarity,
        v_attacker.health,
        v_attacker.strength,
        v_attacker.defense,
        v_attacker.speed,
        v_attacker.critical_rate,
        v_attacker.resistance
      )
    end,
    'defender', case
      when v_defender.instance_id is null then null
      else public.liftr_combat_pet_side_json(
        p_target_user_id,
        v_defender.username,
        v_defender.instance_id,
        v_defender.pet_type,
        v_defender.custom_name,
        v_defender.evolution_stage,
        v_defender.current_level,
        v_defender.rarity,
        v_defender.health,
        v_defender.strength,
        v_defender.defense,
        v_defender.speed,
        v_defender.critical_rate,
        v_defender.resistance
      )
    end,
    'energy', jsonb_build_object(
      'current', coalesce(v_current_energy, 0),
      'max', coalesce(v_max_energy, 5)
    )
  );
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
    'image_url', public.liftr_pet_image_url_for_stage(v_attacker.pet_type, v_attacker.evolution_stage)
  );

  v_defender_snapshot := jsonb_build_object(
    'user_id', p_target_opponent_user_id,
    'pet_instance_id', v_defender.id,
    'name', v_defender_name,
    'pet_type', v_defender.pet_type,
    'evolution_stage', v_defender.evolution_stage,
    'level', v_defender.current_level,
    'rarity', v_defender.rarity::text,
    'image_url', public.liftr_pet_image_url_for_stage(v_defender.pet_type, v_defender.evolution_stage)
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
  v_pet_type text;
  v_image_url text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  perform public.liftr_hatch_pet_egg_for_user(v_user_id);
  perform public.liftr_refresh_profile_energy(v_user_id);

  select to_jsonb(pi.*) into v_pet
  from public.pet_instances pi
  where pi.user_id = v_user_id
    and pi.is_active = true
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(ui.*)), '[]'::jsonb) into v_inventory
  from public.user_inventory ui
  where ui.user_id = v_user_id
    and ui.quantity > 0;

  if v_pet is null then
    return jsonb_build_object(
      'pet', null,
      'stats', null,
      'inventory', v_inventory,
      'xp_required', 0,
      'can_evolve', false,
      'energy', public.liftr_profile_energy_json(v_user_id)
    );
  end if;

  v_stage := v_pet->>'evolution_stage';
  v_pet_type := v_pet->>'pet_type';
  v_image_url := public.liftr_pet_image_url_for_stage(v_pet_type, v_stage);

  if v_image_url is not null then
    v_pet := jsonb_set(v_pet, '{image_url}', to_jsonb(v_image_url), true);
  end if;

  select to_jsonb(ps.*) into v_stats
  from public.pet_instance_stats ps
  where ps.pet_instance_id = (v_pet->>'id')::uuid;

  select required_exp into v_required_exp
  from public.pet_levels
  where level = (v_pet->>'current_level')::integer;

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
    'can_evolve', v_can_evolve,
    'energy', public.liftr_profile_energy_json(v_user_id)
  );
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
  v_owns_egg boolean;
  v_owns_incubator boolean;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity';
  end if;

  if p_item_type = 'pet_rarity_upgrade' then
    raise exception 'use_upgrade_pet_rarity_rpc';
  end if;

  if p_item_type = 'pet_energy_capacity' then
    raise exception 'use_upgrade_pet_energy_capacity_rpc';
  end if;

  select * into v_item
  from public.pet_market_items
  where item_type = p_item_type
    and is_active = true;

  if v_item is null then
    raise exception 'item_not_found';
  end if;

  select exists (
    select 1 from public.pet_instances
    where user_id = v_user_id and is_active = true
  ) into v_has_active_pet;

  select coalesce(quantity, 0) > 0 into v_owns_egg
  from public.user_inventory
  where user_id = v_user_id and item_type = 'pet_egg';

  select coalesce(quantity, 0) > 0 into v_owns_incubator
  from public.user_inventory
  where user_id = v_user_id and item_type = 'incubator';

  if p_item_type = 'pet_egg' then
    if v_has_active_pet then
      raise exception 'already_has_pet';
    end if;
    if coalesce(v_owns_egg, false) then
      raise exception 'already_owns_egg';
    end if;
    if p_quantity != 1 then
      raise exception 'invalid_quantity';
    end if;
  end if;

  if p_item_type = 'incubator' then
    if v_has_active_pet then
      raise exception 'already_has_pet';
    end if;
    if coalesce(v_owns_incubator, false) then
      raise exception 'already_owns_incubator';
    end if;
    if p_quantity != 1 then
      raise exception 'invalid_quantity';
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

revoke all on function public.liftr_refresh_profile_energy(uuid) from public;
revoke all on function public.get_pet_energy_capacity_upgrade_cost(integer) from public;
revoke all on function public.liftr_profile_energy_json(uuid) from public;
revoke all on function public.upgrade_pet_energy_capacity_v1() from public;
revoke all on function public.liftr_combat_pet_side_json(uuid, text, uuid, text, text, text, integer, text, integer, integer, integer, integer, integer, integer) from public;
revoke all on function public.liftr_combat_reward_multiplier(integer) from public;
revoke all on function public.liftr_combat_scaled_rewards(integer, integer) from public;
revoke all on function public.liftr_combat_strike_damage(integer, integer, integer, integer) from public;
revoke all on function public.liftr_combat_cooldown_expires_at(uuid, uuid) from public;
revoke all on function public.liftr_combat_load_side(uuid) from public;
revoke all on function public.get_pet_combat_preview_v1(uuid) from public;
revoke all on function public.execute_pet_combat_v1(uuid) from public;

grant execute on function public.upgrade_pet_energy_capacity_v1() to authenticated;
grant execute on function public.get_pet_combat_preview_v1(uuid) to authenticated;
grant execute on function public.execute_pet_combat_v1(uuid) to authenticated;

commit;

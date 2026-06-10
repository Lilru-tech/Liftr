begin;

-- 1. Pet-type combat moves (cosmetic flavor)
create table if not exists public.pet_type_combat_moves (
  id bigint generated always as identity primary key,
  pet_type text not null references public.pet_types (name) on delete cascade,
  move_name text not null,
  unique (pet_type, move_name)
);

alter table public.pet_type_combat_moves enable row level security;

drop policy if exists pet_type_combat_moves_read on public.pet_type_combat_moves;
create policy pet_type_combat_moves_read on public.pet_type_combat_moves for select using (true);

revoke insert, update, delete on public.pet_type_combat_moves from authenticated;

-- Generic moves for every pet type
insert into public.pet_type_combat_moves (pet_type, move_name)
select pt.name, m.move
from public.pet_types pt
cross join (values ('Tackle'), ('Headbutt'), ('Quick Strike')) m(move)
on conflict do nothing;

-- Winged
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, m.move
from unnest(array[
  'chocobo','chick','eagle','owl','flamingo','phoenix','ice_phoenix','pterodactyl',
  'griffin','mythochic','skydasher','witch_crow','dragon','mechadragon','drakeling','drone_beetle'
]) t(name)
join public.pet_types pt on pt.name = t.name
cross join (values ('Wing Slash'), ('Dive Bomb')) m(move)
on conflict do nothing;

-- Feline / clawed
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, m.move
from unnest(array[
  'tiger','lion','leopard','lynx','cybercat','cryptocat','neon_panther',
  'oniricat','sphinx','fox','holofox','kitsune'
]) t(name)
join public.pet_types pt on pt.name = t.name
cross join (values ('Claw Swipe'), ('Pounce')) m(move)
on conflict do nothing;

-- Biters
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, m.move
from unnest(array[
  'wolf','astrowolf','hellhound','grim_pup','crocodile','shark','snake',
  'void_serpent','tiranosaurus','godzilla','xenopup','dragon','drakeling'
]) t(name)
join public.pet_types pt on pt.name = t.name
cross join (values ('Savage Bite'), ('Snap Attack')) m(move)
on conflict do nothing;

-- Aquatic
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Tail Slap'
from unnest(array['octopus','dolphin','orca','shark','crab','starfishoid','turtle','hippo']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Tentacled / amorphous
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Tentacle Whip'
from unnest(array['octopus','starfishoid','quantum_slime','zorgling']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Heavy
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Stomp'
from unnest(array['elephant','hippo','gorilla','godzilla','tiranosaurus','triceratops','panda','kangaroo']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Horned
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Horn Charge'
from unnest(array['triceratops','unicorn','celestial_kirin']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Shelled
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Shell Bash'
from unnest(array['turtle','armadillo','crab']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Hoppers
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Power Hop'
from unnest(array['bunny','shadowbunny','kangaroo','monkey']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Sneaky
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Sneak Attack'
from unnest(array['raccoon','koala','monkey','fox','kitsune','shadowbunny','cryptocat']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Fire breathers
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Fire Breath'
from unnest(array['dragon','mechadragon','drakeling','phoenix','godzilla','hellhound','meteokko']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, 'Frost Breath'
from unnest(array['ice_phoenix']) t(name)
join public.pet_types pt on pt.name = t.name
on conflict do nothing;

-- Mystic
insert into public.pet_type_combat_moves (pet_type, move_name)
select t.name, m.move
from unnest(array[
  'unicorn','sphinx','chimera','kitsune','soul_wisp','spectrophant','witch_crow','demon',
  'celestial_kirin','shadowbunny','holofox','oniricat','void_serpent','quantum_slime',
  'meteokko','zorgling','cryptocat','ice_phoenix'
]) t(name)
join public.pet_types pt on pt.name = t.name
cross join (values ('Mystic Blast'), ('Shadow Strike')) m(move)
on conflict do nothing;

-- 2. Per-user lifetime combat records
create table if not exists public.pet_combat_user_stats (
  user_id uuid primary key references public.profiles (user_id) on delete cascade,
  max_damage_dealt integer not null default 0,
  max_damage_taken integer not null default 0,
  total_damage_dealt bigint not null default 0,
  total_damage_taken bigint not null default 0,
  crits_landed integer not null default 0,
  dodges_performed integer not null default 0,
  total_battles integer not null default 0,
  wins integer not null default 0,
  losses integer not null default 0,
  draws integer not null default 0,
  current_win_streak integer not null default 0,
  best_win_streak integer not null default 0,
  longest_battle_turns integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.pet_combat_user_stats enable row level security;

drop policy if exists pet_combat_user_stats_select_own on public.pet_combat_user_stats;
create policy pet_combat_user_stats_select_own on public.pet_combat_user_stats
  for select using (auth.uid() = user_id);

revoke insert, update, delete on public.pet_combat_user_stats from authenticated;

create or replace function public.liftr_combat_record_user_stats(
  p_user_id uuid,
  p_max_dealt integer,
  p_max_taken integer,
  p_total_dealt integer,
  p_total_taken integer,
  p_crits integer,
  p_dodges integer,
  p_won boolean,
  p_is_draw boolean,
  p_battle_turns integer
)
returns void
language sql
security definer
set search_path to public
as $$
  insert into public.pet_combat_user_stats as s (
    user_id, max_damage_dealt, max_damage_taken, total_damage_dealt, total_damage_taken,
    crits_landed, dodges_performed, total_battles, wins, losses, draws,
    current_win_streak, best_win_streak, longest_battle_turns, updated_at
  )
  values (
    p_user_id, p_max_dealt, p_max_taken, p_total_dealt, p_total_taken,
    p_crits, p_dodges, 1,
    case when p_won and not p_is_draw then 1 else 0 end,
    case when not p_won and not p_is_draw then 1 else 0 end,
    case when p_is_draw then 1 else 0 end,
    case when p_won and not p_is_draw then 1 else 0 end,
    case when p_won and not p_is_draw then 1 else 0 end,
    p_battle_turns, now()
  )
  on conflict (user_id) do update set
    max_damage_dealt = greatest(s.max_damage_dealt, excluded.max_damage_dealt),
    max_damage_taken = greatest(s.max_damage_taken, excluded.max_damage_taken),
    total_damage_dealt = s.total_damage_dealt + excluded.total_damage_dealt,
    total_damage_taken = s.total_damage_taken + excluded.total_damage_taken,
    crits_landed = s.crits_landed + excluded.crits_landed,
    dodges_performed = s.dodges_performed + excluded.dodges_performed,
    total_battles = s.total_battles + 1,
    wins = s.wins + excluded.wins,
    losses = s.losses + excluded.losses,
    draws = s.draws + excluded.draws,
    current_win_streak = case
      when excluded.wins > 0 then s.current_win_streak + 1
      when excluded.draws > 0 then s.current_win_streak
      else 0
    end,
    best_win_streak = greatest(
      s.best_win_streak,
      case when excluded.wins > 0 then s.current_win_streak + 1 else s.best_win_streak end
    ),
    longest_battle_turns = greatest(s.longest_battle_turns, excluded.longest_battle_turns),
    updated_at = now();
$$;

create or replace function public.get_pet_combat_user_stats_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  s record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into s
  from public.pet_combat_user_stats
  where user_id = v_user_id;

  return jsonb_build_object(
    'max_damage_dealt', coalesce(s.max_damage_dealt, 0),
    'max_damage_taken', coalesce(s.max_damage_taken, 0),
    'total_damage_dealt', coalesce(s.total_damage_dealt, 0),
    'total_damage_taken', coalesce(s.total_damage_taken, 0),
    'crits_landed', coalesce(s.crits_landed, 0),
    'dodges_performed', coalesce(s.dodges_performed, 0),
    'total_battles', coalesce(s.total_battles, 0),
    'wins', coalesce(s.wins, 0),
    'losses', coalesce(s.losses, 0),
    'draws', coalesce(s.draws, 0),
    'current_win_streak', coalesce(s.current_win_streak, 0),
    'best_win_streak', coalesce(s.best_win_streak, 0),
    'longest_battle_turns', coalesce(s.longest_battle_turns, 0)
  );
end;
$$;

-- 3. Strike v3: absolute stat-driven damage
create or replace function public.liftr_combat_strike_v3(
  p_attacker_strength integer,
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
  v_strength numeric := greatest(p_attacker_strength, 1)::numeric;
begin
  damage := 0;
  is_critical := false;
  is_dodged := false;

  v_dodge_chance := least(0.15, greatest(0.02,
    (greatest(p_defender_agility, 0) - greatest(p_attacker_intelligence, 0) / 2.0) * 0.01
  ));
  if random() < v_dodge_chance then
    is_dodged := true;
    return;
  end if;

  is_critical := random() < least(0.5, greatest(p_attacker_critical_rate, 0)::numeric / 100.0);
  if is_critical then
    v_crit_mult := least(2.25, 1.75 + greatest(p_attacker_intelligence, 0) * 0.005);
  end if;

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
    1.4
      * v_strength
      * v_mitigation
      * v_variance
      * v_crit_mult
      * v_fatigue
      * v_first_strike
  )::integer);
end;
$$;

-- 4. Combat execution: HP x10, moves, records
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

  v_attacker_max_hp := greatest(v_attacker.health, 1) * 10;
  v_defender_max_hp := greatest(v_defender.health, 1) * 10;
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

drop function if exists public.liftr_combat_strike_v2(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, boolean);

revoke all on function public.liftr_combat_strike_v3(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, boolean) from public;
revoke all on function public.liftr_combat_record_user_stats(uuid, integer, integer, integer, integer, integer, integer, boolean, boolean, integer) from public;
revoke all on function public.execute_pet_combat_v1(uuid) from public;
grant execute on function public.execute_pet_combat_v1(uuid) to authenticated;
grant execute on function public.get_pet_combat_user_stats_v1() to authenticated;

commit;

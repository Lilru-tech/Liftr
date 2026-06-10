drop function if exists public.get_pet_combat_preview_v1(uuid);
drop function if exists public.liftr_combat_pet_side_json(uuid, text, uuid, text, text, text, integer, text, integer, integer, integer, integer, integer, integer);
drop function if exists public.liftr_combat_pet_side_json(uuid, text, uuid, text, text, text, integer, text, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer);
drop function if exists public.liftr_combat_load_side(uuid);

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
  out intelligence integer,
  out agility integer,
  out stamina integer,
  out critical_rate integer,
  out resistance integer,
  out exploration integer,
  out happiness integer
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
    ps.intelligence,
    ps.agility,
    ps.stamina,
    ps.critical_rate,
    ps.resistance,
    ps.exploration,
    ps.happiness
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
    intelligence,
    agility,
    stamina,
    critical_rate,
    resistance,
    exploration,
    happiness
  from public.pet_instances pi
  join public.pet_instance_stats ps on ps.pet_instance_id = pi.id
  where pi.user_id = p_user_id
    and pi.is_active = true
  order by pi.created_at desc
  limit 1;
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
  p_intelligence integer,
  p_agility integer,
  p_stamina integer,
  p_critical_rate integer,
  p_resistance integer,
  p_exploration integer,
  p_happiness integer
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
      'intelligence', p_intelligence,
      'agility', p_agility,
      'stamina', p_stamina,
      'critical_rate', p_critical_rate,
      'resistance', p_resistance,
      'exploration', p_exploration,
      'happiness', p_happiness
    )
  );
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
        v_attacker.intelligence,
        v_attacker.agility,
        v_attacker.stamina,
        v_attacker.critical_rate,
        v_attacker.resistance,
        v_attacker.exploration,
        v_attacker.happiness
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
        v_defender.intelligence,
        v_defender.agility,
        v_defender.stamina,
        v_defender.critical_rate,
        v_defender.resistance,
        v_defender.exploration,
        v_defender.happiness
      )
    end,
    'energy', jsonb_build_object(
      'current', coalesce(v_current_energy, 0),
      'max', coalesce(v_max_energy, 5)
    )
  );
end;
$$;

grant execute on function public.get_pet_combat_preview_v1(uuid) to authenticated;

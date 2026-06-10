begin;

-- Energía de arena: pasa del refill diario completo (UTC) a regeneración por punto,
-- 1 energía cada 4 horas hasta max_energy. liftr_profile_energy_json expone
-- next_refresh_at y regen_minutes para que los clientes muestren la cuenta atrás.

create or replace function public.liftr_refresh_profile_energy(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_now timestamptz := now();
  v_current integer;
  v_max integer;
  v_last timestamptz;
  v_points integer;
begin
  perform public.allow_profiles_energy_update();

  select current_energy, max_energy, last_energy_refresh
  into v_current, v_max, v_last
  from public.profiles
  where user_id = p_user_id
  for update;

  if not found then
    return;
  end if;

  v_points := greatest(0, floor(extract(epoch from (v_now - v_last)) / 14400))::integer;

  if v_current + v_points >= v_max then
    update public.profiles
    set current_energy = v_max,
        last_energy_refresh = v_now
    where user_id = p_user_id;
  elsif v_points > 0 then
    update public.profiles
    set current_energy = v_current + v_points,
        last_energy_refresh = v_last + (v_points * interval '4 hours')
    where user_id = p_user_id;
  end if;
end;
$$;

revoke all on function public.liftr_refresh_profile_energy(uuid) from public;
revoke all on function public.liftr_refresh_profile_energy(uuid) from anon;
revoke all on function public.liftr_refresh_profile_energy(uuid) from authenticated;

create or replace function public.liftr_profile_energy_json(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object(
    'current', p.current_energy,
    'max', p.max_energy,
    'last_refresh', p.last_energy_refresh,
    'next_refresh_at', case
      when p.current_energy < p.max_energy then p.last_energy_refresh + interval '4 hours'
      else null
    end,
    'regen_minutes', 240
  )
  from public.profiles p
  where p.user_id = p_user_id;
$$;

revoke all on function public.liftr_profile_energy_json(uuid) from public;
revoke all on function public.liftr_profile_energy_json(uuid) from anon;
revoke all on function public.liftr_profile_energy_json(uuid) from authenticated;

create or replace function public.get_pet_combat_preview_v1(p_target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
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
    'energy', public.liftr_profile_energy_json(v_attacker_id)
  );
end;
$$;

revoke all on function public.get_pet_combat_preview_v1(uuid) from public;
revoke all on function public.get_pet_combat_preview_v1(uuid) from anon;
grant execute on function public.get_pet_combat_preview_v1(uuid) to authenticated;

commit;

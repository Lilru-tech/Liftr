begin;

create or replace function public.liftr_compute_hatch_stats_v1(
  p_pet_type text,
  p_rarity text
)
returns jsonb
language plpgsql
stable
set search_path to public
as $$
declare
  weights record;
  total_weight integer;
  base_points integer;
  v_stat_mult numeric;
  stat_keys text[] := array[
    'health', 'strength', 'defense', 'speed', 'intelligence',
    'agility', 'stamina', 'critical_rate', 'resistance',
    'exploration', 'happiness'
  ];
  stat text;
  value integer;
  allocations jsonb := '{}'::jsonb;
begin
  select coalesce(c.stat_multiplier, 1.00)
  into v_stat_mult
  from public.pet_rarity_config c
  where c.rarity::text = p_rarity;

  if v_stat_mult is null then
    v_stat_mult := 1.00;
  end if;

  base_points := greatest(1, round(50 * v_stat_mult)::integer);

  select * into weights
  from public.pet_type_stat_weights
  where pet_type = p_pet_type;

  if weights is null then
    return '{}'::jsonb;
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

  return allocations;
end;
$$;

create or replace function public.recompute_pet_stats_combat_balance_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  pet record;
  log record;
  v_stage text;
  v_delta jsonb;
  v_hatch jsonb;
  v_total_health integer := 0;
  v_total_strength integer := 0;
  v_total_defense integer := 0;
  v_total_speed integer := 0;
  v_total_intelligence integer := 0;
  v_total_agility integer := 0;
  v_total_stamina integer := 0;
  v_total_critical_rate integer := 0;
  v_total_resistance integer := 0;
  v_total_exploration integer := 0;
  v_total_happiness integer := 0;
begin
  for pet in
    select pi.id, pi.pet_type, pi.user_id, pi.rarity::text as rarity
    from public.pet_instances pi
    where lower(pi.evolution_stage) <> 'egg'
  loop
    v_hatch := public.liftr_compute_hatch_stats_v1(pet.pet_type, pet.rarity);

    if v_hatch = '{}'::jsonb then
      continue;
    end if;

    v_total_health := 0;
    v_total_strength := 0;
    v_total_defense := 0;
    v_total_speed := 0;
    v_total_intelligence := 0;
    v_total_agility := 0;
    v_total_stamina := 0;
    v_total_critical_rate := 0;
    v_total_resistance := 0;
    v_total_exploration := 0;
    v_total_happiness := 0;

    for log in
      select pl.id, pl.created_at, pl.new_level
      from public.pet_logs pl
      where pl.pet_instance_id = pet.id
        and pl.event_type = 'level_up'
      order by pl.new_level nulls last, pl.created_at, pl.id
    loop
      v_stage := public.resolve_pet_stage_at_time(pet.id, log.created_at);
      v_delta := public.compute_pet_level_stat_delta_v1(pet.pet_type, v_stage, pet.user_id);

      update public.pet_logs
      set stats_delta = v_delta
      where id = log.id;

      v_total_health := v_total_health + coalesce((v_delta ->> 'health')::integer, 0);
      v_total_strength := v_total_strength + coalesce((v_delta ->> 'strength')::integer, 0);
      v_total_defense := v_total_defense + coalesce((v_delta ->> 'defense')::integer, 0);
      v_total_speed := v_total_speed + coalesce((v_delta ->> 'speed')::integer, 0);
      v_total_intelligence := v_total_intelligence + coalesce((v_delta ->> 'intelligence')::integer, 0);
      v_total_agility := v_total_agility + coalesce((v_delta ->> 'agility')::integer, 0);
      v_total_stamina := v_total_stamina + coalesce((v_delta ->> 'stamina')::integer, 0);
      v_total_critical_rate := v_total_critical_rate + coalesce((v_delta ->> 'critical_rate')::integer, 0);
      v_total_resistance := v_total_resistance + coalesce((v_delta ->> 'resistance')::integer, 0);
      v_total_exploration := v_total_exploration + coalesce((v_delta ->> 'exploration')::integer, 0);
      v_total_happiness := v_total_happiness + coalesce((v_delta ->> 'happiness')::integer, 0);
    end loop;

    insert into public.pet_instance_stats (pet_instance_id)
    values (pet.id)
    on conflict (pet_instance_id) do nothing;

    update public.pet_instance_stats
    set
      health = greatest(0, coalesce((v_hatch ->> 'health')::integer, 0) + v_total_health),
      strength = greatest(0, coalesce((v_hatch ->> 'strength')::integer, 0) + v_total_strength),
      defense = greatest(0, coalesce((v_hatch ->> 'defense')::integer, 0) + v_total_defense),
      speed = greatest(0, coalesce((v_hatch ->> 'speed')::integer, 0) + v_total_speed),
      intelligence = greatest(0, coalesce((v_hatch ->> 'intelligence')::integer, 0) + v_total_intelligence),
      agility = greatest(0, coalesce((v_hatch ->> 'agility')::integer, 0) + v_total_agility),
      stamina = greatest(0, coalesce((v_hatch ->> 'stamina')::integer, 0) + v_total_stamina),
      critical_rate = greatest(0, coalesce((v_hatch ->> 'critical_rate')::integer, 0) + v_total_critical_rate),
      resistance = greatest(0, coalesce((v_hatch ->> 'resistance')::integer, 0) + v_total_resistance),
      exploration = greatest(0, coalesce((v_hatch ->> 'exploration')::integer, 0) + v_total_exploration),
      happiness = greatest(0, coalesce((v_hatch ->> 'happiness')::integer, 0) + v_total_happiness)
    where pet_instance_id = pet.id;
  end loop;
end;
$$;

revoke all on function public.liftr_compute_hatch_stats_v1(text, text) from public;
revoke all on function public.recompute_pet_stats_combat_balance_v1() from public;
revoke all on function public.liftr_compute_hatch_stats_v1(text, text) from anon, authenticated;
revoke all on function public.recompute_pet_stats_combat_balance_v1() from anon, authenticated;

select public.recompute_pet_stats_combat_balance_v1();

commit;

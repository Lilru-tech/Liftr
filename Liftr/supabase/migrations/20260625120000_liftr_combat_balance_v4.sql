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

revoke all on function public.liftr_combat_battle_hp_v1(integer) from public;
revoke all on function public.liftr_combat_strike_v4(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, boolean) from public;

commit;

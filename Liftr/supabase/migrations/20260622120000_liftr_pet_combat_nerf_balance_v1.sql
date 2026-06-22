begin;

create or replace function public.liftr_combat_handicap_pool_multiplier_v1()
returns numeric
language sql
immutable
as $$
  select 1.07::numeric;
$$;

create or replace function public.liftr_combat_arena_max_hp_v1(
  p_health integer,
  p_side_was_nerfed boolean default null
)
returns integer
language sql
immutable
as $$
  select greatest(coalesce(p_health, 0), 1);
$$;

create or replace function public.liftr_combat_nerf_stats_to_target_v1(
  p_weaker_pool integer,
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
  v_stronger_pool integer;
  v_target_pool integer;
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
  v_sum integer;
  v_delta integer;
begin
  v_stronger_pool := public.liftr_combat_stat_pool_v1(
    p_health, p_strength, p_defense, p_speed, p_agility, p_stamina,
    p_resistance, p_critical_rate, p_intelligence, p_exploration
  );
  v_target_pool := floor(
    greatest(coalesce(p_weaker_pool, 0), 0) * public.liftr_combat_handicap_pool_multiplier_v1()
  )::integer;

  if v_stronger_pool <= v_target_pool then
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

  v_factor := v_target_pool::numeric / v_stronger_pool::numeric;

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

  v_sum := public.liftr_combat_stat_pool_v1(
    v_health, v_strength, v_defense, v_speed, v_agility, v_stamina,
    v_resistance, v_critical_rate, v_intelligence, v_exploration
  );
  v_delta := v_target_pool - v_sum;
  if v_delta <> 0 then
    v_health := greatest(1, v_health + v_delta);
  end if;

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

revoke all on function public.liftr_combat_handicap_pool_multiplier_v1() from public;
revoke all on function public.liftr_combat_arena_max_hp_v1(integer, boolean) from public;
revoke all on function public.liftr_combat_nerf_stats_to_target_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer) from public;

commit;

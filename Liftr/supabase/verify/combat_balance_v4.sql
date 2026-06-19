do $$
begin
  if to_regprocedure('public.liftr_combat_battle_hp_v1(integer)') is null then
    raise exception 'missing function liftr_combat_battle_hp_v1';
  end if;

  if to_regprocedure('public.liftr_combat_strike_v4(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, boolean)') is null then
    raise exception 'missing function liftr_combat_strike_v4';
  end if;

  if to_regprocedure('public.recompute_pet_stats_combat_balance_v1()') is null then
    raise exception 'missing function recompute_pet_stats_combat_balance_v1';
  end if;

  if to_regprocedure('public.execute_pet_combat_v1(uuid, boolean)') is null then
    raise exception 'missing function execute_pet_combat_v1';
  end if;

  if public.liftr_combat_battle_hp_v1(100) <> 80 then
    raise exception 'liftr_combat_battle_hp_v1(100) expected 80 got %', public.liftr_combat_battle_hp_v1(100);
  end if;

  if (select count(*) from public.pet_type_stat_weights
      where health_weight + strength_weight + defense_weight + speed_weight
        + intelligence_weight + agility_weight + stamina_weight
        + critical_rate_weight + resistance_weight + exploration_weight
        + happiness_weight <> 40) > 0 then
    raise exception 'pet_type_stat_weights sum validation failed';
  end if;

  if (select health_weight from public.pet_type_stat_weights where pet_type = 'monkey') <> 4 then
    raise exception 'monkey health_weight expected 4';
  end if;

  if (select health_weight from public.pet_type_stat_weights where pet_type = 'griffin') <> 4 then
    raise exception 'griffin health_weight expected 4';
  end if;
end;
$$;

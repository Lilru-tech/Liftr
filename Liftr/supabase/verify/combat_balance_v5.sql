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

  if (select strength_weight from public.pet_type_stat_weights where pet_type = 'neon_panther') <> 4 then
    raise exception 'neon_panther strength_weight expected 4';
  end if;

  if (select exploration_weight from public.pet_type_stat_weights where pet_type = 'neon_panther') <> 4 then
    raise exception 'neon_panther exploration_weight expected 4';
  end if;

  if (select speed_weight from public.pet_type_stat_weights where pet_type = 'griffin') <> 5 then
    raise exception 'griffin speed_weight expected 5';
  end if;

  if (select agility_weight from public.pet_type_stat_weights where pet_type = 'griffin') <> 4 then
    raise exception 'griffin agility_weight expected 4';
  end if;

  if (select intelligence_weight from public.pet_type_stat_weights where pet_type = 'griffin') <> 2 then
    raise exception 'griffin intelligence_weight expected 2';
  end if;

  if (select exploration_weight from public.pet_type_stat_weights where pet_type = 'griffin') <> 3 then
    raise exception 'griffin exploration_weight expected 3';
  end if;

  if (select health_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon health_weight expected 4';
  end if;

  if (select strength_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon strength_weight expected 4';
  end if;

  if (select defense_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 6 then
    raise exception 'dragon defense_weight expected 6';
  end if;

  if (select happiness_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon happiness_weight expected 4';
  end if;

  if (select exploration_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon exploration_weight expected 4';
  end if;

  if (select resistance_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon resistance_weight expected 4';
  end if;

  if (select critical_rate_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 1 then
    raise exception 'dragon critical_rate_weight expected 1';
  end if;

  if (select intelligence_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon intelligence_weight expected 4';
  end if;

  if (select count(*) from public.pet_type_stat_weights
      where health_weight + strength_weight + defense_weight + speed_weight
        + intelligence_weight + agility_weight + stamina_weight
        + critical_rate_weight + resistance_weight + exploration_weight
        + happiness_weight <> 40) > 0 then
    raise exception 'pet_type_stat_weights sum validation failed';
  end if;
end;
$$;

begin;

update public.pet_type_stat_weights
set
  strength_weight = 4,
  exploration_weight = 4
where pet_type = 'neon_panther';

update public.pet_type_stat_weights
set
  speed_weight = 5,
  intelligence_weight = 2,
  agility_weight = 4,
  exploration_weight = 3
where pet_type = 'griffin';

update public.pet_type_stat_weights
set
  health_weight = 4,
  strength_weight = 4,
  defense_weight = 6,
  speed_weight = 3,
  intelligence_weight = 4,
  agility_weight = 2,
  stamina_weight = 4,
  critical_rate_weight = 1,
  resistance_weight = 4,
  exploration_weight = 4,
  happiness_weight = 4
where pet_type = 'dragon';

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
    raise exception 'pet_type_stat_weights combat balance v5 validation failed: % invalid rows', v_bad_count;
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

  if (select health_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon health_weight expected 4';
  end if;

  if (select strength_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 4 then
    raise exception 'dragon strength_weight expected 4';
  end if;

  if (select defense_weight from public.pet_type_stat_weights where pet_type = 'dragon') <> 6 then
    raise exception 'dragon defense_weight expected 6';
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
end;
$$;

commit;

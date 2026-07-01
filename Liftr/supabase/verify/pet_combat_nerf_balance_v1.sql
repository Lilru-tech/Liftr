do $$
declare
  v_nerf record;
  v_weaker_power numeric;
  v_nerfed_power numeric;
  v_hp integer;
begin
  if to_regprocedure('public.liftr_combat_effective_power_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer)') is null then
    raise exception 'missing function liftr_combat_effective_power_v1';
  end if;

  if public.liftr_combat_handicap_pool_multiplier_v1() <> 1.05 then
    raise exception 'handicap pool multiplier expected 1.05 got %', public.liftr_combat_handicap_pool_multiplier_v1();
  end if;

  v_hp := public.liftr_combat_arena_max_hp_v1(272, true);
  if v_hp <> 272 then
    raise exception 'arena max hp expected symmetric raw 272 got %', v_hp;
  end if;

  v_weaker_power := public.liftr_combat_effective_power_v1(
    90, 90, 90, 90, 90, 90, 90, 90, 90, 90
  );

  select * into v_nerf from public.liftr_combat_nerf_stats_to_target_v1(
    90, 90, 90, 90, 90, 90, 90, 90, 90, 90,
    120, 120, 120, 120, 120, 120, 120, 120, 120, 120
  );

  v_nerfed_power := public.liftr_combat_effective_power_v1(
    v_nerf.health, v_nerf.strength, v_nerf.defense, v_nerf.speed,
    v_nerf.agility, v_nerf.stamina, v_nerf.resistance,
    v_nerf.critical_rate, v_nerf.intelligence, v_nerf.exploration
  );

  if abs(v_nerfed_power - v_weaker_power * 1.05) / greatest(v_weaker_power * 1.05, 1) > 0.02 then
    raise exception 'nerfed effective power expected ~% got %', v_weaker_power * 1.05, v_nerfed_power;
  end if;

  raise notice 'pet_combat_nerf_balance_v1 verify passed';
end;
$$;

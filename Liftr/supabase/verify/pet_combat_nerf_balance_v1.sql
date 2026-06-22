do $$
declare
  v_nerf record;
  v_nerfed_pool integer;
  v_hp integer;
begin
  if to_regprocedure('public.liftr_combat_handicap_pool_multiplier_v1()') is null then
    raise exception 'missing function liftr_combat_handicap_pool_multiplier_v1';
  end if;

  if public.liftr_combat_handicap_pool_multiplier_v1() <> 1.07 then
    raise exception 'handicap pool multiplier expected 1.07 got %', public.liftr_combat_handicap_pool_multiplier_v1();
  end if;

  v_hp := public.liftr_combat_arena_max_hp_v1(272, true);
  if v_hp <> 272 then
    raise exception 'arena max hp expected symmetric raw 272 got %', v_hp;
  end if;

  v_hp := public.liftr_combat_arena_max_hp_v1(272, false);
  if v_hp <> 272 then
    raise exception 'arena max hp expected symmetric raw 272 got %', v_hp;
  end if;

  select * into v_nerf from public.liftr_combat_nerf_stats_to_target_v1(
    900,
    120, 120, 120, 120, 120, 120, 120, 120, 120, 120
  );

  v_nerfed_pool := public.liftr_combat_stat_pool_v1(
    v_nerf.health, v_nerf.strength, v_nerf.defense, v_nerf.speed,
    v_nerf.agility, v_nerf.stamina, v_nerf.resistance,
    v_nerf.critical_rate, v_nerf.intelligence, v_nerf.exploration
  );

  if v_nerfed_pool <> floor(900 * 1.07)::integer then
    raise exception 'nerfed pool expected % got %', floor(900 * 1.07)::integer, v_nerfed_pool;
  end if;

  raise notice 'pet_combat_nerf_balance_v1 verify passed';
end;
$$;

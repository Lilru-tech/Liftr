do $$
declare
  v_pool_a integer;
  v_pool_b integer;
  v_comparison_pool integer;
  v_nerf record;
  v_nerfed_pool integer;
  v_balancing jsonb;
  v_premium jsonb;
  v_minimum jsonb;
begin
  if to_regprocedure('public.liftr_combat_stat_pool_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer)') is null then
    raise exception 'missing function liftr_combat_stat_pool_v1';
  end if;

  if to_regprocedure('public.liftr_combat_comparison_pool_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer)') is null then
    raise exception 'missing function liftr_combat_comparison_pool_v1';
  end if;

  if to_regprocedure('public.liftr_combat_is_stat_unbalanced_v1(integer, integer)') is null then
    raise exception 'missing function liftr_combat_is_stat_unbalanced_v1';
  end if;

  if to_regprocedure('public.liftr_combat_nerf_stats_to_target_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer)') is null then
    raise exception 'missing function liftr_combat_nerf_stats_to_target_v1';
  end if;

  if to_regprocedure('public.liftr_combat_handicap_minimum_rewards()') is null then
    raise exception 'missing function liftr_combat_handicap_minimum_rewards';
  end if;

  if to_regprocedure('public.liftr_combat_premium_rewards(integer, integer)') is null then
    raise exception 'missing function liftr_combat_premium_rewards';
  end if;

  if public.liftr_combat_handicap_health_weight_v1() <> 0.25 then
    raise exception 'handicap health weight expected 0.25 got %', public.liftr_combat_handicap_health_weight_v1();
  end if;

  if public.liftr_combat_handicap_threshold_pct_v1() <> 125 then
    raise exception 'handicap threshold pct expected 125 got %', public.liftr_combat_handicap_threshold_pct_v1();
  end if;

  v_pool_a := public.liftr_combat_stat_pool_v1(100, 50, 40, 30, 20, 10, 15, 5, 25, 10);
  v_pool_b := public.liftr_combat_stat_pool_v1(100, 50, 40, 30, 20, 10, 15, 5, 25, 10);

  if v_pool_a <> 305 then
    raise exception 'liftr_combat_stat_pool_v1 sum expected 305 got %', v_pool_a;
  end if;

  v_comparison_pool := public.liftr_combat_comparison_pool_v1(
    1000, 100, 100, 100, 100, 100, 100, 100, 100, 100
  );
  if v_comparison_pool <> 1150 then
    raise exception 'comparison pool expected 1150 got %', v_comparison_pool;
  end if;

  if public.liftr_combat_is_stat_unbalanced_v1(v_pool_a, v_pool_b) then
    raise exception 'equal pools should not be unbalanced';
  end if;

  if not public.liftr_combat_is_stat_unbalanced_v1(1200, 900) then
    raise exception '1200 vs 900 should be unbalanced';
  end if;

  if public.liftr_combat_is_stat_unbalanced_v1(1250, 1000) then
    raise exception '1250 vs 1000 should be balanced (exactly 25%%)';
  end if;

  if not public.liftr_combat_is_stat_unbalanced_v1(1251, 1000) then
    raise exception '1251 vs 1000 should be unbalanced';
  end if;

  if public.liftr_combat_is_stat_unbalanced_v1(1050, 1000) then
    raise exception '1050 vs 1000 should be balanced under 25%% threshold';
  end if;

  if public.liftr_combat_is_stat_unbalanced_v1(
    public.liftr_combat_comparison_pool_v1(1000, 100, 100, 100, 100, 100, 100, 100, 100, 100),
    public.liftr_combat_comparison_pool_v1(800, 100, 100, 100, 100, 100, 100, 100, 100, 100)
  ) then
    raise exception 'HP-only gap should be balanced when other stats are equal';
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

  v_balancing := public.liftr_combat_stat_balancing_json(
    120, 120, 120, 120, 120, 120, 120, 120, 120, 120,
    90, 90, 90, 90, 90, 90, 90, 90, 90, 90
  );

  if coalesce((v_balancing->>'is_unbalanced')::boolean, false) is not true then
    raise exception 'stat_balancing_json should report unbalanced for comparison gap';
  end if;

  if v_balancing->>'stronger_side' <> 'attacker' then
    raise exception 'stronger_side expected attacker got %', v_balancing->>'stronger_side';
  end if;

  v_minimum := public.liftr_combat_handicap_minimum_rewards();
  if (v_minimum->>'xp')::integer <> 10 or (v_minimum->>'coins')::integer <> 5 then
    raise exception 'handicap minimum rewards expected xp:10 coins:5 got %', v_minimum;
  end if;

  v_premium := public.liftr_combat_premium_rewards(5, 20);
  if (v_premium->>'xp')::integer <> greatest(10, 30 + floor(12.5 * 8)::integer) then
    raise exception 'premium rewards xp mismatch got %', v_premium->>'xp';
  end if;

  if (v_premium->>'coins')::integer <> greatest(5, 15 + floor(12.5 * 4)::integer) then
    raise exception 'premium rewards coins mismatch got %', v_premium->>'coins';
  end if;
end;
$$;

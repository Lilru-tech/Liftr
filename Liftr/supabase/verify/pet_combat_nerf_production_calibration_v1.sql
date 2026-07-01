do $$
begin
  if public.liftr_combat_handicap_threshold_pct_v1() <> 125 then
    raise exception 'threshold expected 125 got %', public.liftr_combat_handicap_threshold_pct_v1();
  end if;

  if public.liftr_combat_handicap_health_weight_v1() <> 0.25 then
    raise exception 'health weight expected 0.25 got %', public.liftr_combat_handicap_health_weight_v1();
  end if;

  if public.liftr_combat_handicap_pool_multiplier_v1() <> 1.05 then
    raise exception 'multiplier expected 1.05 got %', public.liftr_combat_handicap_pool_multiplier_v1();
  end if;

  if to_regprocedure('public.liftr_combat_effective_power_v1(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer)') is null then
    raise exception 'missing liftr_combat_effective_power_v1';
  end if;

  if (
    select count(*)
    from pg_proc
    where proname = 'execute_pet_combat_v1'
      and pronamespace = 'public'::regnamespace
  ) <> 1 then
    raise exception 'execute_pet_combat_v1 must have exactly one overload';
  end if;

  raise notice 'pet_combat_nerf_production_calibration_v1 verify passed';
end;
$$;

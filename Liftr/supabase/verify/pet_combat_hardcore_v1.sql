do $$
declare
  v_hardcore jsonb;
  v_balancing jsonb;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'pet_combat_history'
      and column_name = 'is_handicapped'
  ) then
    raise exception 'missing column pet_combat_history.is_handicapped';
  end if;

  if to_regprocedure('public.liftr_combat_hardcore_rewards(integer, integer, integer, integer)') is null then
    raise exception 'missing function liftr_combat_hardcore_rewards';
  end if;

  if to_regprocedure('public.execute_pet_combat_v1(uuid, boolean)') is null then
    raise exception 'missing function execute_pet_combat_v1(uuid, boolean)';
  end if;

  v_hardcore := public.liftr_combat_hardcore_rewards(10, 10, 1200, 900);
  if (v_hardcore->>'xp')::integer <> greatest(10, floor(110 * (1200.0 / 900.0))::integer) then
    raise exception 'hardcore rewards xp mismatch got %', v_hardcore->>'xp';
  end if;

  if (v_hardcore->>'coins')::integer <> greatest(5, floor(55 * (1200.0 / 900.0))::integer) then
    raise exception 'hardcore rewards coins mismatch got %', v_hardcore->>'coins';
  end if;

  v_balancing := public.liftr_combat_stat_balancing_json(
    90, 90, 90, 90, 90, 90, 90, 90, 90, 90,
    120, 120, 120, 120, 120, 120, 120, 120, 120, 120
  );

  if coalesce((v_balancing->>'hardcore_bonus_percent')::integer, -1) <> 33 then
    raise exception 'hardcore_bonus_percent expected 33 got %', v_balancing->>'hardcore_bonus_percent';
  end if;

  if coalesce((v_balancing->>'is_unbalanced')::boolean, false) is not true then
    raise exception 'expected unbalanced stat balancing preview';
  end if;
end;
$$;

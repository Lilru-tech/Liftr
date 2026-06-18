do $$
declare
  v_full integer;
  v_nerfed integer;
begin
  if to_regprocedure('public.liftr_combat_arena_max_hp_v1(integer, boolean)') is null then
    raise exception 'missing function liftr_combat_arena_max_hp_v1';
  end if;

  v_full := public.liftr_combat_arena_max_hp_v1(272, false);
  if v_full <> 272 then
    raise exception 'full hp without nerf expected 272 got %', v_full;
  end if;

  v_nerfed := public.liftr_combat_arena_max_hp_v1(272, true);
  if v_nerfed <> public.liftr_combat_battle_hp_v1(272) then
    raise exception 'nerfed side hp expected % got %', public.liftr_combat_battle_hp_v1(272), v_nerfed;
  end if;

  raise notice 'pet_combat_full_hp_without_nerf_v1 verify passed';
end;
$$;

do $$
declare
  v_hp integer;
begin
  if to_regprocedure('public.liftr_combat_arena_max_hp_v1(integer, boolean)') is null then
    raise exception 'missing function liftr_combat_arena_max_hp_v1';
  end if;

  v_hp := public.liftr_combat_arena_max_hp_v1(272, false);
  if v_hp <> 272 then
    raise exception 'arena max hp expected symmetric raw 272 got %', v_hp;
  end if;

  v_hp := public.liftr_combat_arena_max_hp_v1(272, true);
  if v_hp <> 272 then
    raise exception 'arena max hp expected symmetric raw 272 got %', v_hp;
  end if;

  raise notice 'pet_combat_full_hp_without_nerf_v1 verify passed';
end;
$$;

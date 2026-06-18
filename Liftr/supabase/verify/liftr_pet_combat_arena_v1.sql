begin;

do $$
begin
  if to_regclass('public.pet_combat_history') is null then
    raise exception 'missing table pet_combat_history';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'current_energy'
  ) then
    raise exception 'missing column profiles.current_energy';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'max_energy'
  ) then
    raise exception 'missing column profiles.max_energy';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'last_energy_refresh'
  ) then
    raise exception 'missing column profiles.last_energy_refresh';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_notification_settings'
      and column_name = 'push_pet_combat_challenged'
  ) then
    raise exception 'missing column user_notification_settings.push_pet_combat_challenged';
  end if;

  if to_regprocedure('public.liftr_refresh_profile_energy(uuid)') is null then
    raise exception 'missing function liftr_refresh_profile_energy';
  end if;

  if to_regprocedure('public.upgrade_pet_energy_capacity_v1()') is null then
    raise exception 'missing rpc upgrade_pet_energy_capacity_v1';
  end if;

  if to_regprocedure('public.get_pet_combat_preview_v1(uuid)') is null then
    raise exception 'missing rpc get_pet_combat_preview_v1';
  end if;

  if to_regprocedure('public.execute_pet_combat_v1(uuid, boolean)') is null then
    raise exception 'missing rpc execute_pet_combat_v1';
  end if;

  if public.get_pet_energy_capacity_upgrade_cost(5) != 5000 then
    raise exception 'energy upgrade cost at max 5 expected 5000';
  end if;

  if public.get_pet_energy_capacity_upgrade_cost(6) != 10000 then
    raise exception 'energy upgrade cost at max 6 expected 10000';
  end if;

  if not exists (
    select 1 from public.pet_market_items
    where item_type = 'pet_energy_capacity' and is_active
  ) then
    raise exception 'missing active pet_energy_capacity market item';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'pet_combat_history'
      and policyname = 'pet_combat_history_select_own'
  ) then
    raise exception 'missing RLS policy pet_combat_history_select_own';
  end if;

  raise notice 'liftr_pet_combat_arena_v1 verify passed';
end;
$$;

rollback;

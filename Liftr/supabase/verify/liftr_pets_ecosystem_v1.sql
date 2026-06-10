begin;

do $$
declare
  v_missing text;
begin
  select string_agg(name, ', ')
  into v_missing
  from (
    values
      ('pet_types'),
      ('pet_instances'),
      ('pet_instance_stats'),
      ('user_inventory'),
      ('pet_market_items'),
      ('pet_food_experience'),
      ('pet_levels')
  ) as t(name)
  where to_regclass('public.' || t.name) is null;

  if v_missing is not null then
    raise exception 'missing tables: %', v_missing;
  end if;

  if to_regprocedure('public.get_my_pet_v1()') is null then
    raise exception 'missing rpc get_my_pet_v1';
  end if;

  if to_regprocedure('public.buy_pet_market_item_v1(text,integer)') is null then
    raise exception 'missing rpc buy_pet_market_item_v1';
  end if;

  if to_regprocedure('public.liftr_finalize_pet_hatch(uuid)') is null then
    raise exception 'missing rpc liftr_finalize_pet_hatch';
  end if;

  if to_regprocedure('public.generate_pet_coins_v1(uuid)') is null then
    raise exception 'missing rpc generate_pet_coins_v1';
  end if;

  if to_regprocedure('public.generate_all_pet_coins_v1()') is null then
    raise exception 'missing rpc generate_all_pet_coins_v1';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_notification_settings'
      and column_name = 'push_pet_hatched'
  ) then
    raise exception 'missing column user_notification_settings.push_pet_hatched';
  end if;

  if (select count(*) from public.pet_types) < 60 then
    raise exception 'expected at least 60 pet types seeded';
  end if;

  if (select count(*) from public.pet_market_items where is_active) < 9 then
    raise exception 'expected at least 9 active pet market items';
  end if;

  if to_regprocedure('public.upgrade_pet_rarity_v1()') is null then
    raise exception 'missing rpc upgrade_pet_rarity_v1';
  end if;

  if to_regprocedure('public.upgrade_pet_energy_capacity_v1()') is null then
    raise exception 'missing rpc upgrade_pet_energy_capacity_v1';
  end if;

  if to_regprocedure('public.get_pet_combat_preview_v1(uuid)') is null then
    raise exception 'missing rpc get_pet_combat_preview_v1';
  end if;

  if to_regprocedure('public.execute_pet_combat_v1(uuid)') is null then
    raise exception 'missing rpc execute_pet_combat_v1';
  end if;

  if to_regclass('public.pet_combat_history') is null then
    raise exception 'missing table pet_combat_history';
  end if;

  if to_regprocedure('public.get_pet_rarity_upgrade_cost(public.pet_rarity)') is null then
    raise exception 'missing function get_pet_rarity_upgrade_cost';
  end if;

  if public.get_pet_rarity_upgrade_cost('common'::public.pet_rarity) != 1000 then
    raise exception 'common upgrade cost expected 1000';
  end if;

  if public.get_pet_rarity_upgrade_cost('uncommon'::public.pet_rarity) != 2000 then
    raise exception 'uncommon upgrade cost expected 2000';
  end if;

  if public.get_pet_rarity_upgrade_cost('legendary'::public.pet_rarity) != 16000 then
    raise exception 'legendary upgrade cost expected 16000';
  end if;

  if public.get_next_pet_rarity('common'::public.pet_rarity)::text != 'uncommon' then
    raise exception 'next rarity from common expected uncommon';
  end if;

  if public.get_next_pet_rarity('mythic'::public.pet_rarity) is not null then
    raise exception 'mythic should have no next rarity';
  end if;

  raise notice 'liftr_pets_ecosystem_v1 verify passed';
end;
$$;

rollback;

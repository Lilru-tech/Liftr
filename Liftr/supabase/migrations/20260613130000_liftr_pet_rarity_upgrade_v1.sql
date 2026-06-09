begin;

create or replace function public.get_next_pet_rarity(p_current public.pet_rarity)
returns public.pet_rarity
language sql
stable
set search_path to public
as $$
  select c.rarity
  from public.pet_rarity_config c
  where c.sort_order = (
    select curr.sort_order + 1
    from public.pet_rarity_config curr
    where curr.rarity = p_current
  )
  limit 1;
$$;

create or replace function public.get_pet_rarity_upgrade_cost(p_current public.pet_rarity)
returns integer
language sql
stable
set search_path to public
as $$
  select (1000 * power(2, c.sort_order - 1))::integer
  from public.pet_rarity_config c
  where c.rarity = p_current;
$$;

create or replace function public.upgrade_pet_rarity_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance_id uuid;
  v_current_rarity public.pet_rarity;
  v_next_rarity public.pet_rarity;
  v_cost integer;
  v_purchase_id uuid := gen_random_uuid();
  v_curr_stat_mult numeric;
  v_curr_coin_mult numeric;
  v_next_stat_mult numeric;
  v_next_coin_mult numeric;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  v_instance_id := public.liftr_pet_active_instance_id(v_user_id);

  select pi.rarity
  into v_current_rarity
  from public.pet_instances pi
  where pi.id = v_instance_id
  for update;

  if v_current_rarity is null then
    raise exception 'no_active_pet';
  end if;

  v_next_rarity := public.get_next_pet_rarity(v_current_rarity);

  if v_next_rarity is null then
    raise exception 'max_rarity_reached';
  end if;

  v_cost := public.get_pet_rarity_upgrade_cost(v_current_rarity);

  if not public.apply_liftr_coin_transaction(
    v_user_id,
    -v_cost,
    'pet_rarity_upgrade',
    v_purchase_id
  ) then
    raise exception 'insufficient_coins';
  end if;

  update public.pet_instances
  set rarity = v_next_rarity,
      updated_at = now()
  where id = v_instance_id;

  select stat_multiplier, coin_multiplier
  into v_curr_stat_mult, v_curr_coin_mult
  from public.pet_rarity_config
  where rarity = v_current_rarity;

  select stat_multiplier, coin_multiplier
  into v_next_stat_mult, v_next_coin_mult
  from public.pet_rarity_config
  where rarity = v_next_rarity;

  insert into public.pet_logs (
    user_id,
    pet_instance_id,
    event_type,
    details,
    created_at
  )
  values (
    v_user_id,
    v_instance_id,
    'rarity_upgrade',
    jsonb_build_object(
      'from_rarity', v_current_rarity::text,
      'to_rarity', v_next_rarity::text,
      'cost', v_cost
    ),
    now()
  );

  return jsonb_build_object(
    'pet_instance_id', v_instance_id,
    'from_rarity', v_current_rarity::text,
    'to_rarity', v_next_rarity::text,
    'cost', v_cost,
    'from_stat_multiplier', v_curr_stat_mult,
    'to_stat_multiplier', v_next_stat_mult,
    'from_coin_multiplier', v_curr_coin_mult,
    'to_coin_multiplier', v_next_coin_mult,
    'purchase_id', v_purchase_id
  );
end;
$$;

insert into public.pet_market_items (
  item_type, display_name, description, price, category, image_path, is_active
)
values (
  'pet_rarity_upgrade',
  'Upgrade Rarity',
  'Raise your pet to the next rarity tier. Future level-ups and passive coin income scale with the new multiplier.',
  1000,
  'pet_upgrades',
  'market/rarity_upgrade.png',
  true
)
on conflict (item_type) do update set
  display_name = excluded.display_name,
  description = excluded.description,
  price = excluded.price,
  category = excluded.category,
  image_path = excluded.image_path,
  is_active = excluded.is_active;

create or replace function public.buy_pet_market_item_v1(
  p_item_type text,
  p_quantity integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_item record;
  v_total integer;
  v_purchase_id uuid := gen_random_uuid();
  v_has_active_pet boolean;
  v_owns_egg boolean;
  v_owns_incubator boolean;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity';
  end if;

  if p_item_type = 'pet_rarity_upgrade' then
    raise exception 'use_upgrade_pet_rarity_rpc';
  end if;

  select * into v_item
  from public.pet_market_items
  where item_type = p_item_type
    and is_active = true;

  if v_item is null then
    raise exception 'item_not_found';
  end if;

  select exists (
    select 1 from public.pet_instances
    where user_id = v_user_id and is_active = true
  ) into v_has_active_pet;

  select coalesce(quantity, 0) > 0 into v_owns_egg
  from public.user_inventory
  where user_id = v_user_id and item_type = 'pet_egg';

  select coalesce(quantity, 0) > 0 into v_owns_incubator
  from public.user_inventory
  where user_id = v_user_id and item_type = 'incubator';

  if p_item_type = 'pet_egg' then
    if v_has_active_pet then
      raise exception 'already_has_pet';
    end if;
    if coalesce(v_owns_egg, false) then
      raise exception 'already_owns_egg';
    end if;
    if p_quantity != 1 then
      raise exception 'invalid_quantity';
    end if;
  end if;

  if p_item_type = 'incubator' then
    if v_has_active_pet then
      raise exception 'already_has_pet';
    end if;
    if coalesce(v_owns_incubator, false) then
      raise exception 'already_owns_incubator';
    end if;
    if p_quantity != 1 then
      raise exception 'invalid_quantity';
    end if;
  end if;

  v_total := v_item.price * p_quantity;

  if not public.apply_liftr_coin_transaction(
    v_user_id,
    -v_total,
    'pet_market_purchase',
    v_purchase_id
  ) then
    raise exception 'insufficient_coins';
  end if;

  perform public.liftr_inventory_add(v_user_id, p_item_type, p_quantity);

  return jsonb_build_object(
    'item_type', p_item_type,
    'quantity', p_quantity,
    'total_spent', v_total,
    'purchase_id', v_purchase_id
  );
end;
$$;

revoke all on function public.get_next_pet_rarity(public.pet_rarity) from public;
revoke all on function public.get_pet_rarity_upgrade_cost(public.pet_rarity) from public;
revoke all on function public.upgrade_pet_rarity_v1() from public;

grant execute on function public.upgrade_pet_rarity_v1() to authenticated;

commit;

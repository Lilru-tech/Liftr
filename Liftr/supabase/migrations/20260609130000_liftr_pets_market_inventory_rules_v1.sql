begin;

update public.pet_market_items
set price = 5000
where item_type in ('pet_egg', 'incubator');

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

commit;

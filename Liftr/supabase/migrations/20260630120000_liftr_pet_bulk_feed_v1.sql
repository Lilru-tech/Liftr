drop function if exists public.feed_pet_v1(text);

create or replace function public.feed_pet_v1(
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
  v_instance_id uuid;
  v_stage text;
  v_min_exp integer;
  v_max_exp integer;
  v_gained_exp integer;
  v_total_exp integer := 0;
  v_display_name text;
  v_i integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_quantity is null or p_quantity < 1 then
    raise exception 'invalid_quantity';
  end if;

  v_instance_id := public.liftr_pet_active_instance_id(v_user_id);
  if v_instance_id is null then
    raise exception 'no_active_pet';
  end if;

  select evolution_stage into v_stage
  from public.pet_instances
  where id = v_instance_id
  for update;

  if v_stage is null or lower(v_stage) = 'egg' then
    raise exception 'pet_not_hatched';
  end if;

  if not public.liftr_inventory_consume(v_user_id, p_item_type, p_quantity) then
    raise exception 'no_food_item';
  end if;

  select pfe.min_exp, pfe.max_exp
  into v_min_exp, v_max_exp
  from public.pet_food_experience pfe
  where pfe.item_type = p_item_type
    and lower(pfe.pet_stage) = lower(v_stage);

  if v_min_exp is null or v_max_exp is null then
    raise exception 'no_exp_config';
  end if;

  select pmi.display_name
  into v_display_name
  from public.pet_market_items pmi
  where pmi.item_type = p_item_type;

  for v_i in 1..p_quantity loop
    v_gained_exp := floor(random() * (v_max_exp - v_min_exp + 1))::integer + v_min_exp;
    v_total_exp := v_total_exp + v_gained_exp;

    update public.pet_instances
    set current_xp = current_xp + v_gained_exp,
        total_feedings = total_feedings + 1,
        updated_at = now()
    where id = v_instance_id;

    perform public.check_pet_level_up(v_instance_id);
  end loop;

  insert into public.pet_logs (user_id, pet_instance_id, event_type, item_type, exp_gained, details)
  values (
    v_user_id,
    v_instance_id,
    'fed',
    p_item_type,
    v_total_exp,
    jsonb_build_object(
      'pet_stage', v_stage,
      'quantity', p_quantity,
      'display_name', coalesce(v_display_name, p_item_type),
      'bulk', p_quantity > 1
    )
  );

  return jsonb_build_object('exp_gained', v_total_exp, 'quantity', p_quantity);
end;
$$;

revoke all on function public.feed_pet_v1(text, integer) from public;
grant execute on function public.feed_pet_v1(text, integer) to authenticated;

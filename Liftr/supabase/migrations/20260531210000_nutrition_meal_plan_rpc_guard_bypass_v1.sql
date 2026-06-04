set local check_function_bodies = off;

create or replace function public.nutrition_meal_plan_targets_guard_columns()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_creator_id uuid;
begin
  if coalesce(current_setting('liftr.meal_plan_target_rpc', true), '') = '1' then
    return new;
  end if;

  select p.creator_id
    into v_creator_id
  from public.nutrition_meal_plans p
  where p.id = old.plan_id;

  if (select auth.uid()) = old.target_user_id then
    if new.plan_id is distinct from old.plan_id
      or new.target_user_id is distinct from old.target_user_id
      or new.quantity_g is distinct from old.quantity_g
      or new.ingredient_id is distinct from old.ingredient_id
      or new.recipe_id is distinct from old.recipe_id
      or new.created_at is distinct from old.created_at
    then
      raise exception 'INVITEE_MAY_ONLY_UPDATE_STATUS' using errcode = '42501';
    end if;
    return new;
  end if;

  if (select auth.uid()) = v_creator_id then
    raise exception 'CREATOR_CANNOT_UPDATE_TARGET' using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.accept_meal_plan(p_target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.nutrition_meal_plan_targets%rowtype;
begin
  perform set_config('liftr.meal_plan_target_rpc', '1', true);

  if v_me is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '28000';
  end if;

  select *
    into v_row
  from public.nutrition_meal_plan_targets t
  where t.id = p_target_id
  for update;

  if not found then
    raise exception 'TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_row.target_user_id <> v_me then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'INVALID_STATUS' using errcode = '22023';
  end if;

  update public.nutrition_meal_plan_targets
  set
    status = 'accepted',
    accepted_at = now(),
    updated_at = now()
  where id = p_target_id;
end;
$$;

create or replace function public.reject_meal_plan(p_target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.nutrition_meal_plan_targets%rowtype;
begin
  perform set_config('liftr.meal_plan_target_rpc', '1', true);

  if v_me is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '28000';
  end if;

  select *
    into v_row
  from public.nutrition_meal_plan_targets t
  where t.id = p_target_id
  for update;

  if not found then
    raise exception 'TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_row.target_user_id <> v_me then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_row.status not in ('pending', 'accepted') then
    raise exception 'INVALID_STATUS' using errcode = '22023';
  end if;

  update public.nutrition_meal_plan_targets
  set
    status = 'rejected',
    accepted_at = null,
    updated_at = now()
  where id = p_target_id;
end;
$$;

create or replace function public.update_meal_plan_target(
  p_target_id uuid,
  p_quantity_g numeric,
  p_meal_slot text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_row public.nutrition_meal_plan_targets%rowtype;
begin
  perform set_config('liftr.meal_plan_target_rpc', '1', true);

  if v_me is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '28000';
  end if;

  if p_quantity_g is null or p_quantity_g <= 0 then
    raise exception 'INVALID_QUANTITY' using errcode = '22023';
  end if;

  select *
    into v_row
  from public.nutrition_meal_plan_targets t
  where t.id = p_target_id
  for update;

  if not found then
    raise exception 'TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_row.target_user_id <> v_me then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_row.status not in ('pending', 'accepted') then
    raise exception 'INVALID_STATUS' using errcode = '22023';
  end if;

  update public.nutrition_meal_plan_targets
  set
    quantity_g = p_quantity_g,
    updated_at = now()
  where id = p_target_id;

  if p_meal_slot is not null then
    update public.nutrition_meal_plans p
    set meal_slot = p_meal_slot
    where p.id = v_row.plan_id
      and exists (
        select 1
        from public.nutrition_meal_plan_targets t
        where t.plan_id = p.id
          and t.target_user_id = v_me
      );
  end if;
end;
$$;

create or replace function public.complete_meal_plan_as_eaten(p_target_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_target public.nutrition_meal_plan_targets%rowtype;
  v_plan public.nutrition_meal_plans%rowtype;
  v_log_id uuid := gen_random_uuid();
  v_ingredient_id uuid;
  v_recipe_id uuid;
begin
  perform set_config('liftr.meal_plan_target_rpc', '1', true);

  if v_me is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '28000';
  end if;

  select *
    into v_target
  from public.nutrition_meal_plan_targets t
  where t.id = p_target_id
  for update;

  if not found then
    raise exception 'TARGET_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_target.target_user_id <> v_me then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_target.status = 'eaten' then
    raise exception 'ALREADY_EATEN' using errcode = '22023';
  end if;

  if v_target.status <> 'accepted' then
    raise exception 'INVALID_STATUS' using errcode = '22023';
  end if;

  select *
    into v_plan
  from public.nutrition_meal_plans p
  where p.id = v_target.plan_id;

  if not found then
    raise exception 'PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_ingredient_id := coalesce(v_target.ingredient_id, v_plan.ingredient_id);
  v_recipe_id := coalesce(v_target.recipe_id, v_plan.recipe_id);

  update public.nutrition_meal_plan_targets
  set
    status = 'eaten',
    updated_at = now()
  where id = p_target_id;

  insert into public.nutrition_diary_logs (
    id,
    user_id,
    log_date,
    meal_slot,
    ingredient_id,
    recipe_id,
    quantity_g
  )
  values (
    v_log_id,
    v_target.target_user_id,
    v_plan.plan_date,
    v_plan.meal_slot,
    v_ingredient_id,
    v_recipe_id,
    v_target.quantity_g
  );

  return v_log_id;
end;
$$;

notify pgrst, 'reload schema';

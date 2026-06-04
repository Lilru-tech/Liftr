-- Per-user meal plan targets: food on target, auto-accept creator, RPC updates

set local check_function_bodies = off;

alter table public.nutrition_meal_plan_targets
  add column if not exists ingredient_id uuid references public.nutrition_ingredients (id) on delete set null,
  add column if not exists recipe_id uuid references public.nutrition_recipes (id) on delete set null;

update public.nutrition_meal_plan_targets t
set
  ingredient_id = p.ingredient_id,
  recipe_id = p.recipe_id
from public.nutrition_meal_plans p
where p.id = t.plan_id
  and t.ingredient_id is null
  and t.recipe_id is null;

alter table public.nutrition_meal_plan_targets
  drop constraint if exists nutrition_meal_plan_targets_source_xor;

alter table public.nutrition_meal_plan_targets
  add constraint nutrition_meal_plan_targets_source_xor check (
    num_nonnulls(recipe_id, ingredient_id) = 1
  );

create or replace function public.nutrition_meal_plan_targets_auto_accept_creator()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creator_id uuid;
begin
  select p.creator_id
    into v_creator_id
  from public.nutrition_meal_plans p
  where p.id = new.plan_id;

  if v_creator_id is not null and new.target_user_id = v_creator_id then
    new.status := 'accepted';
    new.accepted_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists nutrition_meal_plan_targets_auto_accept_creator on public.nutrition_meal_plan_targets;
create trigger nutrition_meal_plan_targets_auto_accept_creator
  before insert on public.nutrition_meal_plan_targets
  for each row
  execute function public.nutrition_meal_plan_targets_auto_accept_creator();

create or replace function public.nutrition_meal_plan_targets_guard_columns()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_creator_id uuid;
begin
  select p.creator_id
    into v_creator_id
  from public.nutrition_meal_plans p
  where p.id = old.plan_id;

  if (select auth.uid()) = old.target_user_id then
    if new.plan_id is distinct from old.plan_id
      or new.target_user_id is distinct from old.target_user_id
      or new.ingredient_id is distinct from old.ingredient_id
      or new.recipe_id is distinct from old.recipe_id
      or new.created_at is distinct from old.created_at
      or new.status is distinct from old.status
      or new.accepted_at is distinct from old.accepted_at
    then
      raise exception 'INVITEE_MAY_ONLY_UPDATE_QUANTITY' using errcode = '42501';
    end if;
    return new;
  end if;

  if (select auth.uid()) = v_creator_id then
    raise exception 'CREATOR_CANNOT_UPDATE_TARGET' using errcode = '42501';
  end if;

  return new;
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

create or replace function public.trg_nutrition_meal_plan_targets_after_insert_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creator_id uuid;
  v_creator_username text;
  v_plan public.nutrition_meal_plans%rowtype;
  v_food_name text;
  v_kcal numeric;
begin
  select p.*
    into v_plan
  from public.nutrition_meal_plans p
  where p.id = new.plan_id;

  if not found then
    return new;
  end if;

  v_creator_id := v_plan.creator_id;

  if new.target_user_id is distinct from v_creator_id then
    select coalesce(pr.username, 'Someone')
      into v_creator_username
    from public.profiles pr
    where pr.user_id = v_creator_id;

    if new.ingredient_id is not null then
      select i.name, (i.calories_per_100g * new.quantity_g / 100.0)
        into v_food_name, v_kcal
      from public.nutrition_ingredients i
      where i.id = new.ingredient_id;
    elsif new.recipe_id is not null then
      select r.name
        into v_food_name
      from public.nutrition_recipes r
      where r.id = new.recipe_id;
      v_kcal := null;
    elsif v_plan.ingredient_id is not null then
      select i.name, (i.calories_per_100g * new.quantity_g / 100.0)
        into v_food_name, v_kcal
      from public.nutrition_ingredients i
      where i.id = v_plan.ingredient_id;
    elsif v_plan.recipe_id is not null then
      select r.name
        into v_food_name
      from public.nutrition_recipes r
      where r.id = v_plan.recipe_id;
      v_kcal := null;
    else
      v_food_name := 'a meal';
    end if;

    insert into public.notifications (user_id, type, title, body, is_read, data)
    values (
      new.target_user_id,
      'meal_plan_invite',
      format('%s invited you to %s', coalesce(v_creator_username, 'Someone'), v_plan.meal_slot),
      format(
        '%s · %s g%s',
        coalesce(v_food_name, 'Meal'),
        trim(to_char(new.quantity_g, 'FM999990.##')),
        case when v_kcal is not null then format(' · %s kcal', round(v_kcal)) else '' end
      ),
      false,
      jsonb_build_object(
        'plan_id', new.plan_id,
        'target_id', new.id,
        'meal_slot', v_plan.meal_slot,
        'food_name', coalesce(v_food_name, 'Meal'),
        'quantity_g', new.quantity_g
      )
    );
  end if;

  return new;
end;
$$;

revoke all on function public.update_meal_plan_target(uuid, numeric, text) from public;
grant execute on function public.update_meal_plan_target(uuid, numeric, text) to authenticated;

notify pgrst, 'reload schema';

set local check_function_bodies = off;

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

notify pgrst, 'reload schema';

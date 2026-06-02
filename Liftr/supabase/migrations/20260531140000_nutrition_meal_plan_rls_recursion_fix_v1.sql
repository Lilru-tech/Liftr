-- Break RLS recursion between nutrition_meal_plans and nutrition_meal_plan_targets

set local check_function_bodies = off;

create or replace function public.user_is_nutrition_meal_plan_creator(p_plan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.nutrition_meal_plans p
    where p.id = p_plan_id
      and p.creator_id = (select auth.uid())
  );
$$;

create or replace function public.user_is_nutrition_meal_plan_target(p_plan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.nutrition_meal_plan_targets t
    where t.plan_id = p_plan_id
      and t.target_user_id = (select auth.uid())
  );
$$;

revoke all on function public.user_is_nutrition_meal_plan_creator(uuid) from public;
revoke all on function public.user_is_nutrition_meal_plan_target(uuid) from public;
grant execute on function public.user_is_nutrition_meal_plan_creator(uuid) to authenticated;
grant execute on function public.user_is_nutrition_meal_plan_target(uuid) to authenticated;

drop policy if exists nutrition_meal_plans_select_participant on public.nutrition_meal_plans;
create policy nutrition_meal_plans_select_participant
  on public.nutrition_meal_plans
  for select
  to authenticated
  using (public.user_is_nutrition_meal_plan_target(id));

drop policy if exists nutrition_meal_plan_targets_select_participant on public.nutrition_meal_plan_targets;
create policy nutrition_meal_plan_targets_select_participant
  on public.nutrition_meal_plan_targets
  for select
  to authenticated
  using (
    target_user_id = (select auth.uid())
    or public.user_is_nutrition_meal_plan_creator(plan_id)
  );

drop policy if exists nutrition_meal_plan_targets_insert_creator on public.nutrition_meal_plan_targets;
create policy nutrition_meal_plan_targets_insert_creator
  on public.nutrition_meal_plan_targets
  for insert
  to authenticated
  with check (public.user_is_nutrition_meal_plan_creator(plan_id));

drop policy if exists nutrition_meal_plan_targets_delete_creator on public.nutrition_meal_plan_targets;
create policy nutrition_meal_plan_targets_delete_creator
  on public.nutrition_meal_plan_targets
  for delete
  to authenticated
  using (public.user_is_nutrition_meal_plan_creator(plan_id));

notify pgrst, 'reload schema';

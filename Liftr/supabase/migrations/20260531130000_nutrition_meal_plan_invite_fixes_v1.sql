-- Nutrition meal plan invite fixes: participant plan read access + English notifications

set local check_function_bodies = off;

drop policy if exists nutrition_meal_plans_select_participant on public.nutrition_meal_plans;
create policy nutrition_meal_plans_select_participant
  on public.nutrition_meal_plans
  for select
  to authenticated
  using (
    creator_id = (select auth.uid())
    or exists (
      select 1
      from public.nutrition_meal_plan_targets t
      where t.plan_id = id
        and t.target_user_id = (select auth.uid())
    )
  );

create or replace function public.trg_nutrition_meal_plan_targets_after_insert_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creator_id uuid;
  v_creator_username text;
begin
  select p.creator_id
    into v_creator_id
  from public.nutrition_meal_plans p
  where p.id = new.plan_id;

  if v_creator_id is null then
    return new;
  end if;

  if new.target_user_id is distinct from v_creator_id then
    select coalesce(pr.username, 'Someone')
      into v_creator_username
    from public.profiles pr
    where pr.user_id = v_creator_id;

    insert into public.notifications (user_id, type, title, body, is_read, data)
    values (
      new.target_user_id,
      'meal_plan_invite',
      format('%s invited you to a meal', coalesce(v_creator_username, 'Someone')),
      'A meal was planned with you. Open the invitation to accept or decline.',
      false,
      jsonb_build_object(
        'plan_id', new.plan_id,
        'target_id', new.id
      )
    );
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';

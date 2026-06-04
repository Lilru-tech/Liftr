-- ============================================================================
-- Nutrition meal planning (social) v1
--
-- Decouples future meal plans from nutrition_diary_logs consumption history.
-- Invites partners via nutrition_meal_plan_targets + notifications.
--
-- Idempotent: safe to re-run.
-- ============================================================================

set local check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1) Tables
-- ---------------------------------------------------------------------------

create table if not exists public.nutrition_meal_plans (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (user_id) on delete cascade,
  plan_date date not null,
  meal_slot text not null,
  recipe_id uuid references public.nutrition_recipes (id) on delete set null,
  ingredient_id uuid references public.nutrition_ingredients (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint nutrition_meal_plans_meal_slot_check check (
    meal_slot in ('Breakfast', 'Lunch', 'Dinner', 'Snack')
  ),
  constraint nutrition_meal_plans_source_xor check (
    num_nonnulls(recipe_id, ingredient_id) = 1
  )
);

create index if not exists nutrition_meal_plans_creator_date_idx
  on public.nutrition_meal_plans (creator_id, plan_date desc);

create index if not exists nutrition_meal_plans_date_slot_idx
  on public.nutrition_meal_plans (plan_date, meal_slot);

create table if not exists public.nutrition_meal_plan_targets (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.nutrition_meal_plans (id) on delete cascade,
  target_user_id uuid not null references public.profiles (user_id) on delete cascade,
  quantity_g numeric(10, 2) not null,
  status text not null default 'pending',
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint nutrition_meal_plan_targets_quantity_positive check (quantity_g > 0),
  constraint nutrition_meal_plan_targets_status_check check (
    status in ('pending', 'accepted', 'rejected', 'eaten')
  ),
  constraint nutrition_meal_plan_targets_plan_user_uidx unique (plan_id, target_user_id)
);

create index if not exists nutrition_meal_plan_targets_plan_id_idx
  on public.nutrition_meal_plan_targets (plan_id);

create index if not exists nutrition_meal_plan_targets_user_status_idx
  on public.nutrition_meal_plan_targets (target_user_id, status);

-- ---------------------------------------------------------------------------
-- 2) updated_at + column guard triggers
-- ---------------------------------------------------------------------------

create or replace function public.touch_nutrition_meal_plan_target_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists nutrition_meal_plan_targets_set_updated_at on public.nutrition_meal_plan_targets;
create trigger nutrition_meal_plan_targets_set_updated_at
  before update on public.nutrition_meal_plan_targets
  for each row
  execute function public.touch_nutrition_meal_plan_target_updated_at();

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

drop trigger if exists nutrition_meal_plan_targets_guard_columns on public.nutrition_meal_plan_targets;
create trigger nutrition_meal_plan_targets_guard_columns
  before update on public.nutrition_meal_plan_targets
  for each row
  execute function public.nutrition_meal_plan_targets_guard_columns();

-- ---------------------------------------------------------------------------
-- 3) Notification trigger (meal_plan_invite)
-- ---------------------------------------------------------------------------

create or replace function public.trg_nutrition_meal_plan_targets_after_insert_notify()
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

  if v_creator_id is null then
    return new;
  end if;

  if new.target_user_id is distinct from v_creator_id then
    insert into public.notifications (user_id, type, title, body, is_read, data)
    values (
      new.target_user_id,
      'meal_plan_invite',
      '¡Te han invitado a una comida!',
      'Un usuario ha planificado una comida contigo. Revisa tus invitaciones pendientes para aceptarla.',
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

drop trigger if exists nutrition_meal_plan_targets_ai_notify on public.nutrition_meal_plan_targets;
create trigger nutrition_meal_plan_targets_ai_notify
  after insert on public.nutrition_meal_plan_targets
  for each row
  execute function public.trg_nutrition_meal_plan_targets_after_insert_notify();

-- ---------------------------------------------------------------------------
-- 4) RPCs
-- ---------------------------------------------------------------------------

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
    status = 'rejected',
    updated_at = now()
  where id = p_target_id;
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
    v_plan.ingredient_id,
    v_plan.recipe_id,
    v_target.quantity_g
  );

  return v_log_id;
end;
$$;

revoke all on function public.accept_meal_plan(uuid) from public;
revoke all on function public.reject_meal_plan(uuid) from public;
revoke all on function public.complete_meal_plan_as_eaten(uuid) from public;

grant execute on function public.accept_meal_plan(uuid) to authenticated;
grant execute on function public.reject_meal_plan(uuid) to authenticated;
grant execute on function public.complete_meal_plan_as_eaten(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) RLS
-- ---------------------------------------------------------------------------

alter table public.nutrition_meal_plans enable row level security;
alter table public.nutrition_meal_plan_targets enable row level security;

drop policy if exists nutrition_meal_plans_select_creator on public.nutrition_meal_plans;
create policy nutrition_meal_plans_select_creator
  on public.nutrition_meal_plans
  for select
  to authenticated
  using (creator_id = (select auth.uid()));

drop policy if exists nutrition_meal_plans_insert_creator on public.nutrition_meal_plans;
create policy nutrition_meal_plans_insert_creator
  on public.nutrition_meal_plans
  for insert
  to authenticated
  with check (creator_id = (select auth.uid()));

drop policy if exists nutrition_meal_plans_update_creator on public.nutrition_meal_plans;
create policy nutrition_meal_plans_update_creator
  on public.nutrition_meal_plans
  for update
  to authenticated
  using (creator_id = (select auth.uid()))
  with check (creator_id = (select auth.uid()));

drop policy if exists nutrition_meal_plans_delete_creator on public.nutrition_meal_plans;
create policy nutrition_meal_plans_delete_creator
  on public.nutrition_meal_plans
  for delete
  to authenticated
  using (creator_id = (select auth.uid()));

drop policy if exists nutrition_meal_plan_targets_select_participant on public.nutrition_meal_plan_targets;
create policy nutrition_meal_plan_targets_select_participant
  on public.nutrition_meal_plan_targets
  for select
  to authenticated
  using (
    target_user_id = (select auth.uid())
    or exists (
      select 1
      from public.nutrition_meal_plans p
      where p.id = plan_id
        and p.creator_id = (select auth.uid())
    )
  );

drop policy if exists nutrition_meal_plan_targets_insert_creator on public.nutrition_meal_plan_targets;
create policy nutrition_meal_plan_targets_insert_creator
  on public.nutrition_meal_plan_targets
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.nutrition_meal_plans p
      where p.id = plan_id
        and p.creator_id = (select auth.uid())
    )
  );

drop policy if exists nutrition_meal_plan_targets_update_target on public.nutrition_meal_plan_targets;
create policy nutrition_meal_plan_targets_update_target
  on public.nutrition_meal_plan_targets
  for update
  to authenticated
  using (target_user_id = (select auth.uid()))
  with check (target_user_id = (select auth.uid()));

drop policy if exists nutrition_meal_plan_targets_delete_creator on public.nutrition_meal_plan_targets;
create policy nutrition_meal_plan_targets_delete_creator
  on public.nutrition_meal_plan_targets
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.nutrition_meal_plans p
      where p.id = plan_id
        and p.creator_id = (select auth.uid())
    )
  );

notify pgrst, 'reload schema';

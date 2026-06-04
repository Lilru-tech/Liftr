-- ============================================================================
-- Nutrition privacy + chat shares v1
--
-- Goals:
--  - Privacy by default for user-owned nutrition assets
--  - Strict RLS isolation for nutrition_ingredients + nutrition_recipes
--  - Add chat message kinds: shared_ingredient, shared_recipe
--  - Add atomic clone RPCs to import shared snapshots into the receiver library
--
-- Idempotent: safe to re-run.
-- ============================================================================

set local check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1) Schema: recipes gain is_public (default false)
-- ---------------------------------------------------------------------------

alter table public.nutrition_recipes
  add column if not exists is_public boolean not null default false;

create index if not exists nutrition_recipes_public_idx
  on public.nutrition_recipes (is_public)
  where is_public = true;

update public.nutrition_recipes
   set is_public = true
 where user_id is null
   and is_public = false;

-- Ensure ingredients default remains privacy-by-default.
alter table public.nutrition_ingredients
  alter column is_public set default false;

-- ---------------------------------------------------------------------------
-- 2) RLS: enforce strict visibility + owner-only writes
-- ---------------------------------------------------------------------------

alter table public.nutrition_ingredients enable row level security;
alter table public.nutrition_recipes enable row level security;
alter table public.nutrition_recipe_ingredients enable row level security;

-- Ingredients: visible to owner, system defaults (user_id null), or explicitly public.
drop policy if exists nutrition_ingredients_select_visible on public.nutrition_ingredients;
create policy nutrition_ingredients_select_visible
  on public.nutrition_ingredients
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or user_id is null
    or is_public = true
  );

drop policy if exists nutrition_ingredients_insert_own on public.nutrition_ingredients;
create policy nutrition_ingredients_insert_own
  on public.nutrition_ingredients
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and is_public = false
  );

drop policy if exists nutrition_ingredients_update_own on public.nutrition_ingredients;
create policy nutrition_ingredients_update_own
  on public.nutrition_ingredients
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and is_public = false
  );

drop policy if exists nutrition_ingredients_delete_own on public.nutrition_ingredients;
create policy nutrition_ingredients_delete_own
  on public.nutrition_ingredients
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- Recipes: visible to owner, system defaults (user_id null), or explicitly public.
drop policy if exists nutrition_recipes_select_own on public.nutrition_recipes;
drop policy if exists nutrition_recipes_select_visible on public.nutrition_recipes;
create policy nutrition_recipes_select_visible
  on public.nutrition_recipes
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or user_id is null
    or is_public = true
  );

drop policy if exists nutrition_recipes_insert_own on public.nutrition_recipes;
create policy nutrition_recipes_insert_own
  on public.nutrition_recipes
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and is_public = false
  );

drop policy if exists nutrition_recipes_update_own on public.nutrition_recipes;
create policy nutrition_recipes_update_own
  on public.nutrition_recipes
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and is_public = false
  );

drop policy if exists nutrition_recipes_delete_own on public.nutrition_recipes;
create policy nutrition_recipes_delete_own
  on public.nutrition_recipes
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- Recipe ingredients: visible iff the parent recipe is visible under the same rule.
drop policy if exists nutrition_recipe_ingredients_select_own on public.nutrition_recipe_ingredients;
drop policy if exists nutrition_recipe_ingredients_select_visible on public.nutrition_recipe_ingredients;
create policy nutrition_recipe_ingredients_select_visible
  on public.nutrition_recipe_ingredients
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and (
          r.user_id = (select auth.uid())
          or r.user_id is null
          or r.is_public = true
        )
    )
  );

-- Writes only allowed for recipes owned by the current user.
drop policy if exists nutrition_recipe_ingredients_insert_own on public.nutrition_recipe_ingredients;
create policy nutrition_recipe_ingredients_insert_own
  on public.nutrition_recipe_ingredients
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and r.user_id = (select auth.uid())
        and r.is_public = false
    )
  );

drop policy if exists nutrition_recipe_ingredients_update_own on public.nutrition_recipe_ingredients;
create policy nutrition_recipe_ingredients_update_own
  on public.nutrition_recipe_ingredients
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and r.user_id = (select auth.uid())
        and r.is_public = false
    )
  )
  with check (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and r.user_id = (select auth.uid())
        and r.is_public = false
    )
  );

drop policy if exists nutrition_recipe_ingredients_delete_own on public.nutrition_recipe_ingredients;
create policy nutrition_recipe_ingredients_delete_own
  on public.nutrition_recipe_ingredients
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and r.user_id = (select auth.uid())
        and r.is_public = false
    )
  );

-- ---------------------------------------------------------------------------
-- 3) Chat: extend messages.kind constraint for nutrition share kinds
-- ---------------------------------------------------------------------------

alter table public.messages
  drop constraint if exists messages_kind_check;

alter table public.messages
  add constraint messages_kind_check
  check (
    kind in (
      'text',
      'image',
      'file',
      'system',
      'workout_share',
      'routine_share',
      'achievement_share',
      'segment_share',
      'shared_ingredient',
      'shared_recipe'
    )
  );

-- ---------------------------------------------------------------------------
-- 4) Push notification previews: add labels for nutrition share kinds
-- ---------------------------------------------------------------------------

create or replace function public.trg_messages_after_insert_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_username text;
  v_preview text;
  v_title text;
begin
  if new.kind = 'system' or new.deleted_at is not null then
    return new;
  end if;

  select coalesce(p.username, 'Someone')
    into v_sender_username
  from public.profiles p
  where p.user_id = new.user_id;

  v_title := coalesce(v_sender_username, 'New message');

  v_preview := case
    when new.kind = 'image' then 'Sent an image'
    when new.kind = 'file'  then 'Sent a file'
    when new.kind = 'workout_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent a workout'
      )
    when new.kind = 'routine_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent a routine'
      )
    when new.kind = 'achievement_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent an achievement'
      )
    when new.kind = 'segment_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent a segment'
      )
    when new.kind = 'shared_ingredient' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent an ingredient'
      )
    when new.kind = 'shared_recipe' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent a recipe'
      )
    else
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'New message'
      )
  end;

  insert into public.notifications (user_id, type, title, body, data)
  select
    cp.user_id,
    'dm_message',
    v_title,
    v_preview,
    jsonb_build_object(
      'conversation_id', new.conversation_id,
      'message_id',      new.id,
      'sender_id',       new.user_id,
      'sender_username', coalesce(v_sender_username, '')
    )
  from public.conversation_participants cp
  where cp.conversation_id = new.conversation_id
    and cp.user_id <> new.user_id
    and cp.muted = false;

  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- 5) Clone RPCs: import shared snapshots (atomic, privacy-by-default)
-- ---------------------------------------------------------------------------

create or replace function public.clone_shared_ingredient(p_snapshot jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_new_id uuid := gen_random_uuid();
  v_name text;
  v_cals numeric;
  v_protein numeric;
  v_carbs numeric;
  v_fat numeric;
  v_sat numeric;
  v_sugars numeric;
  v_fiber numeric;
  v_sodium numeric;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    raise exception 'INVALID_SNAPSHOT';
  end if;

  v_name := nullif(btrim(coalesce(p_snapshot->>'name', '')), '');
  if v_name is null then
    raise exception 'INVALID_NAME';
  end if;

  v_cals   := nullif(p_snapshot->>'calories_per_100g', '')::numeric;
  v_protein:= coalesce(nullif(p_snapshot->>'protein_per_100g', '')::numeric, 0);
  v_carbs  := coalesce(nullif(p_snapshot->>'carbs_per_100g', '')::numeric, 0);
  v_fat    := coalesce(nullif(p_snapshot->>'fat_per_100g', '')::numeric, 0);
  v_sat    := coalesce(nullif(p_snapshot->>'saturated_fat_per_100g', '')::numeric, 0);
  v_sugars := coalesce(nullif(p_snapshot->>'sugars_per_100g', '')::numeric, 0);
  v_fiber  := coalesce(nullif(p_snapshot->>'fiber_per_100g', '')::numeric, 0);
  v_sodium := coalesce(nullif(p_snapshot->>'sodium_mg_per_100g', '')::numeric, 0);

  if v_cals is null then
    raise exception 'INVALID_CALORIES';
  end if;

  insert into public.nutrition_ingredients(
    id,
    user_id,
    name,
    calories_per_100g,
    protein_per_100g,
    carbs_per_100g,
    fat_per_100g,
    saturated_fat_per_100g,
    sugars_per_100g,
    fiber_per_100g,
    sodium_mg_per_100g,
    is_public
  ) values (
    v_new_id,
    v_me,
    v_name,
    v_cals,
    v_protein,
    v_carbs,
    v_fat,
    v_sat,
    v_sugars,
    v_fiber,
    v_sodium,
    false
  );

  return v_new_id;
end
$$;

revoke all on function public.clone_shared_ingredient(jsonb) from public;
grant execute on function public.clone_shared_ingredient(jsonb) to authenticated, service_role;

create or replace function public.clone_shared_recipe(p_snapshot jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_recipe_id uuid := gen_random_uuid();
  v_name text;
  v_description text;
  v_items jsonb;
  v_item jsonb;
  v_weight numeric;
  v_ing_id uuid;
  v_ing_name text;
  v_cals numeric;
  v_protein numeric;
  v_carbs numeric;
  v_fat numeric;
  v_sat numeric;
  v_sugars numeric;
  v_fiber numeric;
  v_sodium numeric;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    raise exception 'INVALID_SNAPSHOT';
  end if;

  v_name := nullif(btrim(coalesce(p_snapshot->>'name', '')), '');
  if v_name is null then
    raise exception 'INVALID_NAME';
  end if;

  v_description := nullif(btrim(coalesce(p_snapshot->>'description', '')), '');
  v_items := p_snapshot->'ingredients';
  if v_items is null or jsonb_typeof(v_items) <> 'array' then
    raise exception 'INVALID_INGREDIENTS_ARRAY';
  end if;

  insert into public.nutrition_recipes(
    id,
    user_id,
    name,
    description,
    is_public
  ) values (
    v_recipe_id,
    v_me,
    v_name,
    v_description,
    false
  );

  for v_item in select value from jsonb_array_elements(v_items) as t(value)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'INVALID_INGREDIENT_ITEM';
    end if;

    v_weight := nullif(v_item->>'weight_g', '')::numeric;
    if v_weight is null or v_weight <= 0 then
      raise exception 'INVALID_WEIGHT_G';
    end if;

    v_ing_name := nullif(btrim(coalesce(v_item->>'name', '')), '');
    if v_ing_name is null then
      raise exception 'INVALID_INGREDIENT_NAME';
    end if;

    v_cals   := nullif(v_item->>'calories_per_100g', '')::numeric;
    v_protein:= coalesce(nullif(v_item->>'protein_per_100g', '')::numeric, 0);
    v_carbs  := coalesce(nullif(v_item->>'carbs_per_100g', '')::numeric, 0);
    v_fat    := coalesce(nullif(v_item->>'fat_per_100g', '')::numeric, 0);
    v_sat    := coalesce(nullif(v_item->>'saturated_fat_per_100g', '')::numeric, 0);
    v_sugars := coalesce(nullif(v_item->>'sugars_per_100g', '')::numeric, 0);
    v_fiber  := coalesce(nullif(v_item->>'fiber_per_100g', '')::numeric, 0);
    v_sodium := coalesce(nullif(v_item->>'sodium_mg_per_100g', '')::numeric, 0);

    if v_cals is null then
      raise exception 'INVALID_CALORIES';
    end if;

    v_ing_id := gen_random_uuid();
    insert into public.nutrition_ingredients(
      id,
      user_id,
      name,
      calories_per_100g,
      protein_per_100g,
      carbs_per_100g,
      fat_per_100g,
      saturated_fat_per_100g,
      sugars_per_100g,
      fiber_per_100g,
      sodium_mg_per_100g,
      is_public
    ) values (
      v_ing_id,
      v_me,
      v_ing_name,
      v_cals,
      v_protein,
      v_carbs,
      v_fat,
      v_sat,
      v_sugars,
      v_fiber,
      v_sodium,
      false
    );

    insert into public.nutrition_recipe_ingredients(
      id,
      recipe_id,
      ingredient_id,
      weight_g
    ) values (
      gen_random_uuid(),
      v_recipe_id,
      v_ing_id,
      v_weight
    );
  end loop;

  return v_recipe_id;
end
$$;

revoke all on function public.clone_shared_recipe(jsonb) from public;
grant execute on function public.clone_shared_recipe(jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';


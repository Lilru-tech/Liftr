set local check_function_bodies = off;

create table if not exists public.nutrition_ingredients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  name text not null,
  calories_per_100g numeric(6, 2) not null,
  protein_per_100g numeric(5, 2) not null,
  carbs_per_100g numeric(5, 2) not null,
  fat_per_100g numeric(5, 2) not null,
  is_public boolean not null default false,
  constraint nutrition_ingredients_macros_nonneg check (
    calories_per_100g >= 0
    and protein_per_100g >= 0
    and carbs_per_100g >= 0
    and fat_per_100g >= 0
  )
);

create index if not exists nutrition_ingredients_user_id_idx
  on public.nutrition_ingredients (user_id)
  where user_id is not null;

create index if not exists nutrition_ingredients_public_idx
  on public.nutrition_ingredients (is_public)
  where is_public = true;

create table if not exists public.nutrition_recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create index if not exists nutrition_recipes_user_id_idx
  on public.nutrition_recipes (user_id);

create table if not exists public.nutrition_recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.nutrition_recipes (id) on delete cascade,
  ingredient_id uuid not null references public.nutrition_ingredients (id) on delete cascade,
  weight_g numeric(6, 2) not null,
  constraint nutrition_recipe_ingredients_weight_positive check (weight_g > 0)
);

create index if not exists nutrition_recipe_ingredients_recipe_id_idx
  on public.nutrition_recipe_ingredients (recipe_id);

create table if not exists public.nutrition_diary_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  log_date date not null default current_date,
  meal_slot text not null,
  ingredient_id uuid references public.nutrition_ingredients (id) on delete cascade,
  recipe_id uuid references public.nutrition_recipes (id) on delete cascade,
  quantity_g numeric(6, 2) not null,
  constraint nutrition_diary_logs_meal_slot_check check (
    meal_slot in ('Breakfast', 'Lunch', 'Dinner', 'Snack')
  ),
  constraint nutrition_diary_logs_quantity_positive check (quantity_g > 0),
  constraint nutrition_diary_logs_source_xor check (
    num_nonnulls(ingredient_id, recipe_id) = 1
  )
);

create index if not exists nutrition_diary_logs_user_date_idx
  on public.nutrition_diary_logs (user_id, log_date);

alter table public.nutrition_ingredients enable row level security;
alter table public.nutrition_recipes enable row level security;
alter table public.nutrition_recipe_ingredients enable row level security;
alter table public.nutrition_diary_logs enable row level security;

drop policy if exists nutrition_ingredients_select_visible on public.nutrition_ingredients;
create policy nutrition_ingredients_select_visible
  on public.nutrition_ingredients
  for select
  to authenticated
  using (is_public = true or user_id = (select auth.uid()));

drop policy if exists nutrition_ingredients_insert_own on public.nutrition_ingredients;
create policy nutrition_ingredients_insert_own
  on public.nutrition_ingredients
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists nutrition_ingredients_update_own on public.nutrition_ingredients;
create policy nutrition_ingredients_update_own
  on public.nutrition_ingredients
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists nutrition_ingredients_delete_own on public.nutrition_ingredients;
create policy nutrition_ingredients_delete_own
  on public.nutrition_ingredients
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists nutrition_recipes_select_own on public.nutrition_recipes;
create policy nutrition_recipes_select_own
  on public.nutrition_recipes
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists nutrition_recipes_insert_own on public.nutrition_recipes;
create policy nutrition_recipes_insert_own
  on public.nutrition_recipes
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists nutrition_recipes_update_own on public.nutrition_recipes;
create policy nutrition_recipes_update_own
  on public.nutrition_recipes
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists nutrition_recipes_delete_own on public.nutrition_recipes;
create policy nutrition_recipes_delete_own
  on public.nutrition_recipes
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists nutrition_recipe_ingredients_select_own on public.nutrition_recipe_ingredients;
create policy nutrition_recipe_ingredients_select_own
  on public.nutrition_recipe_ingredients
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and r.user_id = (select auth.uid())
    )
  );

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
    )
  )
  with check (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and r.user_id = (select auth.uid())
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
    )
  );

drop policy if exists nutrition_diary_logs_select_own on public.nutrition_diary_logs;
create policy nutrition_diary_logs_select_own
  on public.nutrition_diary_logs
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists nutrition_diary_logs_insert_own on public.nutrition_diary_logs;
create policy nutrition_diary_logs_insert_own
  on public.nutrition_diary_logs
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists nutrition_diary_logs_update_own on public.nutrition_diary_logs;
create policy nutrition_diary_logs_update_own
  on public.nutrition_diary_logs
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists nutrition_diary_logs_delete_own on public.nutrition_diary_logs;
create policy nutrition_diary_logs_delete_own
  on public.nutrition_diary_logs
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

insert into public.nutrition_ingredients (
  user_id,
  name,
  calories_per_100g,
  protein_per_100g,
  carbs_per_100g,
  fat_per_100g,
  is_public
)
values
  (null, 'Chicken breast (cooked)', 165, 31.00, 0.00, 3.60, true),
  (null, 'White rice (cooked)', 130, 2.70, 28.00, 0.30, true),
  (null, 'Egg (large)', 143, 12.60, 0.72, 9.51, true),
  (null, 'Banana', 89, 1.10, 22.80, 0.30, true),
  (null, 'Potato (boiled)', 87, 1.90, 20.10, 0.10, true),
  (null, 'Sweet potato (baked)', 90, 2.00, 20.70, 0.20, true),
  (null, 'Olive oil', 884, 0.00, 0.00, 100.00, true),
  (null, 'Greek yogurt (plain)', 59, 10.00, 3.60, 0.40, true),
  (null, 'Oats (dry)', 389, 16.90, 66.30, 6.90, true),
  (null, 'Salmon (cooked)', 206, 22.10, 0.00, 12.40, true),
  (null, 'Broccoli (cooked)', 35, 2.40, 7.20, 0.40, true),
  (null, 'Whole wheat bread', 247, 13.00, 41.00, 3.40, true),
  (null, 'Apple', 52, 0.30, 13.80, 0.20, true),
  (null, 'Pasta (cooked)', 131, 5.00, 25.00, 1.10, true),
  (null, 'Ground beef (lean, cooked)', 250, 26.00, 0.00, 15.00, true);

create or replace function public.get_daily_nutrition_recommendation_v1(p_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_consumed numeric := 0;
  v_burned numeric := 0;
  v_net numeric := 0;
  v_text text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select coalesce(sum(
    case
      when l.ingredient_id is not null then
        l.quantity_g * i.calories_per_100g / 100.0
      else
        l.quantity_g * coalesce(
          (
            select
              sum(ri.weight_g * ing.calories_per_100g / 100.0)
              / nullif(sum(ri.weight_g), 0)
            from public.nutrition_recipe_ingredients ri
            join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
            where ri.recipe_id = l.recipe_id
          ),
          0
        )
    end
  ), 0)
  into v_consumed
  from public.nutrition_diary_logs l
  left join public.nutrition_ingredients i on i.id = l.ingredient_id
  where l.user_id = v_uid
    and l.log_date = p_date;

  select coalesce(sum(w.calories_kcal), 0)
  into v_burned
  from public.workouts w
  where w.user_id = v_uid
    and w.state = 'published'
    and coalesce(w.started_at, w.created_at)::date = p_date
    and w.calories_kcal is not null
    and w.calories_kcal > 0;

  v_net := v_consumed - v_burned;

  if v_burned >= 600 and v_net < -400 then
    v_text := format(
      'High activity day (%s kcal burned). You are %s kcal below intake — prioritize protein-rich meals and hydration to recover.',
      round(v_burned, 0)::text,
      round(abs(v_net), 0)::text
    );
  elsif v_burned >= 300 and v_net < -200 then
    v_text := format(
      'Moderate activity (%s kcal burned). Consider adding a balanced meal or snack to close a %s kcal gap.',
      round(v_burned, 0)::text,
      round(abs(v_net), 0)::text
    );
  elsif v_net > 400 then
    v_text := format(
      'Intake exceeds active burn by %s kcal. If your goal is maintenance, balance later meals; for performance days, this surplus can support recovery.',
      round(v_net, 0)::text
    );
  elsif v_net between -150 and 150 then
    v_text := 'Calories consumed and active burn are well balanced for today. Keep consistent meal timing around training.';
  elsif v_net < 0 then
    v_text := format(
      'You are %s kcal under today''s active burn. Add nutrient-dense foods if energy feels low.',
      round(abs(v_net), 0)::text
    );
  else
    v_text := format(
      'Net surplus of %s kcal versus active burn. Adjust portions if aligning with a deficit or maintenance target.',
      round(v_net, 0)::text
    );
  end if;

  return jsonb_build_object(
    'total_calories_consumed', round(v_consumed, 1),
    'total_calories_burned_active', round(v_burned, 1),
    'net_calories_balance', round(v_net, 1),
    'recommendation_text', v_text
  );
end;
$$;

revoke all on function public.get_daily_nutrition_recommendation_v1(date) from public;
grant execute on function public.get_daily_nutrition_recommendation_v1(date) to authenticated;

notify pgrst, 'reload schema';

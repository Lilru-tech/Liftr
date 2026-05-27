set local check_function_bodies = off;

create table if not exists public.user_favorite_nutrition_ingredients (
  user_id uuid not null references auth.users (id) on delete cascade,
  ingredient_id uuid not null references public.nutrition_ingredients (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, ingredient_id)
);

create table if not exists public.user_favorite_nutrition_recipes (
  user_id uuid not null references auth.users (id) on delete cascade,
  recipe_id uuid not null references public.nutrition_recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

create index if not exists user_favorite_nutrition_ingredients_user_id_idx
  on public.user_favorite_nutrition_ingredients (user_id);

create index if not exists user_favorite_nutrition_recipes_user_id_idx
  on public.user_favorite_nutrition_recipes (user_id);

alter table public.user_favorite_nutrition_ingredients enable row level security;
alter table public.user_favorite_nutrition_recipes enable row level security;

drop policy if exists user_favorite_nutrition_ingredients_select_own on public.user_favorite_nutrition_ingredients;
create policy user_favorite_nutrition_ingredients_select_own
  on public.user_favorite_nutrition_ingredients
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists user_favorite_nutrition_ingredients_insert_own on public.user_favorite_nutrition_ingredients;
create policy user_favorite_nutrition_ingredients_insert_own
  on public.user_favorite_nutrition_ingredients
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_favorite_nutrition_ingredients_delete_own on public.user_favorite_nutrition_ingredients;
create policy user_favorite_nutrition_ingredients_delete_own
  on public.user_favorite_nutrition_ingredients
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists user_favorite_nutrition_recipes_select_own on public.user_favorite_nutrition_recipes;
create policy user_favorite_nutrition_recipes_select_own
  on public.user_favorite_nutrition_recipes
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists user_favorite_nutrition_recipes_insert_own on public.user_favorite_nutrition_recipes;
create policy user_favorite_nutrition_recipes_insert_own
  on public.user_favorite_nutrition_recipes
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_favorite_nutrition_recipes_delete_own on public.user_favorite_nutrition_recipes;
create policy user_favorite_nutrition_recipes_delete_own
  on public.user_favorite_nutrition_recipes
  for delete
  to authenticated
  using (user_id = auth.uid());

notify pgrst, 'reload schema';

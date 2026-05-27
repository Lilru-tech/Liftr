set local check_function_bodies = off;

alter table public.nutrition_recipes
  alter column user_id drop not null;

create index if not exists nutrition_recipes_catalog_name_idx
  on public.nutrition_recipes (lower(trim(name)))
  where user_id is null;

drop policy if exists nutrition_recipes_select_own on public.nutrition_recipes;
create policy nutrition_recipes_select_visible
  on public.nutrition_recipes
  for select
  to authenticated
  using (user_id is null or user_id = (select auth.uid()));

drop policy if exists nutrition_recipe_ingredients_select_own on public.nutrition_recipe_ingredients;
create policy nutrition_recipe_ingredients_select_visible
  on public.nutrition_recipe_ingredients
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.nutrition_recipes r
      where r.id = recipe_id
        and (r.user_id is null or r.user_id = (select auth.uid()))
    )
  );

insert into public.nutrition_ingredients (
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
)
select
  v.user_id,
  v.name,
  v.calories_per_100g,
  v.protein_per_100g,
  v.carbs_per_100g,
  v.fat_per_100g,
  v.saturated_fat_per_100g,
  v.sugars_per_100g,
  v.fiber_per_100g,
  v.sodium_mg_per_100g,
  v.is_public
from (
  values
    (null::uuid, 'Parmesan Cheese', 431.00::numeric, 38.00::numeric, 4.10::numeric, 29.00::numeric, 17.00::numeric, 0.80::numeric, 0.00::numeric, 1529.00::numeric, true),
    (null::uuid, 'Bacon / Pancetta', 541.00::numeric, 14.00::numeric, 1.40::numeric, 53.00::numeric, 18.00::numeric, 0.00::numeric, 0.00::numeric, 1700.00::numeric, true)
) as v(
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
)
where not exists (
  select 1
  from public.nutrition_ingredients ni
  where ni.user_id is null
    and ni.is_public = true
    and lower(trim(ni.name)) = lower(trim(v.name))
);

do $$
declare
  r_carbonara uuid;
  r_pisto uuid;
  r_tortilla uuid;
  r_chicken_rice uuid;
  r_avocado_toast uuid;
  r_yogurt_bowl uuid;
  r_greek_salad uuid;
  r_beef_stir_fry uuid;
begin
  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'Classic Pasta Carbonara'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'Classic Pasta Carbonara') returning id into r_carbonara;
  else
    select id into r_carbonara from public.nutrition_recipes where user_id is null and name = 'Classic Pasta Carbonara' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_carbonara;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_carbonara, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Pasta (cooked)' limit 1), 150.00),
    (r_carbonara, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Bacon / Pancetta' limit 1), 50.00),
    (r_carbonara, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Egg (large)' limit 1), 100.00),
    (r_carbonara, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Parmesan Cheese' limit 1), 20.00),
    (r_carbonara, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Table Salt' limit 1), 2.00);

  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'Pisto Manchego (Veggie Stew)'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'Pisto Manchego (Veggie Stew)') returning id into r_pisto;
  else
    select id into r_pisto from public.nutrition_recipes where user_id is null and name = 'Pisto Manchego (Veggie Stew)' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_pisto;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_pisto, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Tomatoes (Raw)' limit 1), 150.00),
    (r_pisto, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Zucchini (Calabacín)' limit 1), 100.00),
    (r_pisto, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Eggplant (Berenjena)' limit 1), 100.00),
    (r_pisto, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Red Bell Pepper' limit 1), 50.00),
    (r_pisto, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Onion (Raw)' limit 1), 50.00),
    (r_pisto, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Olive oil' limit 1), 15.00);

  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'Spanish Tortilla (Potato & Egg)'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'Spanish Tortilla (Potato & Egg)') returning id into r_tortilla;
  else
    select id into r_tortilla from public.nutrition_recipes where user_id is null and name = 'Spanish Tortilla (Potato & Egg)' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_tortilla;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_tortilla, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Potato (boiled)' limit 1), 400.00),
    (r_tortilla, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Egg (large)' limit 1), 250.00),
    (r_tortilla, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Onion (Raw)' limit 1), 100.00),
    (r_tortilla, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Olive oil' limit 1), 25.00),
    (r_tortilla, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Table Salt' limit 1), 4.00);

  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'Fitness Chicken & Rice Bowl'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'Fitness Chicken & Rice Bowl') returning id into r_chicken_rice;
  else
    select id into r_chicken_rice from public.nutrition_recipes where user_id is null and name = 'Fitness Chicken & Rice Bowl' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_chicken_rice;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_chicken_rice, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Chicken breast (cooked)' limit 1), 150.00),
    (r_chicken_rice, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Basmati Rice (Cooked)' limit 1), 150.00),
    (r_chicken_rice, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Broccoli (cooked)' limit 1), 100.00),
    (r_chicken_rice, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Olive oil' limit 1), 10.00);

  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'Avocado Toast with Egg'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'Avocado Toast with Egg') returning id into r_avocado_toast;
  else
    select id into r_avocado_toast from public.nutrition_recipes where user_id is null and name = 'Avocado Toast with Egg' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_avocado_toast;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_avocado_toast, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Whole wheat bread' limit 1), 60.00),
    (r_avocado_toast, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Avocado' limit 1), 60.00),
    (r_avocado_toast, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Egg (large)' limit 1), 50.00);

  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'High-Protein Yogurt Bowl'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'High-Protein Yogurt Bowl') returning id into r_yogurt_bowl;
  else
    select id into r_yogurt_bowl from public.nutrition_recipes where user_id is null and name = 'High-Protein Yogurt Bowl' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_yogurt_bowl;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_yogurt_bowl, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Greek yogurt (plain)' limit 1), 200.00),
    (r_yogurt_bowl, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Blueberries' limit 1), 50.00),
    (r_yogurt_bowl, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Almonds' limit 1), 15.00),
    (r_yogurt_bowl, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Honey' limit 1), 10.00);

  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'Classic Greek Salad'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'Classic Greek Salad') returning id into r_greek_salad;
  else
    select id into r_greek_salad from public.nutrition_recipes where user_id is null and name = 'Classic Greek Salad' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_greek_salad;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_greek_salad, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Tomatoes (Raw)' limit 1), 150.00),
    (r_greek_salad, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Cucumber (With peel)' limit 1), 100.00),
    (r_greek_salad, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Feta Cheese' limit 1), 50.00),
    (r_greek_salad, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Olive oil' limit 1), 12.00);

  if not exists (
    select 1 from public.nutrition_recipes where user_id is null and name = 'Healthy Beef & Broccoli Stir-Fry'
  ) then
    insert into public.nutrition_recipes (user_id, name) values (null, 'Healthy Beef & Broccoli Stir-Fry') returning id into r_beef_stir_fry;
  else
    select id into r_beef_stir_fry from public.nutrition_recipes where user_id is null and name = 'Healthy Beef & Broccoli Stir-Fry' limit 1;
  end if;
  delete from public.nutrition_recipe_ingredients where recipe_id = r_beef_stir_fry;
  insert into public.nutrition_recipe_ingredients (recipe_id, ingredient_id, weight_g) values
    (r_beef_stir_fry, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Sirloin Steak (Trimmed, cooked)' limit 1), 150.00),
    (r_beef_stir_fry, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Broccoli (cooked)' limit 1), 150.00),
    (r_beef_stir_fry, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Onion (Raw)' limit 1), 50.00),
    (r_beef_stir_fry, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Soy Sauce' limit 1), 15.00),
    (r_beef_stir_fry, (select id from public.nutrition_ingredients where user_id is null and is_public = true and name = 'Olive oil' limit 1), 5.00);
end $$;

notify pgrst, 'reload schema';

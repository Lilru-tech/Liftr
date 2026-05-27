set local check_function_bodies = off;

alter table public.nutrition_ingredients
  add column if not exists saturated_fat_per_100g numeric(5, 2) not null default 0.00,
  add column if not exists sugars_per_100g numeric(5, 2) not null default 0.00,
  add column if not exists fiber_per_100g numeric(5, 2) not null default 0.00,
  add column if not exists sodium_mg_per_100g numeric(6, 2) not null default 0.00;

alter table public.nutrition_ingredients
  alter column sodium_mg_per_100g type numeric(10, 2);

alter table public.nutrition_ingredients
  drop constraint if exists nutrition_ingredients_macros_nonneg;

alter table public.nutrition_ingredients
  add constraint nutrition_ingredients_macros_nonneg check (
    calories_per_100g >= 0
    and protein_per_100g >= 0
    and carbs_per_100g >= 0
    and fat_per_100g >= 0
    and saturated_fat_per_100g >= 0
    and sugars_per_100g >= 0
    and fiber_per_100g >= 0
    and sodium_mg_per_100g >= 0
  );

update public.nutrition_ingredients
set saturated_fat_per_100g = 1.00, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 70.00
where id = '22871e1a-42da-48bd-8c43-29766f3f5d4f';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.10, sugars_per_100g = 0.10, fiber_per_100g = 0.40, sodium_mg_per_100g = 1.00
where id = 'bce62a53-f405-4396-8feb-df1738601a56';

update public.nutrition_ingredients
set saturated_fat_per_100g = 3.10, sugars_per_100g = 0.40, fiber_per_100g = 0.00, sodium_mg_per_100g = 124.00
where id = '8b36fadb-9c55-4bd6-8b58-d23a3764a35e';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.10, sugars_per_100g = 12.20, fiber_per_100g = 2.60, sodium_mg_per_100g = 1.00
where id = '01b6372a-2c41-4610-b9cc-fca44d85d6e7';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.00, sugars_per_100g = 0.80, fiber_per_100g = 1.80, sodium_mg_per_100g = 4.00
where id = 'c2af3981-fd41-4602-9da7-dca2d60b8403';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.05, sugars_per_100g = 6.50, fiber_per_100g = 3.30, sodium_mg_per_100g = 36.00
where id = '099e36ee-6dce-4b36-af4b-4800e8738a3b';

update public.nutrition_ingredients
set saturated_fat_per_100g = 14.00, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 2.00
where id = '7ded5ba9-6e47-4676-b93d-c601f4710330';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.10, sugars_per_100g = 3.20, fiber_per_100g = 0.00, sodium_mg_per_100g = 36.00
where id = '1653b741-fc6c-4111-8839-2aa76bf85a8a';

update public.nutrition_ingredients
set saturated_fat_per_100g = 1.20, sugars_per_100g = 1.00, fiber_per_100g = 10.60, sodium_mg_per_100g = 2.00
where id = 'be1a46c7-21cc-4bd9-a51a-a5b3c2d758d7';

update public.nutrition_ingredients
set saturated_fat_per_100g = 2.50, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 60.00
where id = '063221c2-3fc8-4ae5-8c42-07113d7050c8';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.05, sugars_per_100g = 1.40, fiber_per_100g = 3.30, sodium_mg_per_100g = 40.00
where id = 'ed55753c-0359-42dc-b991-3b0f4bb52204';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.70, sugars_per_100g = 4.00, fiber_per_100g = 6.00, sodium_mg_per_100g = 450.00
where id = '0222726c-0cce-4389-bcf0-0412ffe7faa3';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.05, sugars_per_100g = 10.40, fiber_per_100g = 2.40, sodium_mg_per_100g = 1.00
where id = 'cbbc77e2-de6a-4403-87d3-24e449ec4f48';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.20, sugars_per_100g = 0.60, fiber_per_100g = 1.80, sodium_mg_per_100g = 1.00
where id = 'fe589c6d-2ef5-4c81-8c4b-c279697b6852';

update public.nutrition_ingredients
set saturated_fat_per_100g = 6.00, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 70.00
where id = 'a903fca1-00ad-4ea4-ab58-ed1293153a01';

update public.nutrition_ingredients
set saturated_fat_per_100g = 1.00, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 70.00
where user_id is null and is_public = true and name = 'Chicken breast (cooked)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.10, sugars_per_100g = 0.10, fiber_per_100g = 0.40, sodium_mg_per_100g = 1.00
where user_id is null and is_public = true and name = 'White rice (cooked)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 3.10, sugars_per_100g = 0.40, fiber_per_100g = 0.00, sodium_mg_per_100g = 124.00
where user_id is null and is_public = true and name = 'Egg (large)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.10, sugars_per_100g = 12.20, fiber_per_100g = 2.60, sodium_mg_per_100g = 1.00
where user_id is null and is_public = true and name = 'Banana';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.00, sugars_per_100g = 0.80, fiber_per_100g = 1.80, sodium_mg_per_100g = 4.00
where user_id is null and is_public = true and name = 'Potato (boiled)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.05, sugars_per_100g = 6.50, fiber_per_100g = 3.30, sodium_mg_per_100g = 36.00
where user_id is null and is_public = true and name = 'Sweet potato (baked)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 14.00, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 2.00
where user_id is null and is_public = true and name = 'Olive oil';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.10, sugars_per_100g = 3.20, fiber_per_100g = 0.00, sodium_mg_per_100g = 36.00
where user_id is null and is_public = true and name = 'Greek yogurt (plain)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 1.20, sugars_per_100g = 1.00, fiber_per_100g = 10.60, sodium_mg_per_100g = 2.00
where user_id is null and is_public = true and name = 'Oats (dry)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 2.50, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 60.00
where user_id is null and is_public = true and name = 'Salmon (cooked)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.05, sugars_per_100g = 1.40, fiber_per_100g = 3.30, sodium_mg_per_100g = 40.00
where user_id is null and is_public = true and name = 'Broccoli (cooked)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.70, sugars_per_100g = 4.00, fiber_per_100g = 6.00, sodium_mg_per_100g = 450.00
where user_id is null and is_public = true and name = 'Whole wheat bread';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.05, sugars_per_100g = 10.40, fiber_per_100g = 2.40, sodium_mg_per_100g = 1.00
where user_id is null and is_public = true and name = 'Apple';

update public.nutrition_ingredients
set saturated_fat_per_100g = 0.20, sugars_per_100g = 0.60, fiber_per_100g = 1.80, sodium_mg_per_100g = 1.00
where user_id is null and is_public = true and name = 'Pasta (cooked)';

update public.nutrition_ingredients
set saturated_fat_per_100g = 6.00, sugars_per_100g = 0.00, fiber_per_100g = 0.00, sodium_mg_per_100g = 70.00
where user_id is null and is_public = true and name = 'Ground beef (lean, cooked)';

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
    (null::uuid, 'Zucchini (Calabacín)', 17.00::numeric, 1.20::numeric, 3.10::numeric, 0.30::numeric, 0.05::numeric, 2.50::numeric, 1.00::numeric, 8.00::numeric, true),
    (null::uuid, 'Eggplant (Berenjena)', 25.00, 1.00, 6.00, 0.20, 0.03, 3.50, 3.00, 2.00, true),
    (null::uuid, 'Spinach (Raw)', 23.00, 2.90, 3.60, 0.40, 0.06, 0.40, 2.20, 79.00, true),
    (null::uuid, 'Carrots (Raw)', 41.00, 0.90, 9.60, 0.20, 0.04, 4.70, 2.80, 69.00, true),
    (null::uuid, 'Tomatoes (Raw)', 18.00, 0.90, 3.90, 0.20, 0.03, 2.60, 1.20, 5.00, true),
    (null::uuid, 'Cucumber (With peel)', 15.00, 0.70, 3.60, 0.10, 0.03, 1.70, 0.50, 2.00, true),
    (null::uuid, 'Red Bell Pepper', 31.00, 1.00, 6.00, 0.30, 0.03, 4.20, 2.10, 4.00, true),
    (null::uuid, 'Green Bell Pepper', 20.00, 0.90, 4.60, 0.20, 0.03, 2.40, 1.70, 3.00, true),
    (null::uuid, 'Onion (Raw)', 40.00, 1.10, 9.30, 0.10, 0.04, 4.20, 1.70, 4.00, true),
    (null::uuid, 'Garlic', 149.00, 6.40, 33.10, 0.50, 0.09, 1.00, 2.10, 17.00, true),
    (null::uuid, 'Cauliflower (Raw)', 25.00, 1.90, 5.00, 0.30, 0.13, 1.90, 2.00, 30.00, true),
    (null::uuid, 'Asparagus (Raw)', 20.00, 2.20, 3.90, 0.12, 0.04, 1.90, 2.10, 2.00, true),
    (null::uuid, 'White Mushrooms', 22.00, 3.10, 3.30, 0.30, 0.05, 2.00, 1.00, 5.00, true),
    (null::uuid, 'Iceberg Lettuce', 14.00, 0.90, 3.00, 0.14, 0.02, 2.00, 1.20, 10.00, true),
    (null::uuid, 'Kale (Raw)', 49.00, 4.30, 8.80, 0.90, 0.10, 2.30, 3.60, 38.00, true),
    (null::uuid, 'Zucchini (Cooked)', 16.00, 0.60, 2.70, 0.10, 0.02, 1.70, 1.00, 3.00, true),
    (null::uuid, 'Asparagus (Cooked)', 22.00, 2.40, 4.10, 0.20, 0.05, 1.30, 2.00, 14.00, true),
    (null::uuid, 'Green Beans (Boiled)', 35.00, 1.90, 7.90, 0.30, 0.05, 1.40, 3.20, 6.00, true),
    (null::uuid, 'Spinach (Boiled)', 23.00, 3.00, 3.80, 0.30, 0.05, 0.40, 2.40, 70.00, true),
    (null::uuid, 'Mushrooms (Sautéed)', 28.00, 2.20, 4.20, 0.40, 0.07, 1.20, 1.50, 4.00, true),
    (null::uuid, 'Strawberries', 32.00, 0.70, 7.70, 0.30, 0.02, 4.90, 2.00, 1.00, true),
    (null::uuid, 'Blueberries', 57.00, 0.70, 14.50, 0.30, 0.03, 10.00, 2.40, 1.00, true),
    (null::uuid, 'Orange', 47.00, 0.90, 11.80, 0.10, 0.02, 9.40, 2.40, 0.00, true),
    (null::uuid, 'Lemon Juice', 22.00, 0.40, 6.90, 0.20, 0.04, 2.50, 0.30, 1.00, true),
    (null::uuid, 'Peach', 39.00, 0.90, 9.50, 0.30, 0.02, 8.40, 1.50, 0.00, true),
    (null::uuid, 'Pear', 57.00, 0.40, 15.20, 0.10, 0.02, 9.80, 3.10, 1.00, true),
    (null::uuid, 'Kiwi', 61.00, 1.10, 14.70, 0.50, 0.03, 9.00, 3.00, 3.00, true),
    (null::uuid, 'Grapes', 69.00, 0.70, 18.10, 0.20, 0.05, 15.50, 0.90, 2.00, true),
    (null::uuid, 'Pineapple', 50.00, 0.50, 13.10, 0.10, 0.01, 9.90, 1.40, 1.00, true),
    (null::uuid, 'Watermelon', 30.00, 0.60, 7.60, 0.20, 0.02, 6.20, 0.40, 1.00, true),
    (null::uuid, 'Melon (Cantaloupe)', 34.00, 0.80, 8.20, 0.20, 0.05, 7.90, 0.90, 16.00, true),
    (null::uuid, 'Mango', 60.00, 0.80, 15.00, 0.40, 0.09, 13.70, 1.60, 1.00, true),
    (null::uuid, 'Raspberries', 52.00, 1.20, 11.90, 0.70, 0.02, 4.40, 6.50, 1.00, true),
    (null::uuid, 'Blackberries', 43.00, 1.40, 9.60, 0.50, 0.02, 4.90, 5.30, 1.00, true),
    (null::uuid, 'Grapefruit', 42.00, 0.80, 11.00, 0.10, 0.01, 7.00, 1.60, 0.00, true),
    (null::uuid, 'Turkey Breast (Cooked)', 135.00, 30.00, 0.00, 1.30, 0.40, 0.00, 0.00, 68.00, true),
    (null::uuid, 'Chicken Thigh (Skinless, cooked)', 177.00, 24.00, 0.00, 8.00, 2.30, 0.00, 0.00, 80.00, true),
    (null::uuid, 'Pork Loin (Lean, cooked)', 242.00, 27.00, 0.00, 14.00, 5.00, 0.00, 0.00, 62.00, true),
    (null::uuid, 'Canned Tuna (In water, drained)', 116.00, 26.00, 0.00, 1.00, 0.20, 0.00, 0.00, 350.00, true),
    (null::uuid, 'Canned Tuna (In olive oil, drained)', 198.00, 27.00, 0.00, 10.00, 1.50, 0.00, 0.00, 380.00, true),
    (null::uuid, 'Cod Fish (Cooked)', 105.00, 23.00, 0.00, 0.90, 0.15, 0.00, 0.00, 75.00, true),
    (null::uuid, 'Shrimp (Cooked)', 99.00, 24.00, 0.20, 0.30, 0.05, 0.00, 0.00, 111.00, true),
    (null::uuid, 'Egg Whites', 52.00, 11.00, 0.70, 0.20, 0.00, 0.70, 0.00, 166.00, true),
    (null::uuid, 'Sirloin Steak (Trimmed, cooked)', 210.00, 29.00, 0.00, 10.00, 4.00, 0.00, 0.00, 55.00, true),
    (null::uuid, 'Lean Ground Turkey (Cooked)', 203.00, 27.00, 0.00, 10.00, 2.70, 0.00, 0.00, 78.00, true),
    (null::uuid, 'Skimmed Milk (1%)', 42.00, 3.40, 5.00, 1.00, 0.60, 5.00, 0.00, 44.00, true),
    (null::uuid, 'Whole Milk', 61.00, 3.20, 4.80, 3.30, 1.90, 4.80, 0.00, 44.00, true),
    (null::uuid, 'Soy Milk (Unsweetened)', 33.00, 2.80, 1.80, 1.60, 0.20, 0.60, 0.60, 38.00, true),
    (null::uuid, 'Almond Milk (Unsweetened)', 15.00, 0.60, 0.30, 1.20, 0.00, 0.00, 0.20, 70.00, true),
    (null::uuid, 'Cottage Cheese (Low fat)', 82.00, 11.00, 4.30, 2.30, 1.40, 4.00, 0.00, 364.00, true),
    (null::uuid, 'Light Mozzarella', 250.00, 24.00, 2.00, 16.00, 10.00, 1.00, 0.00, 500.00, true),
    (null::uuid, 'Feta Cheese', 264.00, 14.00, 4.00, 21.00, 15.00, 4.00, 0.00, 900.00, true),
    (null::uuid, 'Skimmed Quark Cheese', 65.00, 12.00, 4.00, 0.20, 0.05, 4.00, 0.00, 40.00, true),
    (null::uuid, 'Basmati Rice (Cooked)', 121.00, 3.50, 26.00, 0.40, 0.05, 0.05, 0.60, 1.00, true),
    (null::uuid, 'Brown Rice (Cooked)', 112.00, 2.60, 23.50, 0.90, 0.20, 0.20, 1.80, 1.00, true),
    (null::uuid, 'Quinoa (Cooked)', 120.00, 4.40, 21.30, 1.90, 0.20, 0.90, 2.80, 7.00, true),
    (null::uuid, 'Couscous (Cooked)', 112.00, 3.80, 23.00, 0.20, 0.03, 0.10, 1.40, 5.00, true),
    (null::uuid, 'Plain Rice Cakes (Each/100g avg)', 387.00, 8.00, 81.00, 2.80, 0.50, 0.80, 4.00, 300.00, true),
    (null::uuid, 'Sweet Corn (Boiled)', 96.00, 3.40, 21.00, 1.50, 0.20, 4.50, 2.40, 15.00, true),
    (null::uuid, 'White Bread', 265.00, 9.00, 49.00, 3.20, 0.70, 5.00, 2.70, 490.00, true),
    (null::uuid, 'Gnocchi (Cooked)', 132.00, 3.30, 28.30, 0.40, 0.10, 0.50, 1.60, 280.00, true),
    (null::uuid, 'Lentils (Boiled/Drained)', 116.00, 9.00, 20.00, 0.40, 0.05, 1.80, 7.90, 2.00, true),
    (null::uuid, 'Chickpeas (Boiled/Drained)', 164.00, 8.90, 27.00, 2.60, 0.27, 4.80, 7.60, 24.00, true),
    (null::uuid, 'Black Beans (Boiled/Drained)', 132.00, 8.90, 23.70, 0.50, 0.10, 0.30, 8.70, 1.00, true),
    (null::uuid, 'Kidney Beans (Boiled/Drained)', 127.00, 8.70, 22.80, 0.50, 0.06, 0.30, 6.40, 2.00, true),
    (null::uuid, 'Tofu (Firm)', 144.00, 17.00, 2.80, 8.00, 1.20, 0.50, 2.00, 12.00, true),
    (null::uuid, 'Almonds', 579.00, 21.00, 22.00, 50.00, 3.80, 4.40, 12.50, 1.00, true),
    (null::uuid, 'Walnuts', 654.00, 15.20, 13.70, 65.20, 6.10, 2.60, 6.70, 2.00, true),
    (null::uuid, 'Chia Seeds', 486.00, 16.50, 42.10, 30.70, 3.30, 0.00, 34.40, 16.00, true),
    (null::uuid, 'Flax Seeds', 534.00, 18.30, 28.90, 42.20, 3.70, 1.50, 27.30, 30.00, true),
    (null::uuid, 'Pumpkin Seeds', 559.00, 30.20, 10.70, 49.00, 8.70, 1.40, 6.00, 7.00, true),
    (null::uuid, 'Pure Peanut Butter', 588.00, 25.00, 20.00, 50.00, 10.00, 9.00, 6.00, 12.00, true),
    (null::uuid, 'Unsalted Butter', 717.00, 0.90, 0.10, 81.00, 51.30, 0.10, 0.00, 11.00, true),
    (null::uuid, 'Coconut Oil', 862.00, 0.00, 0.00, 100.00, 87.00, 0.00, 0.00, 0.00, true),
    (null::uuid, 'Avocado', 160.00, 2.00, 8.50, 14.70, 2.10, 0.70, 6.70, 7.00, true),
    (null::uuid, 'Honey', 304.00, 0.30, 82.40, 0.00, 0.00, 82.10, 0.20, 4.00, true),
    (null::uuid, 'Soy Sauce', 53.00, 5.50, 4.90, 0.60, 0.10, 0.80, 0.80, 5493.00, true),
    (null::uuid, 'Table Salt', 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 38758.00, true),
    (null::uuid, 'Black Pepper', 251.00, 10.00, 64.00, 3.30, 1.40, 0.60, 25.00, 20.00, true),
    (null::uuid, 'Whey Protein Isolate (Dry)', 370.00, 85.00, 4.00, 2.00, 1.00, 2.00, 0.00, 200.00, true),
    (null::uuid, 'Casein Protein Powder', 360.00, 78.00, 6.00, 3.00, 1.50, 3.00, 0.00, 180.00, true),
    (null::uuid, 'Lean Ham (Cooked)', 145.00, 21.00, 1.50, 5.50, 1.80, 0.00, 0.00, 1200.00, true),
    (null::uuid, 'Atlantic Mackerel (Cooked)', 262.00, 24.00, 0.00, 18.00, 4.20, 0.00, 0.00, 90.00, true),
    (null::uuid, 'Sardines (Canned in water)', 208.00, 25.00, 0.00, 11.00, 1.50, 0.00, 0.00, 400.00, true),
    (null::uuid, 'Tempeh', 192.00, 20.00, 7.60, 11.00, 2.20, 0.00, 5.00, 9.00, true),
    (null::uuid, 'Edamame (Boiled)', 121.00, 11.90, 8.90, 5.20, 0.60, 2.20, 5.20, 6.00, true),
    (null::uuid, 'Hummus', 166.00, 8.00, 14.30, 9.60, 1.40, 0.30, 6.00, 379.00, true),
    (null::uuid, 'Greek Yogurt (2%)', 73.00, 9.90, 4.00, 2.00, 1.20, 4.00, 0.00, 50.00, true),
    (null::uuid, 'Cream of Rice (Dry)', 370.00, 7.00, 82.00, 1.00, 0.20, 0.00, 1.00, 5.00, true),
    (null::uuid, 'Bulgur (Cooked)', 83.00, 3.10, 18.60, 0.20, 0.04, 0.10, 4.50, 5.00, true),
    (null::uuid, 'Whole Wheat Pasta (Cooked)', 124.00, 5.30, 26.50, 0.50, 0.10, 0.60, 3.20, 4.00, true),
    (null::uuid, 'Bagel (Plain)', 257.00, 10.00, 50.00, 1.50, 0.30, 5.00, 2.30, 430.00, true),
    (null::uuid, 'Tortilla (Whole Wheat)', 310.00, 8.00, 50.00, 8.00, 1.50, 2.00, 6.00, 520.00, true),
    (null::uuid, 'Dates (Medjool)', 277.00, 1.80, 75.00, 0.20, 0.04, 66.50, 6.70, 1.00, true),
    (null::uuid, 'Dried Cranberries (Unsweetened)', 308.00, 0.10, 82.00, 1.40, 0.10, 65.00, 5.70, 3.00, true),
    (null::uuid, 'Dark Chocolate 85%', 598.00, 12.00, 22.00, 52.00, 32.00, 1.00, 14.00, 20.00, true),
    (null::uuid, 'Tahini', 595.00, 17.00, 21.00, 54.00, 7.60, 0.50, 9.00, 115.00, true),
    (null::uuid, 'Sunflower Seeds', 584.00, 21.00, 20.00, 51.00, 4.50, 2.60, 8.60, 9.00, true),
    (null::uuid, 'Hemp Seeds', 553.00, 31.60, 8.70, 48.80, 4.60, 1.50, 4.00, 5.00, true)
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

notify pgrst, 'reload schema';

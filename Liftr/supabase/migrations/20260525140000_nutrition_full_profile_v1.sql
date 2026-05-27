set local check_function_bodies = off;

alter table public.nutrition_ingredients
  add column if not exists saturated_fat_per_100g numeric(5, 2) not null default 0.00,
  add column if not exists sugars_per_100g numeric(5, 2) not null default 0.00,
  add column if not exists fiber_per_100g numeric(5, 2) not null default 0.00,
  add column if not exists sodium_mg_per_100g numeric(6, 2) not null default 0.00;

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
set
  saturated_fat_per_100g = 0.50,
  fiber_per_100g = 0.00,
  sugars_per_100g = 0.00,
  sodium_mg_per_100g = 65.00
where name = 'Chicken breast (cooked)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.10,
  fiber_per_100g = 0.40,
  sugars_per_100g = 0.10,
  sodium_mg_per_100g = 1.00
where name = 'White rice (cooked)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 3.10,
  fiber_per_100g = 0.00,
  sugars_per_100g = 0.40,
  sodium_mg_per_100g = 142.00
where name = 'Egg (large)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.10,
  fiber_per_100g = 2.60,
  sugars_per_100g = 12.20,
  sodium_mg_per_100g = 1.00
where name = 'Banana' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.00,
  fiber_per_100g = 1.80,
  sugars_per_100g = 0.90,
  sodium_mg_per_100g = 5.00
where name = 'Potato (boiled)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.00,
  fiber_per_100g = 3.30,
  sugars_per_100g = 6.50,
  sodium_mg_per_100g = 36.00
where name = 'Sweet potato (baked)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 13.80,
  fiber_per_100g = 0.00,
  sugars_per_100g = 0.00,
  sodium_mg_per_100g = 2.00
where name = 'Olive oil' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.20,
  fiber_per_100g = 0.00,
  sugars_per_100g = 3.20,
  sodium_mg_per_100g = 36.00
where name = 'Greek yogurt (plain)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 1.20,
  fiber_per_100g = 10.60,
  sugars_per_100g = 0.00,
  sodium_mg_per_100g = 2.00
where name = 'Oats (dry)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 2.50,
  fiber_per_100g = 0.00,
  sugars_per_100g = 0.00,
  sodium_mg_per_100g = 59.00
where name = 'Salmon (cooked)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.10,
  fiber_per_100g = 3.30,
  sugars_per_100g = 1.70,
  sodium_mg_per_100g = 41.00
where name = 'Broccoli (cooked)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.60,
  fiber_per_100g = 6.80,
  sugars_per_100g = 5.00,
  sodium_mg_per_100g = 430.00
where name = 'Whole wheat bread' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.00,
  fiber_per_100g = 2.40,
  sugars_per_100g = 10.40,
  sodium_mg_per_100g = 1.00
where name = 'Apple' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 0.20,
  fiber_per_100g = 1.80,
  sugars_per_100g = 0.60,
  sodium_mg_per_100g = 6.00
where name = 'Pasta (cooked)' and is_public = true;

update public.nutrition_ingredients
set
  saturated_fat_per_100g = 6.00,
  fiber_per_100g = 0.00,
  sugars_per_100g = 0.00,
  sodium_mg_per_100g = 72.00
where name = 'Ground beef (lean, cooked)' and is_public = true;

create or replace function public.nutrition_diary_nutrient_total_v1(
  p_date date,
  p_nutrient text
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_col_ing text;
  v_total numeric;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  v_col_ing := case p_nutrient
    when 'calories' then 'calories_per_100g'
    when 'protein' then 'protein_per_100g'
    when 'carbs' then 'carbs_per_100g'
    when 'fat' then 'fat_per_100g'
    when 'saturated_fat' then 'saturated_fat_per_100g'
    when 'sugars' then 'sugars_per_100g'
    when 'fiber' then 'fiber_per_100g'
    when 'sodium_mg' then 'sodium_mg_per_100g'
    else null
  end;

  if v_col_ing is null then
    raise exception 'invalid nutrient: %', p_nutrient using errcode = '22023';
  end if;

  execute format(
    $q$
    select coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.%I / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.%I / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0)
    from public.nutrition_diary_logs l
    left join public.nutrition_ingredients i on i.id = l.ingredient_id
    where l.user_id = $1
      and l.log_date = $2
    $q$,
    v_col_ing,
    v_col_ing
  )
  into v_total
  using v_uid, p_date;

  return v_total;
end;
$$;

revoke all on function public.nutrition_diary_nutrient_total_v1(date, text) from public;
grant execute on function public.nutrition_diary_nutrient_total_v1(date, text) to authenticated;

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
  v_protein numeric := 0;
  v_carbs numeric := 0;
  v_fat numeric := 0;
  v_saturated_fat numeric := 0;
  v_sugars numeric := 0;
  v_fiber numeric := 0;
  v_sodium_mg numeric := 0;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  v_consumed := public.nutrition_diary_nutrient_total_v1(p_date, 'calories');
  v_protein := public.nutrition_diary_nutrient_total_v1(p_date, 'protein');
  v_carbs := public.nutrition_diary_nutrient_total_v1(p_date, 'carbs');
  v_fat := public.nutrition_diary_nutrient_total_v1(p_date, 'fat');
  v_saturated_fat := public.nutrition_diary_nutrient_total_v1(p_date, 'saturated_fat');
  v_sugars := public.nutrition_diary_nutrient_total_v1(p_date, 'sugars');
  v_fiber := public.nutrition_diary_nutrient_total_v1(p_date, 'fiber');
  v_sodium_mg := public.nutrition_diary_nutrient_total_v1(p_date, 'sodium_mg');

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
    'total_protein_g_consumed', round(v_protein, 1),
    'total_carbs_g_consumed', round(v_carbs, 1),
    'total_fat_g_consumed', round(v_fat, 1),
    'total_saturated_fat_g_consumed', round(v_saturated_fat, 1),
    'total_sugars_g_consumed', round(v_sugars, 1),
    'total_fiber_g_consumed', round(v_fiber, 1),
    'total_sodium_mg_consumed', round(v_sodium_mg, 1),
    'recommendation_text', v_text
  );
end;
$$;

revoke all on function public.get_daily_nutrition_recommendation_v1(date) from public;
grant execute on function public.get_daily_nutrition_recommendation_v1(date) to authenticated;

notify pgrst, 'reload schema';

set local check_function_bodies = off;

create or replace function public.get_smart_nutrition_recommendation_v1(
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_day_count integer;
  v_sex text;
  v_date_of_birth date;
  v_height_cm numeric;
  v_weight_kg numeric;
  v_base_calories integer;
  v_age_years integer;
  v_total_calories numeric := 0;
  v_total_protein numeric := 0;
  v_total_carbs numeric := 0;
  v_total_fat numeric := 0;
  v_total_saturated_fat numeric := 0;
  v_total_sugars numeric := 0;
  v_total_fiber numeric := 0;
  v_total_sodium_mg numeric := 0;
  v_diary_days integer := 0;
  v_avg_calories numeric := 0;
  v_avg_protein numeric := 0;
  v_avg_carbs numeric := 0;
  v_avg_fat numeric := 0;
  v_avg_saturated_fat numeric := 0;
  v_avg_sugars numeric := 0;
  v_avg_fiber numeric := 0;
  v_avg_sodium_mg numeric := 0;
  v_total_burned numeric := 0;
  v_avg_burned numeric := 0;
  v_avg_energy_out numeric := 0;
  v_avg_remaining numeric := 0;
  v_strength_sessions integer := 0;
  v_cardio_sessions integer := 0;
  v_protein_target numeric;
  v_alerts jsonb := '[]'::jsonb;
  v_text text;
  v_period_phrase text;
  v_day_word text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  v_start := p_start_date;
  v_end := p_end_date;
  if v_end < v_start then
    v_start := p_end_date;
    v_end := p_start_date;
  end if;
  if (v_end - v_start) > 69 then
    v_end := v_start + 69;
  end if;

  v_day_count := greatest(1, (v_end - v_start) + 1);
  v_day_word := case when v_day_count = 1 then 'day' else 'days' end;

  if v_start = v_end then
    v_period_phrase := 'on ' || to_char(v_start, 'FMMonth FMDD, YYYY');
  elsif v_day_count <= 7 then
    v_period_phrase := format(
      'over %s %s (%s – %s)',
      v_day_count,
      v_day_word,
      to_char(v_start, 'Mon DD'),
      to_char(v_end, 'Mon DD, YYYY')
    );
  else
    v_period_phrase := format(
      'over %s %s, from %s to %s',
      v_day_count,
      v_day_word,
      to_char(v_start, 'Mon DD, YYYY'),
      to_char(v_end, 'Mon DD, YYYY')
    );
  end if;

  select
    p.sex,
    p.date_of_birth,
    p.height_cm,
    p.weight_kg,
    coalesce(p.base_calories_target, 2000)
  into v_sex, v_date_of_birth, v_height_cm, v_weight_kg, v_base_calories
  from public.profiles p
  where p.user_id = v_uid;

  if v_date_of_birth is not null then
    v_age_years := extract(year from age(current_date, v_date_of_birth))::integer;
  end if;

  select
    coalesce(sum(
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
    ), 0),
    coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.protein_per_100g / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.protein_per_100g / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0),
    coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.carbs_per_100g / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.carbs_per_100g / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0),
    coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.fat_per_100g / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.fat_per_100g / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0),
    coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.saturated_fat_per_100g / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.saturated_fat_per_100g / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0),
    coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.sugars_per_100g / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.sugars_per_100g / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0),
    coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.fiber_per_100g / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.fiber_per_100g / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0),
    coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.sodium_mg_per_100g / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.sodium_mg_per_100g / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0),
    count(distinct l.log_date)
  into
    v_total_calories,
    v_total_protein,
    v_total_carbs,
    v_total_fat,
    v_total_saturated_fat,
    v_total_sugars,
    v_total_fiber,
    v_total_sodium_mg,
    v_diary_days
  from public.nutrition_diary_logs l
  left join public.nutrition_ingredients i on i.id = l.ingredient_id
  where l.user_id = v_uid
    and l.log_date between v_start and v_end;

  v_avg_calories := v_total_calories / v_day_count;
  v_avg_protein := v_total_protein / v_day_count;
  v_avg_carbs := v_total_carbs / v_day_count;
  v_avg_fat := v_total_fat / v_day_count;
  v_avg_saturated_fat := v_total_saturated_fat / v_day_count;
  v_avg_sugars := v_total_sugars / v_day_count;
  v_avg_fiber := v_total_fiber / v_day_count;
  v_avg_sodium_mg := v_total_sodium_mg / v_day_count;

  select coalesce(sum(w.calories_kcal), 0)
  into v_total_burned
  from public.workouts w
  where w.user_id = v_uid
    and w.state = 'published'
    and coalesce(w.started_at, w.created_at)::date between v_start and v_end
    and w.calories_kcal is not null
    and w.calories_kcal > 0;

  v_avg_burned := v_total_burned / v_day_count;
  v_avg_energy_out := v_base_calories + v_avg_burned;
  v_avg_remaining := v_avg_energy_out - v_avg_calories;

  select
    count(*) filter (where lower(coalesce(w.kind::text, '')) = 'strength'),
    count(*) filter (where lower(coalesce(w.kind::text, '')) = 'cardio')
  into v_strength_sessions, v_cardio_sessions
  from public.workouts w
  where w.user_id = v_uid
    and w.state = 'published'
    and coalesce(w.started_at, w.created_at)::date between v_start and v_end;

  v_protein_target := 1.6 * coalesce(v_weight_kg, 70);

  if v_avg_protein < v_protein_target then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Your daily protein intake averaged %sg, which is below the recommended 1.6g/kg required for athletic muscle recovery. Consider increasing intake of lean poultry, fish, egg whites, or high-protein dairy.',
        round(v_avg_protein, 0)::text
      )
    );
  end if;

  if v_avg_sodium_mg > 2300 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Your daily sodium intake averaged %s mg, above the 2300 mg guideline. Consider reducing processed foods and added salt.',
        round(v_avg_sodium_mg, 0)::text
      )
    );
  end if;

  if v_avg_sugars > 50 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Your daily sugar intake averaged %s g, above the 50 g daily reference. Favor whole foods and limit sugary drinks and desserts.',
        round(v_avg_sugars, 0)::text
      )
    );
  end if;

  if v_strength_sessions > v_cardio_sessions then
    v_alerts := v_alerts || jsonb_build_array(
      'Strength training dominant phase detected. Ensure carbohydrate timing is centered around workouts to maximize glycogen replenishment.'
    );
  end if;

  if v_diary_days = 0 then
    v_text := format(
      'We did not find meals logged %s. Log breakfast, lunch, dinner, or snacks to unlock personalized recovery insights.',
      v_period_phrase
    );
  elsif v_avg_remaining > 150 then
    v_text := format(
      '%s you averaged about %s kcal from food and %s kcal from workouts per day. With your %s kcal daily target (metabolism + activity), you had roughly %s kcal left in your energy budget on average — flexibility for recovery meals when you need them. You logged food on %s of %s %s.',
      initcap(v_period_phrase),
      round(v_avg_calories, 0)::text,
      round(v_avg_burned, 0)::text,
      round(v_base_calories, 0)::text,
      round(v_avg_remaining, 0)::text,
      v_diary_days,
      v_day_count,
      v_day_word
    );
  elsif v_avg_remaining < -150 then
    v_text := format(
      '%s you averaged about %s kcal from food and %s kcal from workouts per day. Versus your %s kcal daily target, you were about %s kcal over your energy budget on average — consider lighter portions or more activity if you are aiming for maintenance. You logged food on %s of %s %s.',
      initcap(v_period_phrase),
      round(v_avg_calories, 0)::text,
      round(v_avg_burned, 0)::text,
      round(v_base_calories, 0)::text,
      round(abs(v_avg_remaining), 0)::text,
      v_diary_days,
      v_day_count,
      v_day_word
    );
  else
    v_text := format(
      '%s you averaged about %s kcal from food and %s kcal from workouts per day — close to your %s kcal daily target (metabolism + activity). Your intake and energy budget look well balanced. You logged food on %s of %s %s.',
      initcap(v_period_phrase),
      round(v_avg_calories, 0)::text,
      round(v_avg_burned, 0)::text,
      round(v_base_calories, 0)::text,
      v_diary_days,
      v_day_count,
      v_day_word
    );
  end if;

  if v_weight_kg is null and v_diary_days > 0 then
    v_text := v_text || ' Protein tips use a 70 kg reference until you add your weight on your profile.';
  end if;

  return jsonb_build_object(
    'recommendation_text', v_text,
    'alerts', v_alerts,
    'avg_daily_consumed_kcal', round(v_avg_calories, 1),
    'avg_daily_burned_kcal', round(v_avg_burned, 1),
    'base_calories_target', v_base_calories,
    'avg_daily_energy_out', round(v_avg_energy_out, 1),
    'avg_daily_remaining_budget', round(v_avg_remaining, 1)
  );
end;
$$;

notify pgrst, 'reload schema';

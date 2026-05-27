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
  v_strength_sessions integer := 0;
  v_cardio_sessions integer := 0;
  v_protein_target numeric;
  v_net_vs_activity numeric;
  v_alerts jsonb := '[]'::jsonb;
  v_text text;
  v_profile_bits text := '';
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

  select
    count(*) filter (where lower(coalesce(w.kind::text, '')) = 'strength'),
    count(*) filter (where lower(coalesce(w.kind::text, '')) = 'cardio')
  into v_strength_sessions, v_cardio_sessions
  from public.workouts w
  where w.user_id = v_uid
    and w.state = 'published'
    and coalesce(w.started_at, w.created_at)::date between v_start and v_end;

  v_protein_target := 1.6 * coalesce(v_weight_kg, 70);
  v_net_vs_activity := v_avg_calories - v_avg_burned;

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

  if v_age_years is not null then
    v_profile_bits := v_profile_bits || format(' Age %s.', v_age_years);
  end if;
  if v_sex is not null and btrim(v_sex) <> '' and lower(v_sex) <> 'prefer_not_to_say' then
    v_profile_bits := v_profile_bits || format(' Sex: %s.', initcap(replace(v_sex, '_', ' ')));
  end if;
  if v_base_calories is not null then
    v_profile_bits := v_profile_bits || format(' Daily calorie target: %s kcal.', v_base_calories);
  end if;

  if v_diary_days = 0 then
    v_text := format(
      'From %s to %s (%s days), no food was logged in your nutrition diary. Log meals consistently to unlock personalized macro and recovery insights.%s',
      to_char(v_start, 'Mon DD, YYYY'),
      to_char(v_end, 'Mon DD, YYYY'),
      v_day_count,
      v_profile_bits
    );
  else
    if v_net_vs_activity > 50 then
      v_text := format(
        'From %s to %s (%s days), you averaged %s kcal/day consumed and %s kcal/day burned from workouts — a %s kcal/day surplus versus activity. You logged food on %s of %s days.%s',
        to_char(v_start, 'Mon DD, YYYY'),
        to_char(v_end, 'Mon DD, YYYY'),
        v_day_count,
        round(v_avg_calories, 0)::text,
        round(v_avg_burned, 0)::text,
        round(v_net_vs_activity, 0)::text,
        v_diary_days,
        v_day_count,
        v_profile_bits
      );
    elsif v_net_vs_activity < -50 then
      v_text := format(
        'From %s to %s (%s days), you averaged %s kcal/day consumed and %s kcal/day burned from workouts — a %s kcal/day deficit versus activity. You logged food on %s of %s days.%s',
        to_char(v_start, 'Mon DD, YYYY'),
        to_char(v_end, 'Mon DD, YYYY'),
        v_day_count,
        round(v_avg_calories, 0)::text,
        round(v_avg_burned, 0)::text,
        round(abs(v_net_vs_activity), 0)::text,
        v_diary_days,
        v_day_count,
        v_profile_bits
      );
    else
      v_text := format(
        'From %s to %s (%s days), you averaged %s kcal/day consumed and %s kcal/day burned from workouts — intake and activity are closely balanced. You logged food on %s of %s days.%s',
        to_char(v_start, 'Mon DD, YYYY'),
        to_char(v_end, 'Mon DD, YYYY'),
        v_day_count,
        round(v_avg_calories, 0)::text,
        round(v_avg_burned, 0)::text,
        v_diary_days,
        v_day_count,
        v_profile_bits
      );
    end if;

    if v_weight_kg is null then
      v_text := v_text || ' Protein guidance used a 70 kg reference because weight is not set on your profile.';
    end if;
  end if;

  return jsonb_build_object(
    'recommendation_text', v_text,
    'alerts', v_alerts,
    'avg_daily_consumed_kcal', round(v_avg_calories, 1),
    'avg_daily_burned_kcal', round(v_avg_burned, 1)
  );
end;
$$;

revoke all on function public.get_smart_nutrition_recommendation_v1(date, date) from public;
grant execute on function public.get_smart_nutrition_recommendation_v1(date, date) to authenticated;

notify pgrst, 'reload schema';

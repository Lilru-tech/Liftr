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
  v_weight_ref numeric;
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
  v_net_deficit numeric := 0;
  v_logging_adherence numeric := 0;
  v_strength_sessions integer := 0;
  v_endurance_sessions integer := 0;
  v_strength_per_week numeric := 0;
  v_endurance_per_week numeric := 0;
  v_carb_target_g numeric := 0;
  v_protein_target_g numeric := 0;
  v_total_training_sessions integer := 0;
  v_alerts jsonb := '[]'::jsonb;
  v_text text;
  v_opening text;
  v_priority text;
  v_recovery text;
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
    v_period_phrase := 'on ' || to_char(v_start, 'Mon DD, YYYY');
  elsif v_day_count <= 7 then
    v_period_phrase := format(
      'over the last %s %s (%s – %s)',
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
    p.sex::text,
    p.date_of_birth,
    p.height_cm::numeric,
    p.weight_kg
  into v_sex, v_date_of_birth, v_height_cm, v_weight_kg
  from public.profiles p
  where p.user_id = v_uid;

  v_weight_ref := coalesce(nullif(v_weight_kg, 0), 70);
  v_carb_target_g := 2.5 * v_weight_ref;
  v_protein_target_g := 1.8 * v_weight_ref;

  v_base_calories := coalesce(
    public.nutrition_resolve_base_calories_target_v1(v_uid),
    public.nutrition_demographic_fallback_kcal_v1(v_sex)
  );

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
  v_net_deficit := abs(least(v_avg_remaining, 0));
  v_logging_adherence := v_diary_days::numeric / v_day_count;

  select
    count(*) filter (where w.kind = 'strength'::public.workout_kind),
    count(*) filter (where w.kind in ('cardio'::public.workout_kind, 'sport'::public.workout_kind))
  into v_strength_sessions, v_endurance_sessions
  from public.workouts w
  where w.user_id = v_uid
    and w.state = 'published'
    and coalesce(w.started_at, w.created_at)::date between v_start and v_end;

  v_strength_per_week := v_strength_sessions::numeric * 7.0 / v_day_count;
  v_endurance_per_week := v_endurance_sessions::numeric * 7.0 / v_day_count;
  v_total_training_sessions := v_strength_sessions + v_endurance_sessions;

  if v_avg_remaining < -750 and v_avg_burned > 500 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        '🚨 Critical energy deficit detected. You are burning %s kcal but only consuming %s kcal. A prolonged daily deficit of %s kcal at this training volume can cause chronic fatigue, muscle loss, and a sharp drop in performance.',
        round(v_avg_energy_out, 0)::text,
        round(v_avg_calories, 0)::text,
        round(v_net_deficit, 0)::text
      )
    );
  end if;

  if v_avg_sodium_mg > 4500 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Elevated sodium: your daily average of %s mg exceeds the 4500 mg safety limit. Cut back on ultra-processed foods and consult a professional if it persists.',
        round(v_avg_sodium_mg, 0)::text
      )
    );
  elsif v_avg_burned >= 600
    and v_avg_sodium_mg > 2300
    and v_avg_sodium_mg <= 4500 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Your sodium intake is high (%s mg), but it aligns with your high sweat rate from physical activity (%s kcal). Make sure to pair it with consistent hydration to replenish electrolytes.',
        round(v_avg_sodium_mg, 0)::text,
        round(v_avg_burned, 0)::text
      )
    );
  elsif v_avg_sodium_mg > 2300 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Your average sodium intake (%s mg/day) exceeds the 2300 mg reference. Reduce processed foods and added salt unless your training load warrants extra electrolytes.',
        round(v_avg_sodium_mg, 0)::text
      )
    );
  end if;

  if v_endurance_per_week > 3 and v_avg_carbs < v_carb_target_g then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Low fuel for endurance. Your log shows frequent hybrid training but moderate carbohydrate intake (%sg). Consider increasing complex carbs before high-demand sessions.',
        round(v_avg_carbs, 0)::text
      )
    );
  end if;

  if v_strength_per_week > 2 and v_avg_protein < v_protein_target_g then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Muscle recovery at risk. You train strength regularly, but your protein intake (%sg) is below the optimal 1.8g/kg threshold for your current weight. Increase protein sources to protect muscle mass.',
        round(v_avg_protein, 0)::text
      )
    );
  end if;

  if v_avg_sugars > 50 and v_avg_fiber < 20 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Refined carbohydrate pattern detected. Your daily sugar intake is high (%sg) compared to your fiber intake (%sg). Prioritize complex, whole-food carbs (legumes, oats, vegetables) to improve satiety and keep energy levels stable.',
        round(v_avg_sugars, 0)::text,
        round(v_avg_fiber, 0)::text
      )
    );
  end if;

  if v_logging_adherence < 0.75 then
    v_alerts := jsonb_build_array(
      format(
        'Inconsistent logging. You completed the nutrition diary on less than 75%% of selected days (%s of %s %s, %s%%). Daily averages and these recommendations may be skewed due to missing data.',
        v_diary_days,
        v_day_count,
        v_day_word,
        round(100.0 * v_logging_adherence, 0)::text
      )
    ) || v_alerts;
  end if;

  if v_diary_days = 0 then
    v_opening := format(
      'We did not find meals logged %s. Log breakfast, lunch, dinner, or snacks to unlock personalized recovery insights.',
      v_period_phrase
    );
    v_priority := '';
    v_recovery := '';
  elsif v_logging_adherence >= 0.75 then
    v_opening := format(
      'Great job keeping a consistent nutrition log %s (%s of %s %s).',
      v_period_phrase,
      v_diary_days,
      v_day_count,
      v_day_word
    );
    if v_total_training_sessions > 0 then
      v_opening := v_opening || format(
        ' You completed %s published workouts in this period, which gives solid context to fine-tune your nutrition.',
        v_total_training_sessions
      );
    else
      v_opening := v_opening || ' Keep logging your training sessions to refine fuel and recovery recommendations.';
    end if;
  else
    v_opening := format(
      'You logged meals on %s of %s %s %s. The more days you complete the diary, the more accurate your averages and alerts will be.',
      v_diary_days,
      v_day_count,
      v_day_word,
      v_period_phrase
    );
  end if;

  if v_diary_days > 0 then
    if v_avg_remaining < -750 and v_avg_burned > 500 then
      v_priority := format(
        'Your immediate priority is closing the energy deficit: you average %s kcal consumed versus an estimated %s kcal burned (metabolism + activity). Increase calorie intake progressively on intense training days.',
        round(v_avg_calories, 0)::text,
        round(v_avg_energy_out, 0)::text
      );
    elsif v_endurance_per_week > 3 and v_avg_carbs < v_carb_target_g then
      v_priority := format(
        'Prioritize complex carbs: with frequent endurance training, your average of %sg/day is below the %sg target (2.5 g/kg). Replenish glycogen before Hyrox, padel, or demanding cardio sessions.',
        round(v_avg_carbs, 0)::text,
        round(v_carb_target_g, 0)::text
      );
    elsif v_strength_per_week > 2 and v_avg_protein < v_protein_target_g then
      v_priority := format(
        'Increase daily protein: with regular strength training, aim for at least %sg/day (1.8 g/kg); your current average is %sg.',
        round(v_protein_target_g, 0)::text,
        round(v_avg_protein, 0)::text
      );
    elsif v_avg_sugars > 50 and v_avg_fiber < 20 then
      v_priority := format(
        'Improve carbohydrate quality: cut added sugars (average %sg) and raise fiber toward at least 20–25 g/day (currently %sg).',
        round(v_avg_sugars, 0)::text,
        round(v_avg_fiber, 0)::text
      );
    elsif v_avg_sodium_mg > 4500 then
      v_priority := format(
        'Manage sodium: your average of %s mg/day exceeds safe levels; prioritize whole foods and minimize ultra-processed products.',
        round(v_avg_sodium_mg, 0)::text
      );
    elsif v_avg_remaining > 300 then
      v_priority := format(
        'Your energy balance leaves an average surplus of %s kcal/day versus your target + activity. If you are aiming for maintenance or performance, review portions or distribute those calories in pre/post-workout meals instead of accumulating them without a plan.',
        round(v_avg_remaining, 0)::text
      );
    else
      v_priority := format(
        'Your average intake (%s kcal/day) aligns with your estimated expenditure (%s kcal/day, metabolism + training). Stay consistent and adjust macros based on your dominant training modality this week.',
        round(v_avg_calories, 0)::text,
        round(v_avg_energy_out, 0)::text
      );
    end if;

    if v_strength_per_week > v_endurance_per_week then
      v_recovery := format(
        'After strength sessions, prioritize 25–40 g of protein within 2 hours and spread ~%s g of protein across the day to support muscle protein synthesis.',
        round(v_protein_target_g, 0)::text
      );
    elsif v_endurance_per_week > v_strength_per_week then
      v_recovery := format(
        'With cardio and sport predominant, aim for 1–1.2 g/kg of carbohydrates (~%s–%s g) within 2 hours post-workout and add complex carbs 2–3 hours before high-demand sessions.',
        round(v_weight_ref * 1.0, 0)::text,
        round(v_weight_ref * 1.2, 0)::text
      );
    elsif v_total_training_sessions > 0 then
      v_recovery := format(
        'Combine hybrid recovery: moderate-to-high protein (~%s g/day) around strength work and complex carbohydrates (~%s g) timed around your hardest sessions.',
        round(v_protein_target_g, 0)::text,
        round(v_carb_target_g, 0)::text
      );
    else
      v_recovery := 'When you resume training, sync post-strength protein and complex pre/post-cardio carbs to optimize recovery.';
    end if;
  end if;

  v_text := trim(both from concat_ws(
    E'\n\n',
    nullif(v_opening, ''),
    nullif(v_priority, ''),
    nullif(v_recovery, '')
  ));

  if v_weight_kg is null and v_diary_days > 0 then
    v_text := v_text || E'\n\n' || 'Protein and carbohydrate thresholds use a 70 kg reference until you add your weight on your profile.';
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

revoke all on function public.get_smart_nutrition_recommendation_v1(date, date) from public;
grant execute on function public.get_smart_nutrition_recommendation_v1(date, date) to authenticated;

notify pgrst, 'reload schema';

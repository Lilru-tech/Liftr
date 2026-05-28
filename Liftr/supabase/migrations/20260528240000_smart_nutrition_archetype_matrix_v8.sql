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
  v_avg_burned numeric := 0;
  v_avg_energy_out numeric := 0;
  v_avg_remaining numeric := 0;
  v_net_balance numeric := 0;
  v_abs_deficit numeric := 0;
  v_intense_day_count integer := 0;
  v_intense_days_per_week numeric := 0;
  v_days_logged_ratio numeric := 0;
  v_carb_target_g numeric := 0;
  v_protein_target_g numeric := 0;
  v_archetype text;
  v_critical_underfuel boolean := false;
  v_alerts jsonb := '[]'::jsonb;
  v_text text;
  v_critical_prefix text := '';
  v_archetype_body text := '';
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
  v_days_logged_ratio := v_diary_days::numeric / v_day_count;

  select coalesce(avg(daily_kcal), 0)
  into v_avg_burned
  from (
    select
      gs.day::date as workout_day,
      coalesce((
        select sum(w.calories_kcal)
        from public.workouts w
        where w.user_id = v_uid
          and w.state = 'published'::public.workout_state
          and coalesce(w.started_at, w.created_at)::date = gs.day::date
          and w.calories_kcal is not null
          and w.calories_kcal > 0
      ), 0)::numeric as daily_kcal
    from generate_series(v_start::timestamp, v_end::timestamp, interval '1 day') as gs(day)
  ) daily_burn;

  select count(distinct date(coalesce(w.started_at, w.created_at)))
  into v_intense_day_count
  from public.workouts w
  where w.user_id = v_uid
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at)::date between v_start and v_end
    and (
      w.kind in ('strength'::public.workout_kind, 'sport'::public.workout_kind)
      or (
        w.kind = 'cardio'::public.workout_kind
        and coalesce(w.title, '') not ilike '%walk%'
        and coalesce(w.title, '') not ilike '%caminata%'
      )
    );

  v_intense_days_per_week := v_intense_day_count::numeric * 7.0 / v_day_count;
  v_avg_energy_out := v_base_calories + v_avg_burned;
  v_net_balance := v_avg_calories - v_avg_energy_out;
  v_avg_remaining := -v_net_balance;
  v_abs_deficit := abs(least(v_net_balance, 0));

  if v_intense_days_per_week >= 4.5 and v_avg_burned >= 600 then
    v_archetype := 'hybrid_athlete';
  elsif v_intense_days_per_week >= 1.5 then
    v_archetype := 'active_fitness';
  else
    v_archetype := 'sedentary_tracker';
  end if;

  if v_avg_sodium_mg > 4500 then
    v_alerts := v_alerts || jsonb_build_array(
      format(
        'Elevated sodium: your daily average of %s mg exceeds the 4500 mg safety limit. Cut back on ultra-processed foods and consult a professional if it persists.',
        round(v_avg_sodium_mg, 0)::text
      )
    );
  end if;

  if v_archetype = 'hybrid_athlete' then
    if v_avg_sodium_mg > 2300 and v_avg_sodium_mg <= 4500 then
      v_alerts := v_alerts || jsonb_build_array(
        format(
          'Your sodium intake (%s mg) is high, but it is balanced with your high sweat rate from exercise (%s kcal). Prioritize consistent electrolyte replenishment.',
          round(v_avg_sodium_mg, 0)::text,
          round(v_avg_burned, 0)::text
        )
      );
    end if;

    if v_avg_carbs < v_carb_target_g then
      v_alerts := v_alerts || jsonb_build_array(
        format(
          'Low fuel for performance. Your average carbohydrate intake (%sg) is below the %sg target (2.5 g/kg). Replenish glycogen and aim for 1-1.2 g/kg of carbohydrates exclusively in your post-workout meal window within 2 hours.',
          round(v_avg_carbs, 0)::text,
          round(v_carb_target_g, 0)::text
        )
      );
    end if;
  elsif v_archetype = 'active_fitness' then
    if v_avg_protein < v_protein_target_g then
      v_alerts := v_alerts || jsonb_build_array(
        format(
          'Muscle recovery at risk. You train regularly but your average protein intake (%sg) is below the optimal 1.8g/kg threshold for your weight. Increase protein sources to support your training.',
          round(v_avg_protein, 0)::text
        )
      );
    end if;
  elsif v_archetype = 'sedentary_tracker' then
    if v_avg_sodium_mg > 2300 then
      v_alerts := v_alerts || jsonb_build_array(
        format(
          'Your average sodium intake (%s mg/day) exceeds the 2300 mg reference. Reduce processed foods and added salt to support cardiovascular health and metabolic control.',
          round(v_avg_sodium_mg, 0)::text
        )
      );
    end if;

    if v_avg_sugars > 50 and v_avg_fiber < 20 then
      v_alerts := v_alerts || jsonb_build_array(
        format(
          'Refined carbohydrate pattern detected. Your daily sugar intake is high (%sg) relative to low fiber (%sg). Prioritize oats, legumes, and vegetables to improve satiety and insulin response.',
          round(v_avg_sugars, 0)::text,
          round(v_avg_fiber, 0)::text
        )
      );
    end if;
  end if;

  if v_net_balance <= -750 and v_intense_days_per_week >= 1.5 then
    v_critical_underfuel := true;
    v_alerts := v_alerts || jsonb_build_array(
      format(
        '🚨 Underfueling alert: Your body is operating with a severe deficit of %s kcal/day against a high active training volume. Urgently increase your structured calorie intake.',
        round(v_abs_deficit, 0)::text
      )
    );
    v_critical_prefix := format(
      'Underfueling alert: Your body is operating under a severe deficit of %s kcal/day against a high active training volume. It is urgent to increase your structured calorie intake to protect your muscle mass and overall health.',
      round(v_abs_deficit, 0)::text
    );
  end if;

  if v_days_logged_ratio < 0.75 then
    v_alerts := jsonb_build_array(
      'Inconsistent logging. You completed the nutrition diary on less than 75% of the days in the selected range. Calculated averages and these recommendations may be skewed.'
    ) || v_alerts;
  end if;

  if v_diary_days = 0 then
    v_text := format(
      'We did not find meals logged %s. Log breakfast, lunch, dinner, or snacks to unlock personalized recommendations.',
      v_period_phrase
    );
  else
    if v_days_logged_ratio >= 0.75 then
      v_archetype_body := format(
        'Great job keeping a consistent log %s (%s of %s %s).',
        v_period_phrase,
        v_diary_days,
        v_day_count,
        v_day_word
      );
    else
      v_archetype_body := format(
        'You logged meals on %s of %s %s %s.',
        v_diary_days,
        v_day_count,
        v_day_word,
        v_period_phrase
      );
    end if;

    if v_archetype = 'hybrid_athlete' then
      v_archetype_body := v_archetype_body || E'\n\n'
        || 'Your profile matches a high-performance hybrid athlete: prioritize metabolic refueling for your workload, hydration with electrolytes, and carbohydrates to sustain glycogen.';
      if v_avg_carbs < v_carb_target_g then
        v_archetype_body := v_archetype_body || ' '
          || format(
            'Increase complex carbohydrates toward %sg/day and aim for 1-1.2 g/kg of carbohydrates exclusively in your post-workout meal window within 2 hours.',
            round(v_carb_target_g, 0)::text
          );
      end if;
    elsif v_archetype = 'active_fitness' then
      v_archetype_body := v_archetype_body || E'\n\n'
        || 'Your profile reflects active fitness and recomposition: focus on muscle recovery and a structured balance of quality protein, carbohydrates, and fats.';
      if v_avg_protein < v_protein_target_g then
        v_archetype_body := v_archetype_body || ' '
          || format(
            'Aim for at least %sg of daily protein (1.8 g/kg) to support your training.',
            round(v_protein_target_g, 0)::text
          );
      end if;
    else
      v_archetype_body := v_archetype_body || E'\n\n'
        || 'Your profile aligns with health tracking and maintenance: prioritize calorie control, satiety, and sustainable habits for metabolic longevity.';
      if v_avg_sugars > 50 and v_avg_fiber < 20 then
        v_archetype_body := v_archetype_body || ' '
          || 'Replace added sugars with fiber from whole foods (oats, legumes, vegetables).';
      elsif v_avg_sodium_mg > 2300 then
        v_archetype_body := v_archetype_body || ' '
          || 'Moderate sodium by prioritizing whole foods and minimizing ultra-processed products.';
      end if;
    end if;

    v_text := trim(both from concat_ws(
      E'\n\n',
      nullif(v_critical_prefix, ''),
      nullif(v_archetype_body, '')
    ));
  end if;

  if v_weight_kg is null and v_diary_days > 0 then
    v_text := v_text || E'\n\n'
      || 'Protein and carbohydrate thresholds use a 70 kg reference until you add your weight on your profile.';
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

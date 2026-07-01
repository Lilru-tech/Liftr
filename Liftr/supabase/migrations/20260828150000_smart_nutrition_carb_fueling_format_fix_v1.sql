set local check_function_bodies = off;

create or replace function public.nutrition_smart_recommendation_compute_v2(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_start date;
  v_end date;
  v_day_count integer;
  v_sex text;
  v_date_of_birth date;
  v_height_cm numeric;
  v_weight_kg numeric;
  v_weight_ref numeric;
  v_nutrition_goal text := 'maintain';
  v_base_calories integer;
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
  v_alerts jsonb := '[]'::jsonb;
  v_insights jsonb := '[]'::jsonb;
  v_text text;
  v_critical_prefix text := '';
  v_archetype_body text := '';
  v_period_phrase text;
  v_day_word text;
  v_meal_slots jsonb;
  v_training_split jsonb;
  v_weight_trend jsonb;
  v_logging_quality jsonb;
  v_sodium_foods jsonb;
  v_sugar_foods jsonb;
  v_top_slot text;
  v_top_slot_share numeric := 0;
  v_breakfast_days integer := 0;
  v_training_carbs numeric := 0;
  v_rest_carbs numeric := 0;
  v_training_days integer := 0;
  v_rest_days integer := 0;
  v_weekday_avg numeric := 0;
  v_weekend_avg numeric := 0;
  v_kcal_stddev numeric := 0;
  v_food1 text;
  v_food2 text;
  v_share1 numeric := 0;
  v_share2 numeric := 0;
  v_repeat_food text;
  v_repeat_count integer := 0;
  v_weight_interp text;
  c_food_underfuel_fats constant text := ' Incorporate healthy, nutrient-dense fats to close this gap without feeling overly full; prioritize foods like whole avocados, raw nuts (almonds, walnuts), pure nut butters, extra virgin olive oil, and fatty fish like salmon.';
  c_food_protein_sources constant text := ' Focus on lean, bioavailable protein sources throughout your day. Excellent choices include skinless chicken or turkey breast, egg whites, unsweetened Greek yogurt, cottage cheese, lentils, tuna, and lean beef cuts.';
  c_food_complex_carbs constant text := ' Fuel your high-demand training sessions by focusing on clean, complex carbohydrates. Optimize your glycogen restoration by adding whole rolled oats, sweet potatoes, brown or basmati rice, quinoa, bananas, and blueberries to your pre and post-workout meals.';
  c_food_fiber_swaps constant text := ' Action steps: Swap processed snacks or sugary desserts for whole fresh fruits (like raspberries or apples). Increase your daily fiber intake by adding chia seeds, flaxseeds, lentils, chickpeas, oats, and green vegetables like broccoli to your main meals to stabilize insulin and energy levels.';
  c_food_sodium_reduction constant text := ' Reduction strategy: Strictly limit ultra-processed items, packaged snacks, and commercial broths. When cooking at home, drastically cut added table salt and enhance flavor using natural alternatives like garlic powder, onion flakes, lemon juice, and fresh herbs or spices (oregano, cumin, paprika).';
begin
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
    p.weight_kg,
    coalesce(nullif(p.nutrition_goal, ''), 'maintain')
  into v_sex, v_date_of_birth, v_height_cm, v_weight_kg, v_nutrition_goal
  from public.profiles p
  where p.user_id = p_user_id;

  v_weight_ref := coalesce(nullif(v_weight_kg, 0), 70);
  v_carb_target_g := 2.5 * v_weight_ref;
  v_protein_target_g := 1.8 * v_weight_ref;

  v_base_calories := coalesce(
    public.nutrition_resolve_base_calories_target_v1(p_user_id),
    public.nutrition_demographic_fallback_kcal_v1(v_sex)
  );

  select
    coalesce(sum(kcal), 0),
    coalesce(sum(protein_g), 0),
    coalesce(sum(carbs_g), 0),
    coalesce(sum(fat_g), 0),
    coalesce(sum(saturated_fat_g), 0),
    coalesce(sum(sugars_g), 0),
    coalesce(sum(fiber_g), 0),
    coalesce(sum(sodium_mg), 0),
    count(distinct log_date)
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
  from public.nutrition_log_metrics_v1(p_user_id, v_start, v_end);

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
        where w.user_id = p_user_id
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
  where w.user_id = p_user_id
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at)::date between v_start and v_end
    and public.nutrition_is_intense_workout_v1(w.kind, w.title);

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

  v_meal_slots := public.nutrition_meal_slot_summary_v1(p_user_id, v_start, v_end);
  v_training_split := public.nutrition_training_rest_split_v1(p_user_id, v_start, v_end);
  v_weight_trend := public.nutrition_weight_trend_v1(p_user_id, v_start, v_end);
  v_logging_quality := public.nutrition_logging_quality_v1(p_user_id, v_start, v_end);
  v_sodium_foods := public.nutrition_top_food_contributors_v1(p_user_id, v_start, v_end, 'sodium_mg', 3);
  v_sugar_foods := public.nutrition_top_food_contributors_v1(p_user_id, v_start, v_end, 'sugars', 2);

  v_training_carbs := coalesce((v_training_split->'training_day_avg'->>'carbs_g')::numeric, 0);
  v_rest_carbs := coalesce((v_training_split->'rest_day_avg'->>'carbs_g')::numeric, 0);
  v_training_days := coalesce((v_training_split->'training_day_avg'->>'days')::integer, 0);
  v_rest_days := coalesce((v_training_split->'rest_day_avg'->>'days')::integer, 0);
  v_weight_interp := coalesce(v_weight_trend->>'interpretation', 'unknown');

  select x->>'meal_slot', (x->>'kcal_share_percent')::numeric
  into v_top_slot, v_top_slot_share
  from jsonb_array_elements(v_meal_slots) x
  order by (x->>'kcal_share_percent')::numeric desc nulls last
  limit 1;

  select coalesce(max((x->>'log_days')::integer), 0)
  into v_breakfast_days
  from jsonb_array_elements(v_meal_slots) x
  where x->>'meal_slot' = 'Breakfast';

  select
    round(avg(case when extract(isodow from log_date) <= 5 then day_kcal end), 1),
    round(avg(case when extract(isodow from log_date) >= 6 then day_kcal end), 1),
    round(stddev_pop(day_kcal), 1)
  into v_weekday_avg, v_weekend_avg, v_kcal_stddev
  from (
    select log_date, sum(kcal) as day_kcal
    from public.nutrition_log_metrics_v1(p_user_id, v_start, v_end)
    group by log_date
  ) daily;

  if v_diary_days = 0 then
    v_text := format(
      'We did not find meals logged %s. Log breakfast, lunch, dinner, or snacks to unlock personalized recommendations.',
      v_period_phrase
    );
    return jsonb_build_object(
      'recommendation_text', v_text,
      'alerts', '[]'::jsonb,
      'insights', '[]'::jsonb,
      'nutrition_goal', v_nutrition_goal,
      'archetype', v_archetype,
      'avg_daily_consumed_kcal', 0,
      'avg_daily_burned_kcal', round(v_avg_burned, 1),
      'base_calories_target', v_base_calories,
      'avg_daily_energy_out', round(v_avg_energy_out, 1),
      'avg_daily_remaining_budget', round(v_avg_remaining, 1),
      'training_day_avg', v_training_split->'training_day_avg',
      'rest_day_avg', v_training_split->'rest_day_avg',
      'weight_trend', v_weight_trend,
      'meal_slot_summary', v_meal_slots,
      'logging_quality', v_logging_quality
    );
  end if;

  if v_avg_protein >= v_protein_target_g and v_archetype in ('hybrid_athlete', 'active_fitness') then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'protein_on_target',
      'category', 'positive',
      'sentiment', 'positive',
      'priority', 75,
      'title', 'Strong protein consistency',
      'body', format(
        'You average %sg of protein per day (%sg/kg). That supports muscle recovery for your %s training load.',
        round(v_avg_protein, 0)::text,
        round(v_avg_protein / v_weight_ref, 1)::text,
        replace(v_archetype, '_', ' ')
      ),
      'metadata', jsonb_build_object('avg_protein_g', round(v_avg_protein, 1), 'target_g', round(v_protein_target_g, 0))
    ));
  end if;

  if v_days_logged_ratio >= 0.75 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'logging_consistency',
      'category', 'positive',
      'sentiment', 'positive',
      'priority', 60,
      'title', 'Reliable food logging',
      'body', format(
        'You logged meals on %s of %s days (%s%%). These averages are trustworthy enough for personalized coaching.',
        v_diary_days,
        v_day_count,
        round(v_days_logged_ratio * 100, 0)::text
      ),
      'metadata', jsonb_build_object('days_logged', v_diary_days, 'day_count', v_day_count)
    ));
  end if;

  if v_archetype = 'hybrid_athlete' and v_avg_carbs >= v_carb_target_g then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'carb_fueling',
      'category', 'positive',
      'sentiment', 'positive',
      'priority', 55,
      'title', 'Carbs match your training load',
      'body', format(
        'You average %sg of carbohydrates per day (%sg/kg), which supports glycogen for ~%s intense sessions per week.',
        round(v_avg_carbs, 0)::text,
        round(v_avg_carbs / v_weight_ref, 1)::text,
        round(v_intense_days_per_week, 1)::text
      ),
      'metadata', jsonb_build_object('avg_carbs_g', round(v_avg_carbs, 1))
    ));
  end if;

  if v_avg_sodium_mg > 4500 then
    v_food1 := v_sodium_foods->'items'->0->>'food_name';
    v_food2 := v_sodium_foods->'items'->1->>'food_name';
    v_share1 := coalesce((v_sodium_foods->'items'->0->>'share_percent')::numeric, 0);
    v_share2 := coalesce((v_sodium_foods->'items'->1->>'share_percent')::numeric, 0);
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'sodium_food_driver',
      'category', 'micronutrient',
      'sentiment', 'warning',
      'priority', 95,
      'title', 'Sodium driven by your go-to foods',
      'body', case
        when v_food1 is not null and v_food2 is not null then format(
          'Your daily sodium average is %s mg. %s (%s%%) and %s (%s%%) are your biggest contributors. Reduce portions, swap cured meats or cheese, or balance with lower-sodium meals on other days.',
          round(v_avg_sodium_mg, 0)::text,
          v_food1, round(v_share1, 0)::text,
          v_food2, round(v_share2, 0)::text
        )
        else format(
          'Your daily sodium average is %s mg, above the 4500 mg safety limit. Cut back on ultra-processed foods, cured meats, and added salt.%s',
          round(v_avg_sodium_mg, 0)::text,
          c_food_sodium_reduction
        )
      end,
      'metadata', jsonb_build_object('avg_sodium_mg', round(v_avg_sodium_mg, 0), 'top_foods', v_sodium_foods->'items')
    ));
    v_alerts := v_alerts || jsonb_build_array(format(
      'Elevated sodium: your daily average of %s mg exceeds the 4500 mg safety limit. Cut back on ultra-processed foods and consult a professional if it persists.',
      round(v_avg_sodium_mg, 0)::text
    ));
  elsif v_archetype = 'hybrid_athlete' and v_avg_sodium_mg > 2300 and v_avg_sodium_mg <= 4500 then
    v_alerts := v_alerts || jsonb_build_array(format(
      'Your sodium intake (%s mg) is high, but it is balanced with your high sweat rate from exercise (%s kcal). Prioritize consistent electrolyte replenishment.',
      round(v_avg_sodium_mg, 0)::text,
      round(v_avg_burned, 0)::text
    ));
  elsif v_archetype = 'sedentary_tracker' and v_avg_sodium_mg > 2300 then
    v_alerts := v_alerts || jsonb_build_array(format(
      'Your average sodium intake (%s mg/day) exceeds the 2300 mg reference. Reduce processed foods and added salt to support cardiovascular health and metabolic control.',
      round(v_avg_sodium_mg, 0)::text
    ) || c_food_sodium_reduction);
  end if;

  if v_archetype in ('hybrid_athlete', 'active_fitness') and v_avg_fiber < 20 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'low_fiber_active',
      'category', 'micronutrient',
      'sentiment', 'warning',
      'priority', 80,
      'title', 'Fiber is low for your activity level',
      'body', format(
        'You average %sg of fiber per day. Active profiles typically benefit from 25–35g for digestion, satiety, and metabolic health.%s',
        round(v_avg_fiber, 0)::text,
        c_food_fiber_swaps
      ),
      'metadata', jsonb_build_object('avg_fiber_g', round(v_avg_fiber, 1))
    ));
  elsif v_archetype = 'sedentary_tracker' and v_avg_fiber < 25 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'low_fiber_general',
      'category', 'micronutrient',
      'sentiment', 'warning',
      'priority', 70,
      'title', 'Increase daily fiber',
      'body', format(
        'You average %sg of fiber per day. Aim for at least 25g to improve satiety and metabolic control.%s',
        round(v_avg_fiber, 0)::text,
        c_food_fiber_swaps
      ),
      'metadata', jsonb_build_object('avg_fiber_g', round(v_avg_fiber, 1))
    ));
  end if;

  if v_archetype in ('hybrid_athlete', 'active_fitness') and v_avg_sugars > 60 then
    v_food1 := v_sugar_foods->'items'->0->>'food_name';
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'high_sugar_active',
      'category', 'micronutrient',
      'sentiment', 'warning',
      'priority', 65,
      'title', 'Sugar intake is elevated',
      'body', case
        when v_food1 is not null then format(
          'You average %sg of sugar per day. %s is a top contributor — pair sweet items with protein and fiber to reduce energy crashes.',
          round(v_avg_sugars, 0)::text,
          v_food1
        )
        else format(
          'You average %sg of sugar per day. Consider swapping some sweet snacks for fruit, yogurt, or whole grains.',
          round(v_avg_sugars, 0)::text
        )
      end,
      'metadata', jsonb_build_object('avg_sugars_g', round(v_avg_sugars, 1))
    ));
  end if;

  if v_avg_calories > 0 and (v_avg_saturated_fat * 9 / v_avg_calories) > 0.10 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'high_saturated_fat',
      'category', 'micronutrient',
      'sentiment', 'warning',
      'priority', 62,
      'title', 'Saturated fat is high',
      'body', format(
        'Saturated fat provides about %s%% of your daily calories. Try swapping some cheese, bacon, or creamy sauces for lean protein, legumes, or olive-oil-based meals.',
        round(100.0 * v_avg_saturated_fat * 9 / v_avg_calories, 0)::text
      ),
      'metadata', jsonb_build_object('avg_saturated_fat_g', round(v_avg_saturated_fat, 1))
    ));
  end if;

  if v_top_slot is not null and v_top_slot_share >= 45 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'meal_slot_imbalance',
      'category', 'meal_timing',
      'sentiment', 'info',
      'priority', 58,
      'title', format('%s carries most of your calories', v_top_slot),
      'body', format(
        '%s accounts for %s%% of your logged calories in this period. Spreading intake more evenly can improve energy across the day and around training.',
        v_top_slot,
        round(v_top_slot_share, 0)::text
      ),
      'metadata', jsonb_build_object('meal_slot', v_top_slot, 'share_percent', v_top_slot_share)
    ));
  end if;

  if v_breakfast_days > 0 and v_breakfast_days::numeric / greatest(v_diary_days, 1) < 0.5 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'breakfast_gap',
      'category', 'meal_timing',
      'sentiment', 'info',
      'priority', 56,
      'title', 'Breakfast is often missing',
      'body', format(
        'You logged breakfast on only %s of %s days with food entries. A protein-forward breakfast can stabilize appetite and support morning training.',
        v_breakfast_days,
        v_diary_days
      ),
      'metadata', jsonb_build_object('breakfast_log_days', v_breakfast_days, 'days_logged', v_diary_days)
    ));
  end if;

  if v_archetype in ('hybrid_athlete', 'active_fitness')
     and v_training_days >= 3
     and v_rest_days >= 2
     and abs(v_training_carbs - v_rest_carbs) < 15 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'flat_training_carbs',
      'category', 'training_day',
      'sentiment', 'info',
      'priority', 68,
      'title', 'Similar carbs on training and rest days',
      'body', format(
        'Your carbohydrate intake is nearly identical on training days (%sg) and rest days (%sg). Try adding 30–50g of complex carbs on intense days, especially in the post-workout window.',
        round(v_training_carbs, 0)::text,
        round(v_rest_carbs, 0)::text
      ),
      'metadata', jsonb_build_object('training_carbs_g', v_training_carbs, 'rest_carbs_g', v_rest_carbs)
    ));
  end if;

  if v_nutrition_goal = 'cut' and v_avg_remaining > 300 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'cut_surplus',
      'category', 'energy_balance',
      'sentiment', 'warning',
      'priority', 88,
      'title', 'Calorie surplus conflicts with cut goal',
      'body', format(
        'Your goal is fat loss, but you average +%s kcal/day versus your energy budget. Trim portions, reduce liquid calories, or increase activity to reopen a deficit.',
        round(v_avg_remaining, 0)::text
      ),
      'metadata', jsonb_build_object('avg_remaining_kcal', round(v_avg_remaining, 1), 'nutrition_goal', v_nutrition_goal)
    ));
  elsif v_nutrition_goal = 'bulk' and v_avg_remaining < -300 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'bulk_deficit',
      'category', 'energy_balance',
      'sentiment', 'warning',
      'priority', 88,
      'title', 'Calorie deficit conflicts with bulk goal',
      'body', format(
        'Your goal is muscle gain, but you average %s kcal/day below your energy budget. Add a calorie-dense snack or post-workout meal to support growth.',
        round(abs(v_avg_remaining), 0)::text
      ),
      'metadata', jsonb_build_object('avg_remaining_kcal', round(v_avg_remaining, 1), 'nutrition_goal', v_nutrition_goal)
    ));
  elsif v_nutrition_goal = 'maintain' and v_weight_interp = 'stable' and abs(v_avg_remaining) > 400 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'maintain_surplus_stable_weight',
      'category', 'energy_balance',
      'sentiment', 'info',
      'priority', 50,
      'title', 'Stable weight with calorie surplus',
      'body', format(
        'Your weight stayed stable while you averaged +%s kcal/day. Your true expenditure may be higher than estimated, or logging may be incomplete on some days.',
        round(v_avg_remaining, 0)::text
      ),
      'metadata', jsonb_build_object('weight_trend', v_weight_trend)
    ));
  elsif v_nutrition_goal = 'maintain' and v_avg_remaining > 400 and v_weight_interp = 'unknown' then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'maintain_surplus_no_weight',
      'category', 'energy_balance',
      'sentiment', 'info',
      'priority', 45,
      'title', 'Large calorie surplus on maintain goal',
      'body', format(
        'You average +%s kcal/day versus your energy budget. Log body weight regularly so Liftr can tell whether this is maintenance, lean gain, or incomplete logging.',
        round(v_avg_remaining, 0)::text
      ),
      'metadata', jsonb_build_object('avg_remaining_kcal', round(v_avg_remaining, 1))
    ));
  end if;

  if v_weekday_avg > 0 and v_weekend_avg > v_weekday_avg * 1.2 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'weekend_spike',
      'category', 'behavioral',
      'sentiment', 'info',
      'priority', 52,
      'title', 'Weekend calories run higher',
      'body', format(
        'Weekend days average %s kcal versus %s kcal on weekdays. Plan higher-protein weekend meals or pre-log treats to stay aligned with your goal.',
        round(v_weekend_avg, 0)::text,
        round(v_weekday_avg, 0)::text
      ),
      'metadata', jsonb_build_object('weekday_avg_kcal', v_weekday_avg, 'weekend_avg_kcal', v_weekend_avg)
    ));
  end if;

  if v_avg_calories > 0 and v_kcal_stddev > v_avg_calories * 0.4 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'calorie_volatility',
      'category', 'behavioral',
      'sentiment', 'info',
      'priority', 48,
      'title', 'High day-to-day calorie swings',
      'body', format(
        'Your daily calories vary widely (average %s kcal, spread ±%s kcal). More consistent intake can improve recovery predictability and goal tracking.',
        round(v_avg_calories, 0)::text,
        round(v_kcal_stddev, 0)::text
      ),
      'metadata', jsonb_build_object('stddev_kcal', v_kcal_stddev)
    ));
  end if;

  if jsonb_array_length(coalesce(v_logging_quality->'partial_log_dates', '[]'::jsonb)) > 0 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'partial_logging_days',
      'category', 'logging_quality',
      'sentiment', 'info',
      'priority', 72,
      'title', 'Some days look incomplete',
      'body', format(
        '%s day(s) in this window logged less than 40%% of your typical intake. Complete those days or remove partial logs so averages stay accurate.',
        jsonb_array_length(v_logging_quality->'partial_log_dates')
      ),
      'metadata', v_logging_quality
    ));
  end if;

  if v_days_logged_ratio < 0.75 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'incomplete_logging_window',
      'category', 'logging_quality',
      'sentiment', 'warning',
      'priority', 92,
      'title', 'Logging coverage is low',
      'body', format(
        'You logged meals on %s%% of days in this window. Recommendations may be skewed until logging is more consistent.',
        round(v_days_logged_ratio * 100, 0)::text
      ),
      'metadata', v_logging_quality
    ));
    v_alerts := jsonb_build_array(
      'Inconsistent logging. You completed the nutrition diary on less than 75% of the days in the selected range. Calculated averages and these recommendations may be skewed.'
    ) || v_alerts;
  end if;

  select food_name, cnt into v_repeat_food, v_repeat_count
  from (
    select food_name, count(*) as cnt
    from public.nutrition_log_metrics_v1(p_user_id, v_start, v_end)
    group by food_name
    order by count(*) desc
    limit 1
  ) top_food
  where cnt >= 5;

  if v_repeat_food is not null and v_avg_fiber < 20 then
    v_insights := v_insights || jsonb_build_array(jsonb_build_object(
      'id', 'repeat_meal_fiber',
      'category', 'meal_timing',
      'sentiment', 'info',
      'priority', 54,
      'title', format('Boost fiber in your staple: %s', v_repeat_food),
      'body', format(
        '%s appears %s times in this period. Add berries, chia seeds, or vegetables alongside it to raise fiber without changing your routine much.',
        v_repeat_food,
        v_repeat_count
      ),
      'metadata', jsonb_build_object('food_name', v_repeat_food, 'log_count', v_repeat_count)
    ));
  end if;

  if v_archetype = 'hybrid_athlete' and v_avg_carbs < v_carb_target_g then
    v_alerts := v_alerts || jsonb_build_array(format(
      'Low fuel for performance. Your average carbohydrate intake (%sg) is below the %sg target (2.5 g/kg). Replenish glycogen and aim for 1-1.2 g/kg of carbohydrates exclusively in your post-workout meal window within 2 hours.',
      round(v_avg_carbs, 0)::text,
      round(v_carb_target_g, 0)::text
    ) || c_food_complex_carbs);
  elsif v_archetype = 'active_fitness' and v_avg_protein < v_protein_target_g then
    v_alerts := v_alerts || jsonb_build_array(format(
      'Muscle recovery at risk. You train regularly but your average protein intake (%sg) is below the optimal 1.8g/kg threshold for your weight. Increase protein sources to support your training.',
      round(v_avg_protein, 0)::text
    ) || c_food_protein_sources);
  elsif v_archetype = 'sedentary_tracker' and v_avg_sugars > 50 and v_avg_fiber < 20 then
    v_alerts := v_alerts || jsonb_build_array(format(
      'Refined carbohydrate pattern detected. Your daily sugar intake is high (%sg) relative to low fiber (%sg). Prioritize oats, legumes, and vegetables to improve satiety and insulin response.',
      round(v_avg_sugars, 0)::text,
      round(v_avg_fiber, 0)::text
    ) || c_food_fiber_swaps);
  end if;

  if v_net_balance <= -750 and v_intense_days_per_week >= 1.5 then
    v_alerts := v_alerts || jsonb_build_array(format(
      '🚨 Underfueling alert: Your body is operating with a severe deficit of %s kcal/day against a high active training volume. Urgently increase your structured calorie intake.',
      round(v_abs_deficit, 0)::text
    ) || c_food_underfuel_fats);
    v_critical_prefix := format(
      'Underfueling alert: Your body is operating under a severe deficit of %s kcal/day against a high active training volume. It is urgent to increase your structured calorie intake to protect your muscle mass and overall health.',
      round(v_abs_deficit, 0)::text
    ) || c_food_underfuel_fats;
    v_insights := jsonb_build_array(jsonb_build_object(
      'id', 'critical_underfueling',
      'category', 'energy_balance',
      'sentiment', 'warning',
      'priority', 100,
      'title', 'Critical underfueling risk',
      'body', v_critical_prefix,
      'metadata', jsonb_build_object('deficit_kcal', round(v_abs_deficit, 0))
    )) || v_insights;
  end if;

  v_insights := public.nutrition_rank_insights_v1(v_insights, 8);

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
  elsif v_archetype = 'active_fitness' then
    v_archetype_body := v_archetype_body || E'\n\n'
      || 'Your profile reflects active fitness and recomposition: focus on muscle recovery and a structured balance of quality protein, carbohydrates, and fats.';
  else
    v_archetype_body := v_archetype_body || E'\n\n'
      || 'Your profile aligns with health tracking and maintenance: prioritize calorie control, satiety, and sustainable habits for metabolic longevity.';
  end if;

  if jsonb_array_length(v_insights) >= 1 then
    v_text := (v_insights->0->>'body');
    if jsonb_array_length(v_insights) >= 2 then
      v_text := v_text || E'\n\n' || (v_insights->1->>'body');
    end if;
  else
    v_text := v_archetype_body;
  end if;

  v_text := trim(both from concat_ws(E'\n\n', nullif(v_critical_prefix, ''), nullif(v_text, '')));

  if v_weight_kg is null then
    v_text := v_text || E'\n\n'
      || 'Protein and carbohydrate thresholds use a 70 kg reference until you add your weight on your profile.';
  end if;

  return jsonb_build_object(
    'recommendation_text', v_text,
    'alerts', coalesce((
      select jsonb_agg(value)
      from jsonb_array_elements_text(v_alerts) as t(value)
    ), '[]'::jsonb),
    'insights', v_insights,
    'nutrition_goal', v_nutrition_goal,
    'archetype', v_archetype,
    'avg_daily_consumed_kcal', round(v_avg_calories, 1),
    'avg_daily_burned_kcal', round(v_avg_burned, 1),
    'base_calories_target', v_base_calories,
    'avg_daily_energy_out', round(v_avg_energy_out, 1),
    'avg_daily_remaining_budget', round(v_avg_remaining, 1),
    'training_day_avg', v_training_split->'training_day_avg',
    'rest_day_avg', v_training_split->'rest_day_avg',
    'weight_trend', v_weight_trend,
    'meal_slot_summary', v_meal_slots,
    'logging_quality', v_logging_quality
  );
end;
$function$;

notify pgrst, 'reload schema';

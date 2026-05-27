set local check_function_bodies = off;

alter table public.profiles
  add column if not exists base_calories_target integer not null default 2000;

alter table public.nutrition_recipes
  add column if not exists description text;

create or replace function public.get_daily_nutrition_recommendation_v1(p_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_base integer := 2000;
  v_consumed numeric := 0;
  v_burned numeric := 0;
  v_remaining numeric := 0;
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

  select coalesce(p.base_calories_target, 2000)
  into v_base
  from public.profiles p
  where p.user_id = v_uid;

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

  v_remaining := v_base + v_burned - v_consumed;

  if v_remaining < -400 then
    v_text := format(
      'You are %s kcal over your daily target (%s kcal base + %s kcal activity). Consider lighter portions for remaining meals.',
      round(abs(v_remaining), 0)::text,
      round(v_base, 0)::text,
      round(v_burned, 0)::text
    );
  elsif v_remaining between -150 and 150 then
    v_text := format(
      'Intake is aligned with your %s kcal daily target and %s kcal active burn. Keep consistent meal timing around training.',
      round(v_base, 0)::text,
      round(v_burned, 0)::text
    );
  elsif v_burned >= 600 and v_remaining > 400 then
    v_text := format(
      'High activity day (%s kcal burned). You have %s kcal remaining versus your %s kcal base target — prioritize protein-rich meals and hydration.',
      round(v_burned, 0)::text,
      round(v_remaining, 0)::text,
      round(v_base, 0)::text
    );
  elsif v_burned >= 300 and v_remaining > 200 then
    v_text := format(
      'Moderate activity (%s kcal burned). About %s kcal left in your budget (%s kcal base + activity). A balanced meal or snack can help.',
      round(v_burned, 0)::text,
      round(v_remaining, 0)::text,
      round(v_base, 0)::text
    );
  elsif v_remaining > 400 then
    v_text := format(
      'You have %s kcal remaining in today''s budget (%s kcal base + %s kcal activity − %s kcal consumed). Use it for recovery or planned meals.',
      round(v_remaining, 0)::text,
      round(v_base, 0)::text,
      round(v_burned, 0)::text,
      round(v_consumed, 0)::text
    );
  elsif v_remaining < 0 then
    v_text := format(
      'You are %s kcal over today''s budget (%s kcal base + %s kcal activity). Adjust later meals if aligning with maintenance or a deficit.',
      round(abs(v_remaining), 0)::text,
      round(v_base, 0)::text,
      round(v_burned, 0)::text
    );
  else
    v_text := format(
      'About %s kcal remaining toward your %s kcal daily target plus %s kcal from activity.',
      round(v_remaining, 0)::text,
      round(v_base, 0)::text,
      round(v_burned, 0)::text
    );
  end if;

  return jsonb_build_object(
    'base_calories_target', v_base,
    'total_calories_consumed', round(v_consumed, 1),
    'total_calories_burned_active', round(v_burned, 1),
    'remaining_calories', round(v_remaining, 1),
    'net_calories_balance', round(v_remaining, 1),
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

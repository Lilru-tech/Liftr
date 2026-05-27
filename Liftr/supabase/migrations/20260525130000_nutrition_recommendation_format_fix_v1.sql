set local check_function_bodies = off;

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
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select coalesce(sum(
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
  ), 0)
  into v_consumed
  from public.nutrition_diary_logs l
  left join public.nutrition_ingredients i on i.id = l.ingredient_id
  where l.user_id = v_uid
    and l.log_date = p_date;

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
    'recommendation_text', v_text
  );
end;
$$;

notify pgrst, 'reload schema';

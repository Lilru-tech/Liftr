set local check_function_bodies = off;

create or replace function public.get_nutrition_ranking_v1(
  p_ranking_type text,
  p_limit int default 25,
  p_offset int default 0
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_limit int;
  v_offset int;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  v_limit := greatest(1, least(coalesce(p_limit, 25), 100));
  v_offset := greatest(coalesce(p_offset, 0), 0);

  if p_ranking_type not in (
    'highest_calorie_days',
    'highest_calorie_meals',
    'most_logged_ingredients',
    'most_logged_recipes',
    'heaviest_meals'
  ) then
    raise exception 'invalid ranking type: %', p_ranking_type using errcode = '22023';
  end if;

  if p_ranking_type = 'highest_calorie_days' then
    return query
    with log_metrics as (
      select
        l.log_date,
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
        end as kcal
      from public.nutrition_diary_logs l
      left join public.nutrition_ingredients i on i.id = l.ingredient_id
      where l.user_id = v_uid
    ),
    daily_totals as (
      select log_date, sum(kcal) as day_kcal
      from log_metrics
      group by log_date
    ),
    ranked as (
      select
        row_number() over (order by day_kcal desc, log_date desc) as rn,
        log_date,
        round(day_kcal::numeric, 1) as value_numeric
      from daily_totals
    )
    select jsonb_build_object(
      'rank_position', v_offset + ranked.rn,
      'title', to_char(ranked.log_date, 'YYYY-MM-DD'),
      'subtitle', null,
      'value_numeric', ranked.value_numeric,
      'unit_label', 'kcal',
      'metadata_json', jsonb_build_object(
        'log_date', to_char(ranked.log_date, 'YYYY-MM-DD')
      )
    )
    from ranked
    order by ranked.rn
    limit v_limit offset v_offset;

  elsif p_ranking_type = 'highest_calorie_meals' then
    return query
    with log_metrics as (
      select
        l.log_date,
        l.meal_slot,
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
        end as kcal
      from public.nutrition_diary_logs l
      left join public.nutrition_ingredients i on i.id = l.ingredient_id
      where l.user_id = v_uid
    ),
    meal_slot_totals as (
      select log_date, meal_slot, sum(kcal) as slot_kcal
      from log_metrics
      group by log_date, meal_slot
    ),
    ranked as (
      select
        row_number() over (order by slot_kcal desc, log_date desc, meal_slot desc) as rn,
        log_date,
        meal_slot,
        round(slot_kcal::numeric, 1) as value_numeric
      from meal_slot_totals
    )
    select jsonb_build_object(
      'rank_position', v_offset + ranked.rn,
      'title', ranked.meal_slot,
      'subtitle', to_char(ranked.log_date, 'YYYY-MM-DD'),
      'value_numeric', ranked.value_numeric,
      'unit_label', 'kcal',
      'metadata_json', jsonb_build_object(
        'log_date', to_char(ranked.log_date, 'YYYY-MM-DD'),
        'meal_slot', ranked.meal_slot
      )
    )
    from ranked
    order by ranked.rn
    limit v_limit offset v_offset;

  elsif p_ranking_type = 'most_logged_ingredients' then
    return query
    with log_metrics as (
      select
        l.ingredient_id,
        case
          when l.ingredient_id is not null then
            l.quantity_g * i.calories_per_100g / 100.0
          else 0
        end as kcal,
        coalesce(i.name, 'Unknown') as display_name
      from public.nutrition_diary_logs l
      left join public.nutrition_ingredients i on i.id = l.ingredient_id
      where l.user_id = v_uid
        and l.ingredient_id is not null
    ),
    ingredient_stats as (
      select
        ingredient_id,
        max(display_name) as name,
        count(*)::integer as log_count,
        sum(kcal) as total_kcal
      from log_metrics
      group by ingredient_id
    ),
    ranked as (
      select
        row_number() over (order by log_count desc, total_kcal desc, name asc) as rn,
        ingredient_id,
        name,
        log_count,
        round(total_kcal::numeric, 1) as total_kcal
      from ingredient_stats
    )
    select jsonb_build_object(
      'rank_position', v_offset + ranked.rn,
      'title', ranked.name,
      'subtitle', ranked.log_count::text || ' logs',
      'value_numeric', ranked.log_count,
      'unit_label', 'times',
      'metadata_json', jsonb_build_object(
        'ingredient_id', ranked.ingredient_id,
        'total_kcal', ranked.total_kcal
      )
    )
    from ranked
    order by ranked.rn
    limit v_limit offset v_offset;

  elsif p_ranking_type = 'most_logged_recipes' then
    return query
    with log_metrics as (
      select
        l.recipe_id,
        case
          when l.recipe_id is not null then
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
          else 0
        end as kcal,
        coalesce(r.name, 'Unknown') as display_name
      from public.nutrition_diary_logs l
      left join public.nutrition_recipes r on r.id = l.recipe_id
      where l.user_id = v_uid
        and l.recipe_id is not null
    ),
    recipe_stats as (
      select
        recipe_id,
        max(display_name) as name,
        count(*)::integer as log_count,
        sum(kcal) as total_kcal
      from log_metrics
      group by recipe_id
    ),
    ranked as (
      select
        row_number() over (order by log_count desc, total_kcal desc, name asc) as rn,
        recipe_id,
        name,
        log_count,
        round(total_kcal::numeric, 1) as total_kcal
      from recipe_stats
    )
    select jsonb_build_object(
      'rank_position', v_offset + ranked.rn,
      'title', ranked.name,
      'subtitle', ranked.log_count::text || ' logs',
      'value_numeric', ranked.log_count,
      'unit_label', 'times',
      'metadata_json', jsonb_build_object(
        'recipe_id', ranked.recipe_id,
        'total_kcal', ranked.total_kcal
      )
    )
    from ranked
    order by ranked.rn
    limit v_limit offset v_offset;

  elsif p_ranking_type = 'heaviest_meals' then
    return query
    with log_metrics as (
      select
        l.log_date,
        l.meal_slot,
        l.quantity_g
      from public.nutrition_diary_logs l
      where l.user_id = v_uid
    ),
    meal_weight_totals as (
      select log_date, meal_slot, sum(quantity_g) as total_weight_g
      from log_metrics
      group by log_date, meal_slot
    ),
    ranked as (
      select
        row_number() over (order by total_weight_g desc, log_date desc, meal_slot desc) as rn,
        log_date,
        meal_slot,
        round(total_weight_g::numeric, 1) as value_numeric
      from meal_weight_totals
    )
    select jsonb_build_object(
      'rank_position', v_offset + ranked.rn,
      'title', ranked.meal_slot,
      'subtitle', to_char(ranked.log_date, 'YYYY-MM-DD'),
      'value_numeric', ranked.value_numeric,
      'unit_label', 'g',
      'metadata_json', jsonb_build_object(
        'log_date', to_char(ranked.log_date, 'YYYY-MM-DD'),
        'meal_slot', ranked.meal_slot
      )
    )
    from ranked
    order by ranked.rn
    limit v_limit offset v_offset;
  end if;
end;
$$;

revoke all on function public.get_nutrition_ranking_v1(text, int, int) from public;
grant execute on function public.get_nutrition_ranking_v1(text, int, int) to authenticated;

notify pgrst, 'reload schema';

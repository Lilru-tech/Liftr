set local check_function_bodies = off;

create or replace function public.get_nutrition_highlights_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_result jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  with log_metrics as (
    select
      l.id as log_id,
      l.log_date,
      l.meal_slot,
      l.ingredient_id,
      l.recipe_id,
      l.quantity_g,
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
      end as kcal,
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
      end as protein_g,
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
      end as carbs_g,
      coalesce(i.name, r.name, 'Unknown') as display_name,
      case
        when l.ingredient_id is not null then 'i:' || l.ingredient_id::text
        else 'r:' || l.recipe_id::text
      end as food_key
    from public.nutrition_diary_logs l
    left join public.nutrition_ingredients i on i.id = l.ingredient_id
    left join public.nutrition_recipes r on r.id = l.recipe_id
    where l.user_id = v_uid
  ),
  stats as (
    select
      (select count(*)::integer from log_metrics) as total_log_entries,
      (select count(distinct log_date)::integer from log_metrics) as days_logged,
      (select min(log_date) from log_metrics) as first_log_date,
      (select max(log_date) from log_metrics) as last_log_date,
      (select coalesce(sum(kcal), 0) from log_metrics) as total_kcal,
      (select count(*) filter (where recipe_id is not null)::integer from log_metrics) as recipe_log_count,
      (select count(*) filter (where ingredient_id is not null)::integer from log_metrics) as ingredient_log_count
  ),
  daily_totals as (
    select log_date, sum(kcal) as day_kcal
    from log_metrics
    group by log_date
  ),
  peak_day_row as (
    select log_date, day_kcal
    from daily_totals
    order by day_kcal desc, log_date desc
    limit 1
  ),
  meal_slot_totals as (
    select log_date, meal_slot, sum(kcal) as slot_kcal
    from log_metrics
    group by log_date, meal_slot
  ),
  peak_meal_row as (
    select log_date, meal_slot, slot_kcal
    from meal_slot_totals
    order by slot_kcal desc, log_date desc, meal_slot desc
    limit 1
  ),
  meal_weight_totals as (
    select log_date, meal_slot, sum(quantity_g) as total_weight_g
    from log_metrics
    group by log_date, meal_slot
  ),
  heaviest_meal_row as (
    select log_date, meal_slot, total_weight_g
    from meal_weight_totals
    order by total_weight_g desc, log_date desc, meal_slot desc
    limit 1
  ),
  slot_counts as (
    select meal_slot, count(*)::integer as entry_count
    from log_metrics
    group by meal_slot
  ),
  most_used_slot_row as (
    select meal_slot
    from slot_counts
    order by entry_count desc, meal_slot asc
    limit 1
  ),
  ingredient_stats as (
    select
      ingredient_id,
      max(display_name) as name,
      count(*)::integer as log_count,
      sum(kcal) as total_kcal
    from log_metrics
    where ingredient_id is not null
    group by ingredient_id
  ),
  top_ingredient_row as (
    select ingredient_id, name, log_count, total_kcal
    from ingredient_stats
    order by log_count desc, total_kcal desc, name asc
    limit 1
  ),
  recipe_stats as (
    select
      recipe_id,
      max(display_name) as name,
      count(*)::integer as log_count,
      sum(kcal) as total_kcal
    from log_metrics
    where recipe_id is not null
    group by recipe_id
  ),
  top_recipe_row as (
    select recipe_id, name, log_count, total_kcal
    from recipe_stats
    order by log_count desc, total_kcal desc, name asc
    limit 1
  ),
  macro_source_stats as (
    select
      food_key,
      max(display_name) as name,
      sum(protein_g) as total_protein_g,
      sum(carbs_g) as total_carbs_g
    from log_metrics
    group by food_key
  ),
  top_protein_row as (
    select name, total_protein_g
    from macro_source_stats
    where total_protein_g > 0
    order by total_protein_g desc, name asc
    limit 1
  ),
  top_carb_row as (
    select name, total_carbs_g
    from macro_source_stats
    where total_carbs_g > 0
    order by total_carbs_g desc, name asc
    limit 1
  ),
  weekday_weekend as (
    select
      round(avg(day_kcal) filter (where extract(isodow from log_date) between 1 and 5), 1) as weekday_avg_kcal,
      round(avg(day_kcal) filter (where extract(isodow from log_date) in (6, 7)), 1) as weekend_avg_kcal
    from daily_totals
  ),
  logged_dates as (
    select distinct log_date
    from log_metrics
  ),
  streak_numbered as (
    select
      log_date,
      log_date - (row_number() over (order by log_date))::integer as streak_grp
    from logged_dates
  ),
  streak_lens as (
    select
      streak_grp,
      count(*)::integer as streak_len,
      max(log_date) as streak_end
    from streak_numbered
    group by streak_grp
  ),
  streak_agg as (
    select
      coalesce((select max(streak_len) from streak_lens), 0) as best_streak,
      coalesce(
        (
          select sl.streak_len
          from streak_lens sl
          where sl.streak_end = (select max(ld.log_date) from logged_dates ld)
            and sl.streak_end >= current_date - 1
        ),
        0
      ) as current_streak
  ),
  top_ingredients_arr as (
    select coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', ingredient_id,
            'name', name,
            'log_count', log_count,
            'total_kcal', round(total_kcal::numeric, 1)
          )
          order by log_count desc, total_kcal desc, name asc
        )
        from (
          select ingredient_id, name, log_count, total_kcal
          from ingredient_stats
          order by log_count desc, total_kcal desc, name asc
          limit 3
        ) t
      ),
      '[]'::jsonb
    ) as items
  ),
  top_recipes_arr as (
    select coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', recipe_id,
            'name', name,
            'log_count', log_count,
            'total_kcal', round(total_kcal::numeric, 1)
          )
          order by log_count desc, total_kcal desc, name asc
        )
        from (
          select recipe_id, name, log_count, total_kcal
          from recipe_stats
          order by log_count desc, total_kcal desc, name asc
          limit 3
        ) t
      ),
      '[]'::jsonb
    ) as items
  )
  select jsonb_build_object(
    'days_logged', s.days_logged,
    'total_log_entries', s.total_log_entries,
    'first_log_date', case when s.first_log_date is not null then to_char(s.first_log_date, 'YYYY-MM-DD') else null end,
    'last_log_date', case when s.last_log_date is not null then to_char(s.last_log_date, 'YYYY-MM-DD') else null end,
    'avg_kcal_per_logged_day',
      case
        when s.days_logged > 0 then round((s.total_kcal / s.days_logged)::numeric, 1)
        else 0
      end,
    'peak_day',
      case
        when pd.log_date is not null then jsonb_build_object(
          'date', to_char(pd.log_date, 'YYYY-MM-DD'),
          'kcal', round(pd.day_kcal::numeric, 1)
        )
        else null
      end,
    'peak_meal_slot',
      case
        when pm.log_date is not null then jsonb_build_object(
          'date', to_char(pm.log_date, 'YYYY-MM-DD'),
          'meal_slot', pm.meal_slot,
          'kcal', round(pm.slot_kcal::numeric, 1)
        )
        else null
      end,
    'most_used_meal_slot', mus.meal_slot,
    'top_ingredient',
      case
        when ti.ingredient_id is not null then jsonb_build_object(
          'id', ti.ingredient_id,
          'name', ti.name,
          'log_count', ti.log_count,
          'total_kcal', round(ti.total_kcal::numeric, 1)
        )
        else null
      end,
    'top_recipe',
      case
        when tr.recipe_id is not null then jsonb_build_object(
          'id', tr.recipe_id,
          'name', tr.name,
          'log_count', tr.log_count,
          'total_kcal', round(tr.total_kcal::numeric, 1)
        )
        else null
      end,
    'top_ingredients', tia.items,
    'top_recipes', tra.items,
    'recipe_log_share_percent',
      case
        when s.total_log_entries > 0 then
          round((100.0 * s.recipe_log_count / s.total_log_entries)::numeric, 1)
        else 0
      end,
    'macro_champions', jsonb_build_object(
      'top_protein_source',
        case
          when tp.name is not null then jsonb_build_object(
            'name', tp.name,
            'total_g', round(tp.total_protein_g::numeric, 1)
          )
          else null
        end,
      'top_carb_source',
        case
          when tc.name is not null then jsonb_build_object(
            'name', tc.name,
            'total_g', round(tc.total_carbs_g::numeric, 1)
          )
          else null
        end
    ),
    'calorie_volatility', jsonb_build_object(
      'weekday_avg_kcal', coalesce(ww.weekday_avg_kcal, 0),
      'weekend_avg_kcal', coalesce(ww.weekend_avg_kcal, 0)
    ),
    'heaviest_meal',
      case
        when hm.log_date is not null then jsonb_build_object(
          'date', to_char(hm.log_date, 'YYYY-MM-DD'),
          'meal_slot', hm.meal_slot,
          'total_weight_g', round(hm.total_weight_g::numeric, 1)
        )
        else null
      end,
    'consistency_streak', jsonb_build_object(
      'current_streak', sa.current_streak,
      'best_streak', sa.best_streak
    )
  )
  into v_result
  from stats s
  cross join top_ingredients_arr tia
  cross join top_recipes_arr tra
  cross join weekday_weekend ww
  cross join streak_agg sa
  left join peak_day_row pd on true
  left join peak_meal_row pm on true
  left join most_used_slot_row mus on true
  left join top_ingredient_row ti on true
  left join top_recipe_row tr on true
  left join top_protein_row tp on true
  left join top_carb_row tc on true
  left join heaviest_meal_row hm on true;

  return coalesce(
    v_result,
    jsonb_build_object(
      'days_logged', 0,
      'total_log_entries', 0,
      'first_log_date', null,
      'last_log_date', null,
      'avg_kcal_per_logged_day', 0,
      'peak_day', null,
      'peak_meal_slot', null,
      'most_used_meal_slot', null,
      'top_ingredient', null,
      'top_recipe', null,
      'top_ingredients', '[]'::jsonb,
      'top_recipes', '[]'::jsonb,
      'recipe_log_share_percent', 0,
      'macro_champions', jsonb_build_object(
        'top_protein_source', null,
        'top_carb_source', null
      ),
      'calorie_volatility', jsonb_build_object(
        'weekday_avg_kcal', 0,
        'weekend_avg_kcal', 0
      ),
      'heaviest_meal', null,
      'consistency_streak', jsonb_build_object(
        'current_streak', 0,
        'best_streak', 0
      )
    )
  );
end;
$$;

revoke all on function public.get_nutrition_highlights_v1() from public;
grant execute on function public.get_nutrition_highlights_v1() to authenticated;

notify pgrst, 'reload schema';

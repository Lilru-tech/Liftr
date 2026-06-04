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

  with log_kcal as (
    select
      l.id as log_id,
      l.log_date,
      l.meal_slot,
      l.ingredient_id,
      l.recipe_id,
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
      coalesce(i.name, r.name, 'Unknown') as display_name
    from public.nutrition_diary_logs l
    left join public.nutrition_ingredients i on i.id = l.ingredient_id
    left join public.nutrition_recipes r on r.id = l.recipe_id
    where l.user_id = v_uid
  ),
  stats as (
    select
      (select count(*)::integer from log_kcal) as total_log_entries,
      (select count(distinct log_date)::integer from log_kcal) as days_logged,
      (select min(log_date) from log_kcal) as first_log_date,
      (select max(log_date) from log_kcal) as last_log_date,
      (select coalesce(sum(kcal), 0) from log_kcal) as total_kcal,
      (select count(*) filter (where recipe_id is not null)::integer from log_kcal) as recipe_log_count,
      (select count(*) filter (where ingredient_id is not null)::integer from log_kcal) as ingredient_log_count
  ),
  daily_totals as (
    select log_date, sum(kcal) as day_kcal
    from log_kcal
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
    from log_kcal
    group by log_date, meal_slot
  ),
  peak_meal_row as (
    select log_date, meal_slot, slot_kcal
    from meal_slot_totals
    order by slot_kcal desc, log_date desc, meal_slot desc
    limit 1
  ),
  slot_counts as (
    select meal_slot, count(*)::integer as entry_count
    from log_kcal
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
    from log_kcal
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
    from log_kcal
    where recipe_id is not null
    group by recipe_id
  ),
  top_recipe_row as (
    select recipe_id, name, log_count, total_kcal
    from recipe_stats
    order by log_count desc, total_kcal desc, name asc
    limit 1
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
      end
  )
  into v_result
  from stats s
  cross join top_ingredients_arr tia
  cross join top_recipes_arr tra
  left join peak_day_row pd on true
  left join peak_meal_row pm on true
  left join most_used_slot_row mus on true
  left join top_ingredient_row ti on true
  left join top_recipe_row tr on true;

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
      'recipe_log_share_percent', 0
    )
  );
end;
$$;

revoke all on function public.get_nutrition_highlights_v1() from public;
grant execute on function public.get_nutrition_highlights_v1() to authenticated;

notify pgrst, 'reload schema';

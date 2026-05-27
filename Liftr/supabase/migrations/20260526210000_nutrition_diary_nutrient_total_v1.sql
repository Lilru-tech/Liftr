set local check_function_bodies = off;

create or replace function public.nutrition_diary_nutrient_total_v1(
  p_date date,
  p_nutrient text
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_col_ing text;
  v_total numeric;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  v_col_ing := case p_nutrient
    when 'calories' then 'calories_per_100g'
    when 'protein' then 'protein_per_100g'
    when 'carbs' then 'carbs_per_100g'
    when 'fat' then 'fat_per_100g'
    when 'saturated_fat' then 'saturated_fat_per_100g'
    when 'sugars' then 'sugars_per_100g'
    when 'fiber' then 'fiber_per_100g'
    when 'sodium_mg' then 'sodium_mg_per_100g'
    else null
  end;

  if v_col_ing is null then
    raise exception 'invalid nutrient: %', p_nutrient using errcode = '22023';
  end if;

  execute format(
    $q$
    select coalesce(sum(
      case
        when l.ingredient_id is not null then
          l.quantity_g * i.%I / 100.0
        else
          l.quantity_g * coalesce(
            (
              select
                sum(ri.weight_g * ing.%I / 100.0)
                / nullif(sum(ri.weight_g), 0)
              from public.nutrition_recipe_ingredients ri
              join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
              where ri.recipe_id = l.recipe_id
            ),
            0
          )
      end
    ), 0)
    from public.nutrition_diary_logs l
    left join public.nutrition_ingredients i on i.id = l.ingredient_id
    where l.user_id = $1
      and l.log_date = $2
    $q$,
    v_col_ing,
    v_col_ing
  )
  into v_total
  using v_uid, p_date;

  return v_total;
end;
$$;

revoke all on function public.nutrition_diary_nutrient_total_v1(date, text) from public;
grant execute on function public.nutrition_diary_nutrient_total_v1(date, text) to authenticated;

notify pgrst, 'reload schema';

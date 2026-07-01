set local check_function_bodies = off;

create or replace function public.nutrition_is_intense_workout_v1(
  p_kind public.workout_kind,
  p_title text
)
returns boolean
language sql
immutable
as $$
  select
    p_kind in ('strength'::public.workout_kind, 'sport'::public.workout_kind)
    or (
      p_kind = 'cardio'::public.workout_kind
      and coalesce(p_title, '') not ilike '%walk%'
      and coalesce(p_title, '') not ilike '%caminata%'
    );
$$;

create or replace function public.nutrition_log_metrics_v1(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns table (
  log_date date,
  meal_slot text,
  food_name text,
  food_key text,
  kcal numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  saturated_fat_g numeric,
  sugars_g numeric,
  fiber_g numeric,
  sodium_mg numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.log_date,
    l.meal_slot,
    coalesce(i.name, r.name, 'Unknown') as food_name,
    case
      when l.ingredient_id is not null then 'i:' || l.ingredient_id::text
      else 'r:' || l.recipe_id::text
    end as food_key,
    case
      when l.ingredient_id is not null then l.quantity_g * i.calories_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.calories_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as kcal,
    case
      when l.ingredient_id is not null then l.quantity_g * i.protein_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.protein_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as protein_g,
    case
      when l.ingredient_id is not null then l.quantity_g * i.carbs_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.carbs_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as carbs_g,
    case
      when l.ingredient_id is not null then l.quantity_g * i.fat_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.fat_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as fat_g,
    case
      when l.ingredient_id is not null then l.quantity_g * i.saturated_fat_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.saturated_fat_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as saturated_fat_g,
    case
      when l.ingredient_id is not null then l.quantity_g * i.sugars_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.sugars_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as sugars_g,
    case
      when l.ingredient_id is not null then l.quantity_g * i.fiber_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.fiber_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as fiber_g,
    case
      when l.ingredient_id is not null then l.quantity_g * i.sodium_mg_per_100g / 100.0
      else l.quantity_g * coalesce(
        (
          select sum(ri.weight_g * ing.sodium_mg_per_100g / 100.0) / nullif(sum(ri.weight_g), 0)
          from public.nutrition_recipe_ingredients ri
          join public.nutrition_ingredients ing on ing.id = ri.ingredient_id
          where ri.recipe_id = l.recipe_id
        ),
        0
      )
    end as sodium_mg
  from public.nutrition_diary_logs l
  left join public.nutrition_ingredients i on i.id = l.ingredient_id
  left join public.nutrition_recipes r on r.id = l.recipe_id
  where l.user_id = p_user_id
    and l.log_date between p_start_date and p_end_date;
$$;

create or replace function public.nutrition_top_food_contributors_v1(
  p_user_id uuid,
  p_start_date date,
  p_end_date date,
  p_nutrient text,
  p_limit integer default 3
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_total numeric := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  if p_nutrient not in ('calories', 'protein', 'carbs', 'fat', 'saturated_fat', 'sugars', 'fiber', 'sodium_mg') then
    raise exception 'invalid nutrient: %', p_nutrient using errcode = '22023';
  end if;

  execute format(
    $q$
    with food_totals as (
      select
        food_name,
        sum(%I) as amount
      from public.nutrition_log_metrics_v1($1, $2, $3)
      group by food_name
    ),
    ranked as (
      select
        food_name,
        amount,
        sum(amount) over () as total_amount
      from food_totals
      where amount > 0
      order by amount desc
      limit $4
    )
    select
      coalesce(sum(total_amount), 0),
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'food_name', food_name,
            'amount', round(amount, 1),
            'share_percent', case when total_amount > 0 then round(100.0 * amount / total_amount, 1) else 0 end
          )
          order by amount desc
        ),
        '[]'::jsonb
      )
    from ranked
    $q$,
    case p_nutrient
      when 'calories' then 'kcal'
      when 'protein' then 'protein_g'
      when 'carbs' then 'carbs_g'
      when 'fat' then 'fat_g'
      when 'saturated_fat' then 'saturated_fat_g'
      when 'sugars' then 'sugars_g'
      when 'fiber' then 'fiber_g'
      when 'sodium_mg' then 'sodium_mg'
    end
  )
  into v_total, v_rows
  using p_user_id, p_start_date, p_end_date, greatest(1, least(p_limit, 10));

  return jsonb_build_object('total', round(v_total, 1), 'items', coalesce(v_rows, '[]'::jsonb));
end;
$$;

create or replace function public.nutrition_meal_slot_summary_v1(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with slot_day as (
    select
      meal_slot,
      log_date,
      sum(kcal) as slot_kcal
    from public.nutrition_log_metrics_v1(p_user_id, p_start_date, p_end_date)
    group by meal_slot, log_date
  ),
  slot_stats as (
    select
      meal_slot,
      count(*) as log_days,
      round(avg(slot_kcal), 1) as avg_kcal_per_day,
      round(sum(slot_kcal), 1) as total_kcal
    from slot_day
    group by meal_slot
  ),
  daily_totals as (
    select log_date, sum(kcal) as day_kcal
    from public.nutrition_log_metrics_v1(p_user_id, p_start_date, p_end_date)
    group by log_date
  ),
  slot_share as (
    select
      s.meal_slot,
      s.log_days,
      s.avg_kcal_per_day,
      s.total_kcal,
      round(
        100.0 * s.total_kcal / nullif((select sum(day_kcal) from daily_totals), 0),
        1
      ) as kcal_share_percent
    from slot_stats s
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'meal_slot', meal_slot,
        'log_days', log_days,
        'avg_kcal_per_day', avg_kcal_per_day,
        'kcal_share_percent', coalesce(kcal_share_percent, 0)
      )
      order by total_kcal desc
    ),
    '[]'::jsonb
  )
  from slot_share;
$$;

create or replace function public.nutrition_training_rest_split_v1(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with intense_days as (
    select distinct coalesce(w.started_at, w.created_at)::date as d
    from public.workouts w
    where w.user_id = p_user_id
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at)::date between p_start_date and p_end_date
      and public.nutrition_is_intense_workout_v1(w.kind, w.title)
  ),
  daily as (
    select
      m.log_date,
      case when id.d is not null then 'training' else 'rest' end as day_type,
      sum(m.kcal) as kcal,
      sum(m.protein_g) as protein_g,
      sum(m.carbs_g) as carbs_g,
      sum(m.fat_g) as fat_g
    from public.nutrition_log_metrics_v1(p_user_id, p_start_date, p_end_date) m
    left join intense_days id on id.d = m.log_date
    group by m.log_date, day_type
  )
  select jsonb_build_object(
    'training_day_avg', (
      select jsonb_build_object(
        'days', count(*),
        'kcal', round(coalesce(avg(kcal), 0), 1),
        'protein_g', round(coalesce(avg(protein_g), 0), 1),
        'carbs_g', round(coalesce(avg(carbs_g), 0), 1),
        'fat_g', round(coalesce(avg(fat_g), 0), 1)
      )
      from daily where day_type = 'training'
    ),
    'rest_day_avg', (
      select jsonb_build_object(
        'days', count(*),
        'kcal', round(coalesce(avg(kcal), 0), 1),
        'protein_g', round(coalesce(avg(protein_g), 0), 1),
        'carbs_g', round(coalesce(avg(carbs_g), 0), 1),
        'fat_g', round(coalesce(avg(fat_g), 0), 1)
      )
      from daily where day_type = 'rest'
    )
  );
$$;

create or replace function public.nutrition_weight_trend_v1(
  p_user_id uuid,
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
  v_start_kg numeric;
  v_end_kg numeric;
  v_samples integer := 0;
  v_delta numeric := 0;
  v_interp text := 'unknown';
begin
  select count(*)
  into v_samples
  from public.body_weight_entries
  where user_id = p_user_id
    and measured_at::date between p_start_date and p_end_date;

  select weight_kg into v_start_kg
  from public.body_weight_entries
  where user_id = p_user_id
    and measured_at::date between p_start_date and p_end_date
  order by measured_at asc
  limit 1;

  select weight_kg into v_end_kg
  from public.body_weight_entries
  where user_id = p_user_id
    and measured_at::date between p_start_date and p_end_date
  order by measured_at desc
  limit 1;

  if v_samples >= 2 and v_start_kg is not null and v_end_kg is not null then
    v_delta := v_end_kg - v_start_kg;
    if v_delta <= -0.3 then
      v_interp := 'losing';
    elsif v_delta >= 0.3 then
      v_interp := 'gaining';
    else
      v_interp := 'stable';
    end if;
  elsif v_samples = 1 then
    v_interp := 'insufficient';
  else
    v_interp := 'unknown';
  end if;

  return jsonb_build_object(
    'start_kg', round(v_start_kg, 2),
    'end_kg', round(v_end_kg, 2),
    'delta_kg', round(v_delta, 2),
    'samples', v_samples,
    'interpretation', v_interp
  );
end;
$$;

create or replace function public.nutrition_logging_quality_v1(
  p_user_id uuid,
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
  v_day_count integer;
  v_diary_days integer := 0;
  v_days_logged_ratio numeric := 0;
  v_median_kcal numeric := 0;
  v_partial_dates date[] := '{}'::date[];
begin
  v_day_count := greatest(1, (p_end_date - p_start_date) + 1);

  select count(distinct log_date)
  into v_diary_days
  from public.nutrition_diary_logs
  where user_id = p_user_id
    and log_date between p_start_date and p_end_date;

  v_days_logged_ratio := v_diary_days::numeric / v_day_count;

  with daily as (
    select log_date, sum(kcal) as day_kcal
    from public.nutrition_log_metrics_v1(p_user_id, p_start_date, p_end_date)
    group by log_date
  ),
  med as (
    select percentile_cont(0.5) within group (order by day_kcal) as median_kcal
    from daily
  )
  select coalesce(median_kcal, 0) into v_median_kcal from med;

  if v_median_kcal > 0 then
    select coalesce(array_agg(log_date order by log_date), '{}'::date[])
    into v_partial_dates
    from (
      select log_date, sum(kcal) as day_kcal
      from public.nutrition_log_metrics_v1(p_user_id, p_start_date, p_end_date)
      group by log_date
      having sum(kcal) < v_median_kcal * 0.4
    ) partial;
  end if;

  return jsonb_build_object(
    'day_count', v_day_count,
    'days_logged', v_diary_days,
    'days_logged_ratio', round(v_days_logged_ratio, 3),
    'median_kcal_logged_day', round(v_median_kcal, 1),
    'partial_log_dates', to_jsonb(v_partial_dates)
  );
end;
$$;

revoke all on function public.nutrition_is_intense_workout_v1(public.workout_kind, text) from public;
grant execute on function public.nutrition_is_intense_workout_v1(public.workout_kind, text) to authenticated;

revoke all on function public.nutrition_log_metrics_v1(uuid, date, date) from public;
revoke all on function public.nutrition_top_food_contributors_v1(uuid, date, date, text, integer) from public;
revoke all on function public.nutrition_meal_slot_summary_v1(uuid, date, date) from public;
revoke all on function public.nutrition_training_rest_split_v1(uuid, date, date) from public;
revoke all on function public.nutrition_weight_trend_v1(uuid, date, date) from public;
revoke all on function public.nutrition_logging_quality_v1(uuid, date, date) from public;

notify pgrst, 'reload schema';

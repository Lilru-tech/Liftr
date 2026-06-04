set local check_function_bodies = off;

drop function if exists public.nutrition_workout_activity_multiplier_v1(numeric, numeric);

create or replace function public.nutrition_intense_training_days_per_week_v1(p_user_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(
    count(distinct date(coalesce(w.started_at, w.created_at)))::numeric / 4.0,
    0
  )
  from public.workouts w
  where w.user_id = p_user_id
    and w.state = 'published'::public.workout_state
    and (
      w.kind in ('strength'::public.workout_kind, 'sport'::public.workout_kind)
      or (
        w.kind = 'cardio'::public.workout_kind
        and coalesce(w.title, '') not ilike '%walk%'
        and coalesce(w.title, '') not ilike '%caminata%'
      )
    )
    and coalesce(w.started_at, w.created_at) >= now() - interval '28 days';
$$;

create or replace function public.nutrition_workouts_per_week_v1(p_user_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
  select public.nutrition_intense_training_days_per_week_v1(p_user_id);
$$;

create or replace function public.nutrition_workout_activity_multiplier_v1(
  p_intense_days_per_week numeric
)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  v_idpw numeric;
begin
  v_idpw := coalesce(p_intense_days_per_week, 0);

  if v_idpw >= 5.5 then
    return 1.725;
  elsif v_idpw >= 3.5 then
    return 1.55;
  elsif v_idpw >= 1.5 then
    return 1.375;
  end if;

  return 1.2;
end;
$$;

create or replace function public.nutrition_compute_dynamic_metabolic_target_v1(
  p_user_id uuid,
  p_sex text,
  p_date_of_birth date,
  p_height_cm numeric,
  p_weight_kg numeric
)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_bmr integer;
  v_intense_days_per_week numeric;
  v_mult numeric;
begin
  v_bmr := public.nutrition_compute_bmr_kcal_v1(
    p_sex,
    p_date_of_birth,
    p_height_cm,
    p_weight_kg
  );

  v_intense_days_per_week := public.nutrition_intense_training_days_per_week_v1(p_user_id);
  v_mult := public.nutrition_workout_activity_multiplier_v1(v_intense_days_per_week);

  return greatest(800, least(6000, round(v_bmr * v_mult)::integer));
end;
$$;

create or replace function public.nutrition_resolve_base_calories_target_v1(p_user_id uuid)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_sex text;
  v_dob date;
  v_height_cm numeric;
  v_weight_kg numeric;
  v_is_manual boolean;
  v_stored integer;
begin
  select
    p.sex::text,
    p.date_of_birth,
    p.height_cm::numeric,
    p.weight_kg,
    p.base_calories_target_is_manual,
    p.base_calories_target
  into
    v_sex,
    v_dob,
    v_height_cm,
    v_weight_kg,
    v_is_manual,
    v_stored
  from public.profiles p
  where p.user_id = p_user_id;

  if not found then
    return null;
  end if;

  if coalesce(v_is_manual, false) then
    return greatest(800, least(6000, coalesce(v_stored, 1700)));
  end if;

  return public.nutrition_compute_dynamic_metabolic_target_v1(
    p_user_id,
    v_sex,
    v_dob,
    v_height_cm,
    v_weight_kg
  );
end;
$$;

update public.profiles p
set base_calories_target = public.nutrition_resolve_base_calories_target_v1(p.user_id)
where coalesce(p.base_calories_target_is_manual, false) = false;

revoke all on function public.nutrition_intense_training_days_per_week_v1(uuid) from public;
grant execute on function public.nutrition_intense_training_days_per_week_v1(uuid) to authenticated;

revoke all on function public.nutrition_workout_activity_multiplier_v1(numeric) from public;
grant execute on function public.nutrition_workout_activity_multiplier_v1(numeric) to authenticated;

revoke all on function public.nutrition_compute_dynamic_metabolic_target_v1(uuid, text, date, numeric, numeric) from public;
grant execute on function public.nutrition_compute_dynamic_metabolic_target_v1(uuid, text, date, numeric, numeric) to authenticated;

revoke all on function public.nutrition_resolve_base_calories_target_v1(uuid) from public;
grant execute on function public.nutrition_resolve_base_calories_target_v1(uuid) to authenticated;

notify pgrst, 'reload schema';

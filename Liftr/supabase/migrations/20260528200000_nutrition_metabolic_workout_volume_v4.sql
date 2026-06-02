set local check_function_bodies = off;

drop function if exists public.nutrition_workout_activity_multiplier_v1(numeric);

create or replace function public.nutrition_workout_weekly_volume_v1(p_user_id uuid)
returns table (
  workouts_per_week numeric,
  minutes_per_week numeric
)
language sql
stable
set search_path = public
as $$
  select
    coalesce(count(*)::numeric / 4.0, 0),
    coalesce(sum(w.duration_min)::numeric / 4.0, 0)
  from public.workouts w
  where w.user_id = p_user_id
    and w.state = 'published'::public.workout_state
    and w.duration_min is not null
    and w.duration_min > 0
    and not (
      w.kind = 'cardio'::public.workout_kind
      and w.duration_min < 20
    )
    and coalesce(w.started_at, w.created_at) >= now() - interval '28 days';
$$;

create or replace function public.nutrition_workouts_per_week_v1(p_user_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
  select v.workouts_per_week
  from public.nutrition_workout_weekly_volume_v1(p_user_id) v;
$$;

create or replace function public.nutrition_minutes_per_week_v1(p_user_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
  select v.minutes_per_week
  from public.nutrition_workout_weekly_volume_v1(p_user_id) v;
$$;

create or replace function public.nutrition_workout_activity_multiplier_v1(
  p_workouts_per_week numeric,
  p_minutes_per_week numeric
)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  v_wpw numeric;
  v_mpw numeric;
begin
  v_wpw := coalesce(p_workouts_per_week, 0);
  v_mpw := coalesce(p_minutes_per_week, 0);

  if v_wpw > 5.5 and v_mpw >= 240 then
    return 1.725;
  elsif v_wpw > 3.5 and v_mpw >= 150 then
    return 1.55;
  elsif v_wpw > 1.5 and v_mpw >= 60 then
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
  v_wpw numeric;
  v_mpw numeric;
  v_mult numeric;
begin
  v_bmr := public.nutrition_compute_bmr_kcal_v1(
    p_sex,
    p_date_of_birth,
    p_height_cm,
    p_weight_kg
  );

  select v.workouts_per_week, v.minutes_per_week
  into v_wpw, v_mpw
  from public.nutrition_workout_weekly_volume_v1(p_user_id) v;

  v_mult := public.nutrition_workout_activity_multiplier_v1(v_wpw, v_mpw);

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

revoke all on function public.nutrition_workout_weekly_volume_v1(uuid) from public;
grant execute on function public.nutrition_workout_weekly_volume_v1(uuid) to authenticated;

revoke all on function public.nutrition_minutes_per_week_v1(uuid) from public;
grant execute on function public.nutrition_minutes_per_week_v1(uuid) to authenticated;

revoke all on function public.nutrition_workout_activity_multiplier_v1(numeric, numeric) from public;
grant execute on function public.nutrition_workout_activity_multiplier_v1(numeric, numeric) to authenticated;

revoke all on function public.nutrition_compute_dynamic_metabolic_target_v1(uuid, text, date, numeric, numeric) from public;
grant execute on function public.nutrition_compute_dynamic_metabolic_target_v1(uuid, text, date, numeric, numeric) to authenticated;

revoke all on function public.nutrition_resolve_base_calories_target_v1(uuid) from public;
grant execute on function public.nutrition_resolve_base_calories_target_v1(uuid) to authenticated;

notify pgrst, 'reload schema';

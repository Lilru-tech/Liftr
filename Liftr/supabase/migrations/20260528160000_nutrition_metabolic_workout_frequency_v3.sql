set local check_function_bodies = off;

drop function if exists public.nutrition_compute_metabolic_target_kcal_v1(text, date, numeric, numeric);
drop function if exists public.nutrition_compute_metabolic_target_kcal_v1(text, date, numeric, numeric, text);

create or replace function public.nutrition_sex_offset_v1(p_sex text)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  v_sex text;
begin
  v_sex := lower(btrim(coalesce(p_sex, '')));

  if v_sex in ('male', 'm') then
    return 5;
  elsif v_sex in ('female', 'f') then
    return -161;
  end if;

  return -80;
end;
$$;

create or replace function public.nutrition_workouts_per_week_v1(p_user_id uuid)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(
    count(*) filter (
      where w.state = 'published'
        and coalesce(w.started_at, w.created_at) >= now() - interval '28 days'
    )::numeric / 4.0,
    0
  )
  from public.workouts w
  where w.user_id = p_user_id;
$$;

create or replace function public.nutrition_workout_activity_multiplier_v1(p_workouts_per_week numeric)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  v_wpw numeric;
begin
  v_wpw := coalesce(p_workouts_per_week, 0);

  if v_wpw < 1.5 then
    return 1.2;
  elsif v_wpw < 3.5 then
    return 1.375;
  elsif v_wpw < 5.5 then
    return 1.55;
  end if;

  return 1.725;
end;
$$;

create or replace function public.nutrition_compute_bmr_kcal_v1(
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
  v_sex text;
  v_age_years integer;
  v_height_cm numeric;
  v_weight_kg numeric;
  v_bmr numeric;
begin
  v_sex := lower(btrim(coalesce(p_sex, '')));

  if p_date_of_birth is null then
    v_age_years := 30;
  else
    v_age_years := extract(year from age(current_date, p_date_of_birth))::integer;
  end if;

  if p_height_cm is null or p_height_cm <= 0 or p_weight_kg is null or p_weight_kg <= 0 then
    if v_sex in ('male', 'm') then
      v_height_cm := coalesce(nullif(p_height_cm, 0), 175);
      v_weight_kg := coalesce(nullif(p_weight_kg, 0), 75);
    else
      v_height_cm := coalesce(nullif(p_height_cm, 0), 162);
      v_weight_kg := coalesce(nullif(p_weight_kg, 0), 60);
    end if;
  else
    v_height_cm := p_height_cm;
    v_weight_kg := p_weight_kg;
  end if;

  v_bmr := (10 * v_weight_kg)
    + (6.25 * v_height_cm)
    - (5 * v_age_years)
    + public.nutrition_sex_offset_v1(p_sex);

  return greatest(800, least(6000, round(v_bmr)::integer));
end;
$$;

create or replace function public.nutrition_compute_bmr_kcal_v2(
  p_sex text,
  p_date_of_birth date,
  p_height_cm numeric,
  p_weight_kg numeric
)
returns integer
language sql
stable
set search_path = public
as $$
  select public.nutrition_compute_bmr_kcal_v1(
    p_sex,
    p_date_of_birth,
    p_height_cm,
    p_weight_kg
  );
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
  v_mult numeric;
begin
  v_bmr := public.nutrition_compute_bmr_kcal_v1(
    p_sex,
    p_date_of_birth,
    p_height_cm,
    p_weight_kg
  );

  v_wpw := public.nutrition_workouts_per_week_v1(p_user_id);
  v_mult := public.nutrition_workout_activity_multiplier_v1(v_wpw);

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

create or replace function public.profiles_apply_metabolic_target_v1()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(new.base_calories_target_is_manual, false) then
    return new;
  end if;

  new.base_calories_target := public.nutrition_compute_dynamic_metabolic_target_v1(
    new.user_id,
    new.sex::text,
    new.date_of_birth,
    new.height_cm::numeric,
    new.weight_kg
  );

  return new;
end;
$$;

drop trigger if exists profiles_apply_metabolic_target on public.profiles;
create trigger profiles_apply_metabolic_target
  before insert or update of sex, date_of_birth, height_cm, weight_kg, base_calories_target_is_manual
  on public.profiles
  for each row
  execute function public.profiles_apply_metabolic_target_v1();

create or replace function public.tr_fn_workout_sync_metabolism()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_user_id uuid;
begin
  v_target_user_id := coalesce(new.user_id, old.user_id);

  if v_target_user_id is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  update public.profiles p
  set base_calories_target = public.nutrition_resolve_base_calories_target_v1(p.user_id)
  where p.user_id = v_target_user_id
    and coalesce(p.base_calories_target_is_manual, false) = false;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_workouts_sync_metabolism on public.workouts;
create trigger trg_workouts_sync_metabolism
  after insert or update or delete on public.workouts
  for each row
  execute function public.tr_fn_workout_sync_metabolism();

create or replace function public.refresh_profile_metabolic_target_v1(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target integer;
begin
  update public.profiles p
  set base_calories_target = public.nutrition_resolve_base_calories_target_v1(p.user_id)
  where p.user_id = p_user_id
    and coalesce(p.base_calories_target_is_manual, false) = false
  returning p.base_calories_target into v_target;

  return v_target;
end;
$$;

create or replace function public.refresh_all_profile_metabolic_targets_v1()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  update public.profiles p
  set base_calories_target = public.nutrition_resolve_base_calories_target_v1(p.user_id)
  where coalesce(p.base_calories_target_is_manual, false) = false
    and p.base_calories_target is distinct from public.nutrition_resolve_base_calories_target_v1(p.user_id);

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

update public.profiles p
set base_calories_target = public.nutrition_resolve_base_calories_target_v1(p.user_id)
where coalesce(p.base_calories_target_is_manual, false) = false;

revoke all on function public.nutrition_sex_offset_v1(text) from public;
grant execute on function public.nutrition_sex_offset_v1(text) to authenticated;

revoke all on function public.nutrition_workouts_per_week_v1(uuid) from public;
grant execute on function public.nutrition_workouts_per_week_v1(uuid) to authenticated;

revoke all on function public.nutrition_workout_activity_multiplier_v1(numeric) from public;
grant execute on function public.nutrition_workout_activity_multiplier_v1(numeric) to authenticated;

revoke all on function public.nutrition_compute_dynamic_metabolic_target_v1(uuid, text, date, numeric, numeric) from public;
grant execute on function public.nutrition_compute_dynamic_metabolic_target_v1(uuid, text, date, numeric, numeric) to authenticated;

revoke all on function public.nutrition_resolve_base_calories_target_v1(uuid) from public;
grant execute on function public.nutrition_resolve_base_calories_target_v1(uuid) to authenticated;

notify pgrst, 'reload schema';

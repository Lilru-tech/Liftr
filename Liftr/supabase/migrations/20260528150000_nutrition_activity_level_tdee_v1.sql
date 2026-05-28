set local check_function_bodies = off;

alter table public.profiles
  add column if not exists activity_level text;

update public.profiles
set activity_level = 'sedentary'
where activity_level is null or btrim(activity_level) = '';

alter table public.profiles
  alter column activity_level set default 'sedentary';

alter table public.profiles
  alter column activity_level set not null;

alter table public.profiles
  drop constraint if exists profiles_activity_level_check;

alter table public.profiles
  add constraint profiles_activity_level_check
  check (activity_level in ('sedentary', 'lightly_active', 'moderately_active', 'very_active'));

create or replace function public.nutrition_activity_multiplier_v1(p_activity_level text)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_level text;
begin
  v_level := lower(btrim(coalesce(p_activity_level, '')));

  if v_level = 'lightly_active' then
    return 1.375;
  elsif v_level = 'moderately_active' then
    return 1.55;
  elsif v_level = 'very_active' then
    return 1.725;
  end if;

  return 1.2;
end;
$$;

create or replace function public.nutrition_compute_bmr_kcal_v2(
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
  v_bmr numeric;
  v_sex_offset numeric;
begin
  if p_date_of_birth is null
     or p_height_cm is null or p_height_cm <= 0
     or p_weight_kg is null or p_weight_kg <= 0 then
    return null;
  end if;

  v_sex := lower(btrim(coalesce(p_sex, '')));

  if v_sex in ('male', 'm') then
    v_sex_offset := 5;
  elsif v_sex in ('female', 'f') then
    v_sex_offset := -161;
  else
    v_sex_offset := -80;
  end if;

  v_age_years := extract(year from age(current_date, p_date_of_birth))::integer;

  v_bmr := (10 * p_weight_kg)
    + (6.25 * p_height_cm)
    - (5 * v_age_years)
    + v_sex_offset;

  return greatest(800, least(6000, round(v_bmr)::integer));
end;
$$;

create or replace function public.nutrition_compute_bmr_kcal_v1(
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
  select public.nutrition_compute_bmr_kcal_v2(
    p_sex,
    p_date_of_birth,
    p_height_cm,
    p_weight_kg
  );
$$;

drop function if exists public.nutrition_compute_metabolic_target_kcal_v1(text, date, numeric, numeric);

create or replace function public.nutrition_compute_metabolic_target_kcal_v1(
  p_sex text,
  p_date_of_birth date,
  p_height_cm numeric,
  p_weight_kg numeric,
  p_activity_level text
)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_bmr integer;
  v_mult numeric;
begin
  v_bmr := public.nutrition_compute_bmr_kcal_v2(
    p_sex,
    p_date_of_birth,
    p_height_cm,
    p_weight_kg
  );

  if v_bmr is null then
    return null;
  end if;

  v_mult := public.nutrition_activity_multiplier_v1(p_activity_level);

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
  v_activity_level text;
  v_is_manual boolean;
  v_stored integer;
  v_calc integer;
begin
  select
    p.sex::text,
    p.date_of_birth,
    p.height_cm::numeric,
    p.weight_kg,
    p.activity_level::text,
    p.base_calories_target_is_manual,
    p.base_calories_target
  into
    v_sex,
    v_dob,
    v_height_cm,
    v_weight_kg,
    v_activity_level,
    v_is_manual,
    v_stored
  from public.profiles p
  where p.user_id = p_user_id;

  if coalesce(v_is_manual, false) then
    return greatest(
      800,
      least(
        6000,
        coalesce(v_stored, public.nutrition_demographic_fallback_kcal_v1(v_sex))
      )
    );
  end if;

  v_calc := public.nutrition_compute_metabolic_target_kcal_v1(
    v_sex,
    v_dob,
    v_height_cm,
    v_weight_kg,
    v_activity_level
  );

  return coalesce(v_calc, public.nutrition_demographic_fallback_kcal_v1(v_sex));
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

  if tg_op = 'UPDATE' then
    if new.sex is not distinct from old.sex
       and new.date_of_birth is not distinct from old.date_of_birth
       and new.height_cm is not distinct from old.height_cm
       and new.weight_kg is not distinct from old.weight_kg
       and new.activity_level is not distinct from old.activity_level
       and new.base_calories_target_is_manual is not distinct from old.base_calories_target_is_manual then
      return new;
    end if;
  end if;

  new.base_calories_target := coalesce(
    public.nutrition_compute_metabolic_target_kcal_v1(
      new.sex::text,
      new.date_of_birth,
      new.height_cm::numeric,
      new.weight_kg,
      new.activity_level::text
    ),
    public.nutrition_demographic_fallback_kcal_v1(new.sex::text)
  );

  return new;
end;
$$;

drop trigger if exists profiles_apply_metabolic_target on public.profiles;
create trigger profiles_apply_metabolic_target
  before insert or update of sex, date_of_birth, height_cm, weight_kg, activity_level, base_calories_target_is_manual
  on public.profiles
  for each row
  execute function public.profiles_apply_metabolic_target_v1();

update public.profiles p
set base_calories_target = public.nutrition_resolve_base_calories_target_v1(p.user_id)
where coalesce(p.base_calories_target_is_manual, false) = false;

revoke all on function public.nutrition_activity_multiplier_v1(text) from public;
grant execute on function public.nutrition_activity_multiplier_v1(text) to authenticated;

revoke all on function public.nutrition_compute_bmr_kcal_v2(text, date, numeric, numeric) from public;
grant execute on function public.nutrition_compute_bmr_kcal_v2(text, date, numeric, numeric) to authenticated;

revoke all on function public.nutrition_compute_metabolic_target_kcal_v1(text, date, numeric, numeric, text) from public;
grant execute on function public.nutrition_compute_metabolic_target_kcal_v1(text, date, numeric, numeric, text) to authenticated;

revoke all on function public.nutrition_resolve_base_calories_target_v1(uuid) from public;
grant execute on function public.nutrition_resolve_base_calories_target_v1(uuid) to authenticated;

notify pgrst, 'reload schema';

set local check_function_bodies = off;

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
  if tg_op = 'UPDATE' then
    if (old.weight_kg is distinct from new.weight_kg)
       or (old.height_cm is distinct from new.height_cm)
       or (old.date_of_birth is distinct from new.date_of_birth)
       or (old.sex is distinct from new.sex) then
      new.base_calories_target_is_manual := false;
      new.base_calories_target := public.nutrition_compute_dynamic_metabolic_target_v1(
        new.user_id,
        new.sex::text,
        new.date_of_birth,
        new.height_cm::numeric,
        new.weight_kg
      );
    elsif coalesce(new.base_calories_target_is_manual, false) then
      new.base_calories_target := new.base_calories_target;
    else
      new.base_calories_target := public.nutrition_compute_dynamic_metabolic_target_v1(
        new.user_id,
        new.sex::text,
        new.date_of_birth,
        new.height_cm::numeric,
        new.weight_kg
      );
    end if;
  else
    if coalesce(new.base_calories_target_is_manual, false) = false then
      new.base_calories_target := public.nutrition_compute_dynamic_metabolic_target_v1(
        new.user_id,
        new.sex::text,
        new.date_of_birth,
        new.height_cm::numeric,
        new.weight_kg
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_apply_metabolic_target on public.profiles;
create trigger profiles_apply_metabolic_target
  before insert or update of sex, date_of_birth, height_cm, weight_kg, base_calories_target, base_calories_target_is_manual
  on public.profiles
  for each row
  execute function public.profiles_apply_metabolic_target_v1();

notify pgrst, 'reload schema';

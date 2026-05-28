set local check_function_bodies = off;

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

create or replace function public.refresh_profile_weight_kg(p_user_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  v_weight numeric;
begin
  select b.weight_kg
  into v_weight
  from public.body_weight_entries b
  where b.user_id = p_user_id
  order by b.measured_at desc, b.created_at desc
  limit 1;

  update public.profiles p
  set
    weight_kg = v_weight,
    updated_at = now()
  where p.user_id = p_user_id;

  perform public.refresh_profile_metabolic_target_v1(p_user_id);
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
       and new.base_calories_target_is_manual is not distinct from old.base_calories_target_is_manual then
      return new;
    end if;
  end if;

  new.base_calories_target := coalesce(
    public.nutrition_compute_metabolic_target_kcal_v1(
      new.sex::text,
      new.date_of_birth,
      new.height_cm::numeric,
      new.weight_kg
    ),
    public.nutrition_demographic_fallback_kcal_v1(new.sex::text)
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

revoke all on function public.refresh_profile_metabolic_target_v1(uuid) from public;
grant execute on function public.refresh_profile_metabolic_target_v1(uuid) to authenticated;

revoke all on function public.refresh_all_profile_metabolic_targets_v1() from public;

do $$
declare
  v_job_id bigint;
begin
  select jobid
  into v_job_id
  from cron.job
  where jobname = 'refresh_profile_metabolic_targets_daily';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'refresh_profile_metabolic_targets_daily',
    '5 3 * * *',
    $cmd$select public.refresh_all_profile_metabolic_targets_v1()$cmd$
  );
end;
$$;

notify pgrst, 'reload schema';

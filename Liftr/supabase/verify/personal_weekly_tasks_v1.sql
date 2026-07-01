-- Personal weekly tasks v1 — verification script (run in Supabase SQL editor after migration)
-- Expects migration 20260718160000_personal_weekly_tasks_v1.sql applied.

begin;

do $verify$
declare
  v_user uuid;
  v_task_id uuid;
  v_count int;
  v_ws timestamptz;
  v_we timestamptz;
begin
  if to_regclass('public.user_tasks') is null then
    raise exception 'FAIL: public.user_tasks missing — apply migration first';
  end if;

  if to_regclass('public.task_templates') is null then
    raise exception 'FAIL: public.task_templates missing';
  end if;

  select count(*) into v_count from public.task_templates where is_active;
  if v_count < 10 then
    raise exception 'FAIL: expected seeded task_templates, got %', v_count;
  end if;

  select b.w_start, b.w_end into v_ws, v_we from public._challenge_week_bounds_utc(now()) as b;

  select user_id into v_user
  from public.profiles
  limit 1;

  if v_user is null then
    raise notice 'SKIP: no profiles row for live generation test';
  else
    perform public._user_tasks_ensure_weekly_for_user(v_user);

    select count(*) into v_count
    from public.user_tasks ut
    where ut.user_id = v_user and ut.week_start = v_ws and ut.status <> 'expired';

    if v_count <> 5 then
      raise exception 'FAIL: expected 5 user_tasks for current week, got %', v_count;
    end if;

    raise notice 'OK: generated % tasks for user %', v_count, v_user;
  end if;

  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'list_my_weekly_tasks_v1'
  ) then
    raise notice 'OK: list_my_weekly_tasks_v1 exists';
  else
    raise exception 'FAIL: list_my_weekly_tasks_v1 missing';
  end if;

  if exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where c.relname = 'workouts' and t.tgname = 'tr_workouts_evaluate_user_tasks_after_publish'
  ) then
    raise notice 'OK: workout publish trigger exists';
  else
    raise exception 'FAIL: tr_workouts_evaluate_user_tasks_after_publish missing';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'task_points_total'
  ) then
    raise notice 'OK: profiles.task_points_total exists';
  else
    raise exception 'FAIL: profiles.task_points_total missing';
  end if;

  raise notice 'personal_weekly_tasks_v1 verification passed';
end;
$verify$;

rollback;

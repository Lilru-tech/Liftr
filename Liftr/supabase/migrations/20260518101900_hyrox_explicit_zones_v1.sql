drop trigger if exists trg_hyrox_session_exercises_zone_order on public.hyrox_session_exercises;
drop trigger if exists trg_hyrox_routine_exercises_zone_order on public.hyrox_routine_exercises;

alter table public.hyrox_session_exercises
  alter column zone_order drop not null;

alter table public.hyrox_routine_exercises
  alter column zone_order drop not null;

update public.hyrox_session_exercises
set zone_order = null;

update public.hyrox_routine_exercises
set zone_order = null;

alter table public.hyrox_session_exercises
  drop constraint if exists hyrox_session_exercises_zone_order_check;

alter table public.hyrox_session_exercises
  add constraint hyrox_session_exercises_zone_order_check
  check (zone_order is null or zone_order >= 1);

alter table public.hyrox_routine_exercises
  drop constraint if exists hyrox_routine_exercises_zone_order_check;

alter table public.hyrox_routine_exercises
  add constraint hyrox_routine_exercises_zone_order_check
  check (zone_order is null or zone_order >= 1);

drop index if exists public.idx_hyrox_session_exercises_session_zone_order;
drop index if exists public.idx_hyrox_routine_exercises_routine_zone_order;

create index if not exists idx_hyrox_session_exercises_session_zone_order
  on public.hyrox_session_exercises (session_id, zone_order, exercise_order)
  where zone_order is not null;

create index if not exists idx_hyrox_routine_exercises_routine_zone_order
  on public.hyrox_routine_exercises (routine_id, zone_order, exercise_order)
  where zone_order is not null;

alter table public.hyrox_session_exercises
  add column if not exists zone_order integer;

alter table public.hyrox_routine_exercises
  add column if not exists zone_order integer;

update public.hyrox_session_exercises
set zone_order = greatest(1, ((exercise_order::integer + 1) / 2))
where zone_order is null;

update public.hyrox_routine_exercises
set zone_order = greatest(1, ((exercise_order::integer + 1) / 2))
where zone_order is null;

alter table public.hyrox_session_exercises
  alter column zone_order set not null;

alter table public.hyrox_routine_exercises
  alter column zone_order set not null;

alter table public.hyrox_session_exercises
  drop constraint if exists hyrox_session_exercises_zone_order_check;

alter table public.hyrox_session_exercises
  add constraint hyrox_session_exercises_zone_order_check
  check (zone_order >= 1);

alter table public.hyrox_routine_exercises
  drop constraint if exists hyrox_routine_exercises_zone_order_check;

alter table public.hyrox_routine_exercises
  add constraint hyrox_routine_exercises_zone_order_check
  check (zone_order >= 1);

create index if not exists idx_hyrox_session_exercises_session_zone_order
  on public.hyrox_session_exercises (session_id, zone_order, exercise_order);

create index if not exists idx_hyrox_routine_exercises_routine_zone_order
  on public.hyrox_routine_exercises (routine_id, zone_order, exercise_order);

create or replace function public.set_hyrox_exercise_zone_order()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.zone_order is null then
    new.zone_order := greatest(1, ((new.exercise_order::integer + 1) / 2));
  end if;

  return new;
end;
$$;

drop trigger if exists trg_hyrox_session_exercises_zone_order on public.hyrox_session_exercises;
create trigger trg_hyrox_session_exercises_zone_order
before insert or update of exercise_order, zone_order on public.hyrox_session_exercises
for each row execute function public.set_hyrox_exercise_zone_order();

drop trigger if exists trg_hyrox_routine_exercises_zone_order on public.hyrox_routine_exercises;
create trigger trg_hyrox_routine_exercises_zone_order
before insert or update of exercise_order, zone_order on public.hyrox_routine_exercises
for each row execute function public.set_hyrox_exercise_zone_order();

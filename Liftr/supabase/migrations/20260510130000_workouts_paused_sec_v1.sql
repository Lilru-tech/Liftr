-- Active strength workouts now support pausing. Persist the cumulative paused seconds on
-- the workout row so the generated `duration_min` reflects active time only. Defaulting
-- paused_sec to 0 keeps cardio/sport rows and existing strength rows unchanged.

alter table public.workouts
  add column if not exists paused_sec integer not null default 0;

alter table public.workouts
  drop constraint if exists workouts_paused_sec_nonneg;

alter table public.workouts
  add constraint workouts_paused_sec_nonneg check (paused_sec >= 0) not valid;

alter table public.workouts
  validate constraint workouts_paused_sec_nonneg;

alter table public.workouts
  alter column duration_min set expression as (
    case
      when started_at is not null and ended_at is not null then
        greatest(
          0,
          floor((extract(epoch from (ended_at - started_at)) - paused_sec) / 60)::int
        )
      else null
    end
  );

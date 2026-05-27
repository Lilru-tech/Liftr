begin;

alter table public.workout_exercises
  add column if not exists superset_group_id uuid,
  add column if not exists superset_position integer;

alter table public.workout_exercises
  drop constraint if exists workout_exercises_superset_position_positive;

alter table public.workout_exercises
  add constraint workout_exercises_superset_position_positive
  check (superset_position is null or superset_position >= 1);

create index if not exists workout_exercises_superset_group_idx
  on public.workout_exercises (workout_id, superset_group_id, superset_position, order_index)
  where superset_group_id is not null;

commit;

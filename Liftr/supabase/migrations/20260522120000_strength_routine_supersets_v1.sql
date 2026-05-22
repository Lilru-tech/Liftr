begin;

alter table public.strength_routine_exercises
  add column if not exists superset_group_id uuid,
  add column if not exists superset_position integer;

alter table public.strength_routine_exercises
  drop constraint if exists strength_routine_exercises_superset_position_positive;

alter table public.strength_routine_exercises
  add constraint strength_routine_exercises_superset_position_positive
  check (superset_position is null or superset_position >= 1);

create index if not exists strength_routine_exercises_superset_group_idx
  on public.strength_routine_exercises (routine_id, superset_group_id, superset_position, order_index)
  where superset_group_id is not null;

commit;

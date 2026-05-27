begin;

drop policy if exists "we_select_participant" on public.workout_exercises;
create policy "we_select_participant"
on public.workout_exercises
for select
to authenticated
using (
  public.is_workout_participant(workout_id, auth.uid())
);

drop policy if exists "es_select_participant" on public.exercise_sets;
create policy "es_select_participant"
on public.exercise_sets
for select
to authenticated
using (
  exists (
    select 1
    from public.workout_exercises we
    where we.id = exercise_sets.workout_exercise_id
      and public.is_workout_participant(we.workout_id, auth.uid())
  )
);

commit;

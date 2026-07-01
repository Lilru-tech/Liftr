-- Verify update_strength_workout_v1 persists edited sets before first-time finalize purge.
-- Run in staging with a real in-progress strength workout owned by the session user,
-- or adapt the fixture block below.

-- Fixture sketch (uncomment and substitute ids for a one-off manual test):
-- 1. Pick workout_id W with ended_at IS NULL and at least one workout_exercise WE.
-- 2. Ensure exercise_sets for WE have is_completed = false (live template rows).
-- 3. Call update_strength_workout_v1 with p_ended_at := now() and edited set payload.
-- 4. Assert WE still exists and exercise_sets for WE have is_completed = true.

-- Example call shape (replace :workout_id):
/*
select public.update_strength_workout_v1(
  p_workout_id => :workout_id,
  p_title => (select title from public.workouts where id = :workout_id),
  p_notes => (select notes from public.workouts where id = :workout_id),
  p_started_at => (select started_at from public.workouts where id = :workout_id),
  p_ended_at => timezone('utc', now()),
  p_perceived_intensity => (select perceived_intensity::text from public.workouts where id = :workout_id),
  p_exercises => (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'workout_exercise_id', we.id,
        'exercise_id', we.exercise_id,
        'order_index', we.order_index,
        'notes', we.notes,
        'custom_name', we.custom_name,
        'sets', jsonb_build_array(
          jsonb_build_object(
            'set_number', 1,
            'order_index', 1,
            'reps', 10,
            'weight_kg', 22.5,
            'rpe', 9,
            'rest_sec', 60
          )
        )
      )
      order by we.order_index, we.id
    ), '[]'::jsonb)
    from public.workout_exercises we
    where we.workout_id = :workout_id
  )
);

select w.id, w.ended_at, w.state
from public.workouts w
where w.id = :workout_id;

select we.id, we.workout_id, count(es.id) as set_count,
       bool_and(es.is_completed) as all_sets_completed
from public.workout_exercises we
left join public.exercise_sets es on es.workout_exercise_id = we.id
where we.workout_id = :workout_id
group by we.id, we.workout_id
order by we.order_index, we.id;
*/

select 'strength_edit_finalize_order verification template loaded' as status;

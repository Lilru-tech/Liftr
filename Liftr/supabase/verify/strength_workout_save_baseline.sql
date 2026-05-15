-- Baseline timing templates for strength workout save RPCs.
-- Replace :workout_id with a real strength workout id before running in staging.

-- Median-ish sample from production: workout 523 (6 exercises, 24 sets)
-- Heavy sample: workout 457 (7 exercises, 29 sets)

explain (analyze, buffers)
select public.update_strength_workout_v1(
  p_workout_id => 523,
  p_title => (select title from public.workouts where id = 523),
  p_notes => (select notes from public.workouts where id = 523),
  p_started_at => (select started_at from public.workouts where id = 523),
  p_ended_at => (select ended_at from public.workouts where id = 523),
  p_perceived_intensity => (select perceived_intensity::text from public.workouts where id = 523),
  p_exercises => coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'workout_exercise_id', we.id,
          'exercise_id', we.exercise_id,
          'notes', we.notes,
          'custom_name', we.custom_name,
          'sets', coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'set_number', es.set_number,
                  'reps', es.reps,
                  'weight_kg', es.weight_kg,
                  'rpe', es.rpe,
                  'rest_sec', es.rest_sec,
                  'weight_segments', es.weight_segments
                )
                order by es.set_number, es.id
              )
              from public.exercise_sets es
              where es.workout_exercise_id = we.id
            ),
            '[]'::jsonb
          )
        )
        order by we.order_index, we.id
      )
      from public.workout_exercises we
      where we.workout_id = 523
    ),
    '[]'::jsonb
  )
);

explain (analyze, buffers)
select public.finish_strength_workout_v1(
  p_workout_id => 523,
  p_ended_at => timezone('utc', now()),
  p_paused_sec => 0,
  p_exercises => coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'workout_exercise_id', we.id,
          'sets', coalesce(
            (
              select jsonb_agg(
                jsonb_build_object(
                  'set_number', es.set_number,
                  'reps', es.reps,
                  'weight_kg', es.weight_kg,
                  'rpe', es.rpe,
                  'rest_sec', es.rest_sec,
                  'weight_segments', es.weight_segments
                )
                order by es.set_number, es.id
              )
              from public.exercise_sets es
              where es.workout_exercise_id = we.id
            ),
            '[]'::jsonb
          )
        )
        order by we.order_index, we.id
      )
      from public.workout_exercises we
      where we.workout_id = 523
    ),
    '[]'::jsonb
  ),
  p_linked => '[]'::jsonb
);

-- Load strength exercises + sets for a workout row that may belong to the *linked* partner user.
-- The iOS host session uses the partner's workout_id for the guest lane; plain PostgREST reads are
-- blocked by typical RLS ("only owner sees own drafts"). This RPC runs as SECURITY DEFINER and
-- authorizes: workout owner OR user who owns another workout with dual_linked_workout_id = this id.

CREATE OR REPLACE FUNCTION public.fetch_dual_linked_strength_workout_data(p_workout_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  allowed boolean;
  exercises_json jsonb;
  sets_json jsonb;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.workouts w
    WHERE w.id = p_workout_id
      AND (
        w.user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.workouts h
          WHERE h.user_id = auth.uid()
            AND h.dual_linked_workout_id IS NOT DISTINCT FROM w.id
        )
        OR EXISTS (
          SELECT 1
          FROM public.workouts h
          WHERE h.user_id = auth.uid()
            AND h.id IS NOT DISTINCT FROM w.dual_linked_workout_id
        )
      )
  )
  INTO allowed;

  IF NOT allowed THEN
    RAISE EXCEPTION 'forbidden'
      USING ERRCODE = '42501',
            MESSAGE = 'not_allowed_to_read_workout';
  END IF;

  SELECT coalesce(jsonb_agg(row_data ORDER BY ord1, ord2), '[]'::jsonb)
  INTO exercises_json
  FROM (
    SELECT
      jsonb_build_object(
        'id', we.id,
        'exercise_id', we.exercise_id,
        'order_index', we.order_index,
        'notes', we.notes,
        'custom_name', we.custom_name,
        'target_sets', NULL::int,
        'exercises', jsonb_build_object('name', ex.name)
      ) AS row_data,
      we.order_index AS ord1,
      we.id AS ord2
    FROM public.workout_exercises we
    JOIN public.exercises ex ON ex.id = we.exercise_id
    WHERE we.workout_id = p_workout_id
  ) t;

  SELECT coalesce(jsonb_agg(row_data ORDER BY ord1, ord2), '[]'::jsonb)
  INTO sets_json
  FROM (
    SELECT
      jsonb_build_object(
        'id', es.id,
        'workout_exercise_id', es.workout_exercise_id,
        'set_number', es.set_number,
        'reps', es.reps,
        'weight_kg', es.weight_kg,
        'rpe', es.rpe,
        'rest_sec', es.rest_sec
      ) AS row_data,
      es.workout_exercise_id AS ord1,
      es.id AS ord2
    FROM public.exercise_sets es
    JOIN public.workout_exercises we ON we.id = es.workout_exercise_id
    WHERE we.workout_id = p_workout_id
  ) s;

  RETURN jsonb_build_object(
    'exercises', exercises_json,
    'sets', sets_json
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fetch_dual_linked_strength_workout_data(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_dual_linked_strength_workout_data(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_dual_linked_strength_workout_data(bigint) TO service_role;

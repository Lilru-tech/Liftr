-- After a dual session both workouts get ended_at set, but dual_linked_workout_id often
-- stays set. A second "Dual" start hit already_linked because the idempotent branch requires
-- ended_at IS NULL on both. Clear stale symmetric links for the same participant, then clone.

CREATE OR REPLACE FUNCTION public.create_linked_strength_workout_copy(
  p_source_workout_id bigint,
  p_target_user_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  src public.workouts%ROWTYPE;
  guest public.workouts%ROWTYPE;
  new_id bigint;
  we_rec public.workout_exercises%ROWTYPE;
  new_we_id bigint;
  es_rec public.exercise_sets%ROWTYPE;
BEGIN
  SELECT * INTO STRICT src
  FROM public.workouts
  WHERE id = p_source_workout_id;

  IF src.user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF lower(BTRIM(src.kind::text)) IS DISTINCT FROM 'strength' THEN
    RAISE EXCEPTION 'not_strength';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workout_participants wp
    WHERE wp.workout_id = p_source_workout_id
      AND wp.user_id = p_target_user_id
  ) THEN
    RAISE EXCEPTION 'not_participant';
  END IF;

  IF src.dual_linked_workout_id IS NOT NULL THEN
    SELECT * INTO guest
    FROM public.workouts
    WHERE id = src.dual_linked_workout_id;

    IF NOT FOUND THEN
      UPDATE public.workouts
      SET dual_linked_workout_id = NULL
      WHERE id = p_source_workout_id;

      SELECT * INTO STRICT src
      FROM public.workouts
      WHERE id = p_source_workout_id;

    ELSIF guest.user_id = p_target_user_id
      AND guest.dual_linked_workout_id IS NOT DISTINCT FROM p_source_workout_id
      AND guest.ended_at IS NULL
      AND src.ended_at IS NULL
    THEN
      RETURN src.dual_linked_workout_id;

    ELSIF guest.user_id = p_target_user_id
      AND guest.dual_linked_workout_id IS NOT DISTINCT FROM p_source_workout_id
    THEN
      UPDATE public.workouts
      SET dual_linked_workout_id = NULL,
          dual_host_user_id = NULL
      WHERE id = guest.id;

      UPDATE public.workouts
      SET dual_linked_workout_id = NULL
      WHERE id = p_source_workout_id;

      SELECT * INTO STRICT src
      FROM public.workouts
      WHERE id = p_source_workout_id;

    ELSE
      RAISE EXCEPTION 'already_linked';
    END IF;
  END IF;

  INSERT INTO public.workouts (
    user_id,
    kind,
    title,
    notes,
    started_at,
    ended_at,
    state,
    perceived_intensity,
    calories_kcal,
    calories_method,
    calories_weight_kg,
    calories_updated_at,
    healthkit_uuid,
    dual_linked_workout_id,
    dual_host_user_id
  )
  SELECT
    p_target_user_id,
    COALESCE(
      NULLIF(BTRIM(w.kind::text), '')::workout_kind,
      'strength'::workout_kind
    ),
    w.title,
    w.notes,
    w.started_at,
    NULL::timestamptz,
    w.state,
    w.perceived_intensity,
    w.calories_kcal,
    w.calories_method,
    w.calories_weight_kg,
    w.calories_updated_at,
    NULL::text,
    NULL::bigint,
    auth.uid()
  FROM public.workouts w
  WHERE w.id = p_source_workout_id
  RETURNING id INTO new_id;

  FOR we_rec IN
    SELECT * FROM public.workout_exercises
    WHERE workout_id = p_source_workout_id
    ORDER BY order_index ASC, id ASC
  LOOP
    INSERT INTO public.workout_exercises (
      workout_id,
      exercise_id,
      order_index,
      notes,
      custom_name
    )
    VALUES (
      new_id,
      we_rec.exercise_id,
      we_rec.order_index,
      we_rec.notes,
      we_rec.custom_name
    )
    RETURNING id INTO new_we_id;

    FOR es_rec IN
      SELECT * FROM public.exercise_sets
      WHERE workout_exercise_id = we_rec.id
      ORDER BY id ASC
    LOOP
      INSERT INTO public.exercise_sets (
        workout_exercise_id,
        set_number,
        reps,
        weight_kg,
        rpe,
        rest_sec,
        notes
      )
      VALUES (
        new_we_id,
        es_rec.set_number,
        es_rec.reps,
        es_rec.weight_kg,
        es_rec.rpe,
        es_rec.rest_sec,
        es_rec.notes
      );
    END LOOP;
  END LOOP;

  UPDATE public.workouts
  SET dual_linked_workout_id = new_id
  WHERE id = p_source_workout_id;

  UPDATE public.workouts
  SET dual_linked_workout_id = p_source_workout_id
  WHERE id = new_id;

  RETURN new_id;
END;
$function$;

-- Extend plan_strength_squad_programs for published ("Add") workouts: state + optional ended_at.

DROP FUNCTION IF EXISTS public.plan_strength_squad_programs(jsonb, text, text, text, text);
DROP FUNCTION IF EXISTS public.plan_strength_squad_programs(jsonb, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.plan_strength_squad_programs(
  p_programs jsonb,
  p_title text,
  p_notes text,
  p_started_at text,
  p_perceived_intensity text,
  p_state text DEFAULT 'planned',
  p_ended_at text DEFAULT NULL
)
RETURNS bigint[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_planner uuid := auth.uid();
  v_started timestamptz;
  v_ended timestamptz;
  v_state text;
  program jsonb;
  owner_uuid uuid;
  wid bigint;
  new_we_id bigint;
  item jsonb;
  s jsonb;
  all_ids bigint[] := '{}';
  all_owners uuid[] := '{}';
  i int;
  j int;
  v_perceived text;
BEGIN
  IF v_planner IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF jsonb_typeof(p_programs) IS DISTINCT FROM 'array' OR jsonb_array_length(p_programs) < 1 THEN
    RAISE EXCEPTION 'invalid_programs';
  END IF;

  IF jsonb_array_length(p_programs) > 3 THEN
    RAISE EXCEPTION 'too_many_programs';
  END IF;

  IF (p_programs->0->>'owner_user_id')::uuid IS DISTINCT FROM v_planner THEN
    RAISE EXCEPTION 'first_owner_must_be_caller';
  END IF;

  IF (
    SELECT COUNT(DISTINCT (e->>'owner_user_id')::uuid)
    FROM jsonb_array_elements(p_programs) AS e
  ) IS DISTINCT FROM jsonb_array_length(p_programs) THEN
    RAISE EXCEPTION 'duplicate_owner';
  END IF;

  BEGIN
    v_started := p_started_at::timestamptz;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'invalid_started_at';
  END;

  v_state := lower(btrim(coalesce(p_state, 'planned')));
  IF v_state NOT IN ('planned', 'published') THEN
    RAISE EXCEPTION 'invalid_state';
  END IF;

  v_ended := NULL::timestamptz;
  IF p_ended_at IS NOT NULL AND btrim(p_ended_at) <> '' THEN
    BEGIN
      v_ended := p_ended_at::timestamptz;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'invalid_ended_at';
    END;
  END IF;

  v_perceived := NULLIF(BTRIM(COALESCE(p_perceived_intensity, '')), '');

  FOR program IN SELECT * FROM jsonb_array_elements(p_programs)
  LOOP
    owner_uuid := (program->>'owner_user_id')::uuid;
    IF owner_uuid IS NULL THEN
      RAISE EXCEPTION 'invalid_owner';
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
    ) VALUES (
      owner_uuid,
      'strength'::workout_kind,
      NULLIF(BTRIM(p_title), ''),
      NULLIF(BTRIM(p_notes), ''),
      v_started,
      v_ended,
      v_state,
      v_perceived,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL,
      NULL
    ) RETURNING id INTO wid;

    all_ids := array_append(all_ids, wid);
    all_owners := array_append(all_owners, owner_uuid);

    IF jsonb_typeof(program->'items') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'invalid_items';
    END IF;

    FOR item IN SELECT * FROM jsonb_array_elements(program->'items')
    LOOP
      INSERT INTO public.workout_exercises (
        workout_id,
        exercise_id,
        order_index,
        notes,
        custom_name
      ) VALUES (
        wid,
        (item->>'exercise_id')::bigint,
        COALESCE((item->>'order_index')::int, 1),
        NULLIF(BTRIM(COALESCE(item->>'notes', '')), ''),
        NULLIF(BTRIM(COALESCE(item->>'custom_name', '')), '')
      ) RETURNING id INTO new_we_id;

      FOR s IN SELECT * FROM jsonb_array_elements(COALESCE(item->'sets', '[]'::jsonb))
      LOOP
        INSERT INTO public.exercise_sets (
          workout_exercise_id,
          set_number,
          reps,
          weight_kg,
          rpe,
          rest_sec,
          notes
        ) VALUES (
          new_we_id,
          COALESCE((s->>'set_number')::int, 1),
          CASE
            WHEN s ? 'reps' AND s->>'reps' IS NOT NULL AND BTRIM(s->>'reps') <> '' THEN (s->>'reps')::int
            ELSE NULL
          END,
          CASE
            WHEN s ? 'weight_kg' AND jsonb_typeof(s->'weight_kg') = 'number' THEN (s->>'weight_kg')::double precision
            WHEN s ? 'weight_kg' AND s->>'weight_kg' IS NOT NULL AND BTRIM(s->>'weight_kg') <> '' THEN (s->>'weight_kg')::double precision
            ELSE NULL
          END,
          CASE
            WHEN s ? 'rpe' AND jsonb_typeof(s->'rpe') = 'number' THEN (s->>'rpe')::double precision
            WHEN s ? 'rpe' AND s->>'rpe' IS NOT NULL AND BTRIM(s->>'rpe') <> '' THEN (s->>'rpe')::double precision
            ELSE NULL
          END,
          CASE
            WHEN s ? 'rest_sec' AND s->>'rest_sec' IS NOT NULL AND BTRIM(s->>'rest_sec') <> '' THEN (s->>'rest_sec')::int
            ELSE NULL
          END,
          NULLIF(BTRIM(COALESCE(s->>'notes', '')), '')
        );
      END LOOP;
    END LOOP;
  END LOOP;

  FOR i IN 1 .. coalesce(array_length(all_ids, 1), 0)
  LOOP
    FOR j IN 1 .. coalesce(array_length(all_owners, 1), 0)
    LOOP
      CONTINUE WHEN all_owners[i] = all_owners[j];
      INSERT INTO public.workout_participants (workout_id, user_id)
      SELECT all_ids[i], all_owners[j]
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.workout_participants wp
        WHERE wp.workout_id = all_ids[i]
          AND wp.user_id = all_owners[j]
      );
    END LOOP;
  END LOOP;

  RETURN all_ids;
END;
$function$;

REVOKE ALL ON FUNCTION public.plan_strength_squad_programs(jsonb, text, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.plan_strength_squad_programs(jsonb, text, text, text, text, text, text) TO authenticated;

-- Per-person squad: same UUID on all workouts created by plan_strength_squad_programs.
-- create_linked_strength_workout_copy: if host + target share that id, link existing workouts (no clone).
-- Trio 2nd guest: also resolve partner row by planning group when host already links guest1.

ALTER TABLE public.workouts
  ADD COLUMN IF NOT EXISTS strength_planning_group_id uuid;

COMMENT ON COLUMN public.workouts.strength_planning_group_id IS
  'Set when workouts are created together (per-person group); used at dual start to reuse each user''s program instead of cloning the host template.';

CREATE INDEX IF NOT EXISTS idx_workouts_strength_planning_group
  ON public.workouts (strength_planning_group_id)
  WHERE strength_planning_group_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- plan_strength_squad_programs: stamp strength_planning_group_id on each row
-- ---------------------------------------------------------------------------

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
  v_group_id uuid := gen_random_uuid();
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
      dual_host_user_id,
      strength_planning_group_id
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
      NULL,
      v_group_id
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

-- ---------------------------------------------------------------------------
-- create_linked_strength_workout_copy: squad link + trio 2nd guest by group
-- ---------------------------------------------------------------------------

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
  existing_other bigint;
  squad_partner_id bigint;
  we_rec public.workout_exercises%ROWTYPE;
  new_we_id bigint;
  es_rec public.exercise_sets%ROWTYPE;
BEGIN
  SELECT * INTO STRICT src
  FROM public.workouts
  WHERE id = p_source_workout_id;

  IF src.user_id IS DISTINCT FROM auth.uid()
     AND NOT EXISTS (
       SELECT 1
       FROM public.workout_participants wp
       WHERE wp.workout_id = p_source_workout_id
         AND wp.user_id = auth.uid()
     ) THEN
    RAISE EXCEPTION 'not_owner_or_participant';
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

  -- Co-trained per-person plans: link the partner's existing row (same strength_planning_group_id).
  IF src.strength_planning_group_id IS NOT NULL
     AND src.dual_linked_workout_id IS NULL THEN
    SELECT w.id INTO squad_partner_id
    FROM public.workouts w
    WHERE w.user_id = p_target_user_id
      AND w.strength_planning_group_id IS NOT DISTINCT FROM src.strength_planning_group_id
      AND w.id IS DISTINCT FROM p_source_workout_id
      AND w.ended_at IS NULL
      AND lower(btrim(w.state::text)) IN ('planned', 'published')
    ORDER BY w.id
    LIMIT 1;

    IF squad_partner_id IS NOT NULL THEN
      UPDATE public.workouts
      SET
        started_at = src.started_at,
        dual_host_user_id = COALESCE(dual_host_user_id, auth.uid())
      WHERE id = squad_partner_id;

      UPDATE public.workouts
      SET dual_linked_workout_id = squad_partner_id
      WHERE id = p_source_workout_id
        AND dual_linked_workout_id IS NULL;

      UPDATE public.workouts
      SET dual_linked_workout_id = p_source_workout_id
      WHERE id = squad_partner_id;

      RETURN squad_partner_id;
    END IF;
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

    ELSIF guest.user_id IS DISTINCT FROM p_target_user_id THEN
      SELECT w2.id INTO existing_other
      FROM public.workouts w2
      WHERE w2.user_id = p_target_user_id
        AND w2.ended_at IS NULL
        AND src.ended_at IS NULL
        AND (
          w2.dual_linked_workout_id IS NOT DISTINCT FROM p_source_workout_id
          OR (
            src.strength_planning_group_id IS NOT NULL
            AND w2.strength_planning_group_id IS NOT DISTINCT FROM src.strength_planning_group_id
            AND w2.id IS DISTINCT FROM p_source_workout_id
            AND lower(btrim(w2.state::text)) IN ('planned', 'published')
          )
        )
      ORDER BY w2.id DESC
      LIMIT 1;

      IF existing_other IS NOT NULL THEN
        UPDATE public.workouts
        SET
          started_at = src.started_at,
          dual_linked_workout_id = p_source_workout_id,
          dual_host_user_id = COALESCE(dual_host_user_id, auth.uid())
        WHERE id = existing_other;
        RETURN existing_other;
      END IF;

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
    ) VALUES (
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
  WHERE id = p_source_workout_id
    AND dual_linked_workout_id IS NULL;

  UPDATE public.workouts
  SET dual_linked_workout_id = p_source_workout_id
  WHERE id = new_id;

  RETURN new_id;
END;
$function$;

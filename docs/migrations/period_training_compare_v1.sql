-- =============================================================================
-- Liftr — Comparación de agregados (get_period_training_compare_v1 + helpers).
-- Cuerpos con AS '...' (sin $$ ni $BODY$) para clientes que no aceptan dollar-quoting.
-- Ver docs/postgres-sql-execution-notes.md
-- =============================================================================

CREATE OR REPLACE FUNCTION public._period_training_compare_summary(
  p_user uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_kind text
) RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS '
WITH wbase AS (
  SELECT w.id, w.kind::text AS k, w.calories_kcal, w.duration_min
  FROM public.workouts w
  WHERE w.user_id = p_user
    AND w.started_at >= p_start AND w.started_at < p_end
    AND COALESCE(w.state::text, '''') <> ''planned''
    AND (p_kind = ''all'' OR w.kind::text = p_kind)
),
eff AS (
  SELECT zb.id, zb.k, zb.calories_kcal,
    COALESCE(
      CASE WHEN zb.duration_min IS NOT NULL AND zb.duration_min > 0 THEN zb.duration_min::numeric END,
      (SELECT cs.duration_sec::numeric / 60.0 FROM public.cardio_sessions cs WHERE cs.workout_id = zb.id ORDER BY cs.id LIMIT 1),
      (SELECT ss.duration_sec::numeric / 60.0 FROM public.sport_sessions ss WHERE ss.workout_id = zb.id ORDER BY ss.id LIMIT 1),
      0::numeric
    )::bigint AS dm
  FROM wbase zb
),
tot AS (
  SELECT
    COUNT(*)::int AS workout_count,
    COALESCE(SUM(e.dm), 0)::bigint AS duration_min,
    COALESCE(SUM(COALESCE(e.calories_kcal, 0)), 0)::numeric AS calories_kcal
  FROM eff e
),
sc AS (
  SELECT COALESCE(SUM(ws.score), 0)::numeric AS score
  FROM public.workout_scores ws
  WHERE ws.workout_id IN (SELECT id FROM eff)
),
dist AS (
  SELECT COALESCE(SUM(sub.d), 0)::numeric AS distance_km
  FROM (
    SELECT e.id, MAX(cs.distance_km)::numeric AS d
    FROM eff e
    JOIN public.cardio_sessions cs ON cs.workout_id = e.id
    WHERE e.k = ''cardio''
    GROUP BY e.id
  ) sub
),
vol AS (
  SELECT COALESCE(SUM(v.total_volume_kg), 0)::numeric AS volume_kg
  FROM eff e
  JOIN public.vw_workout_volume v ON v.workout_id = e.id
  WHERE e.k = ''strength''
)
SELECT jsonb_build_object(
  ''workout_count'', (SELECT workout_count FROM tot),
  ''duration_min'', (SELECT duration_min FROM tot),
  ''calories_kcal'', (SELECT calories_kcal FROM tot),
  ''score'', (SELECT score FROM sc),
  ''distance_km'', (SELECT distance_km FROM dist),
  ''volume_kg'', (SELECT volume_kg FROM vol)
);
';


CREATE OR REPLACE FUNCTION public._period_training_compare_breakdown(
  p_user uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_kind text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS '
DECLARE
  r jsonb;
BEGIN
  IF p_kind = ''all'' THEN
    WITH wbase AS (
      SELECT w.id, w.kind::text AS k, w.calories_kcal, w.duration_min
      FROM public.workouts w
      WHERE w.user_id = p_user
        AND w.started_at >= p_start AND w.started_at < p_end
        AND COALESCE(w.state::text, '''') <> ''planned''
    ),
    eff AS (
      SELECT zb.id, zb.k, zb.calories_kcal,
        COALESCE(
          CASE WHEN zb.duration_min IS NOT NULL AND zb.duration_min > 0 THEN zb.duration_min::numeric END,
          (SELECT cs.duration_sec::numeric / 60.0 FROM public.cardio_sessions cs WHERE cs.workout_id = zb.id ORDER BY cs.id LIMIT 1),
          (SELECT ss.duration_sec::numeric / 60.0 FROM public.sport_sessions ss WHERE ss.workout_id = zb.id ORDER BY ss.id LIMIT 1),
          0::numeric
        )::bigint AS dm
      FROM wbase zb
    ),
    agg AS (
      SELECT
        e.k AS label,
        COUNT(*)::int AS workout_count,
        SUM(e.dm)::bigint AS duration_min,
        COALESCE(SUM(COALESCE(e.calories_kcal, 0)), 0)::numeric AS calories_kcal,
        COALESCE((
          SELECT SUM(ws.score)::numeric FROM public.workout_scores ws
          WHERE ws.workout_id IN (SELECT e2.id FROM eff e2 WHERE e2.k = e.k)
        ), 0) AS score,
        COALESCE((
          SELECT SUM(mx.d) FROM (
            SELECT e3.id, MAX(cs2.distance_km)::numeric AS d
            FROM eff e3
            JOIN public.cardio_sessions cs2 ON cs2.workout_id = e3.id
            WHERE e3.k = ''cardio'' AND e3.k = e.k
            GROUP BY e3.id
          ) mx
        ), 0)::numeric AS distance_km,
        COALESCE((
          SELECT SUM(v2.total_volume_kg)::numeric
          FROM eff e4
          JOIN public.vw_workout_volume v2 ON v2.workout_id = e4.id
          WHERE e4.k = ''strength'' AND e4.k = e.k
        ), 0)::numeric AS volume_kg
      FROM eff e
      GROUP BY e.k
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.label), ''[]''::jsonb) INTO r FROM agg a;

  ELSIF p_kind = ''cardio'' THEN
    WITH wbase AS (
      SELECT w.id, w.calories_kcal, w.duration_min
      FROM public.workouts w
      WHERE w.user_id = p_user
        AND w.started_at >= p_start AND w.started_at < p_end
        AND COALESCE(w.state::text, '''') <> ''planned''
        AND w.kind::text = ''cardio''
    ),
    lbl AS (
      SELECT DISTINCT ON (wb.id)
        wb.id,
        COALESCE(
          NULLIF(TRIM(cs.activity_code), ''''),
          NULLIF(TRIM(cs.modality), ''''),
          ''other''
        ) AS label,
        wb.calories_kcal,
        COALESCE(
          CASE WHEN wb.duration_min IS NOT NULL AND wb.duration_min > 0 THEN wb.duration_min::numeric END,
          cs.duration_sec::numeric / 60.0,
          0::numeric
        )::bigint AS dm,
        cs.distance_km::numeric AS distance_km
      FROM wbase wb
      JOIN public.cardio_sessions cs ON cs.workout_id = wb.id
      ORDER BY wb.id, cs.id
    ),
    agg AS (
      SELECT
        l.label,
        COUNT(*)::int AS workout_count,
        SUM(l.dm)::bigint AS duration_min,
        COALESCE(SUM(COALESCE(l.calories_kcal, 0)), 0)::numeric AS calories_kcal,
        COALESCE((
          SELECT SUM(ws.score)::numeric FROM public.workout_scores ws
          WHERE ws.workout_id IN (SELECT l2.id FROM lbl l2 WHERE l2.label = l.label)
        ), 0) AS score,
        COALESCE(SUM(l.distance_km), 0)::numeric AS distance_km,
        0::numeric AS volume_kg
      FROM lbl l
      GROUP BY l.label
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.label), ''[]''::jsonb) INTO r FROM agg a;

  ELSIF p_kind = ''strength'' THEN
    WITH wbase AS (
      SELECT w.id, w.calories_kcal, w.duration_min
      FROM public.workouts w
      WHERE w.user_id = p_user
        AND w.started_at >= p_start AND w.started_at < p_end
        AND COALESCE(w.state::text, '''') <> ''planned''
        AND w.kind::text = ''strength''
    ),
    lbl AS (
      SELECT DISTINCT ON (wb.id)
        wb.id,
        COALESCE(NULLIF(TRIM(ex.muscle_primary), ''''), ''other'') AS label,
        wb.calories_kcal,
        COALESCE(
          CASE WHEN wb.duration_min IS NOT NULL AND wb.duration_min > 0 THEN wb.duration_min::numeric END,
          0::numeric
        )::bigint AS dm
      FROM wbase wb
      JOIN public.workout_exercises we ON we.workout_id = wb.id
      JOIN public.exercises ex ON ex.id = we.exercise_id
      ORDER BY wb.id, we.order_index NULLS LAST, we.id
    ),
    agg AS (
      SELECT
        l.label,
        COUNT(*)::int AS workout_count,
        SUM(l.dm)::bigint AS duration_min,
        COALESCE(SUM(COALESCE(l.calories_kcal, 0)), 0)::numeric AS calories_kcal,
        COALESCE((
          SELECT SUM(ws.score)::numeric FROM public.workout_scores ws
          WHERE ws.workout_id IN (SELECT l2.id FROM lbl l2 WHERE l2.label = l.label)
        ), 0) AS score,
        0::numeric AS distance_km,
        COALESCE((
          SELECT SUM(v.total_volume_kg)::numeric
          FROM lbl l3
          JOIN public.vw_workout_volume v ON v.workout_id = l3.id
          WHERE l3.label = l.label
        ), 0)::numeric AS volume_kg
      FROM lbl l
      GROUP BY l.label
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.label), ''[]''::jsonb) INTO r FROM agg a;

  ELSIF p_kind = ''sport'' THEN
    WITH wbase AS (
      SELECT w.id, w.calories_kcal, w.duration_min
      FROM public.workouts w
      WHERE w.user_id = p_user
        AND w.started_at >= p_start AND w.started_at < p_end
        AND COALESCE(w.state::text, '''') <> ''planned''
        AND w.kind::text = ''sport''
    ),
    lbl AS (
      SELECT DISTINCT ON (wb.id)
        wb.id,
        COALESCE(NULLIF(TRIM(ss.sport), ''''), ''other'') AS label,
        wb.calories_kcal,
        COALESCE(
          CASE WHEN wb.duration_min IS NOT NULL AND wb.duration_min > 0 THEN wb.duration_min::numeric END,
          ss.duration_sec::numeric / 60.0,
          0::numeric
        )::bigint AS dm
      FROM wbase wb
      JOIN public.sport_sessions ss ON ss.workout_id = wb.id
      ORDER BY wb.id, ss.id
    ),
    agg AS (
      SELECT
        l.label,
        COUNT(*)::int AS workout_count,
        SUM(l.dm)::bigint AS duration_min,
        COALESCE(SUM(COALESCE(l.calories_kcal, 0)), 0)::numeric AS calories_kcal,
        COALESCE((
          SELECT SUM(ws.score)::numeric FROM public.workout_scores ws
          WHERE ws.workout_id IN (SELECT l2.id FROM lbl l2 WHERE l2.label = l.label)
        ), 0) AS score,
        0::numeric AS distance_km,
        0::numeric AS volume_kg
      FROM lbl l
      GROUP BY l.label
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.label), ''[]''::jsonb) INTO r FROM agg a;

  ELSE
    r := ''[]''::jsonb;
  END IF;

  RETURN COALESCE(r, ''[]''::jsonb);
END;
';


CREATE OR REPLACE FUNCTION public.get_period_training_compare_v1(
  p_user_a uuid,
  p_user_b uuid,
  p_kind text,
  p_a_start timestamptz,
  p_a_end timestamptz,
  p_b_start timestamptz,
  p_b_end timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS '
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION ''not authenticated'' USING errcode = ''42501'';
  END IF;

  IF p_kind IS NULL OR p_kind NOT IN (''all'', ''strength'', ''cardio'', ''sport'') THEN
    RAISE EXCEPTION ''invalid p_kind'' USING errcode = ''22023'';
  END IF;

  IF p_a_start IS NULL OR p_a_end IS NULL OR p_b_start IS NULL OR p_b_end IS NULL THEN
    RAISE EXCEPTION ''interval bounds required'' USING errcode = ''22023'';
  END IF;

  IF p_a_end <= p_a_start OR p_b_end <= p_b_start THEN
    RAISE EXCEPTION ''each interval end must be after start'' USING errcode = ''22023'';
  END IF;

  IF NOT (
    p_user_a = v_me OR EXISTS (
      SELECT 1 FROM public.follows f
      WHERE f.follower_id = v_me AND f.followee_id = p_user_a
    )
  ) THEN
    RAISE EXCEPTION ''forbidden user_a'' USING errcode = ''42501'';
  END IF;

  IF NOT (
    p_user_b = v_me OR EXISTS (
      SELECT 1 FROM public.follows f
      WHERE f.follower_id = v_me AND f.followee_id = p_user_b
    )
  ) THEN
    RAISE EXCEPTION ''forbidden user_b'' USING errcode = ''42501'';
  END IF;

  RETURN jsonb_build_object(
    ''period_a'', jsonb_build_object(
      ''summary'', public._period_training_compare_summary(p_user_a, p_a_start, p_a_end, p_kind),
      ''breakdown'', public._period_training_compare_breakdown(p_user_a, p_a_start, p_a_end, p_kind)
    ),
    ''period_b'', jsonb_build_object(
      ''summary'', public._period_training_compare_summary(p_user_b, p_b_start, p_b_end, p_kind),
      ''breakdown'', public._period_training_compare_breakdown(p_user_b, p_b_start, p_b_end, p_kind)
    )
  );
END;
';

-- GRANT EXECUTE ON FUNCTION public.get_period_training_compare_v1(uuid, uuid, text, timestamptz, timestamptz, timestamptz, timestamptz) TO authenticated;

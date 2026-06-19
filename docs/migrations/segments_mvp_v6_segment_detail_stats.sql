-- =============================================================================
-- Liftr — Segments v6: detalle con longitud/centro, stats de leaderboard,
-- confianza (avg/min/max), mejor marca del viewer; leaderboard incluye
-- `confidence` por fila.
-- Aplicar después de v1–v5. Ejecutar el archivo COMPLETO en una sola petición.
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_segment_detail_v1(uuid);

CREATE OR REPLACE FUNCTION public.get_segment_detail_v1(p_segment_id uuid)
RETURNS TABLE (
  id uuid,
  name text,
  buffer_m double precision,
  status text,
  geojson text,
  created_by uuid,
  foreign_efforts_count bigint,
  segment_length_m double precision,
  center_lat double precision,
  center_lon double precision,
  leaderboard_effort_count bigint,
  leaderboard_athlete_count bigint,
  confidence_avg double precision,
  confidence_min double precision,
  confidence_max double precision,
  viewer_best_elapsed_sec integer,
  viewer_best_workout_id bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $det$
  SELECT
    s.id,
    s.name,
    s.buffer_m,
    s.status,
    ST_AsGeoJSON(s.geom::geometry)::text AS geojson,
    s.created_by,
    COALESCE(
      (
        SELECT count(*)::bigint
        FROM public.segment_efforts se
        WHERE se.segment_id = s.id
          AND se.user_id IS DISTINCT FROM s.created_by
      ),
      0::bigint
    ) AS foreign_efforts_count,
    ST_Length(s.geom)::double precision AS segment_length_m,
    ST_Y(ST_LineInterpolatePoint(s.geom::geometry, 0.5::double precision))::double precision AS center_lat,
    ST_X(ST_LineInterpolatePoint(s.geom::geometry, 0.5::double precision))::double precision AS center_lon,
    COALESCE(
      (
        SELECT count(*)::bigint
        FROM public.segment_efforts se
        INNER JOIN public.workouts w ON w.id = se.workout_id
        WHERE se.segment_id = s.id
          AND w.state = 'published'::public.workout_state
          AND w.kind::text = 'cardio'
      ),
      0::bigint
    ) AS leaderboard_effort_count,
    COALESCE(
      (
        SELECT count(DISTINCT se.user_id)::bigint
        FROM public.segment_efforts se
        INNER JOIN public.workouts w ON w.id = se.workout_id
        WHERE se.segment_id = s.id
          AND w.state = 'published'::public.workout_state
          AND w.kind::text = 'cardio'
      ),
      0::bigint
    ) AS leaderboard_athlete_count,
    (
      SELECT avg(se.confidence)::double precision
      FROM public.segment_efforts se
      INNER JOIN public.workouts w ON w.id = se.workout_id
      WHERE se.segment_id = s.id
        AND w.state = 'published'::public.workout_state
        AND w.kind::text = 'cardio'
        AND se.confidence IS NOT NULL
    ) AS confidence_avg,
    (
      SELECT min(se.confidence)::double precision
      FROM public.segment_efforts se
      INNER JOIN public.workouts w ON w.id = se.workout_id
      WHERE se.segment_id = s.id
        AND w.state = 'published'::public.workout_state
        AND w.kind::text = 'cardio'
        AND se.confidence IS NOT NULL
    ) AS confidence_min,
    (
      SELECT max(se.confidence)::double precision
      FROM public.segment_efforts se
      INNER JOIN public.workouts w ON w.id = se.workout_id
      WHERE se.segment_id = s.id
        AND w.state = 'published'::public.workout_state
        AND w.kind::text = 'cardio'
        AND se.confidence IS NOT NULL
    ) AS confidence_max,
    (
      SELECT se.elapsed_sec
      FROM public.segment_efforts se
      INNER JOIN public.workouts w ON w.id = se.workout_id
      WHERE se.segment_id = s.id
        AND w.state = 'published'::public.workout_state
        AND w.kind::text = 'cardio'
        AND se.user_id = (SELECT auth.uid())
      ORDER BY se.elapsed_sec ASC, se.matched_at ASC NULLS LAST, se.workout_id ASC
      LIMIT 1
    ) AS viewer_best_elapsed_sec,
    (
      SELECT se.workout_id
      FROM public.segment_efforts se
      INNER JOIN public.workouts w ON w.id = se.workout_id
      WHERE se.segment_id = s.id
        AND w.state = 'published'::public.workout_state
        AND w.kind::text = 'cardio'
        AND se.user_id = (SELECT auth.uid())
      ORDER BY se.elapsed_sec ASC, se.matched_at ASC NULLS LAST, se.workout_id ASC
      LIMIT 1
    ) AS viewer_best_workout_id
  FROM public.segments s
  WHERE s.id = p_segment_id
    AND (
      s.status = 'published'
      OR s.created_by = (SELECT auth.uid())
    )
  LIMIT 1;
$det$;

GRANT EXECUTE ON FUNCTION public.get_segment_detail_v1(uuid) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.get_segment_detail_v1(uuid) FROM PUBLIC;

-- --- Leaderboard: columna confidence (misma fila que el effort rankeado)

DROP FUNCTION IF EXISTS public.get_segment_leaderboard_v1(uuid, int);

CREATE OR REPLACE FUNCTION public.get_segment_leaderboard_v1(
  p_segment_id uuid,
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  rank integer,
  user_id uuid,
  username text,
  avatar_url text,
  elapsed_sec integer,
  workout_id bigint,
  matched_at timestamptz,
  effort_at timestamptz,
  confidence double precision
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $lb$
  WITH base AS (
    SELECT
      se.user_id AS uid,
      se.elapsed_sec AS esec,
      se.workout_id AS wid,
      se.matched_at AS mat,
      COALESCE(w.started_at, w.created_at) AS eat,
      se.confidence AS conf,
      row_number() OVER (
        PARTITION BY se.user_id
        ORDER BY se.elapsed_sec ASC, se.matched_at ASC NULLS LAST, se.workout_id ASC
      ) AS user_rn
    FROM public.segment_efforts se
    INNER JOIN public.workouts w ON w.id = se.workout_id
    WHERE se.segment_id = p_segment_id
      AND w.state = 'published'::public.workout_state
      AND w.kind::text = 'cardio'
  ),
  capped AS (
    SELECT uid, esec, wid, mat, eat, conf
    FROM base
    WHERE user_rn <= 10
  ),
  ranked AS (
    SELECT
      c.uid,
      c.esec,
      c.wid,
      c.mat,
      c.eat,
      c.conf,
      row_number() OVER (
        ORDER BY c.esec ASC, c.mat ASC NULLS LAST, c.wid ASC
      ) AS rn
    FROM capped c
  )
  SELECT
    r.rn::integer AS rank,
    r.uid AS user_id,
    pr.username,
    pr.avatar_url,
    r.esec AS elapsed_sec,
    r.wid AS workout_id,
    r.mat AS matched_at,
    r.eat AS effort_at,
    r.conf AS confidence
  FROM ranked r
  LEFT JOIN public.profiles pr ON pr.user_id = r.uid
  ORDER BY r.rn ASC
  LIMIT greatest(1, least(p_limit, 200));
$lb$;

GRANT EXECUTE ON FUNCTION public.get_segment_leaderboard_v1(uuid, int) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.get_segment_leaderboard_v1(uuid, int) FROM PUBLIC;

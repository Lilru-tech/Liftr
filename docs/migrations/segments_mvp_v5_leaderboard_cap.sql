-- =============================================================================
-- Liftr — Segments v5: leaderboard con tope de 10 efforts por usuario, fecha
-- del entreno (COALESCE(started_at, created_at)) y misma firma RPC.
-- Aplicar después de v1–v4. Ejecutar el archivo COMPLETO en una sola petición.
-- =============================================================================

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
  effort_at timestamptz
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
    SELECT uid, esec, wid, mat, eat
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
    r.eat AS effort_at
  FROM ranked r
  LEFT JOIN public.profiles pr ON pr.user_id = r.uid
  ORDER BY r.rn ASC
  LIMIT greatest(1, least(p_limit, 200));
$lb$;

GRANT EXECUTE ON FUNCTION public.get_segment_leaderboard_v1(uuid, int) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.get_segment_leaderboard_v1(uuid, int) FROM PUBLIC;

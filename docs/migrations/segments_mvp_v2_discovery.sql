-- =============================================================================
-- Liftr — Segments discovery v2: search, “my segments”, popularity leaderboard.
-- Apply after segments_mvp_v1 (tables + base RPCs).
--
-- DbVisualizer / JDBC: ejecuta este archivo COMPLETO en una sola petición
-- (no partir por `;` dentro de cuerpos dollar-quoted).
-- =============================================================================

DROP FUNCTION IF EXISTS public.search_segments_v1(text, int);
DROP FUNCTION IF EXISTS public.list_my_segments_v1(int);
DROP FUNCTION IF EXISTS public.list_segments_popularity_leaderboard_v1(text, int);

CREATE OR REPLACE FUNCTION public.search_segments_v1(
  p_query text,
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  name text,
  buffer_m double precision
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $search$
  WITH q AS (
    SELECT lower(btrim(COALESCE(p_query, ''))) AS t
  )
  SELECT
    s.id,
    s.name,
    s.buffer_m
  FROM public.segments s
  CROSS JOIN q
  WHERE char_length(q.t) >= 2
    AND s.status = 'published'
    AND strpos(lower(s.name), q.t) > 0
  ORDER BY s.created_at DESC
  LIMIT greatest(1, least(COALESCE(p_limit, 50), 200));
$search$;

CREATE OR REPLACE FUNCTION public.list_my_segments_v1(p_limit int DEFAULT 100)
RETURNS TABLE (
  id uuid,
  name text,
  buffer_m double precision,
  status text,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $mine$
  SELECT
    s.id,
    s.name,
    s.buffer_m,
    s.status,
    s.created_at
  FROM public.segments s
  WHERE s.created_by = (SELECT auth.uid())
    AND (SELECT auth.uid()) IS NOT NULL
  ORDER BY s.created_at DESC
  LIMIT greatest(1, least(COALESCE(p_limit, 100), 500));
$mine$;

CREATE OR REPLACE FUNCTION public.list_segments_popularity_leaderboard_v1(
  p_period text,
  p_limit int DEFAULT 100
)
RETURNS TABLE (
  rank integer,
  segment_id uuid,
  name text,
  efforts_count bigint,
  buffer_m double precision
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $pop$
  WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  agg AS (
    SELECT
      se.segment_id AS sid,
      COUNT(*)::bigint AS cnt
    FROM public.segment_efforts se
    INNER JOIN public.workouts w ON w.id = se.workout_id
    CROSS JOIN bounds b
    WHERE w.state = 'published'::public.workout_state
      AND se.matched_at >= b.t_start
      AND se.matched_at < b.t_end
    GROUP BY se.segment_id
  ),
  named AS (
    SELECT
      a.sid,
      a.cnt,
      s.name AS seg_name,
      s.buffer_m AS buf
    FROM agg a
    INNER JOIN public.segments s ON s.id = a.sid
    WHERE s.status = 'published'
  )
  SELECT
    row_number() OVER (ORDER BY n.cnt DESC, n.seg_name ASC)::integer AS rank,
    n.sid AS segment_id,
    n.seg_name AS name,
    n.cnt AS efforts_count,
    n.buf AS buffer_m
  FROM named n
  ORDER BY rank ASC
  LIMIT greatest(1, least(COALESCE(p_limit, 100), 200));
$pop$;

GRANT EXECUTE ON FUNCTION public.search_segments_v1(text, int) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.search_segments_v1(text, int) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_my_segments_v1(int) TO authenticated;
REVOKE ALL ON FUNCTION public.list_my_segments_v1(int) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_segments_popularity_leaderboard_v1(text, int) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.list_segments_popularity_leaderboard_v1(text, int) FROM PUBLIC;

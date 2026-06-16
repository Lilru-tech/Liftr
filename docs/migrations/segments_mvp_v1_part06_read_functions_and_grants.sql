-- Parte 6/6 — RPCs de lectura (SQL) + GRANT EXECUTE. Ejecutar archivo COMPLETO.
-- Requiere part01 (tablas). part02–05 deben haberse aplicado ya si quieres matching/crear.

CREATE OR REPLACE FUNCTION public.list_segments_near_v1(
  p_lat double precision,
  p_lon double precision,
  p_radius_m double precision DEFAULT 5000,
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  id uuid,
  name text,
  buffer_m double precision,
  geojson text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $near$
  SELECT
    s.id,
    s.name,
    s.buffer_m,
    ST_AsGeoJSON(s.geom::geometry)::text AS geojson
  FROM public.segments s
  WHERE s.status = 'published'
    AND ST_DWithin(
      s.geom,
      ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
      p_radius_m
    )
  ORDER BY ST_Distance(
    s.geom,
    ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
    false
  ) ASC NULLS LAST
  LIMIT greatest(1, least(p_limit, 200));
$near$;

CREATE OR REPLACE FUNCTION public.get_segment_detail_v1(p_segment_id uuid)
RETURNS TABLE (
  id uuid,
  name text,
  buffer_m double precision,
  status text,
  geojson text
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
    ST_AsGeoJSON(s.geom::geometry)::text AS geojson
  FROM public.segments s
  WHERE s.id = p_segment_id
    AND (
      s.status = 'published'
      OR s.created_by = (SELECT auth.uid())
    )
  LIMIT 1;
$det$;

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

GRANT EXECUTE ON FUNCTION public.match_segment_efforts_for_workout_v1(bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.match_segment_efforts_for_workout_v1(bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_segment_from_workout_v1(bigint, text, double precision, double precision, double precision) TO authenticated;
REVOKE ALL ON FUNCTION public.create_segment_from_workout_v1(bigint, text, double precision, double precision, double precision) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_segments_near_v1(double precision, double precision, double precision, int) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.list_segments_near_v1(double precision, double precision, double precision, int) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_segment_leaderboard_v1(uuid, int) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.get_segment_leaderboard_v1(uuid, int) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_segment_detail_v1(uuid) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.get_segment_detail_v1(uuid) FROM PUBLIC;

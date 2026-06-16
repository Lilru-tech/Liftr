-- =============================================================================
-- Liftr — Segments v3: duplicados al crear, detalle con dueño/efforts ajenos,
-- renombrar (solo nombre) y borrar (solo si no hay efforts de otros usuarios).
-- Aplicar después de segments_mvp_v1 + v2_discovery.
-- Ejecutar el archivo COMPLETO en una sola petición (DbVisualizer / SQL Editor).
-- =============================================================================

-- --- Detalle: incluir created_by y conteo de efforts de usuarios distintos al creador
DROP FUNCTION IF EXISTS public.get_segment_detail_v1(uuid);

CREATE OR REPLACE FUNCTION public.get_segment_detail_v1(p_segment_id uuid)
RETURNS TABLE (
  id uuid,
  name text,
  buffer_m double precision,
  status text,
  geojson text,
  created_by uuid,
  foreign_efforts_count bigint
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
    ) AS foreign_efforts_count
  FROM public.segments s
  WHERE s.id = p_segment_id
    AND (
      s.status = 'published'
      OR s.created_by = (SELECT auth.uid())
    )
  LIMIT 1;
$det$;

-- --- Crear segmento: rechazar si hay otro segmento publicado muy similar (estilo Strava: un tramo canónico)
CREATE OR REPLACE FUNCTION public.create_segment_from_workout_v1(
  p_workout_id bigint,
  p_name text,
  p_start_fraction double precision,
  p_end_fraction double precision,
  p_buffer_m double precision DEFAULT 25
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $create$
DECLARE
  r record;
  route_geom geometry(LineString, 4326);
  sub_geom geometry(LineString, 4326);
  uid uuid;
  new_id uuid;
  a double precision;
  b double precision;
  dup_id uuid;
BEGIN
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'invalid_name' USING ERRCODE = '22023';
  END IF;

  IF p_start_fraction IS NULL OR p_end_fraction IS NULL
     OR p_start_fraction < 0 OR p_end_fraction > 1
     OR p_start_fraction >= p_end_fraction THEN
    RAISE EXCEPTION 'invalid_fractions' USING ERRCODE = '22023';
  END IF;

  IF p_buffer_m IS NULL OR p_buffer_m <= 0 OR p_buffer_m > 500 THEN
    RAISE EXCEPTION 'invalid_buffer' USING ERRCODE = '22023';
  END IF;

  SELECT
    cs.route_geojson,
    w.user_id,
    w.state,
    w.kind::text AS kind_txt
  INTO r
  FROM public.cardio_sessions cs
  INNER JOIN public.workouts w ON w.id = cs.workout_id
  WHERE cs.workout_id = p_workout_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'workout_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF r.user_id IS DISTINCT FROM (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'not_allowed' USING ERRCODE = '42501';
  END IF;

  IF r.kind_txt IS DISTINCT FROM 'cardio' THEN
    RAISE EXCEPTION 'not_cardio' USING ERRCODE = '22023';
  END IF;

  IF r.state IS DISTINCT FROM 'published'::public.workout_state THEN
    RAISE EXCEPTION 'workout_not_published' USING ERRCODE = '22023';
  END IF;

  IF r.route_geojson IS NULL OR btrim(r.route_geojson) = '' THEN
    RAISE EXCEPTION 'no_route' USING ERRCODE = '22023';
  END IF;

  route_geom := ST_SetSRID(ST_GeomFromGeoJSON(r.route_geojson), 4326)::geometry(LineString, 4326);

  IF ST_NPoints(route_geom) < 2 THEN
    RAISE EXCEPTION 'route_too_short' USING ERRCODE = '22023';
  END IF;

  a := least(p_start_fraction, p_end_fraction);
  b := greatest(p_start_fraction, p_end_fraction);
  sub_geom := ST_LineSubstring(route_geom, a, b);

  IF ST_NPoints(sub_geom) < 2 OR ST_Length(sub_geom::geography) < 5 THEN
    RAISE EXCEPTION 'segment_too_short' USING ERRCODE = '22023';
  END IF;

  -- Duplicado ≈ mismo tramo: longitud parecida + ≥86% vértices de cada polilínea dentro del buffer del otro
  SELECT s.id INTO dup_id
  FROM public.segments s
  WHERE s.status = 'published'
    AND ST_Length(s.geom::geography) >= 5
    AND ST_Length(sub_geom::geography) >= 5
    AND ST_Length(sub_geom::geography) BETWEEN ST_Length(s.geom::geography) * 0.5 AND ST_Length(s.geom::geography) * 1.5
    AND (
      SELECT count(*)::numeric
      FROM ST_DumpPoints(sub_geom) dpx
      WHERE ST_DWithin(
        (dpx).geom::geography,
        s.geom,
        greatest(s.buffer_m, p_buffer_m, 30.0)
      )
    ) / NULLIF(ST_NPoints(sub_geom), 0)::numeric >= 0.86
    AND (
      SELECT count(*)::numeric
      FROM ST_DumpPoints(s.geom::geometry) dpy
      WHERE ST_DWithin(
        (dpy).geom::geography,
        sub_geom::geography,
        greatest(s.buffer_m, p_buffer_m, 30.0)
      )
    ) / NULLIF(ST_NPoints(s.geom::geometry), 0)::numeric >= 0.86
  ORDER BY s.created_at ASC
  LIMIT 1;

  IF dup_id IS NOT NULL THEN
    -- No usar MESSAGE en USING: el texto de RAISE EXCEPTION ya fija el mensaje; duplicarlo provoca "RAISE option already specified: MESSAGE".
    RAISE EXCEPTION 'duplicate_segment'
      USING ERRCODE = 'P0001',
            HINT = dup_id::text;
  END IF;

  uid := r.user_id;

  INSERT INTO public.segments (
    created_by,
    name,
    status,
    geom,
    buffer_m,
    source_workout_id
  )
  VALUES (
    uid,
    btrim(p_name),
    'published',
    sub_geom::geography(LineString, 4326),
    p_buffer_m,
    p_workout_id
  )
  RETURNING id INTO new_id;

  PERFORM public._match_segments_for_workout_internal(p_workout_id);

  RETURN new_id;
END;
$create$;

DROP FUNCTION IF EXISTS public.update_my_segment_name_v1(uuid, text);

CREATE OR REPLACE FUNCTION public.update_my_segment_name_v1(
  p_segment_id uuid,
  p_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $upd$
DECLARE
  n int;
BEGIN
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'invalid_name' USING ERRCODE = '22023';
  END IF;

  UPDATE public.segments s
  SET name = btrim(p_name)
  WHERE s.id = p_segment_id
    AND s.created_by = (SELECT auth.uid())
    AND (SELECT auth.uid()) IS NOT NULL
    AND s.status IN ('published', 'draft');

  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'cannot_update_segment' USING ERRCODE = 'P0001';
  END IF;
END;
$upd$;

DROP FUNCTION IF EXISTS public.delete_my_segment_v1(uuid);

CREATE OR REPLACE FUNCTION public.delete_my_segment_v1(p_segment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public'
AS $del$
DECLARE
  n int;
BEGIN
  DELETE FROM public.segments s
  WHERE s.id = p_segment_id
    AND s.created_by = (SELECT auth.uid())
    AND (SELECT auth.uid()) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.segment_efforts se
      WHERE se.segment_id = p_segment_id
        AND se.user_id IS DISTINCT FROM s.created_by
    );

  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'cannot_delete_segment' USING ERRCODE = 'P0001';
  END IF;
END;
$del$;

GRANT EXECUTE ON FUNCTION public.update_my_segment_name_v1(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.update_my_segment_name_v1(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.delete_my_segment_v1(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.delete_my_segment_v1(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_segment_detail_v1(uuid) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.get_segment_detail_v1(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_segment_from_workout_v1(bigint, text, double precision, double precision, double precision) TO authenticated;
REVOKE ALL ON FUNCTION public.create_segment_from_workout_v1(bigint, text, double precision, double precision, double precision) FROM PUBLIC;

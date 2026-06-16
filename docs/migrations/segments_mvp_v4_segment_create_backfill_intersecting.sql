-- =============================================================================
-- Liftr — Segments v4: al crear un segmento, re-matchear entrenos cardio ya
-- publicados cuya ruta intersecta (ST_DWithin) el nuevo segmento.
-- Aplicar después de segments_mvp_v1 + v2 + v3.
-- Ejecutar el archivo COMPLETO en una sola petición (SQL Editor / psql).
-- =============================================================================

-- --- Interno: re-ejecutar _match_segments_for_workout_internal en workouts
--     publicados cuyo LineString está cerca del segmento (filtro grueso antes
--     del cálculo fino de puntos que ya hace la función interna).
CREATE OR REPLACE FUNCTION public._rematch_workouts_intersecting_segment(
  p_segment_id uuid,
  p_exclude_workout_id bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $bf$
DECLARE
  seg_geog geography;
  buf_m double precision;
  thresh_m double precision;
  rec record;
  route_geom geometry(LineString, 4326);
BEGIN
  SELECT s.geom, greatest(s.buffer_m, 50.0)
  INTO seg_geog, buf_m
  FROM public.segments s
  WHERE s.id = p_segment_id
    AND s.status = 'published'
  LIMIT 1;

  IF seg_geog IS NULL THEN
    RETURN;
  END IF;

  -- Umbral conservador (m): rutas que pasan cerca del tramo pueden matchear
  -- con el buffer puntual del matching MVP; evitamos recorrer toda la tabla.
  thresh_m := greatest(buf_m * 3.0, 200.0);

  FOR rec IN
    SELECT cs.workout_id, cs.route_geojson
    FROM public.cardio_sessions cs
    INNER JOIN public.workouts w ON w.id = cs.workout_id
    WHERE w.state = 'published'::public.workout_state
      AND w.kind::text = 'cardio'
      AND cs.route_geojson IS NOT NULL
      AND btrim(cs.route_geojson) <> ''
      AND (
        p_exclude_workout_id IS NULL
        OR cs.workout_id IS DISTINCT FROM p_exclude_workout_id
      )
  LOOP
    BEGIN
      route_geom := ST_SetSRID(ST_GeomFromGeoJSON(rec.route_geojson), 4326)::geometry(LineString, 4326);
    EXCEPTION
      WHEN OTHERS THEN
        CONTINUE;
    END;

    IF ST_NPoints(route_geom) < 5 THEN
      CONTINUE;
    END IF;

    IF NOT ST_DWithin(route_geom::geography, seg_geog, thresh_m) THEN
      CONTINUE;
    END IF;

    PERFORM public._match_segments_for_workout_internal(rec.workout_id);
  END LOOP;
END;
$bf$;

REVOKE ALL ON FUNCTION public._rematch_workouts_intersecting_segment(uuid, bigint) FROM PUBLIC;

-- --- create_segment_from_workout_v1: tras crear, backfill en entrenos que cruzan el segmento
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

  PERFORM public._rematch_workouts_intersecting_segment(new_id, p_workout_id);

  RETURN new_id;
END;
$create$;

GRANT EXECUTE ON FUNCTION public.create_segment_from_workout_v1(bigint, text, double precision, double precision, double precision) TO authenticated;
REVOKE ALL ON FUNCTION public.create_segment_from_workout_v1(bigint, text, double precision, double precision, double precision) FROM PUBLIC;

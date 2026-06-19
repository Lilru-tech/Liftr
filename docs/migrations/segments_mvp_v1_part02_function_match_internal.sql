-- Parte 2/6 — Función interna de matching (PL/pgSQL, muchos `;` dentro del cuerpo).
-- Ejecutar este archivo COMPLETO en una sola petición. Requiere part01.

CREATE OR REPLACE FUNCTION public._match_segments_for_workout_internal(p_workout_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $match$
DECLARE
  r record;
  route_geom geometry(LineString, 4326);
  n_pts int;
  dur int;
  uid uuid;
BEGIN
  SELECT
    cs.route_geojson,
    cs.duration_sec,
    w.user_id,
    w.state,
    w.kind::text AS kind_txt
  INTO r
  FROM public.cardio_sessions cs
  INNER JOIN public.workouts w ON w.id = cs.workout_id
  WHERE cs.workout_id = p_workout_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF r.kind_txt IS DISTINCT FROM 'cardio' THEN
    RETURN;
  END IF;

  IF r.state IS DISTINCT FROM 'published'::public.workout_state THEN
    RETURN;
  END IF;

  IF r.route_geojson IS NULL OR btrim(r.route_geojson) = '' THEN
    RETURN;
  END IF;

  BEGIN
    route_geom := ST_SetSRID(ST_GeomFromGeoJSON(r.route_geojson), 4326)::geometry(LineString, 4326);
  EXCEPTION WHEN OTHERS THEN
    RETURN;
  END;

  n_pts := ST_NPoints(route_geom);
  IF n_pts < 5 THEN
    RETURN;
  END IF;

  dur := COALESCE(r.duration_sec, 0);
  IF dur <= 0 THEN
    RETURN;
  END IF;

  uid := r.user_id;

  DELETE FROM public.segment_efforts WHERE workout_id = p_workout_id;

  INSERT INTO public.segment_efforts (
    segment_id,
    workout_id,
    user_id,
    elapsed_sec,
    time_source,
    match_point_count,
    route_point_count,
    confidence
  )
  SELECT
    s.id,
    p_workout_id,
    uid,
    GREATEST(
      15,
      LEAST(
        dur,
        (
          (
            SELECT count(*)::numeric
            FROM ST_DumpPoints(route_geom) AS dp
            WHERE ST_DWithin((dp).geom::geography, s.geom, s.buffer_m)
          ) / NULLIF(n_pts, 0)::numeric * dur::numeric
        )::integer
      )
    ),
    'route_coverage_estimate',
    (
      SELECT count(*)::int
      FROM ST_DumpPoints(route_geom) AS dp2
      WHERE ST_DWithin((dp2).geom::geography, s.geom, s.buffer_m)
    ),
    n_pts,
    (
      SELECT count(*)::numeric
      FROM ST_DumpPoints(route_geom) AS dp3
      WHERE ST_DWithin((dp3).geom::geography, s.geom, s.buffer_m)
    ) / NULLIF(n_pts, 0)::double precision
  FROM public.segments s
  WHERE s.status = 'published'
    AND (
      SELECT count(*)::int
      FROM ST_DumpPoints(route_geom) AS dpx
      WHERE ST_DWithin((dpx).geom::geography, s.geom, s.buffer_m)
    ) >= greatest(3, n_pts / 15);
END;
$match$;

REVOKE ALL ON FUNCTION public._match_segments_for_workout_internal(bigint) FROM PUBLIC;

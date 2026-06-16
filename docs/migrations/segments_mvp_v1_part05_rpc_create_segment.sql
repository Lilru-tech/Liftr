-- Parte 5/6 — RPC crear segmento desde workout. Ejecutar archivo COMPLETO. Requiere part02.

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

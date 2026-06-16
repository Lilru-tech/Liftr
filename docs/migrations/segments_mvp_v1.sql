-- =============================================================================
-- Liftr — Segmentos MVP (estilo Strava, acotado)
--
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- CÓMO EJECUTAR (importante)
--
-- El script contiene funciones PL/pgSQL y SQL con cuerpos entre delimitadores
-- tipo AS $tag$ ... $tag$; con muchos `;` **dentro** del cuerpo.
--
-- Si tu cliente (p. ej. **DBVisualizer** con “ejecutar sentencia” o split por `;`)
-- parte el texto en cada punto y coma, PostgreSQL verá **dollar quote sin cerrar**
-- (“Unterminated dollar quote”, luego cascada de errores).
--
-- Opciones correctas:
--   1) **Supabase** → SQL Editor → pegar **todo** este archivo → **Run** (una sola ejecución).
--   2) **psql**: `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f docs/migrations/segments_mvp_v1.sql`
--   3) **DBVisualizer / DBeaver / etc.**: ejecutar **el archivo o el buffer completo**
--      como un solo script (no “Execute Statement” por `;`), **o** usar los trozos
--      `segments_mvp_v1_part01_*.sql` … `part06_*.sql` en **orden**, cada archivo
--      **entero** en una sola petición.
-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--
-- Alcance:
--   - PostGIS para geometría WGS84 (4326) y matching por buffer.
--   - Tablas: segments (eje publicable), segment_efforts (un esfuerzo por segmento+workout).
--   - RLS: lectura de segmentos publicados; esfuerzos solo si el workout padre está publicado.
--   - Matching MVP (sin timestamps por punto en route_geojson):
--       * Cuenta vértices de la ruta dentro de ST_DWithin(..., segment.geom, buffer_m).
--       * Match si matched_pts >= GREATEST(3, route_pts / 15).
--       * elapsed_sec = proporción (matched_pts / route_pts) * cardio_sessions.duration_sec
--         (time_source = route_coverage_estimate). Sustituir por tiempos GPS por tramo en v2.
--   - Ejecución: trigger AFTER INSERT/UPDATE OF state ON workouts (cardio + published) llama a
--     _match_segments_for_workout_internal; el usuario puede reintentar con RPC
--     match_segment_efforts_for_workout_v1 (mismo cálculo).
--
-- Deploy: Supabase SQL Editor. Requiere extensión postgis (habitualmente ya en proyecto Supabase).
-- GRANT EXECUTE al final del archivo.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;

-- -----------------------------------------------------------------------------
-- Tablas
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'published'
    CHECK (status IN ('draft', 'published', 'archived')),
  geom geography (LineString, 4326) NOT NULL,
  buffer_m double precision NOT NULL DEFAULT 25
    CHECK (buffer_m > 0 AND buffer_m <= 500),
  source_workout_id bigint REFERENCES public.workouts (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS segments_geom_gix
  ON public.segments USING gist (geom);

CREATE INDEX IF NOT EXISTS segments_status_created_at_idx
  ON public.segments (status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.segment_efforts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  segment_id uuid NOT NULL REFERENCES public.segments (id) ON DELETE CASCADE,
  workout_id bigint NOT NULL REFERENCES public.workouts (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
  elapsed_sec integer NOT NULL CHECK (elapsed_sec > 0),
  time_source text NOT NULL DEFAULT 'route_coverage_estimate',
  match_point_count integer NOT NULL DEFAULT 0,
  route_point_count integer NOT NULL DEFAULT 0,
  confidence double precision,
  matched_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (segment_id, workout_id)
);

CREATE INDEX IF NOT EXISTS segment_efforts_segment_elapsed_idx
  ON public.segment_efforts (segment_id, elapsed_sec ASC);

CREATE INDEX IF NOT EXISTS segment_efforts_workout_idx
  ON public.segment_efforts (workout_id);

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------

ALTER TABLE public.segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.segment_efforts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS segments_select_auth ON public.segments;
CREATE POLICY segments_select_auth
  ON public.segments FOR SELECT TO authenticated
  USING (status = 'published' OR created_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS segments_insert_own ON public.segments;
CREATE POLICY segments_insert_own
  ON public.segments FOR INSERT TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS segments_update_own ON public.segments;
CREATE POLICY segments_update_own
  ON public.segments FOR UPDATE TO authenticated
  USING (created_by = (SELECT auth.uid()))
  WITH CHECK (created_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS segments_delete_own ON public.segments;
CREATE POLICY segments_delete_own
  ON public.segments FOR DELETE TO authenticated
  USING (created_by = (SELECT auth.uid()));

DROP POLICY IF EXISTS segments_select_anon ON public.segments;
CREATE POLICY segments_select_anon
  ON public.segments FOR SELECT TO anon
  USING (status = 'published');

DROP POLICY IF EXISTS segment_efforts_select_auth ON public.segment_efforts;
CREATE POLICY segment_efforts_select_auth
  ON public.segment_efforts FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.workouts w
      WHERE w.id = segment_efforts.workout_id
        AND w.state = 'published'::public.workout_state
    )
  );

DROP POLICY IF EXISTS segment_efforts_select_anon ON public.segment_efforts;
CREATE POLICY segment_efforts_select_anon
  ON public.segment_efforts FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1
      FROM public.workouts w
      WHERE w.id = segment_efforts.workout_id
        AND w.state = 'published'::public.workout_state
    )
  );

-- No INSERT/UPDATE/DELETE directo para clientes: solo SECURITY DEFINER (matching).

REVOKE INSERT, UPDATE, DELETE ON public.segment_efforts FROM authenticated, anon;

GRANT SELECT ON public.segments TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.segments TO authenticated;

GRANT SELECT ON public.segment_efforts TO authenticated, anon;

-- -----------------------------------------------------------------------------
-- Matching interno + trigger
-- -----------------------------------------------------------------------------

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

CREATE OR REPLACE FUNCTION public.trg_workouts_publish_match_segments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $trg$
BEGIN
  IF NEW.kind::text IS DISTINCT FROM 'cardio' THEN
    RETURN NEW;
  END IF;
  IF NEW.state IS DISTINCT FROM 'published'::public.workout_state THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM public._match_segments_for_workout_internal(NEW.id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.state IS DISTINCT FROM 'published'::public.workout_state THEN
      PERFORM public._match_segments_for_workout_internal(NEW.id);
    END IF;
  END IF;

  RETURN NEW;
END;
$trg$;

DROP TRIGGER IF EXISTS workouts_publish_match_segments ON public.workouts;
CREATE TRIGGER workouts_publish_match_segments
  AFTER INSERT OR UPDATE OF state ON public.workouts
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_workouts_publish_match_segments();

-- -----------------------------------------------------------------------------
-- RPC: matching manual (misma lógica que el trigger)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.match_segment_efforts_for_workout_v1(p_workout_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $rpc$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.workouts w
    WHERE w.id = p_workout_id
      AND w.user_id = (SELECT auth.uid())
  ) THEN
    RAISE EXCEPTION 'not_allowed' USING ERRCODE = '42501';
  END IF;

  PERFORM public._match_segments_for_workout_internal(p_workout_id);
END;
$rpc$;

-- -----------------------------------------------------------------------------
-- RPC: crear segmento desde workout (subtramo por fracción 0..1)
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- RPC: listar segmentos cerca de un punto
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- RPC: detalle de segmento (GeoJSON estable para clientes)
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- RPC: leaderboard por segmento
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Grants RPC
-- -----------------------------------------------------------------------------

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

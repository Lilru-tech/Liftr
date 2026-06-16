-- =============================================================================
-- Liftr — Segments v7: notificaciones al quedar 1º en un segmento (misma regla
-- que el leaderboard) y al perder el 1º por un cardio publicado de otro.
--
-- Inserts en public.notifications (inglés). send-notifications + FCM sin
-- cambios si ya envían filas pendientes.
--
-- Aplicar después de v1–v6. Ejecutar el archivo COMPLETO en una sola petición.
--
-- --- Consultas útiles para inspección (no ejecutar como parte de la migración)
--
-- Funciones cuyo nombre contiene "notif":
--   SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname ILIKE '%notif%';
--
--   SELECT routine_name, routine_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public' AND routine_name ILIKE '%notif%';
--
-- Definición de create_notification (evita escanear todos los cuerpos con pg_get_functiondef):
--   SELECT pg_get_functiondef('public.create_notification(uuid,text,text,text,jsonb)'::regprocedure);
-- =============================================================================

-- Si en un entorno de prueba existió el borrador con _queue_notification_v1, quitarla antes de aplicar.
DROP FUNCTION IF EXISTS public._queue_notification_v1(uuid, text, text, text, jsonb);

-- --- KOM actual (rank 1) reutilizando el mismo RPC que la app
CREATE OR REPLACE FUNCTION public._segment_leaderboard_king_v1(p_segment_id uuid)
RETURNS TABLE (
  user_id uuid,
  workout_id bigint,
  elapsed_sec integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $king$
  SELECT lb.user_id, lb.workout_id, lb.elapsed_sec
  FROM public.get_segment_leaderboard_v1(p_segment_id, 1) AS lb
  ORDER BY lb.rank ASC
  LIMIT 1;
$king$;

REVOKE ALL ON FUNCTION public._segment_leaderboard_king_v1(uuid) FROM PUBLIC;

-- Notas: las filas se insertan vía public.create_notification(_user_id, _type, _title, _body, _data)
-- ya desplegada en el proyecto (mismo patrón que notify_workout_like, etc.).

-- --- Matching: snapshot KOM, DELETE, INSERT, notificaciones
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
  prev_uid uuid;
  prev_wid bigint;
  prev_sec int;
  new_uid uuid;
  new_wid bigint;
  new_sec int;
  seg_name text;
  ot_name text;
  seg_sid uuid;
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

  DROP TABLE IF EXISTS _liftr_seg_prev_kom;
  CREATE TEMP TABLE _liftr_seg_prev_kom (
    segment_id uuid NOT NULL PRIMARY KEY,
    king_user_id uuid,
    king_workout_id bigint,
    king_elapsed_sec integer
  ) ON COMMIT DROP;

  INSERT INTO _liftr_seg_prev_kom (segment_id, king_user_id, king_workout_id, king_elapsed_sec)
  SELECT
    o.segment_id,
    k.user_id,
    k.workout_id,
    k.elapsed_sec
  FROM (
    SELECT DISTINCT se.segment_id
    FROM public.segment_efforts se
    WHERE se.workout_id = p_workout_id
  ) o
  LEFT JOIN LATERAL public._segment_leaderboard_king_v1(o.segment_id) k ON true;

  DROP TABLE IF EXISTS _liftr_seg_mid_kom;
  CREATE TEMP TABLE _liftr_seg_mid_kom (
    segment_id uuid NOT NULL PRIMARY KEY,
    king_user_id uuid,
    king_workout_id bigint,
    king_elapsed_sec integer
  ) ON COMMIT DROP;

  INSERT INTO _liftr_seg_mid_kom (segment_id, king_user_id, king_workout_id, king_elapsed_sec)
  SELECT
    c.id,
    k.user_id,
    k.workout_id,
    k.elapsed_sec
  FROM (
    SELECT s.id
    FROM public.segments s
    WHERE s.status = 'published'
      AND (
        SELECT count(*)::int
        FROM ST_DumpPoints(route_geom) AS dpx
        WHERE ST_DWithin((dpx).geom::geography, s.geom, s.buffer_m)
      ) >= greatest(3, n_pts / 15)
      AND NOT EXISTS (
        SELECT 1 FROM _liftr_seg_prev_kom p WHERE p.segment_id = s.id
      )
  ) c
  LEFT JOIN LATERAL public._segment_leaderboard_king_v1(c.id) k ON true;

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

  FOR seg_sid IN
    SELECT DISTINCT segment_id
    FROM (
      SELECT segment_id FROM _liftr_seg_prev_kom
      UNION
      SELECT segment_id FROM public.segment_efforts WHERE workout_id = p_workout_id
    ) sub
  LOOP
    prev_uid := NULL;
    prev_wid := NULL;
    prev_sec := NULL;
    new_uid := NULL;
    new_wid := NULL;
    new_sec := NULL;

    IF EXISTS (SELECT 1 FROM _liftr_seg_prev_kom p WHERE p.segment_id = seg_sid) THEN
      SELECT p.king_user_id, p.king_workout_id, p.king_elapsed_sec
      INTO prev_uid, prev_wid, prev_sec
      FROM _liftr_seg_prev_kom p
      WHERE p.segment_id = seg_sid;
    ELSIF EXISTS (SELECT 1 FROM _liftr_seg_mid_kom m WHERE m.segment_id = seg_sid) THEN
      SELECT m.king_user_id, m.king_workout_id, m.king_elapsed_sec
      INTO prev_uid, prev_wid, prev_sec
      FROM _liftr_seg_mid_kom m
      WHERE m.segment_id = seg_sid;
    END IF;

    SELECT k.user_id, k.workout_id, k.elapsed_sec
    INTO new_uid, new_wid, new_sec
    FROM public._segment_leaderboard_king_v1(seg_sid) k;

    SELECT s.name INTO seg_name FROM public.segments s WHERE s.id = seg_sid;
    IF seg_name IS NULL THEN
      seg_name := 'Segment';
    END IF;

    IF new_uid IS NOT NULL AND new_uid = uid AND new_wid = p_workout_id THEN
      IF prev_uid IS NULL OR prev_uid IS DISTINCT FROM uid THEN
        PERFORM public.create_notification(
          uid,
          'segment_you_are_first',
          'You''re #1 on a segment',
          format('You''re now first on "%s" with your latest cardio.', seg_name),
          jsonb_build_object(
            'segment_id', seg_sid::text,
            'segment_name', seg_name
          )
        );
      END IF;
    END IF;

    IF prev_uid IS NOT NULL
       AND new_uid IS NOT NULL
       AND prev_uid IS DISTINCT FROM new_uid
       AND new_wid = p_workout_id
    THEN
      ot_name := 'Someone';
      SELECT pr.username INTO ot_name
      FROM public.profiles pr
      WHERE pr.user_id = new_uid
      LIMIT 1;
      IF ot_name IS NULL THEN
        ot_name := 'Someone';
      END IF;

      PERFORM public.create_notification(
        prev_uid,
        'segment_lost_first',
        'You were overtaken on a segment',
        format('%s is now first on "%s".', ot_name, seg_name),
        jsonb_build_object(
          'segment_id', seg_sid::text,
          'segment_name', seg_name,
          'overtaker_user_id', new_uid::text,
          'overtaker_username', ot_name
        )
      );
    END IF;
  END LOOP;

  RETURN;
END;
$match$;

REVOKE ALL ON FUNCTION public._match_segments_for_workout_internal(bigint) FROM PUBLIC;

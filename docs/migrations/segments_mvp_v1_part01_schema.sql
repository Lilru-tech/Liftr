-- Parte 1/6 — Segmentos MVP: extensión PostGIS, tablas, RLS, grants de tablas.
-- Ejecutar este archivo COMPLETO en una sola petición (no partir por `;`).
-- Orden: part01 → … → part06.

CREATE EXTENSION IF NOT EXISTS postgis;

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

REVOKE INSERT, UPDATE, DELETE ON public.segment_efforts FROM authenticated, anon;

GRANT SELECT ON public.segments TO authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.segments TO authenticated;

GRANT SELECT ON public.segment_efforts TO authenticated, anon;

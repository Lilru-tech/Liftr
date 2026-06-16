-- Inspección: puntos workout_scores para sport (Hyrox vs resto) y localización del cálculo en Postgres.
-- Ejecutar en Supabase SQL Editor (o psql). Ajustar LIMIT y filtros de usuario según necesidad.
--
-- Rediseño score Hyrox (desplegar en Supabase):
--   supabase/migrations/20260508120000_score_hyrox_v1_redesign.sql
--
-- Prerrequisito opcional: ver columnas reales de workout_scores
--   SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'workout_scores'
--   ORDER BY ordinal_position;

-- =============================================================================
-- 1) Últimos workouts sport NO Hyrox: suma workout_scores + contexto sesión
-- =============================================================================
SELECT
  w.id AS workout_id,
  w.user_id,
  w.started_at,
  w.state,
  ss.sport,
  ss.duration_sec,
  ss.score_for,
  ss.score_against,
  ss.match_result,
  COALESCE(SUM(ws.score), 0)::numeric AS workout_score_sum,
  COUNT(ws.*) AS workout_score_rows
FROM public.workouts w
JOIN public.sport_sessions ss ON ss.workout_id = w.id
LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
WHERE w.kind = 'sport'
  AND w.state = 'published'
  AND lower(ss.sport) <> 'hyrox'
  -- AND w.user_id = auth.uid()
GROUP BY w.id, w.user_id, w.started_at, w.state, ss.sport, ss.duration_sec, ss.score_for, ss.score_against, ss.match_result
ORDER BY w.started_at DESC NULLS LAST
LIMIT 30;

-- =============================================================================
-- 2) Últimos workouts Hyrox: suma workout_scores + tiempo oficial + duración
-- =============================================================================
SELECT
  w.id AS workout_id,
  w.user_id,
  w.started_at,
  w.state,
  ss.id AS sport_session_id,
  ss.sport,
  ss.duration_sec,
  ss.score_for,
  ss.score_against,
  hy.official_time_sec,
  hy.penalty_time_sec,
  hy.no_reps,
  COALESCE(SUM(ws.score), 0)::numeric AS workout_score_sum,
  COUNT(ws.*) AS workout_score_rows
FROM public.workouts w
JOIN public.sport_sessions ss ON ss.workout_id = w.id
LEFT JOIN public.hyrox_session_stats hy ON hy.session_id = ss.id
LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
WHERE w.kind = 'sport'
  AND w.state = 'published'
  AND lower(ss.sport) = 'hyrox'
  -- AND w.user_id = auth.uid()
GROUP BY
  w.id, w.user_id, w.started_at, w.state,
  ss.id, ss.sport, ss.duration_sec, ss.score_for, ss.score_against,
  hy.official_time_sec, hy.penalty_time_sec, hy.no_reps
ORDER BY w.started_at DESC NULLS LAST
LIMIT 30;

-- Correlación rápida Hyrox: ¿el score sube cuando baja el tiempo oficial? (esperable si la fórmula es correcta)
SELECT
  w.id AS workout_id,
  hy.official_time_sec,
  hy.penalty_time_sec,
  ss.duration_sec,
  COALESCE(SUM(ws.score), 0)::numeric AS workout_score_sum
FROM public.workouts w
JOIN public.sport_sessions ss ON ss.workout_id = w.id
LEFT JOIN public.hyrox_session_stats hy ON hy.session_id = ss.id
LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
WHERE w.kind = 'sport'
  AND w.state = 'published'
  AND lower(ss.sport) = 'hyrox'
  AND hy.official_time_sec IS NOT NULL
  AND hy.official_time_sec > 0
GROUP BY w.id, hy.official_time_sec, hy.penalty_time_sec, ss.duration_sec
ORDER BY hy.official_time_sec ASC
LIMIT 50;

-- =============================================================================
-- 3a) Funciones public cuyo cuerpo menciona workout_scores / hyrox / sport_sessions
-- =============================================================================
SELECT n.nspname AS schema, p.proname AS function_name
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind IN ('f', 'p')
  AND (
    pg_get_functiondef(p.oid) ILIKE '%workout_scores%'
    OR pg_get_functiondef(p.oid) ILIKE '%hyrox%'
    OR pg_get_functiondef(p.oid) ILIKE '%sport_sessions%'
  )
ORDER BY p.proname;

-- =============================================================================
-- 3b) Definición de una función concreta (sustituir proname tras revisar 3a)
-- =============================================================================
-- SELECT pg_get_functiondef(p.oid)
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname = 'create_sport_workout_v2';

-- =============================================================================
-- 3c) Triggers en workouts / sport_sessions / workout_scores
-- =============================================================================
SELECT c.relname AS table_name, t.tgname AS trigger_name, pg_get_triggerdef(t.oid, true) AS trigger_def
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND NOT t.tgisinternal
  AND c.relname IN ('workouts', 'sport_sessions', 'workout_scores', 'hyrox_session_stats')
ORDER BY c.relname, t.tgname;

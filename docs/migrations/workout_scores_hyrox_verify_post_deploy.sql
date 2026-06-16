-- Verificación post-despliegue (SQL Editor) tras aplicar
-- supabase/migrations/20260508120000_score_hyrox_v1_redesign.sql
--
-- Tras desplegar, recalcula scores en BD, p. ej.:
--   DO $$ DECLARE r record; BEGIN
--     FOR r IN SELECT w.id FROM public.workouts w
--       JOIN public.sport_sessions s ON s.workout_id = w.id
--       WHERE w.kind = 'sport' AND w.state = 'published' AND lower(s.sport) = 'hyrox'
--     LOOP PERFORM public.upsert_workout_score_v2(r.id); END LOOP;
--   END $$;
--
-- Esperado: public.score_hyrox_v1(w.id) ≈ SUM(ws.score) para filas algorithm = 'sport_v2'.

SELECT
  w.id AS workout_id,
  w.started_at,
  hy.official_time_sec,
  hy.penalty_time_sec,
  ss.duration_sec,
  public.score_hyrox_v1(w.id) AS computed,
  COALESCE(SUM(ws.score) FILTER (WHERE ws.algorithm = 'sport_v2'), 0)::numeric AS stored_sport_v2
FROM public.workouts w
JOIN public.sport_sessions ss ON ss.workout_id = w.id
LEFT JOIN public.hyrox_session_stats hy ON hy.session_id = ss.id
LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
WHERE w.kind = 'sport'
  AND w.state = 'published'
  AND lower(ss.sport) = 'hyrox'
GROUP BY w.id, w.started_at, hy.official_time_sec, hy.penalty_time_sec, ss.duration_sec
ORDER BY w.started_at DESC NULLS LAST
LIMIT 50;

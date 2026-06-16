-- =============================================================================
-- Liftr — Consultas manuales para depurar rankings (SQL Editor / psql).
--
-- NOTA "period" en rankings sociales / deporte: el mismo selector Today / Week /
-- Month / All-time de la app se aplica a la fecha del workout. En SQL es
-- COALESCE(w.started_at, w.created_at) dentro del intervalo [t_start, t_end).
--
-- Achievements (en app solo hay una métrica): get_achievements_unlocked_period_leaderboard_v1
-- cuenta user_achievements con unlocked_at en el intervalo del chip de periodo.
--
-- Si en la query 1a (published_multi_in_bounds, published_in_bounds) = (0, 0): no hay
-- workouts publicados en la semana ISO actual con fecha en ventana; prueba
-- la consulta 1b con ventana "all" o cambia el periodo en la app a All-time.
-- =============================================================================

-- --- 0) ¿Hay publicados esta semana usando la MISMA regla que los RPC?
SELECT
  COUNT(*) FILTER (WHERE w.started_at IS NULL) AS published_week_started_at_null,
  COUNT(*) FILTER (WHERE w.started_at IS NOT NULL) AS published_week_started_at_set,
  COUNT(*) AS published_week_coalesce_rule
FROM public.workouts w
CROSS JOIN (
  SELECT date_trunc('week', now()) AS t_start, now() AS t_end
) b
WHERE w.state = 'published'
  AND COALESCE(w.started_at, w.created_at) >= b.t_start
  AND COALESCE(w.started_at, w.created_at) < b.t_end;

-- --- 1a) Group sessions + ventana SEMANA (igual que p_period = week en RPC)
WITH bounds AS (
  SELECT date_trunc('week', now()) AS t_start, now() AS t_end
),
workout_people AS (
  SELECT w.id AS workout_id, w.user_id AS uid
  FROM public.workouts w
  WHERE w.state = 'published'
  UNION ALL
  SELECT wp.workout_id, wp.user_id
  FROM public.workout_participants wp
  INNER JOIN public.workouts w2 ON w2.id = wp.workout_id AND w2.state = 'published'
),
multi AS (
  SELECT workout_id
  FROM workout_people
  GROUP BY workout_id
  HAVING COUNT(DISTINCT uid) >= 2
)
SELECT
  COUNT(*) FILTER (WHERE w.id IN (SELECT workout_id FROM multi)) AS published_multi_in_bounds,
  COUNT(*) AS published_in_bounds
FROM public.workouts w
CROSS JOIN bounds b
WHERE w.state = 'published'
  AND COALESCE(w.started_at, w.created_at) >= b.t_start
  AND COALESCE(w.started_at, w.created_at) < b.t_end;

-- --- 1b) Misma lógica con ventana ALL-TIME (como p_period = all en la app)
WITH bounds AS (
  SELECT '1970-01-01'::timestamptz AS t_start, now() AS t_end
),
workout_people AS (
  SELECT w.id AS workout_id, w.user_id AS uid
  FROM public.workouts w
  WHERE w.state = 'published'
  UNION ALL
  SELECT wp.workout_id, wp.user_id
  FROM public.workout_participants wp
  INNER JOIN public.workouts w2 ON w2.id = wp.workout_id AND w2.state = 'published'
),
multi AS (
  SELECT workout_id
  FROM workout_people
  GROUP BY workout_id
  HAVING COUNT(DISTINCT uid) >= 2
)
SELECT
  COUNT(*) FILTER (WHERE w.id IN (SELECT workout_id FROM multi)) AS published_multi_in_bounds,
  COUNT(*) AS published_in_bounds
FROM public.workouts w
CROSS JOIN bounds b
WHERE w.state = 'published'
  AND COALESCE(w.started_at, w.created_at) >= b.t_start
  AND COALESCE(w.started_at, w.created_at) < b.t_end;

-- Detalle: workouts con 1 solo participante en tabla (típico dueño + 1 amigo), sin filtro de fechas
SELECT w.id, w.user_id AS owner, COUNT(DISTINCT wp.user_id) AS participant_rows_distinct
FROM public.workouts w
LEFT JOIN public.workout_participants wp ON wp.workout_id = w.id
WHERE w.state = 'published'
GROUP BY w.id, w.user_id
HAVING COUNT(DISTINCT wp.user_id) = 1
LIMIT 20;

-- --- 2) Achievements: total de filas en user_achievements (útil para cotejar con RLS)
SELECT COUNT(*) AS total_rows_in_user_achievements FROM public.user_achievements;

-- --- 3) Ski: sesiones publicadas con sport = ski y join a stats
SELECT
  lower(coalesce(ss.sport::text, '')) AS sport_text,
  COUNT(*) AS sessions,
  COUNT(*) FILTER (WHERE sk.session_id IS NOT NULL) AS with_ski_stats_row,
  SUM(COALESCE(sk.total_distance_km, 0::numeric)) AS sum_km
FROM public.workouts w
JOIN public.sport_sessions ss ON ss.workout_id = w.id
LEFT JOIN public.ski_session_stats sk ON sk.session_id = ss.id
WHERE w.state = 'published'
  AND w.kind::text = 'sport'
GROUP BY 1
ORDER BY sessions DESC
LIMIT 20;

-- --- 4) Llamada directa a los RPC (misma firma que PostgREST)
-- SELECT * FROM public.get_group_workout_sessions_leaderboard_v1('global', 'week', 100, NULL, NULL);
-- SELECT * FROM public.get_group_workout_sessions_leaderboard_v1('global', 'all', 100, NULL, NULL);
-- SELECT * FROM public.get_achievements_unlocked_period_leaderboard_v1('global', 'week', 100, NULL, NULL);
-- SELECT * FROM public.get_ski_distance_leaderboard_v1('global', 'all', 100, NULL, NULL);

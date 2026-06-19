-- =============================================================================
-- Opcional: ejecutar ANTES de ranking_goals_duels_leaderboard_v1.sql
-- y pegar el resultado (o capturas) si algo falla al crear las funciones.
-- =============================================================================

-- 1) Columnas que usa el script de leaderboards
SELECT
  c.table_name,
  c.column_name,
  c.data_type,
  c.udt_name
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN ('weekly_goal_results', 'competitions', 'follows', 'profiles')
  AND c.column_name IN (
    'user_id', 'week_start', 'is_completed',
    'user_a', 'user_b', 'winner_user_id', 'status',
    'follower_id', 'followee_id',
    'username', 'avatar_url', 'sex', 'date_of_birth'
  )
ORDER BY c.table_name, c.ordinal_position;

-- 2) Tipo de competitions.status (text, enum, etc.)
SELECT
  a.attname AS column_name,
  format_type(a.atttypid, a.atttypmod) AS pg_type
FROM pg_attribute a
JOIN pg_class t ON t.oid = a.attrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public'
  AND t.relname = 'competitions'
  AND a.attname = 'status'
  AND NOT a.attisdropped;

-- 3) Muestras de valores reales de status (útil si no es 'finished' exacto)
SELECT DISTINCT status, COUNT(*)::bigint
FROM public.competitions
GROUP BY status
ORDER BY 2 DESC;

-- 4) (Opcional) definición de get_level_leaderboard_v1 para alinear p_age_band después
-- SELECT pg_get_functiondef(oid) FROM pg_proc
-- WHERE proname = 'get_level_leaderboard_v1' AND pronamespace = 'public'::regnamespace;

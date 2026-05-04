-- =============================================================================
-- Liftr — get_goal_stats: semántica alineada con la app (completados vs semana cerrada).
--
-- finished_goals = metas con is_completed (no “semana terminada”).
-- missed_goals    = meta con semana ya pasada y sin completar.
-- finished_percent = 100 * completed / total_goals
-- avg/best         = media y máximo de 100 * achieved/target (sin cap; coherente con UI).
--
-- Cuerpo con AS '...' (sin dollar-quotes) para DbVisualizer y clientes que trocean en `;`.
-- Supabase / psql también lo aceptan. Ver docs/postgres-sql-execution-notes.md
--
-- Si la transacción anterior falló: ROLLBACK; y si DROP ya se ejecutó, vuelve a correr
-- este script entero (recrea la función).
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_goal_stats(uuid);

CREATE FUNCTION public.get_goal_stats(p_user_id uuid)
RETURNS TABLE(
    total_goals integer,
    finished_goals integer,
    missed_goals integer,
    finished_percent double precision,
    avg_progress_percent double precision,
    best_progress_percent double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS '
  WITH base AS (
    SELECT
      wg.id AS goal_id,
      wg.week_start::date AS ws,
      (wg.week_start::date + interval ''7 days'')::date AS week_end_exclusive,
      NULLIF(wg.target_value::numeric, 0) AS tgt,
      COALESCE(wgr.achieved_value, 0)::numeric AS ach,
      COALESCE(wgr.is_completed, false) AS done
    FROM public.weekly_goals wg
    LEFT JOIN public.weekly_goal_results wgr
      ON wgr.goal_id = wg.id
     AND wgr.week_start = wg.week_start
     AND wgr.user_id = wg.user_id
    WHERE wg.user_id = p_user_id
  ),
  scored AS (
    SELECT
      b.*,
      CASE
        WHEN b.tgt IS NOT NULL THEN (100.0 * b.ach / b.tgt)::double precision
        ELSE 0::double precision
      END AS pct_raw
    FROM base b
  )
  SELECT
    COUNT(*)::integer AS total_goals,
    COUNT(*) FILTER (WHERE s.done)::integer AS finished_goals,
    COUNT(*) FILTER (
      WHERE NOT s.done
        AND s.week_end_exclusive <= (timezone(''utc'', now()))::date
    )::integer AS missed_goals,
    ROUND(
      (100.0 * COUNT(*) FILTER (WHERE s.done)::numeric / NULLIF(COUNT(*), 0)::numeric),
      1
    )::double precision AS finished_percent,
    ROUND(AVG(s.pct_raw)::numeric, 1)::double precision AS avg_progress_percent,
    ROUND(MAX(s.pct_raw)::numeric, 1)::double precision AS best_progress_percent
  FROM scored s
';

COMMENT ON FUNCTION public.get_goal_stats(uuid) IS
'Agregados de weekly_goals + weekly_goal_results: total, completados (is_completed), missed (semana pasada y no completado), % completitud, media y mejor % logrado.';

GRANT EXECUTE ON FUNCTION public.get_goal_stats(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_goal_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_goal_stats(uuid) TO service_role;

COMMIT;

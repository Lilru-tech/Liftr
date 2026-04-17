-- =============================================================================
-- Weekly goal recommendation — audit helpers
-- =============================================================================
-- The iOS app calls RPC: get_weekly_goal_recommendation(p_user_id, p_metric)
-- with metric values: workouts | calories | score (see GoalMetric.swift).
--
-- Replace AUDIT_USER below (single place) before running in Supabase SQL Editor.
--
-- 1) SOURCE OF TRUTH FOR THE FORMULA
--    Supabase → Database → Functions → get_weekly_goal_recommendation
--    Copy the CREATE OR REPLACE FUNCTION body into your migrations repo or
--    into the placeholder section below for traceability.
--
-- ---------------------------------------------------------------------------
-- PASTE RPC DEFINITION FROM SUPABASE DASHBOARD BELOW (optional)
-- ---------------------------------------------------------------------------
-- /* RPC body not stored in this repo by default — paste from Supabase. */
-- ---------------------------------------------------------------------------
-- =============================================================================

-- AUDIT_USER: change UUID here only
WITH params AS (
  SELECT '4F009D0B-547E-4090-AA7E-1C70197E9E99'::uuid AS uid
)
SELECT get_weekly_goal_recommendation(
  p_user_id => (SELECT uid FROM params),
  p_metric => 'score'
) AS rpc_score;

WITH params AS (
  SELECT '4F009D0B-547E-4090-AA7E-1C70197E9E99'::uuid AS uid
)
SELECT get_weekly_goal_recommendation(
  p_user_id => (SELECT uid FROM params),
  p_metric => 'calories'
) AS rpc_calories;

WITH params AS (
  SELECT '4F009D0B-547E-4090-AA7E-1C70197E9E99'::uuid AS uid
)
SELECT get_weekly_goal_recommendation(
  p_user_id => (SELECT uid FROM params),
  p_metric => 'workouts'
) AS rpc_workouts;

-- =============================================================================
-- MANUAL WINDOW — compare totals to RPC (same user as AUDIT_USER above)
-- Week boundaries: Monday start, date in Europe/Madrid (matches iOS
-- GoalsManager: Calendar firstWeekday = 2 + dateOnlyString Europe/Madrid).
--
-- If your RPC filters workouts (e.g. state = 'finished'), add the same
-- predicate to per_workout as in the backend function.
-- =============================================================================

WITH params AS (
  SELECT '4F009D0B-547E-4090-AA7E-1C70197E9E99'::uuid AS uid
),
madrid AS (
  SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Madrid')::date AS today_madrid
),
madrid_week_start AS (
  SELECT
    today_madrid - ((EXTRACT(isodow FROM today_madrid)::int - 1) * interval '1 day') AS ws
  FROM madrid
),
per_workout AS (
  SELECT
    w.id AS workout_id,
    (w.started_at AT TIME ZONE 'Europe/Madrid')::date AS day_madrid,
    COALESCE(s.sum_score, 0)::numeric AS score_pts,
    COALESCE(w.calories_kcal, 0)::numeric AS kcal
  FROM workouts w
  CROSS JOIN params p
  LEFT JOIN LATERAL (
    SELECT SUM(ws.score) AS sum_score
    FROM workout_scores ws
    WHERE ws.workout_id = w.id
  ) s ON true
  WHERE w.user_id = p.uid
    AND w.started_at IS NOT NULL
),
with_week AS (
  SELECT
    pw.*,
    (pw.day_madrid - ((EXTRACT(isodow FROM pw.day_madrid)::int - 1) * interval '1 day'))::date AS week_start_monday_madrid
  FROM per_workout pw
),
weekly AS (
  SELECT
    week_start_monday_madrid,
    COUNT(DISTINCT workout_id)::numeric AS workouts_count,
    SUM(kcal)::numeric AS calories_sum,
    SUM(score_pts)::numeric AS score_sum
  FROM with_week
  GROUP BY week_start_monday_madrid
),
eligible AS (
  SELECT w.*
  FROM weekly w
  CROSS JOIN madrid_week_start m
  WHERE w.week_start_monday_madrid >= m.ws - interval '49 days'
    AND w.week_start_monday_madrid <= m.ws
)
SELECT * FROM eligible ORDER BY week_start_monday_madrid DESC;

-- Aggregates: compare round(avg(...)) to typical RPC outputs.
WITH params AS (
  SELECT '4F009D0B-547E-4090-AA7E-1C70197E9E99'::uuid AS uid
),
madrid AS (
  SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'Europe/Madrid')::date AS today_madrid
),
madrid_week_start AS (
  SELECT
    today_madrid - ((EXTRACT(isodow FROM today_madrid)::int - 1) * interval '1 day') AS ws
  FROM madrid
),
per_workout AS (
  SELECT
    w.id AS workout_id,
    (w.started_at AT TIME ZONE 'Europe/Madrid')::date AS day_madrid,
    COALESCE(s.sum_score, 0)::numeric AS score_pts,
    COALESCE(w.calories_kcal, 0)::numeric AS kcal
  FROM workouts w
  CROSS JOIN params p
  LEFT JOIN LATERAL (
    SELECT SUM(ws.score) AS sum_score
    FROM workout_scores ws
    WHERE ws.workout_id = w.id
  ) s ON true
  WHERE w.user_id = p.uid
    AND w.started_at IS NOT NULL
),
with_week AS (
  SELECT
    pw.*,
    (pw.day_madrid - ((EXTRACT(isodow FROM pw.day_madrid)::int - 1) * interval '1 day'))::date AS week_start_monday_madrid
  FROM per_workout pw
),
weekly AS (
  SELECT
    week_start_monday_madrid,
    COUNT(DISTINCT workout_id)::numeric AS workouts_count,
    SUM(kcal)::numeric AS calories_sum,
    SUM(score_pts)::numeric AS score_sum
  FROM with_week
  GROUP BY week_start_monday_madrid
),
eligible AS (
  SELECT w.*
  FROM weekly w
  CROSS JOIN madrid_week_start m
  WHERE w.week_start_monday_madrid >= m.ws - interval '49 days'
    AND w.week_start_monday_madrid <= m.ws
)
SELECT
  round(avg(score_sum))::int AS manual_avg_score_rounded,
  round(avg(calories_sum))::int AS manual_avg_calories_rounded,
  round(avg(workouts_count))::int AS manual_avg_workouts_rounded,
  count(*)::int AS weeks_in_window
FROM eligible;

-- If your RPC excludes the in-progress week, replace `FROM eligible` above with:
-- FROM (SELECT e.* FROM eligible e CROSS JOIN madrid_week_start m
--       WHERE e.week_start_monday_madrid < m.ws) eligible_no_current

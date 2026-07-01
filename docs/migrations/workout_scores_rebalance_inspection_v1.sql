-- Score distribution inspection (all kinds). Run in Supabase SQL Editor after rebalance deploy.

WITH scored AS (
  SELECT
    w.id,
    w.kind,
    w.started_at,
    COALESCE(SUM(ws.score), 0) AS total_score
  FROM public.workouts w
  LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
  WHERE w.state = 'published'
  GROUP BY w.id, w.kind, w.started_at
)
SELECT
  kind,
  COUNT(*) AS workouts,
  ROUND(AVG(total_score)::numeric, 1) AS avg_total,
  ROUND(MIN(total_score)::numeric, 1) AS min_total,
  ROUND(MAX(total_score)::numeric, 1) AS max_total,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_score)::numeric, 1) AS median_total
FROM scored
GROUP BY kind
ORDER BY kind;

WITH scored AS (
  SELECT
    w.id,
    lower(coalesce(cs.activity_code, cs.activity_type, cs.modality)) AS activity,
    COALESCE(SUM(ws.score), 0) AS total_score
  FROM public.workouts w
  JOIN public.cardio_sessions cs ON cs.workout_id = w.id
  LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
  WHERE w.state = 'published'
    AND w.kind = 'cardio'
  GROUP BY w.id, cs.activity_code, cs.activity_type, cs.modality
)
SELECT
  activity,
  COUNT(*) AS workouts,
  ROUND(AVG(total_score)::numeric, 1) AS avg_score,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_score)::numeric, 1) AS median_score
FROM scored
GROUP BY activity
ORDER BY median_score DESC;

WITH scored AS (
  SELECT
    w.id,
    lower(ss.sport) AS sport,
    COALESCE(SUM(ws.score), 0) AS total_score
  FROM public.workouts w
  JOIN public.sport_sessions ss ON ss.workout_id = w.id
  LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
  WHERE w.state = 'published'
    AND w.kind = 'sport'
  GROUP BY w.id, ss.sport
)
SELECT
  sport,
  COUNT(*) AS workouts,
  ROUND(AVG(total_score)::numeric, 1) AS avg_score,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_score)::numeric, 1) AS median_score
FROM scored
GROUP BY sport
ORDER BY median_score DESC;

SELECT
  w.id AS workout_id,
  hy.official_time_sec,
  hy.no_reps,
  COALESCE(SUM(ws.score), 0) AS stored_score,
  public.score_hyrox_v1(w.id) AS computed_score
FROM public.workouts w
JOIN public.sport_sessions ss ON ss.workout_id = w.id
LEFT JOIN public.hyrox_session_stats hy ON hy.session_id = ss.id
LEFT JOIN public.workout_scores ws ON ws.workout_id = w.id
WHERE w.state = 'published'
  AND lower(ss.sport) = 'hyrox'
GROUP BY w.id, hy.official_time_sec, hy.no_reps
HAVING ABS(COALESCE(SUM(ws.score), 0) - public.score_hyrox_v1(w.id)) > 0.01
ORDER BY w.started_at DESC;

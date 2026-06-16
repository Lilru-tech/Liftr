-- Optional: run in Supabase SQL Editor before/after deploying ranking_training_metrics_leaderboard_v1.sql
-- to validate data coverage (plan: sql-introspect).

-- Sport: match_result distribution
-- SELECT match_result, count(*) FROM sport_sessions WHERE match_result IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 30;

-- Cardio: distance / pace coverage
-- SELECT count(*) FILTER (WHERE distance_km IS NOT NULL AND distance_km > 0),
--        count(*) FILTER (WHERE avg_pace_sec_per_km IS NOT NULL AND avg_pace_sec_per_km > 0)
-- FROM cardio_sessions;

-- Strength: volume view (if present)
-- SELECT count(*), coalesce(sum(total_volume_kg), 0) FROM vw_workout_volume;

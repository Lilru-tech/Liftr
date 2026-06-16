-- =============================================================================
-- Liftr — Training leaderboards: strength volume (from exercise_sets),
-- cardio distance (cardio_sessions.distance_km), sport match wins (match_result = win).
-- Semantics: same audience filters as get_goals_completed_leaderboard_v1 (scope/sex/age).
-- Period: day / week / month / all on workouts.started_at (UTC date_trunc); excludes planned.
-- Deploy in Supabase SQL Editor. Grant EXECUTE to authenticated (and anon if you expose ranking).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_strength_volume_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL,
  p_muscle_primary text DEFAULT NULL
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  total_volume_kg numeric,
  workouts_cnt int
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS '
BEGIN
  RETURN QUERY
  WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, ''week''))
        WHEN ''day''   THEN date_trunc(''day'', now())
        WHEN ''week''  THEN date_trunc(''week'', now())
        WHEN ''month'' THEN date_trunc(''month'', now())
        WHEN ''all''   THEN ''1970-01-01''::timestamptz
        ELSE date_trunc(''week'', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = ''strength''
      AND w.state IS DISTINCT FROM ''planned''::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  vol AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id)::int AS workouts_cnt,
      SUM(
        COALESCE(es.reps, 0)::numeric * COALESCE(es.weight_kg, 0::numeric)
      )::numeric AS total_volume_kg
    FROM bw
    INNER JOIN public.workout_exercises we ON we.workout_id = bw.id
    INNER JOIN public.exercises ex ON ex.id = we.exercise_id
    INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    WHERE
      (p_muscle_primary IS NULL OR p_muscle_primary = ''''
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(p_muscle_primary)))
    GROUP BY bw.user_id
    HAVING SUM(
      COALESCE(es.reps, 0)::numeric * COALESCE(es.weight_kg, 0::numeric)
    ) > 0
  ),
  scoped AS (
    SELECT v.uid, v.workouts_cnt, v.total_volume_kg
    FROM vol v
    INNER JOIN public.profiles pr ON pr.user_id = v.uid
    WHERE
      (p_sex IS NULL OR p_sex = '''' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''''
        OR (
          CASE p_age_band
            WHEN ''18-24'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN ''25-34'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN ''35-44'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN ''45-54'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN ''55+''   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, ''global'') = ''global''
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT
      s.uid,
      s.workouts_cnt,
      s.total_volume_kg,
      ROW_NUMBER() OVER (ORDER BY s.total_volume_kg DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT
    o.rnk::int AS rank,
    o.uid AS user_id,
    pr.username,
    pr.avatar_url,
    o.total_volume_kg,
    o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk;
END;
';

CREATE OR REPLACE FUNCTION public.get_cardio_distance_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL,
  p_activity_code text DEFAULT NULL
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  total_distance_km numeric,
  workouts_cnt int
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS '
BEGIN
  RETURN QUERY
  WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, ''week''))
        WHEN ''day''   THEN date_trunc(''day'', now())
        WHEN ''week''  THEN date_trunc(''week'', now())
        WHEN ''month'' THEN date_trunc(''month'', now())
        WHEN ''all''   THEN ''1970-01-01''::timestamptz
        ELSE date_trunc(''week'', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = ''cardio''
      AND w.state IS DISTINCT FROM ''planned''::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  dist AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id)::int AS workouts_cnt,
      SUM(COALESCE(cs.distance_km, 0::numeric))::numeric AS total_distance_km
    FROM bw
    INNER JOIN public.cardio_sessions cs ON cs.workout_id = bw.id
    WHERE
      (p_activity_code IS NULL OR p_activity_code = ''''
        OR lower(btrim(coalesce(cs.activity_code, cs.modality, ''''))) = lower(btrim(p_activity_code)))
    GROUP BY bw.user_id
    HAVING SUM(COALESCE(cs.distance_km, 0::numeric)) > 0
  ),
  scoped AS (
    SELECT d.uid, d.workouts_cnt, d.total_distance_km
    FROM dist d
    INNER JOIN public.profiles pr ON pr.user_id = d.uid
    WHERE
      (p_sex IS NULL OR p_sex = '''' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''''
        OR (
          CASE p_age_band
            WHEN ''18-24'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN ''25-34'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN ''35-44'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN ''45-54'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN ''55+''   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, ''global'') = ''global''
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT
      s.uid,
      s.workouts_cnt,
      s.total_distance_km,
      ROW_NUMBER() OVER (ORDER BY s.total_distance_km DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT
    o.rnk::int AS rank,
    o.uid AS user_id,
    pr.username,
    pr.avatar_url,
    o.total_distance_km,
    o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk;
END;
';

CREATE OR REPLACE FUNCTION public.get_sport_match_wins_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  wins bigint,
  matches_played bigint
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS '
BEGIN
  RETURN QUERY
  WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, ''week''))
        WHEN ''day''   THEN date_trunc(''day'', now())
        WHEN ''week''  THEN date_trunc(''week'', now())
        WHEN ''month'' THEN date_trunc(''month'', now())
        WHEN ''all''   THEN ''1970-01-01''::timestamptz
        ELSE date_trunc(''week'', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = ''sport''
      AND w.state IS DISTINCT FROM ''planned''::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id) FILTER (WHERE lower(btrim(ss.match_result::text)) = ''win'')::bigint AS wins,
      COUNT(DISTINCT bw.id)::bigint AS matches_played
    FROM bw
    INNER JOIN public.sport_sessions ss ON ss.workout_id = bw.id
    WHERE ss.match_result IS NOT NULL
      AND btrim(ss.match_result::text) <> ''''
    GROUP BY bw.user_id
    HAVING COUNT(DISTINCT bw.id) FILTER (WHERE lower(btrim(ss.match_result::text)) = ''win'') > 0
  ),
  scoped AS (
    SELECT a.uid, a.wins, a.matches_played
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '''' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''''
        OR (
          CASE p_age_band
            WHEN ''18-24'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN ''25-34'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN ''35-44'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN ''45-54'' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN ''55+''   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, ''global'') = ''global''
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1
          FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT
      s.uid,
      s.wins,
      s.matches_played,
      ROW_NUMBER() OVER (ORDER BY s.wins DESC, s.matches_played DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT
    o.rnk::int AS rank,
    o.uid AS user_id,
    pr.username,
    pr.avatar_url,
    o.wins,
    o.matches_played
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk;
END;
';

GRANT EXECUTE ON FUNCTION public.get_strength_volume_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cardio_distance_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sport_match_wins_leaderboard_v1(text, text, int, text, text) TO authenticated;

-- =============================================================================
-- Liftr — Extended training leaderboards (elevation, cardio time, best pace,
-- strength reps/sets/max set weight, sport play time, win rate) + optional
-- sport filter on match wins.
-- Deploy after ranking_training_metrics_leaderboard_v1.sql.
-- Replaces get_sport_match_wins_leaderboard_v1 with a 6-arg version (adds p_sport).
--
-- NOTE (DbVisualizer / JDBC clients): bodies use LANGUAGE sql + dollar quotes
-- with NO semicolon inside the quote so tools that split scripts on ";" do not
-- break PL/pgSQL RETURN QUERY ... ; END; blocks.
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_sport_match_wins_leaderboard_v1(text, text, int, text, text);

CREATE OR REPLACE FUNCTION public.get_sport_match_wins_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL,
  p_sport text DEFAULT NULL
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  wins bigint,
  matches_played bigint
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'sport'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id) FILTER (WHERE lower(btrim(ss.match_result::text)) = 'win')::bigint AS wins,
      COUNT(DISTINCT bw.id)::bigint AS matches_played
    FROM bw
    INNER JOIN public.sport_sessions ss ON ss.workout_id = bw.id
    WHERE ss.match_result IS NOT NULL
      AND btrim(ss.match_result::text) <> ''
      AND (
        p_sport IS NULL OR btrim(p_sport) = ''
        OR lower(btrim(coalesce(ss.sport::text, ''))) = lower(btrim(p_sport))
      )
    GROUP BY bw.user_id
    HAVING COUNT(DISTINCT bw.id) FILTER (WHERE lower(btrim(ss.match_result::text)) = 'win') > 0
  ),
  scoped AS (
    SELECT a.uid, a.wins, a.matches_played
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
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
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_cardio_elevation_leaderboard_v1(
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
  total_elevation_m bigint,
  workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'cardio'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id)::int AS workouts_cnt,
      SUM(COALESCE(cs.elevation_gain_m, 0))::bigint AS total_elevation_m
    FROM bw
    INNER JOIN public.cardio_sessions cs ON cs.workout_id = bw.id
    WHERE
      (p_activity_code IS NULL OR p_activity_code = ''
        OR lower(btrim(coalesce(cs.activity_code, cs.modality, ''))) = lower(btrim(p_activity_code)))
    GROUP BY bw.user_id
    HAVING SUM(COALESCE(cs.elevation_gain_m, 0)) > 0
  ),
  scoped AS (
    SELECT a.uid, a.workouts_cnt, a.total_elevation_m
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.workouts_cnt, s.total_elevation_m,
      ROW_NUMBER() OVER (ORDER BY s.total_elevation_m DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_elevation_m, o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_cardio_duration_leaderboard_v1(
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
  total_duration_sec bigint,
  workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'cardio'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id)::int AS workouts_cnt,
      SUM(COALESCE(cs.duration_sec, 0))::bigint AS total_duration_sec
    FROM bw
    INNER JOIN public.cardio_sessions cs ON cs.workout_id = bw.id
    WHERE
      (p_activity_code IS NULL OR p_activity_code = ''
        OR lower(btrim(coalesce(cs.activity_code, cs.modality, ''))) = lower(btrim(p_activity_code)))
    GROUP BY bw.user_id
    HAVING SUM(COALESCE(cs.duration_sec, 0)) > 0
  ),
  scoped AS (
    SELECT a.uid, a.workouts_cnt, a.total_duration_sec
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.workouts_cnt, s.total_duration_sec,
      ROW_NUMBER() OVER (ORDER BY s.total_duration_sec DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_duration_sec, o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_cardio_best_pace_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL,
  p_activity_code text DEFAULT NULL,
  p_min_distance_km numeric DEFAULT 1.0
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  best_pace_sec_per_km int,
  qualifying_workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'cardio'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  sess AS (
    SELECT bw.user_id AS uid, bw.id AS wid, cs.avg_pace_sec_per_km AS pace
    FROM bw
    INNER JOIN public.cardio_sessions cs ON cs.workout_id = bw.id
    WHERE cs.avg_pace_sec_per_km IS NOT NULL
      AND cs.avg_pace_sec_per_km > 0
      AND cs.distance_km IS NOT NULL
      AND cs.distance_km >= GREATEST(0.01::numeric, COALESCE(p_min_distance_km, 1.0))
      AND (
        p_activity_code IS NULL OR p_activity_code = ''
        OR lower(btrim(coalesce(cs.activity_code, cs.modality, ''))) = lower(btrim(p_activity_code))
      )
  ),
  agg AS (
    SELECT
      s.uid,
      MIN(s.pace)::int AS best_pace_sec_per_km,
      COUNT(DISTINCT s.wid)::int AS qualifying_workouts_cnt
    FROM sess s
    GROUP BY s.uid
    HAVING MIN(s.pace) IS NOT NULL
  ),
  scoped AS (
    SELECT a.uid, a.best_pace_sec_per_km, a.qualifying_workouts_cnt
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.best_pace_sec_per_km, s.qualifying_workouts_cnt,
      ROW_NUMBER() OVER (
        ORDER BY s.best_pace_sec_per_km ASC, s.qualifying_workouts_cnt DESC, s.uid
      ) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.best_pace_sec_per_km, o.qualifying_workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_strength_total_reps_leaderboard_v1(
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
  total_reps bigint,
  workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'strength'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id)::int AS workouts_cnt,
      SUM(COALESCE(es.reps, 0))::bigint AS total_reps
    FROM bw
    INNER JOIN public.workout_exercises we ON we.workout_id = bw.id
    INNER JOIN public.exercises ex ON ex.id = we.exercise_id
    INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    WHERE
      (p_muscle_primary IS NULL OR p_muscle_primary = ''
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(p_muscle_primary)))
    GROUP BY bw.user_id
    HAVING SUM(COALESCE(es.reps, 0)) > 0
  ),
  scoped AS (
    SELECT a.uid, a.workouts_cnt, a.total_reps
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.workouts_cnt, s.total_reps,
      ROW_NUMBER() OVER (ORDER BY s.total_reps DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_reps, o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_strength_total_sets_leaderboard_v1(
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
  total_sets bigint,
  workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'strength'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id)::int AS workouts_cnt,
      COUNT(es.id)::bigint AS total_sets
    FROM bw
    INNER JOIN public.workout_exercises we ON we.workout_id = bw.id
    INNER JOIN public.exercises ex ON ex.id = we.exercise_id
    INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    WHERE
      (p_muscle_primary IS NULL OR p_muscle_primary = ''
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(p_muscle_primary)))
    GROUP BY bw.user_id
    HAVING COUNT(es.id) > 0
  ),
  scoped AS (
    SELECT a.uid, a.workouts_cnt, a.total_sets
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.workouts_cnt, s.total_sets,
      ROW_NUMBER() OVER (ORDER BY s.total_sets DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_sets, o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_strength_max_set_weight_leaderboard_v1(
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
  max_weight_kg numeric,
  workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'strength'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  per_set AS (
    SELECT bw.user_id AS uid, bw.id AS wid, es.weight_kg
    FROM bw
    INNER JOIN public.workout_exercises we ON we.workout_id = bw.id
    INNER JOIN public.exercises ex ON ex.id = we.exercise_id
    INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    WHERE COALESCE(es.reps, 0) > 0
      AND COALESCE(es.weight_kg, 0::numeric) > 0
      AND (
        p_muscle_primary IS NULL OR p_muscle_primary = ''
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(p_muscle_primary))
      )
  ),
  agg AS (
    SELECT
      p.uid,
      COUNT(DISTINCT p.wid)::int AS workouts_cnt,
      MAX(p.weight_kg)::numeric AS max_weight_kg
    FROM per_set p
    GROUP BY p.uid
    HAVING MAX(p.weight_kg) IS NOT NULL
  ),
  scoped AS (
    SELECT a.uid, a.workouts_cnt, a.max_weight_kg
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.workouts_cnt, s.max_weight_kg,
      ROW_NUMBER() OVER (ORDER BY s.max_weight_kg DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.max_weight_kg, o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_sport_duration_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL,
  p_sport text DEFAULT NULL
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  total_duration_sec bigint,
  workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'sport'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id)::int AS workouts_cnt,
      SUM(COALESCE(ss.duration_sec, 0))::bigint AS total_duration_sec
    FROM bw
    INNER JOIN public.sport_sessions ss ON ss.workout_id = bw.id
    WHERE
      p_sport IS NULL OR btrim(p_sport) = ''
      OR lower(btrim(coalesce(ss.sport::text, ''))) = lower(btrim(p_sport))
    GROUP BY bw.user_id
    HAVING SUM(COALESCE(ss.duration_sec, 0)) > 0
  ),
  scoped AS (
    SELECT a.uid, a.workouts_cnt, a.total_duration_sec
    FROM agg a
    INNER JOIN public.profiles pr ON pr.user_id = a.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.workouts_cnt, s.total_duration_sec,
      ROW_NUMBER() OVER (ORDER BY s.total_duration_sec DESC, s.workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_duration_sec, o.workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

CREATE OR REPLACE FUNCTION public.get_sport_win_rate_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL,
  p_sport text DEFAULT NULL,
  p_min_matches int DEFAULT 3
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  wins bigint,
  matches_played bigint,
  win_rate numeric
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $ranking_v2$
WITH bounds AS (
    SELECT
      CASE lower(coalesce(p_period, 'week'))
        WHEN 'day'   THEN date_trunc('day', now())
        WHEN 'week'  THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'all'   THEN '1970-01-01'::timestamptz
        ELSE date_trunc('week', now())
      END AS t_start,
      now() AS t_end
  ),
  bw AS (
    SELECT w.id, w.user_id
    FROM public.workouts w
    CROSS JOIN bounds b
    WHERE w.kind::text = 'sport'
      AND w.state IS DISTINCT FROM 'planned'::public.workout_state
      AND w.started_at >= b.t_start
      AND w.started_at < b.t_end
  ),
  agg AS (
    SELECT
      bw.user_id AS uid,
      COUNT(DISTINCT bw.id) FILTER (WHERE lower(btrim(ss.match_result::text)) = 'win')::bigint AS wins,
      COUNT(DISTINCT bw.id)::bigint AS matches_played
    FROM bw
    INNER JOIN public.sport_sessions ss ON ss.workout_id = bw.id
    WHERE ss.match_result IS NOT NULL
      AND btrim(ss.match_result::text) <> ''
      AND (
        p_sport IS NULL OR btrim(p_sport) = ''
        OR lower(btrim(coalesce(ss.sport::text, ''))) = lower(btrim(p_sport))
      )
    GROUP BY bw.user_id
    HAVING COUNT(DISTINCT bw.id) >= GREATEST(1, COALESCE(p_min_matches, 3))
  ),
  rated AS (
    SELECT
      a.uid,
      a.wins,
      a.matches_played,
      (a.wins::numeric / NULLIF(a.matches_played, 0))::numeric AS win_rate
    FROM agg a
    WHERE a.matches_played > 0
  ),
  scoped AS (
    SELECT r.uid, r.wins, r.matches_played, r.win_rate
    FROM rated r
    INNER JOIN public.profiles pr ON pr.user_id = r.uid
    WHERE
      (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
      AND (
        p_age_band IS NULL OR p_age_band = ''
        OR (
          CASE p_age_band
            WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
            WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
            WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
            WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
            WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
            ELSE TRUE
          END
        )
      )
      AND (
        COALESCE(p_scope, 'global') = 'global'
        OR pr.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
        )
      )
  ),
  ordered AS (
    SELECT s.uid, s.wins, s.matches_played, s.win_rate,
      ROW_NUMBER() OVER (ORDER BY s.win_rate DESC, s.wins DESC, s.matches_played DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.wins, o.matches_played, o.win_rate
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$ranking_v2$;

GRANT EXECUTE ON FUNCTION public.get_sport_match_wins_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cardio_elevation_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cardio_duration_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cardio_best_pace_leaderboard_v1(text, text, int, text, text, text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_strength_total_reps_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_strength_total_sets_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_strength_max_set_weight_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sport_duration_leaderboard_v1(text, text, int, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sport_win_rate_leaderboard_v1(text, text, int, text, text, text, int) TO authenticated;

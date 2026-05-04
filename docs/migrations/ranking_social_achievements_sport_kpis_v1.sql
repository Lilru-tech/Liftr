-- =============================================================================
-- Liftr — Social engagement (likes/comments on published workouts), group
-- sessions (≥2 people: owner + participants), achievements unlocked (period + all-time),
-- Hyrox best official time, football goals sum, ski distance sum.
-- Same scope/sex/age pattern as ranking_training_metrics_leaderboard_v2.sql.
-- LANGUAGE sql + dollar body WITHOUT internal ";" (DbVisualizer-safe).
-- Deploy in Supabase SQL Editor after prior ranking migrations.
--
-- Group sessions: count DISTINCT people as workout owner UNION workout_participants
-- (participants rows do not include the owner in the app data model).
-- Period filter on workouts uses COALESCE(started_at, created_at) so rows with null
-- started_at still fall into day/week/month windows when created_at is set.
-- Achievements + sport stats RPCs: SECURITY DEFINER so aggregation is not limited
-- by RLS on user_achievements / *_session_stats (invoker would only see own rows).
-- Group sessions: SECURITY DEFINER so workout_participants / workouts aggregation for
-- global leaderboards is not truncated by RLS when invoked as authenticated.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_workout_likes_received_leaderboard_v1(
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
  likes_received bigint,
  published_workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $r$
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
  agg AS (
    SELECT
      w.user_id AS uid,
      COUNT(*)::bigint AS likes_received,
      COUNT(DISTINCT w.id)::int AS published_workouts_cnt
    FROM public.workout_likes wl
    INNER JOIN public.workouts w ON w.id = wl.workout_id
    CROSS JOIN bounds b
    WHERE w.state = 'published'::public.workout_state
      AND COALESCE(w.started_at, w.created_at) >= b.t_start
      AND COALESCE(w.started_at, w.created_at) < b.t_end
    GROUP BY w.user_id
    HAVING COUNT(*) > 0
  ),
  scoped AS (
    SELECT a.uid, a.likes_received, a.published_workouts_cnt
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
    SELECT s.uid, s.likes_received, s.published_workouts_cnt,
      ROW_NUMBER() OVER (ORDER BY s.likes_received DESC, s.published_workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.likes_received, o.published_workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

CREATE OR REPLACE FUNCTION public.get_workout_comments_received_leaderboard_v1(
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
  comments_received bigint,
  published_workouts_cnt int
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $r$
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
  agg AS (
    SELECT
      w.user_id AS uid,
      COUNT(*)::bigint AS comments_received,
      COUNT(DISTINCT w.id)::int AS published_workouts_cnt
    FROM public.workout_comments wc
    INNER JOIN public.workouts w ON w.id = wc.workout_id
    CROSS JOIN bounds b
    WHERE w.state = 'published'::public.workout_state
      AND COALESCE(w.started_at, w.created_at) >= b.t_start
      AND COALESCE(w.started_at, w.created_at) < b.t_end
      AND wc.deleted_at IS NULL
    GROUP BY w.user_id
    HAVING COUNT(*) > 0
  ),
  scoped AS (
    SELECT a.uid, a.comments_received, a.published_workouts_cnt
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
    SELECT s.uid, s.comments_received, s.published_workouts_cnt,
      ROW_NUMBER() OVER (ORDER BY s.comments_received DESC, s.published_workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.comments_received, o.published_workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

-- get_group_workout_sessions_leaderboard_v1: published_workouts_cnt = all published
-- workouts in period; group_sessions_cnt = those with >=2 people (owner + participants).
CREATE OR REPLACE FUNCTION public.get_group_workout_sessions_leaderboard_v1(
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
  group_sessions_cnt int,
  published_workouts_cnt int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $r$
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
  workout_people AS (
    SELECT w.id AS workout_id, w.user_id AS uid
    FROM public.workouts w
    WHERE w.state = 'published'::public.workout_state
    UNION ALL
    SELECT wp.workout_id, wp.user_id
    FROM public.workout_participants wp
    INNER JOIN public.workouts w2 ON w2.id = wp.workout_id
      AND w2.state = 'published'::public.workout_state
  ),
  multi AS (
    SELECT wp.workout_id
    FROM workout_people wp
    GROUP BY wp.workout_id
    HAVING COUNT(DISTINCT wp.uid) >= 2
  ),
  agg AS (
    SELECT
      w.user_id AS uid,
      COUNT(DISTINCT w.id) FILTER (WHERE m.workout_id IS NOT NULL)::int AS group_sessions_cnt,
      COUNT(DISTINCT w.id)::int AS published_workouts_cnt
    FROM public.workouts w
    CROSS JOIN bounds b
    LEFT JOIN multi m ON m.workout_id = w.id
    WHERE w.state = 'published'::public.workout_state
      AND COALESCE(w.started_at, w.created_at) >= b.t_start
      AND COALESCE(w.started_at, w.created_at) < b.t_end
    GROUP BY w.user_id
    HAVING COUNT(DISTINCT w.id) FILTER (WHERE m.workout_id IS NOT NULL) > 0
  ),
  scoped AS (
    SELECT a.uid, a.group_sessions_cnt, a.published_workouts_cnt
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
    SELECT s.uid, s.group_sessions_cnt, s.published_workouts_cnt,
      ROW_NUMBER() OVER (ORDER BY s.group_sessions_cnt DESC, s.published_workouts_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.group_sessions_cnt, o.published_workouts_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

CREATE OR REPLACE FUNCTION public.get_achievements_unlocked_period_leaderboard_v1(
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
  unlocked_cnt bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $r$
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
  agg AS (
    SELECT ua.user_id AS uid, COUNT(*)::bigint AS unlocked_cnt
    FROM public.user_achievements ua
    CROSS JOIN bounds b
    WHERE ua.unlocked_at >= b.t_start
      AND ua.unlocked_at < b.t_end
    GROUP BY ua.user_id
    HAVING COUNT(*) > 0
  ),
  scoped AS (
    SELECT a.uid, a.unlocked_cnt
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
    SELECT s.uid, s.unlocked_cnt,
      ROW_NUMBER() OVER (ORDER BY s.unlocked_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.unlocked_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

CREATE OR REPLACE FUNCTION public.get_achievements_total_unlocked_leaderboard_v1(
  p_scope text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  total_unlocked bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $r$
WITH agg AS (
    SELECT ua.user_id AS uid, COUNT(*)::bigint AS total_unlocked
    FROM public.user_achievements ua
    GROUP BY ua.user_id
    HAVING COUNT(*) > 0
  ),
  scoped AS (
    SELECT a.uid, a.total_unlocked
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
    SELECT s.uid, s.total_unlocked,
      ROW_NUMBER() OVER (ORDER BY s.total_unlocked DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_unlocked
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

CREATE OR REPLACE FUNCTION public.get_hyrox_best_official_time_leaderboard_v1(
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
  best_official_time_sec int,
  hyrox_sessions_cnt int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $r$
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
  per_sess AS (
    SELECT w.user_id AS uid, ss.id AS sid, hy.official_time_sec AS tsec
    FROM public.workouts w
    INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
    INNER JOIN public.hyrox_session_stats hy ON hy.session_id = ss.id
    CROSS JOIN bounds b
    WHERE w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND lower(coalesce(ss.sport::text, '')) = 'hyrox'
      AND COALESCE(w.started_at, w.created_at) >= b.t_start
      AND COALESCE(w.started_at, w.created_at) < b.t_end
      AND hy.official_time_sec IS NOT NULL
      AND hy.official_time_sec > 0
  ),
  agg AS (
    SELECT uid, MIN(tsec)::int AS best_official_time_sec, COUNT(DISTINCT sid)::int AS hyrox_sessions_cnt
    FROM per_sess
    GROUP BY uid
  ),
  scoped AS (
    SELECT a.uid, a.best_official_time_sec, a.hyrox_sessions_cnt
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
    SELECT s.uid, s.best_official_time_sec, s.hyrox_sessions_cnt,
      ROW_NUMBER() OVER (ORDER BY s.best_official_time_sec ASC, s.hyrox_sessions_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.best_official_time_sec, o.hyrox_sessions_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

CREATE OR REPLACE FUNCTION public.get_football_goals_leaderboard_v1(
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
  total_goals bigint,
  sessions_cnt int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $r$
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
  agg AS (
    SELECT
      w.user_id AS uid,
      SUM(COALESCE(fb.goals, 0))::bigint AS total_goals,
      COUNT(DISTINCT w.id)::int AS sessions_cnt
    FROM public.workouts w
    INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
    INNER JOIN public.football_session_stats fb ON fb.session_id = ss.id
    CROSS JOIN bounds b
    WHERE w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND lower(coalesce(ss.sport::text, '')) = 'football'
      AND COALESCE(w.started_at, w.created_at) >= b.t_start
      AND COALESCE(w.started_at, w.created_at) < b.t_end
    GROUP BY w.user_id
    HAVING SUM(COALESCE(fb.goals, 0)) > 0
  ),
  scoped AS (
    SELECT a.uid, a.total_goals, a.sessions_cnt
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
    SELECT s.uid, s.total_goals, s.sessions_cnt,
      ROW_NUMBER() OVER (ORDER BY s.total_goals DESC, s.sessions_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_goals, o.sessions_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

CREATE OR REPLACE FUNCTION public.get_ski_distance_leaderboard_v1(
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
  total_distance_km numeric,
  sessions_cnt int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $r$
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
  agg AS (
    SELECT
      w.user_id AS uid,
      SUM(COALESCE(sk.total_distance_km, 0::numeric))::numeric AS total_distance_km,
      COUNT(DISTINCT w.id)::int AS sessions_cnt
    FROM public.workouts w
    INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
    INNER JOIN public.ski_session_stats sk ON sk.session_id = ss.id
    CROSS JOIN bounds b
    WHERE w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND lower(coalesce(ss.sport::text, '')) = 'ski'
      AND COALESCE(w.started_at, w.created_at) >= b.t_start
      AND COALESCE(w.started_at, w.created_at) < b.t_end
    GROUP BY w.user_id
    HAVING SUM(COALESCE(sk.total_distance_km, 0::numeric)) > 0
  ),
  scoped AS (
    SELECT a.uid, a.total_distance_km, a.sessions_cnt
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
    SELECT s.uid, s.total_distance_km, s.sessions_cnt,
      ROW_NUMBER() OVER (ORDER BY s.total_distance_km DESC, s.sessions_cnt DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_distance_km, o.sessions_cnt
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk
$r$;

GRANT EXECUTE ON FUNCTION public.get_workout_likes_received_leaderboard_v1(text, text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_workout_comments_received_leaderboard_v1(text, text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_group_workout_sessions_leaderboard_v1(text, text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_achievements_unlocked_period_leaderboard_v1(text, text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_achievements_total_unlocked_leaderboard_v1(text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_hyrox_best_official_time_leaderboard_v1(text, text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_football_goals_leaderboard_v1(text, text, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ski_distance_leaderboard_v1(text, text, int, text, text) TO authenticated;

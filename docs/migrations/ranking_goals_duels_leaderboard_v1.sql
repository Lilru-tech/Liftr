-- =============================================================================
-- Liftr — Leaderboards: goals completados (weekly_goal_results) y duelos
-- ganados (competitions: competition_status = finished, winner_user_id).
-- Cuerpo AS '...' (sin $$). Filtros p_scope / p_sex / p_age_band alineados con
-- public.get_level_leaderboard_v1 (friends = global OR yo O gente a la que sigo).
-- Desplegar en Supabase SQL Editor. Ajusta GRANT si hace falta.
-- Si competitions está vacía, get_duels_won… devuelve 0 filas (esperable).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_goals_completed_leaderboard_v1(
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
  completed_goals bigint,
  goal_weeks bigint
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS '
BEGIN
  RETURN QUERY
  WITH agg AS (
    SELECT
      wgr.user_id AS uid,
      COUNT(*)::bigint AS completed_goals,
      COUNT(DISTINCT wgr.week_start) FILTER (WHERE wgr.is_completed)::bigint AS goal_weeks
    FROM public.weekly_goal_results wgr
    WHERE wgr.is_completed = true
    GROUP BY wgr.user_id
  ),
  scoped AS (
    SELECT a.uid, a.completed_goals, a.goal_weeks
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
      s.completed_goals,
      s.goal_weeks,
      ROW_NUMBER() OVER (ORDER BY s.completed_goals DESC, s.goal_weeks DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT
    o.rnk::int AS rank,
    o.uid AS user_id,
    pr.username,
    pr.avatar_url,
    o.completed_goals,
    o.goal_weeks
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk;
END;
';

CREATE OR REPLACE FUNCTION public.get_duels_won_leaderboard_v1(
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
  wins bigint,
  duels_finished bigint
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS '
BEGIN
  RETURN QUERY
  WITH finished AS (
    SELECT c.id, c.user_a, c.user_b, c.winner_user_id
    FROM public.competitions c
    WHERE c.status = ''finished''::public.competition_status
  ),
  part AS (
    SELECT f.user_a AS uid FROM finished f
    UNION ALL
    SELECT f.user_b FROM finished f
  ),
  duels_count AS (
    SELECT p.uid, COUNT(*)::bigint AS duels_finished
    FROM part p
    GROUP BY p.uid
  ),
  win_count AS (
    SELECT f.winner_user_id AS uid, COUNT(*)::bigint AS wins
    FROM finished f
    WHERE f.winner_user_id IS NOT NULL
    GROUP BY f.winner_user_id
  ),
  merged AS (
    SELECT
      COALESCE(d.uid, w.uid) AS uid,
      COALESCE(w.wins, 0::bigint) AS wins,
      COALESCE(d.duels_finished, 0::bigint) AS duels_finished
    FROM duels_count d
    FULL OUTER JOIN win_count w ON w.uid = d.uid
  ),
  scoped AS (
    SELECT m.uid, m.wins, m.duels_finished
    FROM merged m
    INNER JOIN public.profiles pr ON pr.user_id = m.uid
    WHERE
      m.wins > 0
      AND (p_sex IS NULL OR p_sex = '''' OR pr.sex = p_sex::public.sex)
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
      s.duels_finished,
      ROW_NUMBER() OVER (ORDER BY s.wins DESC, s.duels_finished DESC, s.uid) AS rnk
    FROM scoped s
  )
  SELECT
    o.rnk::int AS rank,
    o.uid AS user_id,
    pr.username,
    pr.avatar_url,
    o.wins,
    o.duels_finished
  FROM ordered o
  INNER JOIN public.profiles pr ON pr.user_id = o.uid
  WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
  ORDER BY o.rnk;
END;
';

-- GRANT EXECUTE ON FUNCTION public.get_goals_completed_leaderboard_v1(text, int, text, text) TO authenticated;
-- GRANT EXECUTE ON FUNCTION public.get_duels_won_leaderboard_v1(text, int, text, text) TO authenticated;

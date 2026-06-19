-- =============================================================================
-- Liftr — Añade achievements: handball, hockey, rugby, ski
-- y función public.unlock_extra_sport_achievements + orquestador.
-- Ejecutar en Supabase SQL Editor. Revisar al final: SELECT COUNT(*) FROM achievements;
-- Cuerpos con $$ (DbVisualizer y varios clientes solo cierran correctamente con $$;
-- ejecutar el bloque CREATE FUNCTION completo en un único lote / "Execute all").
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Catálogo (id vía nextval; code único; sin icon_url; inglés alineado al resto)
-- ---------------------------------------------------------------------------
INSERT INTO public.achievements (code, name, description, category, requirement_type, requirement_value)
VALUES
  -- HANDBALL (13)
  ('handball_played_10', 'Handball 10', 'Play 10 handball matches', 'sport', 'count', 10),
  ('handball_played_50', 'Handball 50', 'Play 50 handball matches', 'sport', 'count', 50),
  ('handball_played_100', 'Handball 100', 'Play 100 handball matches', 'sport', 'count', 100),
  ('handball_win_1', 'First Handball Win', 'Win 1 handball match', 'sport', 'count', 1),
  ('handball_win_5', 'Handball On Board', 'Win 5 handball matches', 'sport', 'count', 5),
  ('handball_win_10', 'Handball 10 Wins', 'Win 10 handball matches', 'sport', 'count', 10),
  ('handball_win_25', 'Handball 25 Wins', 'Win 25 handball matches', 'sport', 'count', 25),
  ('handball_win_50', 'Handball Champion', 'Win 50 handball matches', 'sport', 'count', 50),
  ('handball_win_streak_3', 'Handball Triple', 'Win 3 handball matches in a row', 'sport', 'streak', 3),
  ('handball_win_streak_5', 'Handball Unstoppable', 'Win 5 handball matches in a row', 'sport', 'streak', 5),
  ('handball_goals_1', 'First Handball Goal', 'Score 1 handball goal', 'sport', 'count', 1),
  ('handball_goals_10', 'Handball Scorer 10', 'Score 10 handball goals', 'sport', 'count', 10),
  ('handball_goals_50', 'Handball Scorer 50', 'Score 50 handball goals', 'sport', 'count', 50),
  -- HOCKEY (13)
  ('hockey_played_10', 'Hockey 10', 'Play 10 hockey games', 'sport', 'count', 10),
  ('hockey_played_50', 'Hockey 50', 'Play 50 hockey games', 'sport', 'count', 50),
  ('hockey_played_100', 'Hockey 100', 'Play 100 hockey games', 'sport', 'count', 100),
  ('hockey_win_1', 'First Hockey Win', 'Win 1 hockey game', 'sport', 'count', 1),
  ('hockey_win_5', 'Hockey On Board', 'Win 5 hockey games', 'sport', 'count', 5),
  ('hockey_win_10', 'Hockey 10 Wins', 'Win 10 hockey games', 'sport', 'count', 10),
  ('hockey_win_25', 'Hockey 25 Wins', 'Win 25 hockey games', 'sport', 'count', 25),
  ('hockey_win_50', 'Hockey Champion', 'Win 50 hockey games', 'sport', 'count', 50),
  ('hockey_win_streak_3', 'Hockey Triple', 'Win 3 hockey games in a row', 'sport', 'streak', 3),
  ('hockey_win_streak_5', 'Hockey Unstoppable', 'Win 5 hockey games in a row', 'sport', 'streak', 5),
  ('hockey_goals_1', 'First Hockey Goal', 'Score 1 hockey goal', 'sport', 'count', 1),
  ('hockey_goals_10', 'Hockey Scorer 10', 'Score 10 hockey goals', 'sport', 'count', 10),
  ('hockey_goals_50', 'Hockey Scorer 50', 'Score 50 hockey goals', 'sport', 'count', 50),
  -- RUGBY (13)
  ('rugby_played_10', 'Rugby 10', 'Play 10 rugby matches', 'sport', 'count', 10),
  ('rugby_played_50', 'Rugby 50', 'Play 50 rugby matches', 'sport', 'count', 50),
  ('rugby_played_100', 'Rugby 100', 'Play 100 rugby matches', 'sport', 'count', 100),
  ('rugby_win_1', 'First Rugby Win', 'Win 1 rugby match', 'sport', 'count', 1),
  ('rugby_win_5', 'Rugby On Board', 'Win 5 rugby matches', 'sport', 'count', 5),
  ('rugby_win_10', 'Rugby 10 Wins', 'Win 10 rugby matches', 'sport', 'count', 10),
  ('rugby_win_25', 'Rugby 25 Wins', 'Win 25 rugby matches', 'sport', 'count', 25),
  ('rugby_win_50', 'Rugby Champion', 'Win 50 rugby matches', 'sport', 'count', 50),
  ('rugby_win_streak_3', 'Rugby Triple', 'Win 3 rugby matches in a row', 'sport', 'streak', 3),
  ('rugby_win_streak_5', 'Rugby Unstoppable', 'Win 5 rugby matches in a row', 'sport', 'streak', 5),
  ('rugby_tries_1', 'First Try', 'Score 1 try', 'sport', 'count', 1),
  ('rugby_tries_10', 'Rugby Tries 10', 'Score 10 tries', 'sport', 'count', 10),
  ('rugby_tries_50', 'Rugby Tries 50', 'Score 50 tries', 'sport', 'count', 50),
  -- SKI (18) — sin victorias: sesiones, km, carreras, bajada vertical acumulada
  ('ski_sessions_1', 'First Snow Day', 'Log 1 ski / snowboard session', 'sport', 'count', 1),
  ('ski_sessions_5', 'Ski 5', 'Log 5 ski / snowboard sessions', 'sport', 'count', 5),
  ('ski_sessions_10', 'Ski 10', 'Log 10 ski / snowboard sessions', 'sport', 'count', 10),
  ('ski_sessions_25', 'Ski 25', 'Log 25 ski / snowboard sessions', 'sport', 'count', 25),
  ('ski_sessions_50', 'Ski 50', 'Log 50 ski / snowboard sessions', 'sport', 'count', 50),
  ('ski_total_km_10', 'Ski 10K', 'Accumulate 10 km tracked distance on snow', 'sport', 'count', 10),
  ('ski_total_km_25', 'Ski 25K', 'Accumulate 25 km tracked distance on snow', 'sport', 'count', 25),
  ('ski_total_km_50', 'Ski 50K', 'Accumulate 50 km tracked distance on snow', 'sport', 'count', 50),
  ('ski_total_km_100', 'Ski 100K', 'Accumulate 100 km tracked distance on snow', 'sport', 'count', 100),
  ('ski_total_km_250', 'Ski 250K', 'Accumulate 250 km tracked distance on snow', 'sport', 'count', 250),
  ('ski_total_km_500', 'Ski 500K', 'Accumulate 500 km tracked distance on snow', 'sport', 'count', 500),
  ('ski_runs_10', 'Ten Runs', 'Log 10 lift runs in total', 'sport', 'count', 10),
  ('ski_runs_25', '25 Runs', 'Log 25 lift runs in total', 'sport', 'count', 25),
  ('ski_runs_50', '50 Runs', 'Log 50 lift runs in total', 'sport', 'count', 50),
  ('ski_runs_100', '100 Runs', 'Log 100 lift runs in total', 'sport', 'count', 100),
  ('ski_vertical_m_5000', '5K Vertical', 'Accumulate 5,000 m total vertical drop', 'sport', 'count', 5000),
  ('ski_vertical_m_10000', '10K Vertical', 'Accumulate 10,000 m total vertical drop', 'sport', 'count', 10000),
  ('ski_vertical_m_25000', '25K Vertical', 'Accumulate 25,000 m total vertical drop', 'sport', 'count', 25000)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2) Función de desbloqueo
-- DbVisualizer: ejecuta en UNA sola petición todo desde "CREATE OR REPLACE" de esta
-- función hasta el cierre "END; $$;" (l. ~436). No uses "Run current statement"
-- si eso corta en el primer ";" del DECLARE.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.unlock_extra_sport_achievements(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_streak_handball  int := 0;
  v_streak_hockey     int := 0;
  v_streak_rugby      int := 0;
  v_hb_goals          int := 0;
  v_hk_goals          int := 0;
  v_rg_tries          int := 0;
  v_ski_sessions      int := 0;
  v_ski_km_floor      int := 0;  -- floor(SUM km) para umbrales enteros
  v_ski_runs_sum      int := 0;
  v_ski_vert          int := 0;
BEGIN
  -- Agregados stats (solo si existen filas y deporte coherente)
  IF to_regclass('public.handball_session_stats') IS NOT NULL THEN
    SELECT COALESCE(SUM(h.goals), 0)::int INTO v_hb_goals
    FROM public.handball_session_stats h
    JOIN public.sport_sessions ss ON ss.id = h.session_id
    JOIN public.workouts w ON w.id = ss.workout_id
    WHERE w.user_id = p_user_id
      AND w.state = 'published'
      AND ss.sport = 'handball';
  END IF;

  IF to_regclass('public.hockey_session_stats') IS NOT NULL THEN
    SELECT COALESCE(SUM(hk.goals), 0)::int INTO v_hk_goals
    FROM public.hockey_session_stats hk
    JOIN public.sport_sessions ss ON ss.id = hk.session_id
    JOIN public.workouts w ON w.id = ss.workout_id
    WHERE w.user_id = p_user_id
      AND w.state = 'published'
      AND ss.sport = 'hockey';
  END IF;

  IF to_regclass('public.rugby_session_stats') IS NOT NULL THEN
    SELECT COALESCE(SUM(rg.tries), 0)::int INTO v_rg_tries
    FROM public.rugby_session_stats rg
    JOIN public.sport_sessions ss ON ss.id = rg.session_id
    JOIN public.workouts w ON w.id = ss.workout_id
    WHERE w.user_id = p_user_id
      AND w.state = 'published'
      AND ss.sport = 'rugby';
  END IF;

  -- Ski: una sola agregación (sesiones = filas; km/runs/vertical = sumas)
  IF to_regclass('public.ski_session_stats') IS NOT NULL THEN
    SELECT
      COUNT(*)::int,
      FLOOR(COALESCE(SUM(COALESCE(sk.total_distance_km, 0)), 0))::int,
      COALESCE(SUM(COALESCE(sk.runs_count, 0)), 0)::int,
      COALESCE(SUM(COALESCE(sk.vertical_drop_m, 0)), 0)::int
    INTO v_ski_sessions, v_ski_km_floor, v_ski_runs_sum, v_ski_vert
    FROM public.sport_sessions ss
    JOIN public.workouts w ON w.id = ss.workout_id
    JOIN public.ski_session_stats sk ON sk.session_id = ss.id
    WHERE w.user_id = p_user_id
      AND w.state = 'published'
      AND ss.sport = 'ski';
  END IF;

  -- HANDBALL played / wins (mismo criterio que unlock_sport_achievements)
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball') >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_played_10'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball') >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_played_50'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball') >= 100 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_played_100'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;

  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
          OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_win_1'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
          OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_win_5'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
          OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_win_10'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
          OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 25 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_win_25'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
          OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_win_50'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;

  WITH s AS (
    SELECT w.started_at AS ts,
      (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
        OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against)) AS won
    FROM public.sport_sessions ss
    JOIN public.workouts w ON w.id = ss.workout_id
    WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'handball'
    ORDER BY w.started_at
  ),
  g AS (
    SELECT s.*, SUM(CASE WHEN s.won THEN 0 ELSE 1 END) OVER (ORDER BY s.ts) AS grp FROM s
  )
  SELECT COALESCE(MAX(c.cnt), 0) INTO v_streak_handball
  FROM (SELECT grp, COUNT(*)::int AS cnt FROM g WHERE g.won GROUP BY grp) c;

  IF v_streak_handball >= 3 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_win_streak_3'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_streak_handball >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_win_streak_5'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;

  IF v_hb_goals >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_goals_1' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_hb_goals >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_goals_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_hb_goals >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'handball_goals_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;

  -- HOCKEY (mismo patrón)
  IF (SELECT COUNT(*) FROM public.sport_sessions ss
      JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey') >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_played_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey') >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_played_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey') >= 100 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_played_100' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_win_1' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_win_5' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_win_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 25 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_win_25' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_win_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  WITH s AS (
    SELECT w.started_at AS ts, (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
      OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against)) AS won
    FROM public.sport_sessions ss
    JOIN public.workouts w ON w.id = ss.workout_id
    WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'hockey' ORDER BY w.started_at
  ), g AS (SELECT s.*, SUM(CASE WHEN s.won THEN 0 ELSE 1 END) OVER (ORDER BY s.ts) AS grp FROM s)
  SELECT COALESCE(MAX(c.cnt), 0) INTO v_streak_hockey
  FROM (SELECT grp, COUNT(*)::int AS cnt FROM g WHERE g.won GROUP BY grp) c;
  IF v_streak_hockey >= 3 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_win_streak_3' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_streak_hockey >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_win_streak_5' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_hk_goals >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_goals_1' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_hk_goals >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_goals_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_hk_goals >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'hockey_goals_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;

  -- RUGBY
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby') >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_played_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby') >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_played_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby') >= 100 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_played_100' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_win_1' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_win_5' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_win_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 25 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_win_25' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF (SELECT COUNT(*) FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
      WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby'
        AND (COALESCE(ss.won, false) OR ss.match_result::text = 'win' OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against))) >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_win_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  WITH s AS (
    SELECT w.started_at AS ts, (COALESCE(ss.won, false) OR ss.match_result::text = 'win'
      OR (ss.score_for IS NOT NULL AND ss.score_against IS NOT NULL AND ss.score_for > ss.score_against)) AS won
    FROM public.sport_sessions ss JOIN public.workouts w ON w.id = ss.workout_id
    WHERE w.user_id = p_user_id AND w.state = 'published' AND ss.sport = 'rugby' ORDER BY w.started_at
  ), g AS (SELECT s.*, SUM(CASE WHEN s.won THEN 0 ELSE 1 END) OVER (ORDER BY s.ts) AS grp FROM s)
  SELECT COALESCE(MAX(c.cnt), 0) INTO v_streak_rugby
  FROM (SELECT grp, COUNT(*)::int AS cnt FROM g WHERE g.won GROUP BY grp) c;
  IF v_streak_rugby >= 3 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_win_streak_3' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_streak_rugby >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_win_streak_5' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_rg_tries >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_tries_1' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_rg_tries >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_tries_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_rg_tries >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'rugby_tries_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;

  -- SKI
  IF v_ski_sessions >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_sessions_1' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_sessions >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_sessions_5' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_sessions >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_sessions_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_sessions >= 25 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_sessions_25' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_sessions >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_sessions_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_km_floor >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_total_km_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_km_floor >= 25 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_total_km_25' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_km_floor >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_total_km_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_km_floor >= 100 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_total_km_100' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_km_floor >= 250 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_total_km_250' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_km_floor >= 500 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_total_km_500' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_runs_sum >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_runs_10' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_runs_sum >= 25 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_runs_25' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_runs_sum >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_runs_50' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_runs_sum >= 100 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_runs_100' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_vert >= 5000 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_vertical_m_5000' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_vert >= 10000 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_vertical_m_10000' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_ski_vert >= 25000 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at) SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'ski_vertical_m_25000' ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) Orquestador (mismo criterio: un bloque entero hasta "$$;")
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_and_unlock_achievements_for(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  sig  text;
  call text;
BEGIN
  sig  := 'public.unlock_workout_achievements(uuid)';
  call := 'SELECT public.unlock_workout_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_run_achievements(uuid)';
  call := 'SELECT public.unlock_run_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_bike_achievements(uuid)';
  call := 'SELECT public.unlock_bike_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_ebike_achievements(uuid)';
  call := 'SELECT public.unlock_ebike_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_mtb_achievements(uuid)';
  call := 'SELECT public.unlock_mtb_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_indoor_cycling_achievements(uuid)';
  call := 'SELECT public.unlock_indoor_cycling_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_rowerg_achievements(uuid)';
  call := 'SELECT public.unlock_rowerg_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_swim_pool_achievements(uuid)';
  call := 'SELECT public.unlock_swim_pool_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_swim_ow_achievements(uuid)';
  call := 'SELECT public.unlock_swim_ow_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_walk_achievements(uuid)';
  call := 'SELECT public.unlock_walk_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_hike_achievements(uuid)';
  call := 'SELECT public.unlock_hike_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_treadmill_achievements(uuid)';
  call := 'SELECT public.unlock_treadmill_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_hyrox_achievements(uuid)';
  call := 'SELECT public.unlock_hyrox_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_cardio_generic_achievements(uuid)';
  call := 'SELECT public.unlock_cardio_generic_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_cardio_advanced_achievements(uuid)';
  call := 'SELECT public.unlock_cardio_advanced_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_misc_time_achievements(uuid)';
  call := 'SELECT public.unlock_misc_time_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_strength_achievements(uuid)';
  call := 'SELECT public.unlock_strength_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_social_achievements(uuid)';
  call := 'SELECT public.unlock_social_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_sport_achievements(uuid)';
  call := 'SELECT public.unlock_sport_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  -- NUEVO: handball / hockey / rugby / ski (misma conexión que otras funciones)
  sig  := 'public.unlock_extra_sport_achievements(uuid)';
  call := 'SELECT public.unlock_extra_sport_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_ranking_achievements(uuid)';
  call := 'SELECT public.unlock_ranking_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_streak_achievements(uuid)';
  call := 'SELECT public.unlock_streak_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  sig  := 'public.unlock_meta_achievements(uuid)';
  call := 'SELECT public.unlock_meta_achievements($1)';
  IF to_regprocedure(sig) IS NOT NULL THEN EXECUTE call USING p_user_id; END IF;

  RETURN;
END;
$$;

COMMIT;

-- ---------------------------------------------------------------------------
-- 4) Comprobación manual (tras COMMIT, ejecutar en otra transacción)
-- ---------------------------------------------------------------------------
-- SELECT COUNT(*) FROM public.achievements;  -- esperado: 355 (298 + 57)
-- SELECT public.check_and_unlock_achievements_for('TU-UUID-USER'::uuid);
-- SELECT code, is_unlocked FROM get_user_achievements('TU-UUID-USER'::uuid)
--   WHERE code ~ '^(handball_|hockey_|rugby_|ski_)' ORDER BY code;

-- ---------------------------------------------------------------------------
-- 5) Permisos (si el resto de unlock_* los tienen, replicar; si no, omitir)
-- ---------------------------------------------------------------------------
-- GRANT EXECUTE ON FUNCTION public.unlock_extra_sport_achievements(uuid) TO authenticated;
-- GRANT EXECUTE ON FUNCTION public.unlock_extra_sport_achievements(uuid) TO service_role;

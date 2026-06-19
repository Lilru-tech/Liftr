-- Home feed while signed out: allow role `anon` to read published workouts and the
-- same embedded rows the apps select for feed cards (scores, likes, participants,
-- sport/cardio session summaries).
--
-- Your existing policies already allow `anon` on `profiles` (e.g. profiles_select_all).
-- This migration does NOT change profiles.
--
-- Inspect after apply:
--   SELECT tablename, policyname, roles, cmd FROM pg_policies
--   WHERE policyname LIKE '%anon%' ORDER BY tablename, policyname;

-- Published workouts only (global feed)
DROP POLICY IF EXISTS "workouts_select_anon_published" ON public.workouts;
CREATE POLICY "workouts_select_anon_published"
  ON public.workouts FOR SELECT TO anon
  USING (state = 'published');

DROP POLICY IF EXISTS "sport_sessions_select_anon_published_parent" ON public.sport_sessions;
CREATE POLICY "sport_sessions_select_anon_published_parent"
  ON public.sport_sessions FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = sport_sessions.workout_id AND w.state = 'published'
    )
  );

DROP POLICY IF EXISTS "cardio_sessions_select_anon_published_parent" ON public.cardio_sessions;
CREATE POLICY "cardio_sessions_select_anon_published_parent"
  ON public.cardio_sessions FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = cardio_sessions.workout_id AND w.state = 'published'
    )
  );

DROP POLICY IF EXISTS "workout_scores_select_anon_published_parent" ON public.workout_scores;
CREATE POLICY "workout_scores_select_anon_published_parent"
  ON public.workout_scores FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_scores.workout_id AND w.state = 'published'
    )
  );

DROP POLICY IF EXISTS "workout_likes_select_anon_published_parent" ON public.workout_likes;
CREATE POLICY "workout_likes_select_anon_published_parent"
  ON public.workout_likes FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_likes.workout_id AND w.state = 'published'
    )
  );

DROP POLICY IF EXISTS "workout_participants_select_anon_published_parent" ON public.workout_participants;
CREATE POLICY "workout_participants_select_anon_published_parent"
  ON public.workout_participants FOR SELECT TO anon
  USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_participants.workout_id AND w.state = 'published'
    )
  );

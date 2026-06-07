alter policy basketball_write_own on public.basketball_session_stats
  with check (
    exists (
      select 1
      from public.sport_sessions ss
      join public.workouts w on w.id = ss.workout_id
      where ss.id = basketball_session_stats.session_id
        and w.user_id = (select auth.uid())
    )
  );

alter policy football_write_own on public.football_session_stats
  with check (
    exists (
      select 1
      from public.sport_sessions ss
      join public.workouts w on w.id = ss.workout_id
      where ss.id = football_session_stats.session_id
        and w.user_id = (select auth.uid())
    )
  );

alter policy racket_write_own on public.racket_session_stats
  with check (
    exists (
      select 1
      from public.sport_sessions ss
      join public.workouts w on w.id = ss.workout_id
      where ss.id = racket_session_stats.session_id
        and w.user_id = (select auth.uid())
    )
  );

alter policy ws_write_own on public.workout_scores
  with check (
    exists (
      select 1
      from public.workouts w
      where w.id = workout_scores.workout_id
        and w.user_id = (select auth.uid())
    )
  );

drop policy if exists "workout_comments_insert_authenticated" on public.workout_comments;

drop policy if exists "Service can insert notification settings" on public.user_notification_settings;
create policy "Service can insert notification settings"
  on public.user_notification_settings
  for insert
  to service_role
  with check (true);

drop policy if exists "Insert any notification" on public.notifications;

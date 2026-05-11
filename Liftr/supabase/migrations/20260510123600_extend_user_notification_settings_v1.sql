set local check_function_bodies = off;

alter table public.user_notification_settings
  add column if not exists push_goal_completed boolean not null default true,
  add column if not exists push_goal_almost_done boolean not null default true,
  add column if not exists push_competition_invite boolean not null default true,
  add column if not exists push_competition_accepted boolean not null default true,
  add column if not exists push_competition_declined boolean not null default true,
  add column if not exists push_competition_cancelled boolean not null default true,
  add column if not exists push_competition_expired boolean not null default true,
  add column if not exists push_competition_result_win boolean not null default true,
  add column if not exists push_competition_result_lose boolean not null default true,
  add column if not exists push_competition_workout_pending_review boolean not null default true,
  add column if not exists push_competition_workout_accepted boolean not null default true,
  add column if not exists push_competition_workout_rejected boolean not null default true,
  add column if not exists push_segment_you_are_first boolean not null default true,
  add column if not exists push_segment_lost_first boolean not null default true,
  add column if not exists push_challenge_won boolean not null default true,
  add column if not exists push_challenge_won_weekly boolean not null default true,
  add column if not exists push_workout_kind_inactive boolean not null default true;


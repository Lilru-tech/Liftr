set local check_function_bodies = off;

alter table public.user_notification_settings
  add column if not exists push_meal_plan_invite boolean not null default true;

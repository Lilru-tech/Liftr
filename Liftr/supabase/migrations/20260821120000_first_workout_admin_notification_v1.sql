begin;

create table public.admin_notification_milestones (
  user_id uuid primary key references auth.users (id) on delete cascade,
  first_workout_id bigint references public.workouts (id) on delete set null,
  notified_at timestamptz not null default now()
);

alter table public.admin_notification_milestones enable row level security;

revoke all on table public.admin_notification_milestones from anon, authenticated;

commit;

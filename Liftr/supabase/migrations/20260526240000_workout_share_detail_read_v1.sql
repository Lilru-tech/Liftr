begin;

create or replace function public.is_workout_shared_with_user(
  p_workout_id bigint,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.messages m
    join public.conversation_participants cp
      on cp.conversation_id = m.conversation_id
     and cp.user_id = p_user_id
    where m.kind = 'workout_share'
      and m.deleted_at is null
      and (m.metadata->>'workout_id')::bigint = p_workout_id
      and m.user_id is distinct from p_user_id
  );
$$;

drop policy if exists "we_select_workout_share" on public.workout_exercises;
create policy "we_select_workout_share"
on public.workout_exercises
for select
to authenticated
using (
  public.is_workout_shared_with_user(workout_id)
);

drop policy if exists "es_select_workout_share" on public.exercise_sets;
create policy "es_select_workout_share"
on public.exercise_sets
for select
to authenticated
using (
  exists (
    select 1
    from public.workout_exercises we
    where we.id = exercise_sets.workout_exercise_id
      and public.is_workout_shared_with_user(we.workout_id)
  )
);

drop policy if exists "cs_select_workout_share" on public.cardio_sessions;
create policy "cs_select_workout_share"
on public.cardio_sessions
for select
to authenticated
using (
  public.is_workout_shared_with_user(workout_id)
);

drop policy if exists "ss_select_workout_share" on public.sport_sessions;
create policy "ss_select_workout_share"
on public.sport_sessions
for select
to authenticated
using (
  public.is_workout_shared_with_user(workout_id)
);

create index if not exists messages_workout_share_workout_id_idx
  on public.messages (((metadata->>'workout_id')::bigint))
  where kind = 'workout_share' and deleted_at is null;

commit;

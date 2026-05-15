set local check_function_bodies = off;

alter table public.user_notification_settings
  add column if not exists push_apple_health_cardio_imported boolean not null default true;

create or replace function public.notify_apple_health_cardio_imported(
  p_workout_id bigint,
  p_title text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_owner_id uuid;
  v_title text;
  v_body text;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  select w.user_id, coalesce(nullif(trim(p_title), ''), w.title, 'Workout')
    into v_owner_id, v_title
  from public.workouts w
  where w.id = p_workout_id;

  if v_owner_id is null then
    raise exception 'workout not found';
  end if;

  if v_owner_id <> v_user_id then
    raise exception 'forbidden';
  end if;

  v_body := format('Your %s session from Apple Health is now in Liftr.', v_title);

  insert into public.notifications (user_id, type, title, body, data)
  values (
    v_user_id,
    'apple_health_cardio_imported',
    'Workout imported',
    v_body,
    jsonb_build_object(
      'workout_id', p_workout_id,
      'owner_id', v_user_id
    )
  );
end;
$$;

revoke all on function public.notify_apple_health_cardio_imported(bigint, text) from public;
grant execute on function public.notify_apple_health_cardio_imported(bigint, text) to authenticated;

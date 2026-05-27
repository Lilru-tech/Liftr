begin;

create or replace function public.start_workout_v1(
  p_workout_id bigint,
  p_started_at timestamp with time zone default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.workouts%rowtype;
  v_started_at timestamptz := coalesce(p_started_at, timezone('utc', now()));
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into strict v_row
  from public.workouts
  where id = p_workout_id
  for update;

  if v_row.user_id is distinct from auth.uid()
     and not exists (
       select 1
       from public.workout_participants wp
       where wp.workout_id = p_workout_id
         and wp.user_id = auth.uid()
     ) then
    raise exception 'forbidden';
  end if;

  update public.workouts
  set started_at = v_started_at,
      ended_at = null
  where id = p_workout_id
  returning * into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'user_id', v_row.user_id,
    'kind', v_row.kind::text,
    'started_at', v_row.started_at,
    'ended_at', v_row.ended_at,
    'state', v_row.state::text
  );
end;
$function$;

revoke all on function public.start_workout_v1(bigint, timestamp with time zone) from public;
revoke all on function public.start_workout_v1(bigint, timestamp with time zone) from anon;
grant execute on function public.start_workout_v1(bigint, timestamp with time zone) to authenticated;

commit;

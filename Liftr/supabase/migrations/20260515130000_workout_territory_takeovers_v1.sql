create or replace function public.list_workout_territory_takeovers_v1 (
  p_workout_id bigint
)
  returns table (
    victim_user_id uuid,
    victim_username text,
    victim_avatar_url text,
    cells_taken integer,
    share_taken_pct numeric
  )
  language sql
  stable
  security invoker
  set search_path = public
as $$
  select
    t.victim_user_id,
    coalesce(p.username, 'user') as victim_username,
    p.avatar_url as victim_avatar_url,
    t.cells_taken,
    t.share_taken_pct
  from public.territory_capture_takeovers t
    join public.profiles p on p.user_id = t.victim_user_id
  where t.workout_id = p_workout_id
  order by t.cells_taken desc, coalesce(p.username, 'user');
$$;

grant execute on function public.list_workout_territory_takeovers_v1 (bigint) to authenticated;

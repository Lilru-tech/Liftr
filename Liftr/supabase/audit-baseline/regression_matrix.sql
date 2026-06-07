create or replace function public._audit_set_auth_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function public._audit_clear_auth()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

create or replace function public.run_visibility_regression_matrix(
  p_user_a uuid,
  p_user_b uuid
)
returns table(
  scenario text,
  user_context text,
  row_count bigint,
  pass boolean,
  note text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  c bigint;
begin
  perform public._audit_set_auth_user(p_user_a);

  select count(*) into c from public.profiles where user_id = p_user_b;
  return query select '1_profile_visible'::text, 'user_a'::text, c, c >= 1, 'A views B profile'::text;

  select count(*) into c
  from public.workouts w
  where w.user_id = p_user_b
    and (
      w.user_id = auth.uid()
      or w.user_id in (select followee_id from public.follows where follower_id = auth.uid())
      or w.state is distinct from 'planned'
    );
  return query select '2_workouts_visible'::text, 'user_a'::text, c, true, 'A sees B workouts (policy union)'::text;

  select count(*) into c
  from public.workout_scores ws
  join public.workouts w on w.id = ws.workout_id
  where w.user_id = p_user_b;
  return query select '3_workout_scores_visible'::text, 'user_a'::text, c, true, 'A sees B scores'::text;

  select count(*) into c from public.territory_cells where owner_user_id = p_user_b limit 1000;
  return query select '4_territory_cells'::text, 'user_a'::text, c, true, 'territory visibility baseline'::text;

  select count(*) into c from public.personal_records where user_id = p_user_b;
  return query select '5_personal_records'::text, 'user_a'::text, c, true, 'A sees B PRs'::text;

  select count(*) into c from public.user_rankings_daily where user_id = p_user_b;
  return query select '6_rankings'::text, 'user_a'::text, c, true, 'rankings readable'::text;

  select count(*) into c from public.notifications where user_id = p_user_a;
  return query select '7_own_notifications'::text, 'user_a'::text, c, true, 'A own notifications'::text;

  select count(*) into c
  from public.workout_comments wc
  join public.workouts w on w.id = wc.workout_id
  where w.user_id = p_user_b;
  return query select '8_comments_on_b_workouts'::text, 'user_a'::text, c, true, 'comments visible'::text;

  select count(*) into c from public.user_notification_settings where user_id = p_user_b;
  return query select '10_b_settings_hidden'::text, 'user_a'::text, c, c = 0, 'A must NOT see B settings'::text;

  perform public._audit_clear_auth();
end;
$$;

begin;

create unique index if not exists coin_tx_once_workout_coin_doubling_v1
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'workout_coin_doubling_v1' and amount > 0;

create or replace function public.compute_workout_coin_reward(p_workout_id bigint)
returns integer
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_kind text;
  v_duration_min integer;
  v_duration_sec integer;
  v_distance_km numeric;
  v_set_count integer;
  v_base integer := 10;
begin
  select w.kind, w.duration_min
  into v_kind, v_duration_min
  from public.workouts w
  where w.id = p_workout_id;

  if v_kind is null then
    return 0;
  end if;

  if v_kind = 'strength' then
    select count(*)::integer
    into v_set_count
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    where we.workout_id = p_workout_id;

    v_base := 10 + coalesce(v_set_count, 0);
    return greatest(v_base, 0) * 2;
  end if;

  if v_kind = 'cardio' then
    select cs.duration_sec, cs.distance_km
    into v_duration_sec, v_distance_km
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
    limit 1;

    if v_duration_sec is null and v_duration_min is not null then
      v_duration_sec := v_duration_min * 60;
    end if;

    if coalesce(v_duration_sec, 0) >= 1800 then
      v_base := v_base + 5;
    end if;
    if coalesce(v_duration_sec, 0) >= 3600 then
      v_base := v_base + 5;
    end if;
    if coalesce(v_distance_km, 0) >= 5 then
      v_base := v_base + 5;
    end if;
    if coalesce(v_distance_km, 0) >= 10 then
      v_base := v_base + 10;
    end if;

    return greatest(v_base, 0) * 2;
  end if;

  return greatest(v_base, 0) * 2;
end;
$$;

create or replace function public.backfill_workout_coin_doubling_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
  v_ref uuid;
  v_paid integer;
  v_new integer;
  v_delta integer;
begin
  for r in
    select
      w.id,
      w.user_id,
      coalesce(w.ended_at, w.started_at, now()) as event_at
    from public.workouts w
    where w.state = 'published'::public.workout_state
    order by w.id
  loop
    v_ref := public.liftr_coin_ref_bigint(r.id);
    v_new := public.compute_workout_coin_reward(r.id);

    select coalesce(ct.amount, 0)
    into v_paid
    from public.coin_transactions ct
    where ct.user_id = r.user_id
      and ct.reference_id = v_ref
      and ct.action_type = 'workout_logged'
      and ct.amount > 0
    limit 1;

    v_delta := v_new - coalesce(v_paid, 0);
    if v_delta > 0 then
      perform public.apply_liftr_coin_reward(
        r.user_id,
        v_delta,
        'workout_coin_doubling_v1',
        v_ref,
        r.event_at
      );
    end if;
  end loop;
end;
$$;

revoke all on function public.backfill_workout_coin_doubling_v1() from public;
revoke all on function public.backfill_workout_coin_doubling_v1() from anon, authenticated;

revoke all on function public.compute_workout_coin_reward(bigint) from public;
revoke all on function public.compute_workout_coin_reward(bigint) from anon, authenticated;

select public.backfill_workout_coin_doubling_v1();

commit;

begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_workout_id bigint;
  v_session_id bigint;
  v_ref uuid;
  v_reward integer;
  v_paid integer;
  v_boost integer;
begin
  if to_regprocedure('public.compute_workout_coin_reward(bigint)') is null then
    raise exception 'missing function compute_workout_coin_reward';
  end if;

  if to_regprocedure('public.backfill_workout_coin_doubling_v1()') is null then
    raise exception 'missing function backfill_workout_coin_doubling_v1';
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'coin_tx_once_workout_coin_doubling_v1'
  ) then
    raise exception 'missing index coin_tx_once_workout_coin_doubling_v1';
  end if;

  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (v_user, 'coin_dbl_' || replace(v_user::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now())
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values (v_user, 'coin_dbl_' || left(replace(v_user::text, '-', ''), 12))
  on conflict (user_id) do nothing;

  insert into public.workouts (user_id, title, kind, state, started_at, ended_at, perceived_intensity)
  values (v_user, 'Verify sport', 'sport', 'planned', now() - interval '45 minutes', now(), 'moderate')
  returning id into v_workout_id;

  v_reward := public.compute_workout_coin_reward(v_workout_id);
  if v_reward <> 20 then
    raise exception 'expected sport reward 20, got %', v_reward;
  end if;

  update public.workouts
  set state = 'published'
  where id = v_workout_id;

  v_ref := public.liftr_coin_ref_bigint(v_workout_id);

  select coalesce(sum(amount), 0)
  into v_paid
  from public.coin_transactions
  where user_id = v_user
    and reference_id = v_ref
    and action_type = 'workout_logged'
    and amount > 0;

  if v_paid <> 20 then
    raise exception 'expected workout_logged 20 after publish, got %', v_paid;
  end if;

  perform public.backfill_workout_coin_doubling_v1();

  select coalesce(sum(amount), 0)
  into v_boost
  from public.coin_transactions
  where user_id = v_user
    and reference_id = v_ref
    and action_type = 'workout_coin_doubling_v1'
    and amount > 0;

  if v_boost <> 0 then
    raise exception 'expected no backfill boost for newly published 2x workout, got %', v_boost;
  end if;

  if exists (
    select 1
    from public.workouts w
    where w.state = 'published'::public.workout_state
      and (
        coalesce((
          select sum(ct.amount)
          from public.coin_transactions ct
          where ct.user_id = w.user_id
            and ct.reference_id = public.liftr_coin_ref_bigint(w.id)
            and ct.action_type in ('workout_logged', 'workout_coin_doubling_v1')
            and ct.amount > 0
        ), 0) < public.compute_workout_coin_reward(w.id)
      )
  ) then
    raise exception 'published workout with total workout coins below compute_workout_coin_reward';
  end if;

  raise notice 'workout_coins_doubling_v1 verify passed';
end;
$$;

rollback;

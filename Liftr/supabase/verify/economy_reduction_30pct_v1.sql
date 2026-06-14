begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_workout_id bigint;
  v_ref uuid;
  v_reward integer;
  v_paid integer;
  v_elder_min integer;
  v_elder_max integer;
  v_scale numeric;
begin
  if to_regprocedure('public.backfill_economy_reduction_30pct_v1()') is null then
    raise exception 'missing function backfill_economy_reduction_30pct_v1';
  end if;

  v_scale := public.liftr_workout_coin_scale_factor();
  if v_scale <> 5.95 then
    raise exception 'expected workout scale 5.95, got %', v_scale;
  end if;

  select coins_min_per_hour, coins_max_per_hour
  into v_elder_min, v_elder_max
  from public.pet_stage_rewards
  where lower(stage) = 'elder';

  if v_elder_min <> 11 or v_elder_max <> 20 then
    raise exception 'expected elder passive range 11-20, got %-%,', v_elder_min, v_elder_max;
  end if;

  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (v_user, 'econ_30_' || replace(v_user::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now())
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values (v_user, 'econ_30_' || left(replace(v_user::text, '-', ''), 12))
  on conflict (user_id) do nothing;

  insert into public.workouts (user_id, title, kind, state, started_at, ended_at, perceived_intensity)
  values (v_user, 'Verify sport 30pct', 'sport', 'planned', now() - interval '45 minutes', now(), 'moderate')
  returning id into v_workout_id;

  v_reward := public.compute_workout_coin_reward(v_workout_id);
  if v_reward <> 60 then
    raise exception 'expected sport reward 60, got %', v_reward;
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

  if v_paid <> 60 then
    raise exception 'expected workout_logged 60 after publish, got %', v_paid;
  end if;

  raise notice 'economy_reduction_30pct_v1 verify passed';
end;
$$;

rollback;

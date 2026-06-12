begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_workout_id bigint;
  v_ref uuid;
  v_base integer;
  v_paid integer;
  v_stage_min integer;
  v_stage_max integer;
begin
  if to_regprocedure('public.compute_workout_coin_reward(bigint)') is null then
    raise exception 'missing function compute_workout_coin_reward';
  end if;

  if to_regprocedure('public.compute_workout_coin_reward_with_pet_bonus(bigint, uuid, timestamptz)') is null then
    raise exception 'missing function compute_workout_coin_reward_with_pet_bonus';
  end if;

  if to_regprocedure('public.backfill_economy_rebalance_v1()') is null then
    raise exception 'missing function backfill_economy_rebalance_v1';
  end if;

  if not exists (
    select 1
    from public.pet_training_bonus_config
    where lower(stage) = 'elder'
      and rarity = 'mythic'::public.pet_rarity
      and bonus_pct = 50.00
  ) then
    raise exception 'missing elder mythic training bonus seed';
  end if;

  select coins_min_per_hour, coins_max_per_hour
  into v_stage_min, v_stage_max
  from public.pet_stage_rewards
  where lower(stage) = 'elder';

  if v_stage_min <> 15 or v_stage_max <> 28 then
    raise exception 'expected elder passive range 15-28, got %-%,', v_stage_min, v_stage_max;
  end if;

  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (v_user, 'econ_rb_' || replace(v_user::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now())
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values (v_user, 'econ_rb_' || left(replace(v_user::text, '-', ''), 12))
  on conflict (user_id) do nothing;

  insert into public.workouts (user_id, title, kind, state, started_at, ended_at, perceived_intensity)
  values (v_user, 'Verify sport rebalance', 'sport', 'planned', now() - interval '45 minutes', now(), 'moderate')
  returning id into v_workout_id;

  v_base := public.compute_workout_coin_reward(v_workout_id);
  if v_base <> 85 then
    raise exception 'expected sport base reward 85, got %', v_base;
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

  if v_paid <> 85 then
    raise exception 'expected workout_logged 85 after publish, got %', v_paid;
  end if;

  if public.get_pet_training_bonus_pct_for_pet('baby', 'common') <> 1.00 then
    raise exception 'expected common baby bonus 1%%';
  end if;

  if public.get_pet_training_bonus_pct_for_pet('egg', 'common') <> 0 then
    raise exception 'expected egg bonus 0';
  end if;

  raise notice 'economy_rebalance_v1 verify passed';
end;
$$;

rollback;

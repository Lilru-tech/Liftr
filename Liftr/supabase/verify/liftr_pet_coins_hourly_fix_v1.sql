begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_instance_id uuid := gen_random_uuid();
  v_type text;
  v_coins integer;
  v_last_gen timestamptz;
  v_now_hour timestamptz := date_trunc('hour', now());
  v_tx_count integer;
begin
  select name into v_type from public.pet_types limit 1;
  if v_type is null then
    insert into public.pet_types (name, display_name) values ('verify_coin_type', 'Verify Coin Type');
    v_type := 'verify_coin_type';
  end if;

  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values (
    v_user,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'pet_coins_hourly_fix@example.com',
    jsonb_build_object('username', 'pet_coins_hourly_fix'),
    now(),
    now()
  );

  insert into public.profiles (user_id, username)
  values (v_user, 'pet_coins_hourly_fix')
  on conflict (user_id) do nothing;

  insert into public.pet_instances (
    id,
    user_id,
    pet_type,
    is_active,
    is_equipped,
    evolution_stage,
    rarity,
    current_level,
    last_coins_generated_at
  )
  values (
    v_instance_id,
    v_user,
    v_type,
    true,
    true,
    'baby',
    'common',
    1,
    null
  );

  v_coins := public.generate_pet_coins_v1(v_user);
  if v_coins <= 0 then
    raise exception 'caso 1: first payout expected coins > 0, got %', v_coins;
  end if;

  select last_coins_generated_at into v_last_gen
  from public.pet_instances
  where id = v_instance_id;

  if v_last_gen <> v_now_hour then
    raise exception 'caso 1: expected last_coins_generated_at=%, got %', v_now_hour, v_last_gen;
  end if;

  delete from public.coin_transactions where user_id = v_user;

  update public.pet_instances
  set last_coins_generated_at = v_now_hour - interval '1 hour' + interval '200 milliseconds'
  where id = v_instance_id;

  v_coins := public.generate_pet_coins_v1(v_user);
  if v_coins <= 0 then
    raise exception 'caso 2: sub-second drift must still grant 1 hour, got %', v_coins;
  end if;

  select count(*) into v_tx_count
  from public.coin_transactions
  where user_id = v_user
    and action_type = 'pet_coins_generated';

  if v_tx_count < 1 then
    raise exception 'caso 2: expected at least 1 ledger row, got %', v_tx_count;
  end if;

  update public.pet_instances
  set last_coins_generated_at = v_now_hour - interval '2 hours'
  where id = v_instance_id;

  v_coins := public.generate_pet_coins_v1(v_user);
  if v_coins <= 0 then
    raise exception 'caso 3: 2-hour catch-up expected coins > 0, got %', v_coins;
  end if;

  select count(*) into v_tx_count
  from public.coin_transactions
  where user_id = v_user
    and action_type = 'pet_coins_generated';

  if v_tx_count < 2 then
    raise exception 'caso 3: expected at least 2 ledger rows after catch-up, got %', v_tx_count;
  end if;

  update public.pet_instances
  set last_coins_generated_at = now() - interval '30 minutes'
  where id = v_instance_id;

  v_coins := public.generate_pet_coins_v1(v_user);
  if v_coins <> 0 then
    raise exception 'caso 4: same-hour dedup expected 0 coins, got %', v_coins;
  end if;

  update public.pet_instances
  set evolution_stage = 'egg'
  where id = v_instance_id;

  v_coins := public.generate_pet_coins_v1(v_user);
  if v_coins <> 0 then
    raise exception 'caso 5: egg must return 0, got %', v_coins;
  end if;

  raise notice 'liftr_pet_coins_hourly_fix_v1: todos los casos OK';
end;
$$;

rollback;

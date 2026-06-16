do $$
declare
  v_email text := :'email';
  v_password text := :'password';
  v_user_id uuid;
  v_pet_type text;
  v_instance_id uuid;
  v_balance integer;
begin
  if v_email is null or length(trim(v_email)) = 0 then
    raise exception 'email is required';
  end if;

  if v_password is null or length(v_password) < 8 then
    raise exception 'password must be at least 8 characters';
  end if;

  select id into v_user_id
  from auth.users
  where email = v_email;

  if v_user_id is null then
    v_user_id := gen_random_uuid();
    insert into auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    values (
      v_user_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      v_email,
      crypt(v_password, gen_salt('bf')),
      now(),
      jsonb_build_object('username', 'ui_regression_tester'),
      now(),
      now()
    );
  else
    update auth.users
    set encrypted_password = crypt(v_password, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_user_id;
  end if;

  insert into public.profiles (user_id, username)
  values (v_user_id, 'ui_regression_tester')
  on conflict (user_id) do update
  set username = excluded.username;

  delete from public.coin_transactions
  where user_id = v_user_id
    and action_type = 'ui_regression_seed';

  insert into public.coin_transactions (user_id, amount, action_type, reference_id)
  values (v_user_id, 10000, 'ui_regression_seed', gen_random_uuid());

  select coins_balance into v_balance
  from public.profiles
  where user_id = v_user_id;

  if coalesce(v_balance, 0) < 5000 then
    raise exception 'expected at least 5000 coins after seed, got %', v_balance;
  end if;

  select name into v_pet_type
  from public.pet_types
  order by name
  limit 1;

  if v_pet_type is null then
    raise exception 'no pet types seeded';
  end if;

  if not exists (
    select 1
    from public.pet_instances
    where user_id = v_user_id
      and is_active = true
  ) then
    v_instance_id := gen_random_uuid();
    insert into public.pet_instances (
      id,
      user_id,
      pet_type,
      custom_name,
      evolution_stage,
      current_xp,
      current_level,
      rarity,
      hatch_at,
      is_equipped,
      is_active,
      reroll_count
    )
    values (
      v_instance_id,
      v_user_id,
      v_pet_type,
      'RegressionPet',
      'baby',
      0,
      1,
      'common',
      now() - interval '1 hour',
      true,
      true,
      0
    );

    perform public.generate_initial_pet_stats(v_instance_id);
  end if;

  raise notice 'ui regression user seeded for % with % coins', v_email, v_balance;
end;
$$;

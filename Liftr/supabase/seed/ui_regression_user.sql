create extension if not exists pgcrypto with schema extensions;

insert into public.pet_types (name, display_name, description)
values ('bunny', 'Bunny', 'Fast, adorable, and always hopping around.')
on conflict (name) do nothing;

insert into public.pet_market_items (item_type, display_name, description, price, category, image_path, is_active)
values ('food_baby', 'Baby Snack', 'Best food for baby-stage pets.', 250, 'pet_food', 'market/food_baby.png', true)
on conflict (item_type) do update
set display_name = excluded.display_name,
    description = excluded.description,
    price = excluded.price,
    category = excluded.category,
    image_path = excluded.image_path,
    is_active = excluded.is_active;

insert into public.pet_food_experience (item_type, pet_stage, min_exp, max_exp)
values ('food_baby', 'baby', 200, 300)
on conflict (item_type, pet_stage) do update
set min_exp = excluded.min_exp,
    max_exp = excluded.max_exp;

do $$
declare
  v_email text := '__EMAIL__';
  v_password text := '__PASSWORD__';
  v_user_id uuid;
  v_identity_id uuid;
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

  select id into v_instance_id
  from auth.instances
  limit 1;

  if v_instance_id is null then
    v_instance_id := '00000000-0000-0000-0000-000000000000'::uuid;
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
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    values (
      v_user_id,
      v_instance_id,
      'authenticated',
      'authenticated',
      v_email,
      extensions.crypt(v_password, extensions.gen_salt('bf')),
      now(),
      '',
      '',
      '',
      '',
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('username', 'ui_regression_tester'),
      now(),
      now()
    );
  else
    update auth.users
    set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        instance_id = coalesce(instance_id, v_instance_id),
        confirmation_token = coalesce(confirmation_token, ''),
        recovery_token = coalesce(recovery_token, ''),
        email_change_token_new = coalesce(email_change_token_new, ''),
        email_change = coalesce(email_change, ''),
        raw_app_meta_data = coalesce(
          raw_app_meta_data,
          jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'))
        ),
        updated_at = now()
    where id = v_user_id;
  end if;

  delete from auth.identities
  where user_id = v_user_id
    and provider = 'email';

  v_identity_id := gen_random_uuid();

  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    v_identity_id,
    v_user_id,
    v_user_id::text,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email',
    now(),
    now(),
    now()
  );

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
    raise notice 'no pet types seeded; skipping pet instance creation';
  else
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
  end if;

  raise notice 'ui regression user seeded for % with % coins', v_email, v_balance;
end;
$$;

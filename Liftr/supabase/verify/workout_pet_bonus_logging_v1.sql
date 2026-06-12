begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_workout_id bigint;
  v_ref uuid;
  v_base integer;
  v_bonus integer;
  v_log_message text;
begin
  if to_regprocedure('public.grant_workout_coin_rewards_v1(bigint, uuid, timestamptz)') is null then
    raise exception 'missing function grant_workout_coin_rewards_v1';
  end if;

  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
  values (
    v_user,
    'pet_bonus_' || replace(v_user::text, '-', '') || '@liftr.test',
    crypt('verify', gen_salt('bf')),
    now(),
    now(),
    now(),
    jsonb_build_object('username', 'pet_bonus_' || left(replace(v_user::text, '-', ''), 12))
  )
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values (v_user, 'pet_bonus_' || left(replace(v_user::text, '-', ''), 12))
  on conflict (user_id) do update set username = excluded.username;

  insert into public.pet_instances (
    user_id,
    pet_type,
    evolution_stage,
    rarity,
    is_active,
    is_equipped
  )
  values (
    v_user,
    'dragon',
    'elder',
    'mythic'::public.pet_rarity,
    true,
    true
  );

  insert into public.workouts (user_id, title, kind, state, started_at, ended_at, perceived_intensity)
  values (v_user, 'Verify pet bonus log', 'sport', 'planned', now() - interval '45 minutes', now(), 'moderate')
  returning id into v_workout_id;

  update public.workouts
  set state = 'published'
  where id = v_workout_id;

  v_ref := public.liftr_coin_ref_bigint(v_workout_id);

  select coalesce(sum(case when action_type = 'workout_logged' then amount else 0 end), 0)
  into v_base
  from public.coin_transactions
  where user_id = v_user
    and reference_id = v_ref;

  select coalesce(sum(case when action_type = 'workout_pet_training_bonus' then amount else 0 end), 0)
  into v_bonus
  from public.coin_transactions
  where user_id = v_user
    and reference_id = v_ref;

  if v_base <> 60 then
    raise exception 'expected workout_logged base 60, got %', v_base;
  end if;

  if v_bonus <> 30 then
    raise exception 'expected workout_pet_training_bonus 30, got %', v_bonus;
  end if;

  select pl.details->>'message'
  into v_log_message
  from public.pet_logs pl
  where pl.user_id = v_user
    and pl.event_type = 'workout_pet_bonus'
  order by pl.created_at desc
  limit 1;

  if coalesce(v_log_message, '') = '' then
    raise exception 'expected non-empty workout_pet_bonus pet log message';
  end if;

  raise notice 'workout_pet_bonus_logging_v1 verify passed';
end;
$$;

rollback;

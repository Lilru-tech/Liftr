begin;

do $$
declare
  v_creator uuid := gen_random_uuid();
  v_opponent uuid := gen_random_uuid();
  v_competition_id bigint;
  v_balance integer;
  v_summary jsonb;
  v_ok boolean;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values
    (v_creator, 'comp_bet_creator_' || replace(v_creator::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now()),
    (v_opponent, 'comp_bet_opp_' || replace(v_opponent::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now())
  on conflict do nothing;

  insert into public.profiles (user_id, username, coins_balance)
  values
    (v_creator, 'comp_creator_' || left(replace(v_creator::text, '-', ''), 10), 100),
    (v_opponent, 'comp_opp_' || left(replace(v_opponent::text, '-', ''), 10), 80)
  on conflict (user_id) do update
  set coins_balance = excluded.coins_balance;

  perform set_config('request.jwt.claim.sub', v_creator::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  begin
    perform public.rpc_create_competition(
      v_opponent,
      now() + interval '30 days',
      'workouts'::goal_metric,
      5,
      48,
      90
    );
    raise exception 'expected bet_exceeds_max_allowed for bet above min balance';
  exception
    when others then
      if sqlerrm not like '%bet_exceeds_max_allowed%' then
        raise;
      end if;
  end;

  v_competition_id := public.rpc_create_competition(
    v_opponent,
    now() + interval '30 days',
    'workouts'::goal_metric,
    5,
    48,
    50
  );

  select coins_balance into v_balance from public.profiles where user_id = v_creator;
  if v_balance <> 50 then
    raise exception 'expected creator balance 50 after escrow, got %', v_balance;
  end if;

  perform set_config('request.jwt.claim.sub', v_opponent::text, true);

  perform public.accept_competition(v_competition_id);

  select coins_balance into v_balance from public.profiles where user_id = v_opponent;
  if v_balance <> 30 then
    raise exception 'expected opponent balance 30 after escrow, got %', v_balance;
  end if;

  update public.competitions
  set status = 'finished',
      finished_at = now(),
      winner_user_id = v_creator
  where id = v_competition_id;

  select coins_balance into v_balance from public.profiles where user_id = v_creator;
  if v_balance <> 150 then
    raise exception 'expected creator balance 150 after win, got %', v_balance;
  end if;

  select coins_balance into v_balance from public.profiles where user_id = v_opponent;
  if v_balance <> 30 then
    raise exception 'expected opponent balance 30 after loss, got %', v_balance;
  end if;

  v_competition_id := public.rpc_create_competition(
    v_opponent,
    now() + interval '30 days',
    'workouts'::goal_metric,
    5,
    48,
    20
  );

  perform set_config('request.jwt.claim.sub', v_opponent::text, true);
  perform public.decline_competition(v_competition_id);

  select coins_balance into v_balance from public.profiles where user_id = v_creator;
  if v_balance <> 150 then
    raise exception 'expected creator balance unchanged after declined refund, got %', v_balance;
  end if;

  v_competition_id := public.rpc_create_competition(
    v_opponent,
    now() + interval '30 days',
    'workouts'::goal_metric,
    5,
    48,
    10
  );

  perform set_config('request.jwt.claim.sub', v_creator::text, true);
  perform public.cancel_competition_invite(v_competition_id);

  select coins_balance into v_balance from public.profiles where user_id = v_creator;
  if v_balance <> 150 then
    raise exception 'expected creator balance 150 after cancel refund, got %', v_balance;
  end if;

  v_competition_id := public.rpc_create_competition(
    v_opponent,
    now() + interval '30 days',
    'workouts'::goal_metric,
    5,
    48,
    15
  );

  perform set_config('request.jwt.claim.sub', v_opponent::text, true);
  perform public.accept_competition(v_competition_id);

  update public.competitions
  set status = 'finished',
      finished_at = now(),
      winner_user_id = null
  where id = v_competition_id;

  select coins_balance into v_balance from public.profiles where user_id = v_creator;
  if v_balance <> 165 then
    raise exception 'expected creator balance 165 after draw refund, got %', v_balance;
  end if;

  select coins_balance into v_balance from public.profiles where user_id = v_opponent;
  if v_balance <> 30 then
    raise exception 'expected opponent balance 30 after draw refund, got %', v_balance;
  end if;

  perform set_config('request.jwt.claim.sub', v_creator::text, true);
  v_summary := public.get_my_competition_escrow_summary_v1();
  if coalesce((v_summary->>'escrowed_total')::integer, -1) <> 0 then
    raise exception 'expected zero escrow summary after settled challenges, got %', v_summary;
  end if;

  raise notice 'competition_bet_escrow_v1 verify passed';
end;
$$;

rollback;

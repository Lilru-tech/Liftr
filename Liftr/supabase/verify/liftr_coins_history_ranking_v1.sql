begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_ref uuid := public.liftr_coin_ref_bigint(999999002);
  v_count integer;
  v_deleted integer;
  v_balance integer;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (v_user, 'coin_hist_' || replace(v_user::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now())
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values (v_user, 'coin_hist_' || left(replace(v_user::text, '-', ''), 12))
  on conflict (user_id) do nothing;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public.apply_liftr_coin_reward(v_user, 5, 'comment_added', v_ref);

  select count(*) into v_count
  from public.list_my_coin_transactions_v1(20);
  if v_count < 1 then
    raise exception 'expected at least one transaction from list_my_coin_transactions_v1';
  end if;

  select coins_balance into v_balance from public.profiles where user_id = v_user;

  v_deleted := public.clear_my_coin_history_v1();
  if v_deleted < 1 then
    raise exception 'expected clear_my_coin_history_v1 to delete rows';
  end if;

  select coins_balance into v_count from public.profiles where user_id = v_user;
  if v_count <> v_balance then
    raise exception 'expected coins_balance unchanged after clear, was % now %', v_balance, v_count;
  end if;

  select count(*) into v_count
  from public.get_coins_leaderboard_v1('global', 10, null, null)
  where user_id = v_user;
  if v_count < 1 then
    raise exception 'expected user on coins leaderboard when balance > 0';
  end if;

  raise notice 'liftr_coins_history_ranking_v1 verify passed';
end;
$$;

rollback;

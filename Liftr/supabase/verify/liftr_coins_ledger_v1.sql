begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_ref uuid := public.liftr_coin_ref_bigint(999999001);
  v_balance integer;
  v_inserted boolean;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (v_user, 'coin_verify_' || replace(v_user::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now())
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values (v_user, 'coin_verify_' || left(replace(v_user::text, '-', ''), 12))
  on conflict (user_id) do nothing;

  v_inserted := public.apply_liftr_coin_reward(v_user, 2, 'like_given', v_ref);
  if not v_inserted then
    raise exception 'expected first like_given insert to succeed';
  end if;

  v_inserted := public.apply_liftr_coin_reward(v_user, 2, 'like_given', v_ref);
  if v_inserted then
    raise exception 'expected duplicate like_given insert to be ignored';
  end if;

  select coins_balance into v_balance from public.profiles where user_id = v_user;
  if v_balance <> 2 then
    raise exception 'expected coins_balance=2 after one like, got %', v_balance;
  end if;

  begin
    update public.profiles set coins_balance = 999 where user_id = v_user;
    raise exception 'expected client-style coins_balance update to fail';
  exception
    when others then
      if sqlerrm not like '%coins_balance_is_server_managed%' then
        raise;
      end if;
  end;

  raise notice 'liftr_coins_ledger_v1 verify passed';
end;
$$;

rollback;

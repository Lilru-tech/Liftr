begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_ref uuid;
  v_i integer;
  v_count integer;
  v_page1 integer;
  v_page2 integer;
begin
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (v_user, 'coin_page_' || replace(v_user::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now())
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values (v_user, 'coin_page_' || left(replace(v_user::text, '-', ''), 12))
  on conflict (user_id) do nothing;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  for v_i in 1..25 loop
    v_ref := public.liftr_coin_ref_bigint(880000000 + v_i);
    perform public.apply_liftr_coin_reward(v_user, 1, 'comment_added', v_ref);
  end loop;

  select count(*) into v_page1
  from public.list_my_coin_transactions_v1(20, 0);
  if v_page1 <> 20 then
    raise exception 'expected 20 rows on first page, got %', v_page1;
  end if;

  select count(*) into v_page2
  from public.list_my_coin_transactions_v1(20, 20);
  if v_page2 <> 5 then
    raise exception 'expected 5 rows on second page, got %', v_page2;
  end if;

  select count(*) into v_count
  from public.list_my_coin_transactions_v1(20);
  if v_count <> 20 then
    raise exception 'expected single-arg overload to return 20 rows, got %', v_count;
  end if;

  raise notice 'coin_transactions_pagination_v1 verify passed';
end;
$$;

rollback;

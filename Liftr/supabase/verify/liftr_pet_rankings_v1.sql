begin;

do $$
declare
  v_user_a uuid := gen_random_uuid();
  v_user_b uuid := gen_random_uuid();
  v_pet_a uuid := gen_random_uuid();
  v_pet_b uuid := gen_random_uuid();
  v_type text;
  v_count integer;
  v_rank integer;
  v_value numeric;
  v_pet_name text;
begin
  select name into v_type from public.pet_types limit 1;
  if v_type is null then
    insert into public.pet_types (name, display_name) values ('verify_type', 'Verify Type');
    v_type := 'verify_type';
  end if;

  insert into auth.users (id, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_user_meta_data)
  values
    (v_user_a, 'pet_rank_a_' || replace(v_user_a::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now(), jsonb_build_object('username', 'pet_rank_a_' || left(replace(v_user_a::text, '-', ''), 10))),
    (v_user_b, 'pet_rank_b_' || replace(v_user_b::text, '-', '') || '@liftr.test', crypt('verify', gen_salt('bf')), now(), now(), now(), jsonb_build_object('username', 'pet_rank_b_' || left(replace(v_user_b::text, '-', ''), 10)))
  on conflict do nothing;

  insert into public.profiles (user_id, username)
  values
    (v_user_a, 'pet_rank_a_' || left(replace(v_user_a::text, '-', ''), 10)),
    (v_user_b, 'pet_rank_b_' || left(replace(v_user_b::text, '-', ''), 10))
  on conflict (user_id) do nothing;

  insert into public.pet_instances (id, user_id, pet_type, custom_name, evolution_stage, current_level, current_xp, is_active, is_equipped)
  values
    (v_pet_a, v_user_a, v_type, 'VerifyDragonA', 'teen', 12, 340, true, true),
    (v_pet_b, v_user_b, v_type, null, 'baby', 4, 50, true, true);

  insert into public.pet_instance_stats (pet_instance_id, health, strength, defense)
  values
    (v_pet_a, 2400, 60, 45),
    (v_pet_b, 1200, 20, 15);

  insert into public.pet_combat_user_stats (user_id, max_damage_dealt, max_damage_taken, total_damage_dealt, total_damage_taken, total_battles, wins, losses, draws)
  values
    (v_user_a, 180, 120, 5400, 3200, 8, 6, 2, 0),
    (v_user_b, 90, 200, 1100, 2600, 3, 1, 2, 0);

  perform set_config('request.jwt.claim.sub', v_user_a::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select l.rank, l.value, l.pet_name into v_rank, v_value, v_pet_name
  from public.get_pet_leaderboard_v1('level', 'global', 1000, null, null) l
  where l.user_id = v_user_a;
  if v_rank is null or v_value <> 12 or v_pet_name <> 'VerifyDragonA' then
    raise exception 'level leaderboard mismatch for user A: rank %, value %, pet_name %', v_rank, v_value, v_pet_name;
  end if;

  select count(*) into v_count
  from public.get_pet_leaderboard_v1('total_stats', 'global', 1000, null, null) l
  where l.user_id in (v_user_a, v_user_b);
  if v_count <> 2 then
    raise exception 'expected both users on total_stats leaderboard, got %', v_count;
  end if;

  select l.value into v_value
  from public.get_pet_leaderboard_v1('win_rate', 'global', 1000, null, null) l
  where l.user_id = v_user_a;
  if v_value is distinct from 75.0 then
    raise exception 'expected 75.0 win_rate for user A, got %', v_value;
  end if;

  select count(*) into v_count
  from public.get_pet_leaderboard_v1('win_rate', 'global', 1000, null, null) l
  where l.user_id = v_user_b;
  if v_count <> 0 then
    raise exception 'expected user B excluded from win_rate (battles < 5)';
  end if;

  select l.value into v_value
  from public.get_pet_leaderboard_v1('max_damage_dealt', 'global', 1000, null, null) l
  where l.user_id = v_user_b;
  if v_value is distinct from 90 then
    raise exception 'expected max_damage_dealt 90 for user B, got %', v_value;
  end if;

  select count(*) into v_count
  from public.get_pet_leaderboard_v1('losses', 'friends', 1000, null, null) l
  where l.user_id = v_user_b;
  if v_count <> 0 then
    raise exception 'expected user B excluded from friends scope (no follow)';
  end if;

  insert into public.follows (follower_id, followee_id) values (v_user_a, v_user_b);

  select count(*) into v_count
  from public.get_pet_leaderboard_v1('losses', 'friends', 1000, null, null) l
  where l.user_id = v_user_b;
  if v_count <> 1 then
    raise exception 'expected user B on friends losses leaderboard after follow';
  end if;

  begin
    perform * from public.get_pet_leaderboard_v1('bogus', 'global', 10, null, null);
    raise exception 'expected invalid_metric exception';
  exception
    when others then
      if sqlerrm <> 'invalid_metric' then
        raise;
      end if;
  end;

  raise notice 'liftr_pet_rankings_v1 verify passed';
end;
$$;

rollback;

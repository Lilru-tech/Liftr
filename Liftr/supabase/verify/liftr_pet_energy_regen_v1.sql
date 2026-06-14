-- Verificación de liftr_pet_energy_regen_v1 (regeneración 1 energía / 4h).
-- Ejecutar completo: corre dentro de una transacción y hace ROLLBACK al final.

begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_current integer;
  v_max integer;
  v_last timestamptz;
  v_json jsonb;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values (v_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'energy_regen_test@example.com', jsonb_build_object('username', 'energy_regen_test'),
          now(), now());

  perform public.allow_profiles_energy_update();
  update public.profiles
  set current_energy = 1, max_energy = 5, last_energy_refresh = now() - interval '9 hours'
  where user_id = v_user;

  -- Caso 1: 9h transcurridas => +2 puntos, last_refresh avanza 8h
  perform public.liftr_refresh_profile_energy(v_user);

  select current_energy, max_energy, last_energy_refresh
  into v_current, v_max, v_last
  from public.profiles where user_id = v_user;

  if v_current <> 3 then
    raise exception 'caso 1: esperado current=3, obtenido %', v_current;
  end if;
  if abs(extract(epoch from (v_last - (now() - interval '1 hour')))) > 5 then
    raise exception 'caso 1: esperado last_refresh ~ now()-1h, obtenido %', v_last;
  end if;

  -- Caso 2: json con next_refresh_at = last_refresh + 4h y regen_minutes = 240
  v_json := public.liftr_profile_energy_json(v_user);
  if (v_json->>'next_refresh_at')::timestamptz <> v_last + interval '4 hours' then
    raise exception 'caso 2: next_refresh_at incorrecto: %', v_json;
  end if;
  if (v_json->>'regen_minutes')::integer <> 240 then
    raise exception 'caso 2: regen_minutes incorrecto: %', v_json;
  end if;

  -- Caso 3: acumulación que excede max => cap en max y last_refresh = now()
  perform public.allow_profiles_energy_update();
  update public.profiles
  set current_energy = 4, last_energy_refresh = now() - interval '30 hours'
  where user_id = v_user;

  perform public.liftr_refresh_profile_energy(v_user);

  select current_energy, last_energy_refresh
  into v_current, v_last
  from public.profiles where user_id = v_user;

  if v_current <> 5 then
    raise exception 'caso 3: esperado current=5 (cap), obtenido %', v_current;
  end if;
  if abs(extract(epoch from (v_last - now()))) > 5 then
    raise exception 'caso 3: esperado last_refresh ~ now(), obtenido %', v_last;
  end if;

  -- Caso 4: lleno => next_refresh_at null
  v_json := public.liftr_profile_energy_json(v_user);
  if v_json->>'next_refresh_at' is not null then
    raise exception 'caso 4: esperado next_refresh_at null, obtenido %', v_json;
  end if;

  -- Caso 5: sin tiempo transcurrido => sin cambios
  perform public.allow_profiles_energy_update();
  update public.profiles
  set current_energy = 2, last_energy_refresh = now() - interval '1 hour'
  where user_id = v_user;

  perform public.liftr_refresh_profile_energy(v_user);

  select current_energy, last_energy_refresh
  into v_current, v_last
  from public.profiles where user_id = v_user;

  if v_current <> 2 then
    raise exception 'caso 5: esperado current=2 sin cambios, obtenido %', v_current;
  end if;

  raise notice 'liftr_pet_energy_regen_v1: todos los casos OK';
end;
$$;

rollback;

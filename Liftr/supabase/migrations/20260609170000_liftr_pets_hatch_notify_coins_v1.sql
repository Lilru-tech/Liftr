begin;

alter table public.user_notification_settings
  add column if not exists push_pet_hatched boolean not null default true;

create or replace function public.liftr_finalize_pet_hatch(p_instance_id uuid)
returns boolean
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid;
  v_pet_type text;
  v_rarity text;
begin
  update public.pet_instances
  set evolution_stage = 'baby',
      updated_at = now()
  where id = p_instance_id
    and evolution_stage = 'egg'
  returning user_id, pet_type, rarity::text
  into v_user_id, v_pet_type, v_rarity;

  if not found then
    return false;
  end if;

  perform public.generate_initial_pet_stats(p_instance_id);

  insert into public.pet_logs (user_id, pet_instance_id, event_type, details)
  values (v_user_id, p_instance_id, 'hatched', jsonb_build_object('stage', 'baby'));

  insert into public.notifications (user_id, type, title, body, data)
  select
    v_user_id,
    'pet_hatched',
    'Your pet has hatched!',
    format('You''ve just hatched a new %s! Take care of it.', v_pet_type),
    jsonb_build_object(
      'pet_instance_id', p_instance_id::text,
      'pet_type', v_pet_type,
      'rarity', v_rarity
    )
  where not exists (
    select 1
    from public.notifications n
    where n.user_id = v_user_id
      and n.type = 'pet_hatched'
      and n.data->>'pet_instance_id' = p_instance_id::text
  );

  return true;
end;
$$;

create or replace function public.liftr_hatch_pet_egg_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
begin
  if p_user_id is null then
    return;
  end if;

  for r in
    select id
    from public.pet_instances
    where user_id = p_user_id
      and evolution_stage = 'egg'
      and hatch_at is not null
      and hatch_at <= now()
      and is_active = true
  loop
    perform public.liftr_finalize_pet_hatch(r.id);
  end loop;
end;
$$;

create or replace function public.check_and_hatch_pet_eggs_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
begin
  for r in
    select id
    from public.pet_instances
    where evolution_stage = 'egg'
      and hatch_at is not null
      and hatch_at <= now()
      and is_active = true
  loop
    perform public.liftr_finalize_pet_hatch(r.id);
  end loop;
end;
$$;

create or replace function public.generate_pet_coins_v1(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to public
as $$
declare
  v_instance_id uuid;
  v_stage text;
  v_rarity text;
  coins_min integer;
  coins_max integer;
  hours_elapsed integer;
  i integer;
  coins_this_hour integer;
  total_coins integer := 0;
  last_gen timestamptz;
  v_coin_mult numeric;
  v_ref_id uuid;
  v_hour_bucket text;
begin
  if p_user_id is null then
    return 0;
  end if;

  select pi.id, pi.evolution_stage, pi.last_coins_generated_at, pi.rarity::text
  into v_instance_id, v_stage, last_gen, v_rarity
  from public.pet_instances pi
  where pi.user_id = p_user_id
    and pi.is_active = true
  limit 1;

  if v_instance_id is null or v_stage is null or lower(v_stage) = 'egg' then
    return 0;
  end if;

  select pr.coins_min_per_hour, pr.coins_max_per_hour
  into coins_min, coins_max
  from public.pet_stage_rewards pr
  where lower(pr.stage) = lower(v_stage);

  if coins_min is null or coins_max is null then
    return 0;
  end if;

  v_coin_mult := public.get_pet_coin_multiplier(p_user_id);

  if last_gen is null then
    hours_elapsed := 1;
  else
    hours_elapsed := floor(extract(epoch from now() - last_gen) / 3600)::integer;
  end if;

  hours_elapsed := least(hours_elapsed, 24);

  if hours_elapsed <= 0 then
    return 0;
  end if;

  v_hour_bucket := to_char(date_trunc('hour', now()), 'YYYYMMDDHH24');
  v_ref_id := public.liftr_coin_ref_date('pet_coins:' || v_instance_id::text || ':' || v_hour_bucket);

  for i in 1..hours_elapsed loop
    coins_this_hour := floor(random() * (coins_max - coins_min + 1))::integer + coins_min;
    coins_this_hour := greatest(0, round(coins_this_hour * v_coin_mult)::integer);
    total_coins := total_coins + coins_this_hour;

    insert into public.pet_logs (user_id, pet_instance_id, event_type, details, created_at)
    values (
      p_user_id,
      v_instance_id,
      'coins_generated',
      jsonb_build_object(
        'coins', coins_this_hour::text,
        'hours_elapsed', '1',
        'pet_stage', v_stage,
        'rarity', v_rarity
      ),
      coalesce(last_gen, now()) + (i || ' hour')::interval
    );
  end loop;

  update public.pet_instances
  set last_coins_generated_at = now(),
      updated_at = now()
  where id = v_instance_id;

  if total_coins > 0 then
    perform public.apply_liftr_coin_transaction(
      p_user_id,
      total_coins,
      'pet_coins_generated',
      v_ref_id
    );
  end if;

  return coalesce(total_coins, 0);
end;
$$;

create or replace function public.generate_all_pet_coins_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
begin
  for r in
    select distinct user_id
    from public.pet_instances
    where is_active = true
      and evolution_stage is distinct from 'egg'
  loop
    perform public.generate_pet_coins_v1(r.user_id);
  end loop;
end;
$$;

create unique index if not exists coin_tx_once_pet_coins_generated
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'pet_coins_generated' and amount > 0;

create or replace function public.get_my_pet_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_user_id uuid := auth.uid();
  v_pet jsonb;
  v_stats jsonb;
  v_inventory jsonb;
  v_required_exp integer;
  v_can_evolve boolean := false;
  v_stage text;
  v_level integer;
  v_pet_type text;
  v_image_url text;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  perform public.liftr_hatch_pet_egg_for_user(v_user_id);

  select to_jsonb(pi.*) into v_pet
  from public.pet_instances pi
  where pi.user_id = v_user_id
    and pi.is_active = true
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(ui.*)), '[]'::jsonb) into v_inventory
  from public.user_inventory ui
  where ui.user_id = v_user_id
    and ui.quantity > 0;

  if v_pet is null then
    return jsonb_build_object(
      'pet', null,
      'stats', null,
      'inventory', v_inventory,
      'xp_required', 0,
      'can_evolve', false
    );
  end if;

  v_stage := v_pet->>'evolution_stage';
  v_pet_type := v_pet->>'pet_type';
  v_image_url := public.liftr_pet_image_url_for_stage(v_pet_type, v_stage);

  if v_image_url is not null then
    v_pet := jsonb_set(v_pet, '{image_url}', to_jsonb(v_image_url), true);
  end if;

  select to_jsonb(ps.*) into v_stats
  from public.pet_instance_stats ps
  where ps.pet_instance_id = (v_pet->>'id')::uuid;

  select required_exp into v_required_exp
  from public.pet_levels
  where level = (v_pet->>'current_level')::integer;

  v_level := (v_pet->>'current_level')::integer;

  v_can_evolve := case lower(v_stage)
    when 'baby' then v_level >= 25
    when 'kid' then v_level >= 50
    when 'teen' then v_level >= 75
    when 'adult' then v_level >= 100
    else false
  end;

  return jsonb_build_object(
    'pet', v_pet,
    'stats', v_stats,
    'inventory', v_inventory,
    'xp_required', coalesce(v_required_exp, 0),
    'can_evolve', v_can_evolve
  );
end;
$$;

revoke all on function public.liftr_finalize_pet_hatch(uuid) from public;
revoke all on function public.generate_pet_coins_v1(uuid) from public;
revoke all on function public.generate_all_pet_coins_v1() from public;

grant execute on function public.liftr_finalize_pet_hatch(uuid) to service_role;
grant execute on function public.generate_pet_coins_v1(uuid) to service_role;
grant execute on function public.generate_all_pet_coins_v1() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (select 1 from cron.job where jobname = 'liftr_generate_pet_coins_job') then
      perform cron.schedule(
        'liftr_generate_pet_coins_job',
        '0 * * * *',
        'select public.generate_all_pet_coins_v1();'
      );
    end if;
  end if;
end;
$$;

commit;

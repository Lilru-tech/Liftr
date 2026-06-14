begin;

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
  v_now_hour timestamptz;
  v_last_hour timestamptz;
  v_hour_at timestamptz;
  v_ledger_ok boolean;
begin
  if p_user_id is null then
    return 0;
  end if;

  select pi.id, pi.evolution_stage, pi.last_coins_generated_at, pi.rarity::text
  into v_instance_id, v_stage, last_gen, v_rarity
  from public.pet_instances pi
  where pi.user_id = p_user_id
    and pi.is_active = true
  limit 1
  for update;

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
  v_now_hour := date_trunc('hour', now());

  if last_gen is null then
    hours_elapsed := 1;
    v_last_hour := v_now_hour - interval '1 hour';
  else
    v_last_hour := date_trunc('hour', last_gen);
    hours_elapsed := greatest(
      0,
      extract(epoch from (v_now_hour - v_last_hour)) / 3600
    )::integer;
  end if;

  hours_elapsed := least(hours_elapsed, 24);

  if hours_elapsed <= 0 then
    return 0;
  end if;

  for i in 1..hours_elapsed loop
    v_hour_at := v_last_hour + (i * interval '1 hour');
    v_hour_bucket := to_char(v_hour_at, 'YYYYMMDDHH24');
    v_ref_id := public.liftr_coin_ref_date('pet_coins:' || v_instance_id::text || ':' || v_hour_bucket);

    coins_this_hour := floor(random() * (coins_max - coins_min + 1))::integer + coins_min;
    coins_this_hour := greatest(0, round(coins_this_hour * v_coin_mult)::integer);

    v_ledger_ok := public.apply_liftr_coin_transaction(
      p_user_id,
      coins_this_hour,
      'pet_coins_generated',
      v_ref_id,
      v_hour_at
    );

    if v_ledger_ok then
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
        v_hour_at
      );
    end if;
  end loop;

  update public.pet_instances
  set last_coins_generated_at = v_last_hour + (hours_elapsed * interval '1 hour'),
      updated_at = now()
  where id = v_instance_id;

  return coalesce(total_coins, 0);
end;
$$;

commit;

begin;

update public.pet_logs pl
set created_at = coalesce(pi.last_coins_generated_at, now()) - interval '1 hour'
from public.pet_instances pi
where pl.pet_instance_id = pi.id
  and pl.event_type = 'coins_generated'
  and pl.created_at > now();

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
      date_trunc('hour', now()) - ((hours_elapsed - i) || ' hour')::interval
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

commit;

begin;

create or replace function public.liftr_workout_coin_scale_factor()
returns numeric
language sql
immutable
as $$
  select 5.95::numeric;
$$;

update public.pet_stage_rewards
set
  coins_min_per_hour = case lower(stage)
    when 'baby' then 2
    when 'kid' then 4
    when 'teen' then 6
    when 'adult' then 8
    when 'elder' then 11
    when 'egg' then 0
    else coins_min_per_hour
  end,
  coins_max_per_hour = case lower(stage)
    when 'baby' then 5
    when 'kid' then 8
    when 'teen' then 10
    when 'adult' then 13
    when 'elder' then 20
    when 'egg' then 0
    else coins_max_per_hour
  end;

create unique index if not exists coin_tx_once_workout_economy_reduction_30pct_v1
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'workout_economy_reduction_30pct_v1';

create unique index if not exists coin_tx_once_pet_passive_economy_reduction_30pct_v1
  on public.coin_transactions (user_id, action_type)
  where action_type = 'pet_passive_economy_reduction_30pct_v1';

create or replace function public.backfill_economy_reduction_30pct_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
  u record;
  v_ref uuid;
  v_paid integer;
  v_new integer;
  v_delta integer;
  v_clawback integer;
  v_passive_paid integer;
begin
  for r in
    select
      w.id,
      w.user_id,
      coalesce(w.ended_at, w.started_at, now()) as event_at
    from public.workouts w
    where w.state = 'published'::public.workout_state
    order by w.id
  loop
    v_ref := public.liftr_coin_ref_bigint(r.id);
    v_new := public.compute_workout_coin_reward_with_pet_bonus(r.id, r.user_id, r.event_at);

    select coalesce(sum(ct.amount), 0)
    into v_paid
    from public.coin_transactions ct
    where ct.user_id = r.user_id
      and ct.reference_id = v_ref
      and ct.action_type in (
        'workout_logged',
        'workout_coin_doubling_v1',
        'workout_economy_rebalance_v1'
      )
      and ct.amount > 0;

    v_delta := v_new - coalesce(v_paid, 0);
    if v_delta < 0 then
      perform public.apply_economy_rebalance_clawback_v1(
        r.user_id,
        v_delta,
        'workout_economy_reduction_30pct_v1',
        v_ref
      );
    end if;
  end loop;

  for u in
    select
      ct.user_id,
      coalesce(sum(ct.amount), 0)::integer as passive_paid
    from public.coin_transactions ct
    where ct.action_type = 'pet_coins_generated'
      and ct.amount > 0
    group by ct.user_id
    having coalesce(sum(ct.amount), 0) > 0
  loop
    v_passive_paid := u.passive_paid;
    v_clawback := round(v_passive_paid * 0.30)::integer;
    if v_clawback > 0 then
      perform public.apply_economy_rebalance_clawback_v1(
        u.user_id,
        -v_clawback,
        'pet_passive_economy_reduction_30pct_v1',
        public.liftr_coin_ref_uuid(u.user_id)
      );
    end if;
  end loop;
end;
$$;

revoke all on function public.backfill_economy_reduction_30pct_v1() from public;
revoke all on function public.backfill_economy_reduction_30pct_v1() from anon, authenticated;

select public.backfill_economy_reduction_30pct_v1();

commit;

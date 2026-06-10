begin;

alter table public.competitions
  add column if not exists bet_amount int not null default 0;

alter table public.competitions
  drop constraint if exists competitions_bet_amount_check;

alter table public.competitions
  add constraint competitions_bet_amount_check
  check (bet_amount >= 0);

insert into public.coin_reward_rules (action_type, amount, enabled) values
  ('competition_bet_escrow', 0, true),
  ('competition_bet_win', 0, true),
  ('competition_bet_refund_draw', 0, true),
  ('competition_bet_refund_cancelled', 0, true)
on conflict (action_type) do nothing;

create unique index if not exists coin_tx_once_competition_bet_escrow
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'competition_bet_escrow' and amount <> 0;

create unique index if not exists coin_tx_once_competition_bet_win
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'competition_bet_win' and amount <> 0;

create unique index if not exists coin_tx_once_competition_bet_refund_draw
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'competition_bet_refund_draw' and amount <> 0;

create unique index if not exists coin_tx_once_competition_bet_refund_cancelled
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'competition_bet_refund_cancelled' and amount <> 0;

create or replace function public.apply_liftr_coin_transaction(
  p_user_id uuid,
  p_amount integer,
  p_action_type text,
  p_reference_id uuid default null,
  p_created_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path to public
as $$
declare
  v_balance integer;
begin
  if p_user_id is null or p_amount is null or p_amount = 0 or p_action_type is null then
    return false;
  end if;

  if p_amount < 0 then
    select coalesce(coins_balance, 0)
    into v_balance
    from public.profiles
    where user_id = p_user_id
    for update;

    if not found then
      raise exception 'profile_not_found';
    end if;

    if v_balance < abs(p_amount) then
      raise exception 'insufficient_coins';
    end if;
  end if;

  begin
    insert into public.coin_transactions (user_id, amount, action_type, reference_id, created_at)
    values (
      p_user_id,
      p_amount,
      p_action_type,
      p_reference_id,
      coalesce(p_created_at, now())
    );
    return true;
  exception
    when unique_violation then
      return false;
  end;
end;
$$;

create or replace function public.apply_liftr_coin_reward(
  p_user_id uuid,
  p_amount integer,
  p_action_type text,
  p_reference_id uuid default null,
  p_created_at timestamptz default null
)
returns boolean
language plpgsql
security definer
set search_path to public
as $$
begin
  return public.apply_liftr_coin_transaction(
    p_user_id,
    p_amount,
    p_action_type,
    p_reference_id,
    p_created_at
  );
end;
$$;

revoke all on function public.apply_liftr_coin_transaction(uuid, integer, text, uuid, timestamptz) from public;

create or replace function public.competition_escrow_bet(
  p_competition_id bigint,
  p_user_id uuid,
  p_bet_amount integer
)
returns boolean
language plpgsql
security definer
set search_path to public
as $$
begin
  if p_bet_amount is null or p_bet_amount <= 0 then
    return false;
  end if;

  return public.apply_liftr_coin_transaction(
    p_user_id,
    -p_bet_amount,
    'competition_bet_escrow',
    public.liftr_coin_ref_bigint(p_competition_id)
  );
end;
$$;

revoke all on function public.competition_escrow_bet(bigint, uuid, integer) from public;

create or replace function public.competition_settle_bet(p_competition_id bigint)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  c public.competitions%rowtype;
  v_ref uuid;
begin
  select *
  into c
  from public.competitions
  where id = p_competition_id;

  if not found or coalesce(c.bet_amount, 0) <= 0 then
    return;
  end if;

  v_ref := public.liftr_coin_ref_bigint(p_competition_id);

  if c.status = 'finished' then
    if c.winner_user_id is not null then
      perform public.apply_liftr_coin_transaction(
        c.winner_user_id,
        c.bet_amount * 2,
        'competition_bet_win',
        v_ref
      );
    else
      perform public.apply_liftr_coin_transaction(
        c.user_a,
        c.bet_amount,
        'competition_bet_refund_draw',
        v_ref
      );
      perform public.apply_liftr_coin_transaction(
        c.user_b,
        c.bet_amount,
        'competition_bet_refund_draw',
        v_ref
      );
    end if;
  elsif c.status in ('declined', 'cancelled', 'expired') then
    perform public.apply_liftr_coin_transaction(
      c.created_by,
      c.bet_amount,
      'competition_bet_refund_cancelled',
      v_ref
    );
  end if;
end;
$$;

revoke all on function public.competition_settle_bet(bigint) from public;

create or replace function public.trg_competition_settle_bet_on_status_change()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if new.status is distinct from old.status
     and new.status in ('finished', 'declined', 'cancelled', 'expired') then
    perform public.competition_settle_bet(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_competition_settle_bet on public.competitions;
create trigger trg_competition_settle_bet
  after update of status on public.competitions
  for each row
  execute function public.trg_competition_settle_bet_on_status_change();

create or replace function public.competition_get_max_bet_v1(p_opponent_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_me uuid;
  v_my_balance integer;
  v_opp_balance integer;
begin
  v_me := auth.uid();
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  if p_opponent_id is null or p_opponent_id = v_me then
    raise exception 'Invalid opponent';
  end if;

  select coalesce(coins_balance, 0)
  into v_my_balance
  from public.profiles
  where user_id = v_me;

  select coalesce(coins_balance, 0)
  into v_opp_balance
  from public.profiles
  where user_id = p_opponent_id;

  return least(coalesce(v_my_balance, 0), coalesce(v_opp_balance, 0));
end;
$$;

revoke all on function public.competition_get_max_bet_v1(uuid) from public;
grant execute on function public.competition_get_max_bet_v1(uuid) to authenticated;

create or replace function public.get_my_competition_escrow_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_me uuid;
  v_escrowed_total integer;
  v_staked_count integer;
begin
  v_me := auth.uid();
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select
    coalesce(sum(
      case
        when bet_amount <= 0 then 0
        when status = 'active' then bet_amount
        when status = 'pending' and created_by = v_me then bet_amount
        else 0
      end
    ), 0),
    count(*) filter (
      where bet_amount > 0
        and (
          status = 'active'
          or (status = 'pending' and created_by = v_me)
        )
    )
  into v_escrowed_total, v_staked_count
  from public.competitions
  where (user_a = v_me or user_b = v_me)
    and status in ('pending', 'active');

  return jsonb_build_object(
    'escrowed_total', v_escrowed_total,
    'pending_count', (
      select count(*)::integer
      from public.competitions
      where (user_a = v_me or user_b = v_me)
        and status = 'pending'
        and bet_amount > 0
        and created_by = v_me
    ),
    'active_staked_count', (
      select count(*)::integer
      from public.competitions
      where (user_a = v_me or user_b = v_me)
        and status = 'active'
        and bet_amount > 0
    ),
    'staked_challenge_count', v_staked_count
  );
end;
$$;

revoke all on function public.get_my_competition_escrow_summary_v1() from public;
grant execute on function public.get_my_competition_escrow_summary_v1() to authenticated;

create or replace function public.expire_stale_competition_invites_v1()
returns integer
language plpgsql
security definer
set search_path to public
as $$
declare
  v_count integer;
begin
  with expired as (
    update public.competitions
    set status = 'expired',
        finished_at = coalesce(finished_at, now()),
        updated_at = now()
    where status = 'pending'
      and invite_expires_at <= now()
    returning id
  )
  select count(*)::integer into v_count from expired;

  return coalesce(v_count, 0);
end;
$$;

revoke all on function public.expire_stale_competition_invites_v1() from public;
grant execute on function public.expire_stale_competition_invites_v1() to authenticated;

create or replace function public.expire_pending_competition_bets_v1()
returns integer
language plpgsql
security definer
set search_path to public
as $$
declare
  v_competition_id bigint;
  v_count integer := 0;
begin
  for v_competition_id in
    select id
    from public.competitions
    where status = 'pending'
      and bet_amount > 0
      and created_at < now() - interval '7 days'
    for update skip locked
  loop
    update public.competitions
    set status = 'expired',
        finished_at = coalesce(finished_at, now()),
        updated_at = now()
    where id = v_competition_id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.expire_pending_competition_bets_v1() from public;

drop function if exists public.rpc_create_competition(uuid, timestamptz, goal_metric, numeric, integer);

create or replace function public.rpc_create_competition(
  p_opponent_id uuid,
  p_time_limit_at timestamptz default null,
  p_metric goal_metric default null,
  p_target_value numeric default null,
  p_expire_hours integer default 48,
  p_bet_amount integer default 0
)
returns bigint
language plpgsql
security definer
set search_path to public
as $$
declare
  v_me uuid;
  v_competition_id bigint;
  v_max_bet integer;
  v_my_balance integer;
  v_opp_balance integer;
  v_invite_expires_at timestamptz;
  v_bet integer;
begin
  v_me := auth.uid();
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  if p_opponent_id is null or p_opponent_id = v_me then
    raise exception 'Invalid opponent';
  end if;

  if p_time_limit_at is null and p_metric is null then
    raise exception 'A competition must have at least a time limit or a metric goal.';
  end if;

  if (p_metric is null and p_target_value is not null)
     or (p_metric is not null and (p_target_value is null or p_target_value <= 0)) then
    raise exception 'Invalid target value.';
  end if;

  v_bet := coalesce(p_bet_amount, 0);
  if v_bet < 0 then
    raise exception 'Invalid bet amount.';
  end if;

  if v_bet > 0 then
    select coalesce(coins_balance, 0)
    into v_my_balance
    from public.profiles
    where user_id = v_me
    for update;

    select coalesce(coins_balance, 0)
    into v_opp_balance
    from public.profiles
    where user_id = p_opponent_id;

    v_max_bet := least(coalesce(v_my_balance, 0), coalesce(v_opp_balance, 0));
    if v_bet > v_max_bet then
      raise exception 'bet_exceeds_max_allowed';
    end if;

    v_invite_expires_at := now() + interval '7 days';
  else
    v_invite_expires_at := now() + make_interval(hours => coalesce(p_expire_hours, 48));
  end if;

  insert into public.competitions (
    created_by,
    user_a,
    user_b,
    status,
    invite_expires_at,
    bet_amount
  )
  values (
    v_me,
    v_me,
    p_opponent_id,
    'pending',
    v_invite_expires_at,
    v_bet
  )
  returning id into v_competition_id;

  insert into public.competition_goals (competition_id, time_limit_at, metric, target_value)
  values (v_competition_id, p_time_limit_at, p_metric, p_target_value);

  if v_bet > 0 then
    perform public.competition_escrow_bet(v_competition_id, v_me, v_bet);
  end if;

  return v_competition_id;
end;
$$;

revoke all on function public.rpc_create_competition(uuid, timestamptz, goal_metric, numeric, integer, integer) from public;
grant execute on function public.rpc_create_competition(uuid, timestamptz, goal_metric, numeric, integer, integer) to authenticated;

create or replace function public.accept_competition(p_competition_id bigint)
returns void
language plpgsql
security definer
set search_path to public, extensions
as $$
declare
  c record;
  v_me uuid;
begin
  v_me := auth.uid();
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select *
  into c
  from public.competitions
  where id = p_competition_id
  for update;

  if not found then
    raise exception 'Competition not found';
  end if;

  if v_me not in (c.user_a, c.user_b) then
    raise exception 'Not allowed';
  end if;

  if c.status <> 'pending' then
    raise exception 'Competition is not pending';
  end if;

  if c.invite_expires_at <= now() then
    update public.competitions
    set status = 'expired',
        finished_at = coalesce(finished_at, now()),
        updated_at = now()
    where id = p_competition_id;
    raise exception 'Invitation expired';
  end if;

  if coalesce(c.bet_amount, 0) > 0 then
    perform public.competition_escrow_bet(p_competition_id, v_me, c.bet_amount);
  end if;

  update public.competitions
  set status = 'active',
      accepted_at = now(),
      updated_at = now()
  where id = p_competition_id;
end;
$$;

revoke all on function public.accept_competition(bigint) from public;
grant execute on function public.accept_competition(bigint) to authenticated;

create or replace function public.decline_competition(p_competition_id bigint)
returns void
language plpgsql
security definer
set search_path to public, extensions
as $$
declare
  c record;
begin
  select *
  into c
  from public.competitions
  where id = p_competition_id
  for update;

  if not found then
    raise exception 'Competition not found';
  end if;

  if auth.uid() not in (c.user_a, c.user_b) then
    raise exception 'Not allowed';
  end if;

  if c.status <> 'pending' then
    raise exception 'Competition is not pending';
  end if;

  update public.competitions
  set status = 'declined',
      declined_at = now(),
      finished_at = coalesce(finished_at, now()),
      updated_at = now()
  where id = p_competition_id;
end;
$$;

revoke all on function public.decline_competition(bigint) from public;
grant execute on function public.decline_competition(bigint) to authenticated;

create or replace function public.cancel_competition_invite(p_competition_id bigint)
returns void
language plpgsql
security definer
set search_path to public, extensions
as $$
declare
  c record;
begin
  select *
  into c
  from public.competitions
  where id = p_competition_id
  for update;

  if not found then
    raise exception 'Competition not found';
  end if;

  if c.created_by <> auth.uid() then
    raise exception 'Only creator can cancel';
  end if;

  if c.status <> 'pending' then
    raise exception 'Can only cancel pending invites';
  end if;

  update public.competitions
  set status = 'cancelled',
      cancelled_at = now(),
      finished_at = coalesce(finished_at, now()),
      updated_at = now()
  where id = p_competition_id;
end;
$$;

revoke all on function public.cancel_competition_invite(bigint) from public;
grant execute on function public.cancel_competition_invite(bigint) to authenticated;

create or replace function public.rpc_cancel_competition(p_competition_id bigint)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_me uuid;
begin
  v_me := auth.uid();
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  perform public.cancel_competition_invite(p_competition_id);
end;
$$;

revoke all on function public.rpc_cancel_competition(bigint) from public;
grant execute on function public.rpc_cancel_competition(bigint) to authenticated;

create or replace function public.competition_update_progress_and_maybe_finish(p_competition_id bigint)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_goal_metric goal_metric;
  v_target numeric;
  v_time_limit timestamptz;
  v_now timestamptz := now();

  v_user_a uuid;
  v_user_b uuid;

  v_prog_a numeric := 0;
  v_prog_b numeric := 0;

  v_status competition_status;
begin
  select user_a, user_b, status
  into v_user_a, v_user_b, v_status
  from public.competitions
  where id = p_competition_id;

  if v_status <> 'active' then
    return;
  end if;

  select metric, target_value, time_limit_at
  into v_goal_metric, v_target, v_time_limit
  from public.competition_goals
  where competition_id = p_competition_id;

  if v_goal_metric = 'workouts' then
    select count(*) into v_prog_a
    from public.competition_workouts
    where competition_id = p_competition_id and workout_owner_id = v_user_a and status = 'accepted';

    select count(*) into v_prog_b
    from public.competition_workouts
    where competition_id = p_competition_id and workout_owner_id = v_user_b and status = 'accepted';

  elsif v_goal_metric = 'calories' then
    select coalesce(sum(calories_snapshot), 0) into v_prog_a
    from public.competition_workouts
    where competition_id = p_competition_id and workout_owner_id = v_user_a and status = 'accepted';

    select coalesce(sum(calories_snapshot), 0) into v_prog_b
    from public.competition_workouts
    where competition_id = p_competition_id and workout_owner_id = v_user_b and status = 'accepted';

  elsif v_goal_metric = 'score' then
    select coalesce(sum(score_snapshot), 0) into v_prog_a
    from public.competition_workouts
    where competition_id = p_competition_id and workout_owner_id = v_user_a and status = 'accepted';

    select coalesce(sum(score_snapshot), 0) into v_prog_b
    from public.competition_workouts
    where competition_id = p_competition_id and workout_owner_id = v_user_b and status = 'accepted';
  end if;

  if (v_time_limit is not null and v_now >= v_time_limit)
     or (v_target is not null and (v_prog_a >= v_target or v_prog_b >= v_target)) then

    update public.competitions
    set status = 'finished',
        finished_at = v_now,
        winner_user_id = case
          when v_prog_a = v_prog_b then null
          when v_prog_a > v_prog_b then v_user_a
          else v_user_b
        end,
        updated_at = v_now
    where id = p_competition_id;
  end if;
end;
$$;

revoke insert on public.competitions from authenticated;
revoke insert on public.competition_goals from authenticated;
revoke update on public.competitions from authenticated;

do $$
declare
  v_job_id bigint;
begin
  select jobid
  into v_job_id
  from cron.job
  where jobname = 'expire_pending_competition_bets_hourly';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'expire_pending_competition_bets_hourly',
    '0 * * * *',
    $cmd$select public.expire_pending_competition_bets_v1()$cmd$
  );
end;
$$;

notify pgrst, 'reload schema';

commit;

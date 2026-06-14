begin;

create extension if not exists "uuid-ossp";

create table if not exists public.coin_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  amount int not null,
  action_type text not null,
  reference_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists coin_transactions_user_id_created_at_idx
  on public.coin_transactions (user_id, created_at desc);

create index if not exists coin_transactions_action_type_idx
  on public.coin_transactions (action_type);

alter table public.profiles
  add column if not exists coins_balance int not null default 0;

alter table public.achievements
  add column if not exists coin_reward_tier text;

alter table public.achievements
  drop constraint if exists achievements_coin_reward_tier_check;

alter table public.achievements
  add constraint achievements_coin_reward_tier_check
  check (coin_reward_tier is null or coin_reward_tier in ('bronze', 'silver', 'gold'));

update public.achievements
set coin_reward_tier = case
  when requirement_value <= 1 then 'bronze'
  when requirement_value <= 50 then 'silver'
  else 'gold'
end
where coin_reward_tier is null;

create table if not exists public.coin_reward_rules (
  action_type text primary key,
  amount int not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.coin_reward_rules (action_type, amount, enabled) values
  ('like_given', 2, true),
  ('comment_added', 5, true),
  ('user_followed', 5, true),
  ('earned_follower', 10, true),
  ('achievement_unlocked_bronze', 25, true),
  ('achievement_unlocked_silver', 50, true),
  ('achievement_unlocked_gold', 100, true),
  ('weekly_goal_perfect_week', 40, true),
  ('workout_consistency_streak', 50, true)
on conflict (action_type) do nothing;

create unique index if not exists coin_tx_once_like_given
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'like_given' and amount > 0;

create unique index if not exists coin_tx_once_user_followed
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'user_followed' and amount > 0;

create unique index if not exists coin_tx_once_earned_follower
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'earned_follower' and amount > 0;

create unique index if not exists coin_tx_once_comment_added
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'comment_added' and amount > 0;

create unique index if not exists coin_tx_once_workout_logged
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'workout_logged' and amount > 0;

create unique index if not exists coin_tx_once_achievement_unlocked
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'achievement_unlocked' and amount > 0;

create unique index if not exists coin_tx_once_weekly_goal_perfect_week
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'weekly_goal_perfect_week' and amount > 0;

create unique index if not exists coin_tx_once_workout_consistency_streak
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'workout_consistency_streak' and amount > 0;

create or replace function public.liftr_coin_ref_bigint(p_id bigint)
returns uuid
language sql
immutable
as $$
  select extensions.uuid_generate_v5(
    '6ba7b810-9dad-11d1-80b4-00c04fd430c8'::uuid,
    'liftr:bigint:' || p_id::text
  );
$$;

create or replace function public.liftr_coin_ref_uuid(p_id uuid)
returns uuid
language sql
immutable
as $$
  select extensions.uuid_generate_v5(
    '6ba7b810-9dad-11d1-80b4-00c04fd430c8'::uuid,
    'liftr:uuid:' || p_id::text
  );
$$;

create or replace function public.liftr_coin_ref_date(p_key text)
returns uuid
language sql
immutable
as $$
  select extensions.uuid_generate_v5(
    '6ba7b810-9dad-11d1-80b4-00c04fd430c8'::uuid,
    'liftr:date:' || p_key
  );
$$;

create or replace function public.allow_profiles_coin_balance_update()
returns void
language sql
security definer
set search_path to public
as $$
  select set_config('app.allow_coin_update', 'true', true);
$$;

create or replace function public.protect_profiles_coins_balance()
returns trigger
language plpgsql
set search_path to public
as $$
begin
  if old.coins_balance is distinct from new.coins_balance
     and current_setting('app.allow_coin_update', true) is distinct from 'true' then
    raise exception 'coins_balance_is_server_managed';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_profiles_coins_balance on public.profiles;
create trigger trg_protect_profiles_coins_balance
  before update on public.profiles
  for each row
  execute function public.protect_profiles_coins_balance();

create or replace function public.sync_profiles_coins_balance()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  perform public.allow_profiles_coin_balance_update();
  update public.profiles
  set coins_balance = coalesce(coins_balance, 0) + new.amount
  where user_id = new.user_id;
  return new;
end;
$$;

drop trigger if exists trg_coin_transactions_sync_balance on public.coin_transactions;
create trigger trg_coin_transactions_sync_balance
  after insert on public.coin_transactions
  for each row
  execute function public.sync_profiles_coins_balance();

create or replace function public.get_coin_reward_amount(p_action_type text, p_fallback integer)
returns integer
language sql
stable
security definer
set search_path to public
as $$
  select coalesce(
    (select amount from public.coin_reward_rules where action_type = p_action_type and enabled = true),
    p_fallback
  );
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
  if p_user_id is null or p_amount is null or p_amount = 0 or p_action_type is null then
    return false;
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

create or replace function public.resolve_achievement_coin_amount(p_achievement_id bigint)
returns integer
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_tier text;
  v_requirement integer;
begin
  select a.coin_reward_tier, a.requirement_value
  into v_tier, v_requirement
  from public.achievements a
  where a.id = p_achievement_id;

  if v_tier is null then
    if coalesce(v_requirement, 1) <= 1 then
      v_tier := 'bronze';
    elsif coalesce(v_requirement, 1) <= 50 then
      v_tier := 'silver';
    else
      v_tier := 'gold';
    end if;
  end if;

  return case v_tier
    when 'bronze' then public.get_coin_reward_amount('achievement_unlocked_bronze', 25)
    when 'silver' then public.get_coin_reward_amount('achievement_unlocked_silver', 50)
    else public.get_coin_reward_amount('achievement_unlocked_gold', 100)
  end;
end;
$$;

create or replace function public.compute_workout_coin_reward(p_workout_id bigint)
returns integer
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_kind text;
  v_duration_min integer;
  v_duration_sec integer;
  v_distance_km numeric;
  v_set_count integer;
  v_reward integer := 10;
begin
  select w.kind, w.duration_min
  into v_kind, v_duration_min
  from public.workouts w
  where w.id = p_workout_id;

  if v_kind is null then
    return 0;
  end if;

  if v_kind = 'strength' then
    select count(*)::integer
    into v_set_count
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    where we.workout_id = p_workout_id;

    return 10 + coalesce(v_set_count, 0);
  end if;

  if v_kind = 'cardio' then
    select cs.duration_sec, cs.distance_km
    into v_duration_sec, v_distance_km
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
    limit 1;

    if v_duration_sec is null and v_duration_min is not null then
      v_duration_sec := v_duration_min * 60;
    end if;

    if coalesce(v_duration_sec, 0) >= 1800 then
      v_reward := v_reward + 5;
    end if;
    if coalesce(v_duration_sec, 0) >= 3600 then
      v_reward := v_reward + 5;
    end if;
    if coalesce(v_distance_km, 0) >= 5 then
      v_reward := v_reward + 5;
    end if;
    if coalesce(v_distance_km, 0) >= 10 then
      v_reward := v_reward + 10;
    end if;

    return v_reward;
  end if;

  return 10;
end;
$$;

create or replace function public.evaluate_workout_consistency_streak_coins(p_user_id uuid, p_anchor_date date default current_date)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_streak_start date;
  v_consecutive integer;
begin
  with workout_days as (
    select distinct (coalesce(w.ended_at, w.started_at, now()) at time zone 'utc')::date as workout_day
    from public.workouts w
    where w.user_id = p_user_id
      and w.state = 'published'::public.workout_state
  ),
  ordered as (
    select
      workout_day,
      workout_day - (row_number() over (order by workout_day))::integer as streak_group
    from workout_days
    where workout_day <= p_anchor_date
  ),
  groups as (
    select streak_group, min(workout_day) as streak_start, count(*)::integer as streak_len
    from ordered
    group by streak_group
  )
  select g.streak_start, g.streak_len
  into v_streak_start, v_consecutive
  from groups g
  where g.streak_len >= 7
    and p_anchor_date between g.streak_start and (g.streak_start + (g.streak_len - 1))
  order by g.streak_start desc
  limit 1;

  if v_streak_start is null then
    return;
  end if;

  perform public.apply_liftr_coin_reward(
    p_user_id,
    public.get_coin_reward_amount('workout_consistency_streak', 50),
    'workout_consistency_streak',
    public.liftr_coin_ref_date(v_streak_start::text)
  );
end;
$$;

create or replace function public.evaluate_weekly_goal_perfect_week_coins(p_user_id uuid, p_week_start date)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_total integer;
  v_completed integer;
begin
  select count(*)::integer,
         count(*) filter (where coalesce(wgr.is_completed, false))::integer
  into v_total, v_completed
  from public.weekly_goals wg
  left join public.weekly_goal_results wgr
    on wgr.goal_id = wg.id
   and wgr.week_start = wg.week_start
  where wg.user_id = p_user_id
    and wg.week_start = p_week_start;

  if v_total = 0 or v_completed < v_total then
    return;
  end if;

  perform public.apply_liftr_coin_reward(
    p_user_id,
    public.get_coin_reward_amount('weekly_goal_perfect_week', 40),
    'weekly_goal_perfect_week',
    public.liftr_coin_ref_date(p_week_start::text)
  );
end;
$$;

create or replace function public.trg_coins_on_workout_publish()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
declare
  v_amount integer;
  v_day date;
begin
  if tg_op = 'INSERT' then
    if new.state <> 'published'::public.workout_state then
      return new;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.state <> 'published'::public.workout_state
       or old.state is not distinct from 'published'::public.workout_state then
      return new;
    end if;
  else
    return new;
  end if;

  v_amount := public.compute_workout_coin_reward(new.id);
  if v_amount > 0 then
    perform public.apply_liftr_coin_reward(
      new.user_id,
      v_amount,
      'workout_logged',
      public.liftr_coin_ref_bigint(new.id),
      coalesce(new.ended_at, new.started_at, now())
    );
  end if;

  v_day := (coalesce(new.ended_at, new.started_at, now()) at time zone 'utc')::date;
  perform public.evaluate_workout_consistency_streak_coins(new.user_id, v_day);

  return new;
end;
$$;

drop trigger if exists trg_coins_on_workout_publish on public.workouts;
create trigger trg_coins_on_workout_publish
  after insert or update of state on public.workouts
  for each row
  execute function public.trg_coins_on_workout_publish();

create or replace function public.trg_coins_on_workout_like()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  perform public.apply_liftr_coin_reward(
    new.user_id,
    public.get_coin_reward_amount('like_given', 2),
    'like_given',
    public.liftr_coin_ref_bigint(new.workout_id)
  );
  return new;
end;
$$;

drop trigger if exists trg_coins_on_workout_like on public.workout_likes;
create trigger trg_coins_on_workout_like
  after insert on public.workout_likes
  for each row
  execute function public.trg_coins_on_workout_like();

create or replace function public.trg_coins_on_workout_comment()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if new.deleted_at is not null then
    return new;
  end if;

  perform public.apply_liftr_coin_reward(
    new.user_id,
    public.get_coin_reward_amount('comment_added', 5),
    'comment_added',
    public.liftr_coin_ref_bigint(new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_coins_on_workout_comment on public.workout_comments;
create trigger trg_coins_on_workout_comment
  after insert on public.workout_comments
  for each row
  execute function public.trg_coins_on_workout_comment();

create or replace function public.trg_coins_on_follow()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  perform public.apply_liftr_coin_reward(
    new.follower_id,
    public.get_coin_reward_amount('user_followed', 5),
    'user_followed',
    public.liftr_coin_ref_uuid(new.followee_id)
  );

  perform public.apply_liftr_coin_reward(
    new.followee_id,
    public.get_coin_reward_amount('earned_follower', 10),
    'earned_follower',
    public.liftr_coin_ref_uuid(new.follower_id)
  );

  return new;
end;
$$;

drop trigger if exists trg_coins_on_follow on public.follows;
create trigger trg_coins_on_follow
  after insert on public.follows
  for each row
  execute function public.trg_coins_on_follow();

create or replace function public.trg_coins_on_achievement_unlock()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
declare
  v_amount integer;
begin
  v_amount := public.resolve_achievement_coin_amount(new.achievement_id);
  if v_amount > 0 then
    perform public.apply_liftr_coin_reward(
      new.user_id,
      v_amount,
      'achievement_unlocked',
      public.liftr_coin_ref_bigint(new.achievement_id),
      coalesce(new.unlocked_at, now())
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_coins_on_achievement_unlock on public.user_achievements;
create trigger trg_coins_on_achievement_unlock
  after insert on public.user_achievements
  for each row
  execute function public.trg_coins_on_achievement_unlock();

create or replace function public.trg_coins_on_weekly_goal_result()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if coalesce(new.is_completed, false) then
    perform public.evaluate_weekly_goal_perfect_week_coins(new.user_id, new.week_start);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_coins_on_weekly_goal_result on public.weekly_goal_results;
create trigger trg_coins_on_weekly_goal_result
  after insert or update of is_completed on public.weekly_goal_results
  for each row
  execute function public.trg_coins_on_weekly_goal_result();

create or replace function public.reconcile_profiles_coins_balance()
returns void
language plpgsql
security definer
set search_path to public
as $$
begin
  perform public.allow_profiles_coin_balance_update();
  update public.profiles p
  set coins_balance = coalesce(s.total, 0)
  from (
    select ct.user_id, sum(ct.amount)::integer as total
    from public.coin_transactions ct
    group by ct.user_id
  ) s
  where p.user_id = s.user_id;

  perform public.allow_profiles_coin_balance_update();
  update public.profiles p
  set coins_balance = 0
  where not exists (
    select 1 from public.coin_transactions ct where ct.user_id = p.user_id
  );
end;
$$;

create or replace function public.backfill_liftr_coins_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
  v_amount integer;
  v_day date;
begin
  for r in
    select w.id, w.user_id, coalesce(w.ended_at, w.started_at, now()) as event_at
    from public.workouts w
    where w.state = 'published'::public.workout_state
    order by w.id
  loop
    v_amount := public.compute_workout_coin_reward(r.id);
    if v_amount > 0 then
      perform public.apply_liftr_coin_reward(
        r.user_id,
        v_amount,
        'workout_logged',
        public.liftr_coin_ref_bigint(r.id),
        r.event_at
      );
    end if;
  end loop;

  for r in
    select wl.user_id, wl.workout_id, now() as event_at
    from public.workout_likes wl
    order by wl.workout_id, wl.user_id
  loop
    perform public.apply_liftr_coin_reward(
      r.user_id,
      public.get_coin_reward_amount('like_given', 2),
      'like_given',
      public.liftr_coin_ref_bigint(r.workout_id),
      r.event_at
    );
  end loop;

  for r in
    select wc.user_id, wc.id as comment_id, coalesce(wc.created_at, now()) as event_at
    from public.workout_comments wc
    where wc.deleted_at is null
    order by wc.id
  loop
    perform public.apply_liftr_coin_reward(
      r.user_id,
      public.get_coin_reward_amount('comment_added', 5),
      'comment_added',
      public.liftr_coin_ref_bigint(r.comment_id),
      r.event_at
    );
  end loop;

  for r in
    select f.follower_id, f.followee_id
    from public.follows f
    order by f.follower_id, f.followee_id
  loop
    perform public.apply_liftr_coin_reward(
      r.follower_id,
      public.get_coin_reward_amount('user_followed', 5),
      'user_followed',
      public.liftr_coin_ref_uuid(r.followee_id)
    );
    perform public.apply_liftr_coin_reward(
      r.followee_id,
      public.get_coin_reward_amount('earned_follower', 10),
      'earned_follower',
      public.liftr_coin_ref_uuid(r.follower_id)
    );
  end loop;

  for r in
    select ua.user_id, ua.achievement_id, coalesce(ua.unlocked_at, now()) as event_at
    from public.user_achievements ua
    order by ua.user_id, ua.achievement_id
  loop
    v_amount := public.resolve_achievement_coin_amount(r.achievement_id);
    if v_amount > 0 then
      perform public.apply_liftr_coin_reward(
        r.user_id,
        v_amount,
        'achievement_unlocked',
        public.liftr_coin_ref_bigint(r.achievement_id),
        r.event_at
      );
    end if;
  end loop;

  for r in
    select wg.user_id, wg.week_start
    from public.weekly_goals wg
    group by wg.user_id, wg.week_start
  loop
    perform public.evaluate_weekly_goal_perfect_week_coins(r.user_id, r.week_start);
  end loop;

  for r in
    select distinct w.user_id
    from public.workouts w
    where w.state = 'published'::public.workout_state
  loop
    for v_day in
      select distinct (coalesce(w.ended_at, w.started_at, now()) at time zone 'utc')::date as workout_day
      from public.workouts w
      where w.user_id = r.user_id
        and w.state = 'published'::public.workout_state
    loop
      perform public.evaluate_workout_consistency_streak_coins(r.user_id, v_day);
    end loop;
  end loop;

  perform public.reconcile_profiles_coins_balance();
end;
$$;

alter table public.coin_transactions enable row level security;
alter table public.coin_reward_rules enable row level security;

drop policy if exists coin_transactions_select_own on public.coin_transactions;
create policy coin_transactions_select_own
  on public.coin_transactions
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists coin_reward_rules_select_authenticated on public.coin_reward_rules;
create policy coin_reward_rules_select_authenticated
  on public.coin_reward_rules
  for select
  to authenticated
  using (true);

revoke insert, update, delete on public.coin_transactions from anon, authenticated;
revoke insert, update, delete on public.coin_reward_rules from anon, authenticated;

grant select on public.coin_transactions to authenticated;
grant select on public.coin_reward_rules to authenticated;

revoke all on function public.apply_liftr_coin_reward(uuid, integer, text, uuid, timestamptz) from public;
revoke all on function public.apply_liftr_coin_reward(uuid, integer, text, uuid, timestamptz) from anon, authenticated;

revoke all on function public.compute_workout_coin_reward(bigint) from public;
revoke all on function public.compute_workout_coin_reward(bigint) from anon, authenticated;

revoke all on function public.resolve_achievement_coin_amount(bigint) from public;
revoke all on function public.resolve_achievement_coin_amount(bigint) from anon, authenticated;

revoke all on function public.evaluate_workout_consistency_streak_coins(uuid, date) from public;
revoke all on function public.evaluate_workout_consistency_streak_coins(uuid, date) from anon, authenticated;

revoke all on function public.evaluate_weekly_goal_perfect_week_coins(uuid, date) from public;
revoke all on function public.evaluate_weekly_goal_perfect_week_coins(uuid, date) from anon, authenticated;

revoke all on function public.reconcile_profiles_coins_balance() from public;
revoke all on function public.reconcile_profiles_coins_balance() from anon, authenticated;

revoke all on function public.backfill_liftr_coins_v1() from public;
revoke all on function public.backfill_liftr_coins_v1() from anon, authenticated;

revoke all on function public.allow_profiles_coin_balance_update() from public;
revoke all on function public.allow_profiles_coin_balance_update() from anon, authenticated;

perform public.backfill_liftr_coins_v1();

commit;

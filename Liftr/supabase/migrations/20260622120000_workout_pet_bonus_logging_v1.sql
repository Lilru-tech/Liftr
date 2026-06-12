begin;

create table if not exists public.pet_workout_bonus_messages (
  id serial primary key,
  message text not null
);

alter table public.pet_workout_bonus_messages enable row level security;

drop policy if exists pet_workout_bonus_messages_read on public.pet_workout_bonus_messages;
create policy pet_workout_bonus_messages_read on public.pet_workout_bonus_messages
  for select using (true);

insert into public.pet_workout_bonus_messages (message) values
  ('Your pet claims those reps were {bonus_pct}% easier thanks to their aura. +{coins} coins.'),
  ('Spotter mode activated. {pet_name} held the imaginary bar while you collected +{coins} coins.'),
  ('Scientific fact: pets increase gains by {bonus_pct}%. Also science: +{coins} coins.'),
  ('{pet_name} did a victory lap around your gym bag. +{coins} bonus coins.'),
  ('Your pet flexed so hard the coin jar exploded: +{coins} coins!'),
  ('{pet_name} whispered ''one more set'' and the universe paid +{coins} coins.'),
  ('Certified gym gremlin {pet_name} boosted this session by {bonus_pct}%. +{coins} coins earned.'),
  ('{pet_name} stared at the dumbbells until they felt guilty. +{coins} coins for you.'),
  ('Your pet negotiated a {bonus_pct}% raise with the coin gods. Result: +{coins} coins.'),
  ('{pet_name} counted your reps out loud. The neighbors complained, but you got +{coins} coins.'),
  ('Legend says {pet_name} only appears for legends. Today that legend got +{coins} coins.'),
  ('{pet_name} filed a performance bonus report: +{coins} coins approved.'),
  ('Your pet did absolutely nothing… except earn you +{coins} bonus coins.'),
  ('{pet_name} believes in you so hard the coins showed up anyway: +{coins}.'),
  ('Workout complete. {pet_name} demanded a tip and the tip was +{coins} coins.'),
  ('{pet_name} activated turbo hype mode (+{bonus_pct}%). Payout: +{coins} coins.'),
  ('Your pet traded one motivational nod for +{coins} coins. Fair deal.'),
  ('{pet_name} says the grind was worth it. The coins agree: +{coins}.'),
  ('Coin rain detected. Source: {pet_name}. Amount: +{coins} coins.'),
  ('{pet_name} ran quality control on your sets and issued +{coins} bonus coins.'),
  ('Your pet challenged the workout to a duel and won +{coins} coins for the team.'),
  ('{pet_name} put on tiny imaginary wrist wraps. Bonus unlocked: +{coins} coins.'),
  ('Session review: effort A+, pet support S-tier. Reward: +{coins} coins.'),
  ('{pet_name} celebrated with a silent roar. You celebrated with +{coins} coins.'),
  ('Your pet turned {bonus_pct}% extra effort into +{coins} shiny coins.');

create or replace function public.pick_pet_workout_bonus_message(
  p_coins integer,
  p_bonus_pct numeric,
  p_pet_name text
)
returns text
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_template text;
  v_name text;
begin
  v_name := coalesce(nullif(trim(p_pet_name), ''), 'Your pet');

  select m.message
  into v_template
  from public.pet_workout_bonus_messages m
  order by random()
  limit 1;

  if v_template is null then
    return format('%s helped you earn +%s bonus coins.', v_name, coalesce(p_coins, 0));
  end if;

  return replace(
    replace(
      replace(v_template, '{coins}', coalesce(p_coins, 0)::text),
      '{bonus_pct}',
      trim(to_char(coalesce(p_bonus_pct, 0), 'FM999990.##'))
    ),
    '{pet_name}',
    v_name
  );
end;
$$;

create unique index if not exists coin_tx_once_workout_pet_training_bonus
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'workout_pet_training_bonus' and amount > 0;

create or replace function public.grant_workout_coin_rewards_v1(
  p_workout_id bigint,
  p_user_id uuid,
  p_event_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_event_at timestamptz;
  v_ref uuid;
  v_base integer;
  v_bonus_pct numeric;
  v_bonus integer;
  v_instance_id uuid;
  v_pet_name text;
  v_message text;
begin
  if p_workout_id is null or p_user_id is null then
    return;
  end if;

  v_event_at := coalesce(
    p_event_at,
    (
      select coalesce(w.ended_at, w.started_at, now())
      from public.workouts w
      where w.id = p_workout_id
    ),
    now()
  );
  v_ref := public.liftr_coin_ref_bigint(p_workout_id);

  v_base := public.compute_workout_coin_reward(p_workout_id);
  v_bonus_pct := public.get_pet_training_bonus_pct(p_user_id);
  v_bonus := round(coalesce(v_base, 0) * coalesce(v_bonus_pct, 0) / 100.0)::integer;

  if coalesce(v_base, 0) > 0 then
    perform public.apply_liftr_coin_reward(
      p_user_id,
      v_base,
      'workout_logged',
      v_ref,
      v_event_at
    );
  end if;

  if coalesce(v_bonus, 0) > 0 then
    perform public.apply_liftr_coin_reward(
      p_user_id,
      v_bonus,
      'workout_pet_training_bonus',
      v_ref,
      v_event_at
    );

    v_instance_id := public.liftr_pet_active_instance_id(p_user_id);

    select coalesce(nullif(trim(pi.custom_name), ''), pt.display_name, pi.pet_type, 'Your pet')
    into v_pet_name
    from public.pet_instances pi
    left join public.pet_types pt on pt.name = pi.pet_type
    where pi.id = v_instance_id;

    v_message := public.pick_pet_workout_bonus_message(v_bonus, v_bonus_pct, v_pet_name);

    insert into public.pet_logs (
      user_id,
      pet_instance_id,
      event_type,
      details,
      created_at
    )
    values (
      p_user_id,
      v_instance_id,
      'workout_pet_bonus',
      jsonb_build_object(
        'coins', v_bonus::text,
        'bonus_pct', trim(to_char(v_bonus_pct, 'FM999990.##')),
        'base_coins', coalesce(v_base, 0)::text,
        'workout_id', p_workout_id::text,
        'message', v_message
      ),
      v_event_at
    );
  end if;
end;
$$;

create or replace function public.trg_coins_on_workout_publish()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
declare
  v_day date;
  v_event_at timestamptz;
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

  v_event_at := coalesce(new.ended_at, new.started_at, now());
  perform public.grant_workout_coin_rewards_v1(new.id, new.user_id, v_event_at);

  v_day := (v_event_at at time zone 'utc')::date;
  perform public.evaluate_workout_consistency_streak_coins(new.user_id, v_day);

  return new;
end;
$$;

revoke all on function public.pick_pet_workout_bonus_message(integer, numeric, text) from public;
revoke all on function public.grant_workout_coin_rewards_v1(bigint, uuid, timestamptz) from public;
revoke all on function public.pick_pet_workout_bonus_message(integer, numeric, text) from anon, authenticated;
revoke all on function public.grant_workout_coin_rewards_v1(bigint, uuid, timestamptz) from anon, authenticated;

commit;

begin;

insert into public.coin_reward_rules (action_type, amount, enabled) values
  ('nutrition_ingredient_logged', 3, true),
  ('nutrition_recipe_logged', 5, true),
  ('nutrition_ingredient_created', 10, true),
  ('nutrition_recipe_created', 15, true)
on conflict (action_type) do nothing;

create unique index if not exists coin_tx_once_nutrition_ingredient_logged
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'nutrition_ingredient_logged' and amount > 0;

create unique index if not exists coin_tx_once_nutrition_recipe_logged
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'nutrition_recipe_logged' and amount > 0;

create unique index if not exists coin_tx_once_nutrition_ingredient_created
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'nutrition_ingredient_created' and amount > 0;

create unique index if not exists coin_tx_once_nutrition_recipe_created
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'nutrition_recipe_created' and amount > 0;

create or replace function public.trg_coins_on_nutrition_diary_log()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if new.ingredient_id is not null then
    perform public.apply_liftr_coin_reward(
      new.user_id,
      public.get_coin_reward_amount('nutrition_ingredient_logged', 3),
      'nutrition_ingredient_logged',
      public.liftr_coin_ref_uuid(new.id)
    );
  elsif new.recipe_id is not null then
    perform public.apply_liftr_coin_reward(
      new.user_id,
      public.get_coin_reward_amount('nutrition_recipe_logged', 5),
      'nutrition_recipe_logged',
      public.liftr_coin_ref_uuid(new.id)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_coins_on_nutrition_diary_log on public.nutrition_diary_logs;
create trigger trg_coins_on_nutrition_diary_log
  after insert on public.nutrition_diary_logs
  for each row
  execute function public.trg_coins_on_nutrition_diary_log();

create or replace function public.trg_coins_on_nutrition_ingredient_created()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if new.user_id is null then
    return new;
  end if;

  perform public.apply_liftr_coin_reward(
    new.user_id,
    public.get_coin_reward_amount('nutrition_ingredient_created', 10),
    'nutrition_ingredient_created',
    public.liftr_coin_ref_uuid(new.id)
  );

  return new;
end;
$$;

drop trigger if exists trg_coins_on_nutrition_ingredient_created on public.nutrition_ingredients;
create trigger trg_coins_on_nutrition_ingredient_created
  after insert on public.nutrition_ingredients
  for each row
  execute function public.trg_coins_on_nutrition_ingredient_created();

create or replace function public.trg_coins_on_nutrition_recipe_created()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if new.user_id is null then
    return new;
  end if;

  perform public.apply_liftr_coin_reward(
    new.user_id,
    public.get_coin_reward_amount('nutrition_recipe_created', 15),
    'nutrition_recipe_created',
    public.liftr_coin_ref_uuid(new.id)
  );

  return new;
end;
$$;

drop trigger if exists trg_coins_on_nutrition_recipe_created on public.nutrition_recipes;
create trigger trg_coins_on_nutrition_recipe_created
  after insert on public.nutrition_recipes
  for each row
  execute function public.trg_coins_on_nutrition_recipe_created();

create or replace function public.backfill_nutrition_coin_rewards_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
begin
  for r in
    select
      l.id,
      l.user_id,
      l.ingredient_id,
      l.recipe_id,
      (l.log_date::timestamptz + interval '12 hours') as event_at
    from public.nutrition_diary_logs l
    order by l.log_date, l.id
  loop
    if r.ingredient_id is not null then
      perform public.apply_liftr_coin_reward(
        r.user_id,
        public.get_coin_reward_amount('nutrition_ingredient_logged', 3),
        'nutrition_ingredient_logged',
        public.liftr_coin_ref_uuid(r.id),
        r.event_at
      );
    elsif r.recipe_id is not null then
      perform public.apply_liftr_coin_reward(
        r.user_id,
        public.get_coin_reward_amount('nutrition_recipe_logged', 5),
        'nutrition_recipe_logged',
        public.liftr_coin_ref_uuid(r.id),
        r.event_at
      );
    end if;
  end loop;

  for r in
    select i.id, i.user_id
    from public.nutrition_ingredients i
    where i.user_id is not null
    order by i.id
  loop
    perform public.apply_liftr_coin_reward(
      r.user_id,
      public.get_coin_reward_amount('nutrition_ingredient_created', 10),
      'nutrition_ingredient_created',
      public.liftr_coin_ref_uuid(r.id)
    );
  end loop;

  for r in
    select nr.id, nr.user_id, coalesce(nr.created_at, now()) as event_at
    from public.nutrition_recipes nr
    where nr.user_id is not null
    order by nr.created_at, nr.id
  loop
    perform public.apply_liftr_coin_reward(
      r.user_id,
      public.get_coin_reward_amount('nutrition_recipe_created', 15),
      'nutrition_recipe_created',
      public.liftr_coin_ref_uuid(r.id),
      r.event_at
    );
  end loop;
end;
$$;

revoke all on function public.trg_coins_on_nutrition_diary_log() from public;
revoke all on function public.trg_coins_on_nutrition_diary_log() from anon, authenticated;

revoke all on function public.trg_coins_on_nutrition_ingredient_created() from public;
revoke all on function public.trg_coins_on_nutrition_ingredient_created() from anon, authenticated;

revoke all on function public.trg_coins_on_nutrition_recipe_created() from public;
revoke all on function public.trg_coins_on_nutrition_recipe_created() from anon, authenticated;

revoke all on function public.backfill_nutrition_coin_rewards_v1() from public;
revoke all on function public.backfill_nutrition_coin_rewards_v1() from anon, authenticated;

select public.backfill_nutrition_coin_rewards_v1();

commit;

begin;

create or replace function public.liftr_coin_source_key(p_action_type text)
returns text
language sql
immutable
as $$
  select case
    when p_action_type in (
      'workout_coin_doubling_v1',
      'workout_economy_rebalance_v1',
      'workout_economy_reduction_30pct_v1',
      'pet_passive_economy_rebalance_v1',
      'pet_passive_economy_reduction_30pct_v1'
    ) then null
    when p_action_type = 'workout_logged' then 'workouts'
    when p_action_type = 'workout_pet_training_bonus' then 'pet_workout_bonus'
    when p_action_type = 'pet_coins_generated' then 'pet_coins'
    when p_action_type in (
      'like_given',
      'comment_added',
      'user_followed',
      'earned_follower'
    ) then 'social'
    when p_action_type in (
      'nutrition_ingredient_logged',
      'nutrition_recipe_logged',
      'nutrition_ingredient_created',
      'nutrition_recipe_created'
    ) then 'nutrition'
    when p_action_type in (
      'achievement_unlocked',
      'achievement_unlocked_bronze',
      'achievement_unlocked_silver',
      'achievement_unlocked_gold'
    ) then 'achievements'
    when p_action_type in (
      'weekly_goal_perfect_week',
      'workout_consistency_streak'
    ) then 'goals_streaks'
    when p_action_type in (
      'competition_bet_win',
      'competition_bet_refund_draw',
      'competition_bet_refund_cancelled'
    ) then 'competition'
    when p_action_type = 'pet_combat_reward' then 'pet_combat'
    else 'other'
  end;
$$;

create or replace function public.get_my_coin_sources_v1(
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns table (
  source_key text,
  total_amount integer
)
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  return query
  select
    grouped.source_key,
    grouped.total_amount::integer
  from (
    select
      public.liftr_coin_source_key(ct.action_type) as source_key,
      sum(ct.amount) as total_amount
    from public.coin_transactions ct
    where ct.user_id = v_uid
      and ct.amount > 0
      and public.liftr_coin_source_key(ct.action_type) is not null
      and (
        p_start is null
        or p_end is null
        or (ct.created_at >= p_start and ct.created_at < p_end)
      )
    group by public.liftr_coin_source_key(ct.action_type)
  ) grouped
  where grouped.source_key is not null
    and grouped.total_amount > 0
  order by grouped.total_amount desc, grouped.source_key asc;
end;
$$;

revoke all on function public.liftr_coin_source_key(text) from public;
revoke all on function public.get_my_coin_sources_v1(timestamptz, timestamptz) from public;
revoke all on function public.get_my_coin_sources_v1(timestamptz, timestamptz) from anon;
grant execute on function public.get_my_coin_sources_v1(timestamptz, timestamptz) to authenticated;

commit;

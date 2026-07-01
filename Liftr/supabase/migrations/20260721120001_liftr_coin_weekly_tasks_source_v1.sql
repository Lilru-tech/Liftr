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
      'user_task_completed',
      'weekly_task_refresh'
    ) then 'weekly_tasks'
    when p_action_type in (
      'competition_bet_win',
      'competition_bet_refund_draw',
      'competition_bet_refund_cancelled'
    ) then 'competition'
    when p_action_type = 'pet_combat_reward' then 'pet_combat'
    else 'other'
  end;
$$;

commit;

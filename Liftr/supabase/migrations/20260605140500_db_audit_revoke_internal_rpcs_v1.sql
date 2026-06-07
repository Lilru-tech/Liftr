do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (
        p.proname like '\_%' escape '\'
        or p.proname like 'trg\_%' escape '\'
        or p.proname in (
          'body_weight_entries_after_change',
          'conversation_messages_broadcast_trigger',
          'enqueue_workout_inactivity_nudges',
          'handle_new_user',
          'notify_comment_mentions',
          'notify_goal_almost_done',
          'notify_goal_completed',
          'nutrition_meal_plan_targets_auto_accept_creator',
          'tr_fn_workout_sync_metabolism'
        )
      )
      and p.proname not like '\_st\_%' escape '\'
      and p.proname not like '\_postgis\_%' escape '\'
  loop
    execute format('revoke all on function %s from anon, authenticated', fn.signature);
  end loop;
end
$$;

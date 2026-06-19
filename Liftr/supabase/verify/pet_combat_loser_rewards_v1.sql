do $$
declare
  v_loser jsonb;
begin
  if to_regprocedure('public.liftr_combat_loser_rewards(jsonb)') is null then
    raise exception 'missing function liftr_combat_loser_rewards';
  end if;

  v_loser := public.liftr_combat_loser_rewards('{"xp":110,"coins":55}'::jsonb);
  if (v_loser->>'xp')::integer <> 27 or (v_loser->>'coins')::integer <> 13 then
    raise exception 'scaled loser rewards expected 27/13 got %/%', v_loser->>'xp', v_loser->>'coins';
  end if;

  v_loser := public.liftr_combat_loser_rewards('{"xp":10,"coins":5}'::jsonb);
  if (v_loser->>'xp')::integer <> 3 or (v_loser->>'coins')::integer <> 1 then
    raise exception 'minimum loser rewards expected 3/1 got %/%', v_loser->>'xp', v_loser->>'coins';
  end if;

  v_loser := public.liftr_combat_loser_rewards('{"xp":146,"coins":73}'::jsonb);
  if (v_loser->>'xp')::integer <> 36 or (v_loser->>'coins')::integer <> 18 then
    raise exception 'hardcore loser rewards expected 36/18 got %/%', v_loser->>'xp', v_loser->>'coins';
  end if;

  raise notice 'pet_combat_loser_rewards_v1 verify passed';
end;
$$;

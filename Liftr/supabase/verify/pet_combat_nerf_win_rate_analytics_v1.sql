with handicapped as (
  select
    h.id,
    h.created_at,
    h.winner_user_id,
    h.attacker_user_id,
    h.defender_user_id,
    h.battle_log->'stat_balancing'->>'applied_to' as applied_to,
    h.battle_log->'stat_balancing'->>'mode' as mode,
    h.battle_log->'stat_balancing'->>'pool_multiplier' as pool_multiplier,
    (
      (h.battle_log->'stat_balancing'->>'applied_to' = 'attacker' and h.winner_user_id = h.attacker_user_id)
      or (h.battle_log->'stat_balancing'->>'applied_to' = 'defender' and h.winner_user_id = h.defender_user_id)
    ) as nerfed_side_won
  from public.pet_combat_history h
  where h.is_handicapped = true
    and coalesce(h.battle_log->'stat_balancing'->>'mode', 'balanced') = 'balanced'
    and h.created_at >= now() - interval '30 days'
)
select
  count(*) as battles_30d,
  round(100.0 * count(*) filter (where nerfed_side_won) / nullif(count(*), 0), 1) as nerfed_side_win_pct,
  count(*) filter (where pool_multiplier = '1.05') as v2_battles,
  count(*) filter (where pool_multiplier = '1.07') as v1_battles,
  case
    when count(*) filter (where pool_multiplier = '1.05') >= 50
      and round(100.0 * count(*) filter (where pool_multiplier = '1.05' and nerfed_side_won)
        / nullif(count(*) filter (where pool_multiplier = '1.05'), 0), 1) between 45 and 55
    then 'PASS'
    when count(*) filter (where pool_multiplier = '1.05') < 50
    then 'INSUFFICIENT_SAMPLE'
    else 'FAIL'
  end as v2_calibration_status
from handicapped;

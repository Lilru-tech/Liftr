begin;

create or replace function public.compute_pet_level_stat_delta_v1(
  p_pet_type text,
  p_stage text,
  p_user_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to public
as $$
declare
  min_points integer;
  max_points integer;
  v_stat_mult numeric;
  total_weight integer;
  w_health integer;
  w_strength integer;
  w_defense integer;
  w_speed integer;
  w_intelligence integer;
  w_agility integer;
  w_stamina integer;
  w_critical_rate integer;
  w_resistance integer;
  w_exploration integer;
  w_happiness integer;
  stat_budget integer;
  jitter numeric;
  r_health integer;
  r_strength integer;
  r_defense integer;
  r_speed integer;
  r_intelligence integer;
  r_agility integer;
  r_stamina integer;
  r_critical_rate integer;
  r_resistance integer;
  r_exploration integer;
  r_happiness integer;
begin
  select stats_min_per_level, stats_max_per_level
  into min_points, max_points
  from public.pet_stage_rewards
  where lower(stage) = lower(coalesce(p_stage, 'baby'));

  if min_points is null or max_points is null then
    min_points := 5;
    max_points := 10;
  end if;

  v_stat_mult := public.get_pet_stat_multiplier(p_user_id);

  select
    health_weight, strength_weight, defense_weight, speed_weight, intelligence_weight,
    agility_weight, stamina_weight, critical_rate_weight, resistance_weight,
    exploration_weight, happiness_weight
  into
    w_health, w_strength, w_defense, w_speed, w_intelligence,
    w_agility, w_stamina, w_critical_rate, w_resistance,
    w_exploration, w_happiness
  from public.pet_type_stat_weights
  where pet_type = p_pet_type;

  if w_health is null then
    return '{}'::jsonb;
  end if;

  total_weight := w_health + w_strength + w_defense + w_speed + w_intelligence
    + w_agility + w_stamina + w_critical_rate + w_resistance
    + w_exploration + w_happiness;

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_health := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_health::numeric / total_weight) * jitter * 20)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_strength := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_strength::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_defense := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_defense::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_speed := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_speed::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_intelligence := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_intelligence::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_agility := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_agility::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_stamina := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_stamina::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_critical_rate := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_critical_rate::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_resistance := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_resistance::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_exploration := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_exploration::numeric / total_weight) * jitter)::integer);

  stat_budget := floor(random() * (max_points - min_points + 1))::integer + min_points;
  jitter := 0.5 + random();
  r_happiness := greatest(0, floor(stat_budget * coalesce(v_stat_mult, 1) * (w_happiness::numeric / total_weight) * jitter)::integer);

  return jsonb_build_object(
    'health', r_health,
    'strength', r_strength,
    'defense', r_defense,
    'speed', r_speed,
    'intelligence', r_intelligence,
    'agility', r_agility,
    'stamina', r_stamina,
    'critical_rate', r_critical_rate,
    'resistance', r_resistance,
    'exploration', r_exploration,
    'happiness', r_happiness
  );
end;
$$;

select public.backfill_pet_level_stat_variance_v1();

commit;

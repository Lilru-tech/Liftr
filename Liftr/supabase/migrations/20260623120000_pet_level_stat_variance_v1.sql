begin;

create or replace function public.resolve_pet_stage_at_time(
  p_pet_instance_id uuid,
  p_at timestamptz
)
returns text
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_stage text;
begin
  if p_pet_instance_id is null then
    return 'baby';
  end if;

  select pl.details->>'to_stage'
  into v_stage
  from public.pet_logs pl
  where pl.pet_instance_id = p_pet_instance_id
    and pl.event_type = 'evolution'
    and pl.created_at <= coalesce(p_at, now())
  order by pl.created_at desc
  limit 1;

  if v_stage is not null and v_stage <> '' then
    return lower(v_stage);
  end if;

  return 'baby';
end;
$$;

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

create or replace function public.apply_pet_stat_delta_v1(
  p_pet_instance_id uuid,
  p_delta jsonb
)
returns void
language plpgsql
security definer
set search_path to public
as $$
begin
  if p_pet_instance_id is null or p_delta is null then
    return;
  end if;

  insert into public.pet_instance_stats (pet_instance_id)
  values (p_pet_instance_id)
  on conflict (pet_instance_id) do nothing;

  update public.pet_instance_stats
  set
    health = coalesce(health, 0) + coalesce((p_delta ->> 'health')::integer, 0),
    strength = coalesce(strength, 0) + coalesce((p_delta ->> 'strength')::integer, 0),
    defense = coalesce(defense, 0) + coalesce((p_delta ->> 'defense')::integer, 0),
    speed = coalesce(speed, 0) + coalesce((p_delta ->> 'speed')::integer, 0),
    intelligence = coalesce(intelligence, 0) + coalesce((p_delta ->> 'intelligence')::integer, 0),
    agility = coalesce(agility, 0) + coalesce((p_delta ->> 'agility')::integer, 0),
    stamina = coalesce(stamina, 0) + coalesce((p_delta ->> 'stamina')::integer, 0),
    critical_rate = coalesce(critical_rate, 0) + coalesce((p_delta ->> 'critical_rate')::integer, 0),
    resistance = coalesce(resistance, 0) + coalesce((p_delta ->> 'resistance')::integer, 0),
    exploration = coalesce(exploration, 0) + coalesce((p_delta ->> 'exploration')::integer, 0),
    happiness = coalesce(happiness, 0) + coalesce((p_delta ->> 'happiness')::integer, 0)
  where pet_instance_id = p_pet_instance_id;
end;
$$;

create or replace function public.distribute_pet_stats(p_pet_instance_id uuid, p_level_up boolean default true)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  p_type text;
  p_stage text;
  v_user_id uuid;
  new_level integer;
  v_delta jsonb;
begin
  select pi.pet_type, pi.evolution_stage, pi.user_id
  into p_type, p_stage, v_user_id
  from public.pet_instances pi
  where pi.id = p_pet_instance_id;

  if p_type is null then
    return;
  end if;

  v_delta := public.compute_pet_level_stat_delta_v1(p_type, p_stage, v_user_id);
  perform public.apply_pet_stat_delta_v1(p_pet_instance_id, v_delta);

  if p_level_up then
    update public.pet_instances
    set current_level = current_level + 1,
        updated_at = now()
    where id = p_pet_instance_id
    returning current_level into new_level;

    insert into public.pet_logs (user_id, pet_instance_id, event_type, new_level, stats_delta)
    values (
      v_user_id,
      p_pet_instance_id,
      'level_up',
      new_level,
      v_delta
    );
  end if;
end;
$$;

create or replace function public.backfill_pet_level_stat_variance_v1()
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  pet record;
  log record;
  v_stage text;
  v_delta jsonb;
  v_hatch_health integer;
  v_hatch_strength integer;
  v_hatch_defense integer;
  v_hatch_speed integer;
  v_hatch_intelligence integer;
  v_hatch_agility integer;
  v_hatch_stamina integer;
  v_hatch_critical_rate integer;
  v_hatch_resistance integer;
  v_hatch_exploration integer;
  v_hatch_happiness integer;
  v_total_health integer := 0;
  v_total_strength integer := 0;
  v_total_defense integer := 0;
  v_total_speed integer := 0;
  v_total_intelligence integer := 0;
  v_total_agility integer := 0;
  v_total_stamina integer := 0;
  v_total_critical_rate integer := 0;
  v_total_resistance integer := 0;
  v_total_exploration integer := 0;
  v_total_happiness integer := 0;
begin
  for pet in
    select distinct pi.id, pi.pet_type, pi.user_id
    from public.pet_instances pi
    join public.pet_logs pl on pl.pet_instance_id = pi.id
    where pl.event_type = 'level_up'
      and lower(pi.evolution_stage) <> 'egg'
  loop
    select
      coalesce(ps.health, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'health')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.strength, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'strength')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.defense, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'defense')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.speed, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'speed')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.intelligence, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'intelligence')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.agility, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'agility')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.stamina, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'stamina')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.critical_rate, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'critical_rate')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.resistance, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'resistance')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.exploration, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'exploration')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0),
      coalesce(ps.happiness, 0)
        - coalesce((
          select sum(coalesce((pl.stats_delta ->> 'happiness')::integer, 0))
          from public.pet_logs pl
          where pl.pet_instance_id = pet.id
            and pl.event_type = 'level_up'
        ), 0)
    into
      v_hatch_health,
      v_hatch_strength,
      v_hatch_defense,
      v_hatch_speed,
      v_hatch_intelligence,
      v_hatch_agility,
      v_hatch_stamina,
      v_hatch_critical_rate,
      v_hatch_resistance,
      v_hatch_exploration,
      v_hatch_happiness
    from public.pet_instance_stats ps
    where ps.pet_instance_id = pet.id;

    v_total_health := 0;
    v_total_strength := 0;
    v_total_defense := 0;
    v_total_speed := 0;
    v_total_intelligence := 0;
    v_total_agility := 0;
    v_total_stamina := 0;
    v_total_critical_rate := 0;
    v_total_resistance := 0;
    v_total_exploration := 0;
    v_total_happiness := 0;

    for log in
      select pl.id, pl.created_at, pl.new_level
      from public.pet_logs pl
      where pl.pet_instance_id = pet.id
        and pl.event_type = 'level_up'
      order by pl.new_level nulls last, pl.created_at, pl.id
    loop
      v_stage := public.resolve_pet_stage_at_time(pet.id, log.created_at);
      v_delta := public.compute_pet_level_stat_delta_v1(pet.pet_type, v_stage, pet.user_id);

      update public.pet_logs
      set stats_delta = v_delta
      where id = log.id;

      v_total_health := v_total_health + coalesce((v_delta ->> 'health')::integer, 0);
      v_total_strength := v_total_strength + coalesce((v_delta ->> 'strength')::integer, 0);
      v_total_defense := v_total_defense + coalesce((v_delta ->> 'defense')::integer, 0);
      v_total_speed := v_total_speed + coalesce((v_delta ->> 'speed')::integer, 0);
      v_total_intelligence := v_total_intelligence + coalesce((v_delta ->> 'intelligence')::integer, 0);
      v_total_agility := v_total_agility + coalesce((v_delta ->> 'agility')::integer, 0);
      v_total_stamina := v_total_stamina + coalesce((v_delta ->> 'stamina')::integer, 0);
      v_total_critical_rate := v_total_critical_rate + coalesce((v_delta ->> 'critical_rate')::integer, 0);
      v_total_resistance := v_total_resistance + coalesce((v_delta ->> 'resistance')::integer, 0);
      v_total_exploration := v_total_exploration + coalesce((v_delta ->> 'exploration')::integer, 0);
      v_total_happiness := v_total_happiness + coalesce((v_delta ->> 'happiness')::integer, 0);
    end loop;

    insert into public.pet_instance_stats (pet_instance_id)
    values (pet.id)
    on conflict (pet_instance_id) do nothing;

    update public.pet_instance_stats
    set
      health = greatest(0, coalesce(v_hatch_health, 0) + v_total_health),
      strength = greatest(0, coalesce(v_hatch_strength, 0) + v_total_strength),
      defense = greatest(0, coalesce(v_hatch_defense, 0) + v_total_defense),
      speed = greatest(0, coalesce(v_hatch_speed, 0) + v_total_speed),
      intelligence = greatest(0, coalesce(v_hatch_intelligence, 0) + v_total_intelligence),
      agility = greatest(0, coalesce(v_hatch_agility, 0) + v_total_agility),
      stamina = greatest(0, coalesce(v_hatch_stamina, 0) + v_total_stamina),
      critical_rate = greatest(0, coalesce(v_hatch_critical_rate, 0) + v_total_critical_rate),
      resistance = greatest(0, coalesce(v_hatch_resistance, 0) + v_total_resistance),
      exploration = greatest(0, coalesce(v_hatch_exploration, 0) + v_total_exploration),
      happiness = greatest(0, coalesce(v_hatch_happiness, 0) + v_total_happiness)
    where pet_instance_id = pet.id;
  end loop;
end;
$$;

revoke all on function public.resolve_pet_stage_at_time(uuid, timestamptz) from public;
revoke all on function public.compute_pet_level_stat_delta_v1(text, text, uuid) from public;
revoke all on function public.apply_pet_stat_delta_v1(uuid, jsonb) from public;
revoke all on function public.backfill_pet_level_stat_variance_v1() from public;

revoke all on function public.resolve_pet_stage_at_time(uuid, timestamptz) from anon, authenticated;
revoke all on function public.compute_pet_level_stat_delta_v1(text, text, uuid) from anon, authenticated;
revoke all on function public.apply_pet_stat_delta_v1(uuid, jsonb) from anon, authenticated;
revoke all on function public.backfill_pet_level_stat_variance_v1() from anon, authenticated;

select public.backfill_pet_level_stat_variance_v1();

commit;

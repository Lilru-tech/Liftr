update public.task_templates set
  title_template = 'Log a {value} km run',
  description_template = 'Complete a run of at least {value} km this week.',
  base_reward_coins = 18
where code = 'cardio_run_distance_beginner';

update public.task_templates set
  title_template = 'Push your distance: {value} km',
  description_template = 'Log a single run of at least {value} km.',
  base_reward_coins = 35
where code = 'cardio_run_distance_stretch';

update public.task_templates set
  title_template = 'Hold a {value} min/km pace',
  description_template = 'Run at least {secondary} km at {value} min/km or faster.',
  base_reward_coins = 40
where code = 'cardio_run_pace_stretch';

update public.task_templates set
  title_template = 'Walk {value} km',
  description_template = 'Log a walk of at least {value} km.',
  base_reward_coins = 16
where code = 'cardio_walk_distance_beginner';

update public.task_templates set
  title_template = '{value} min strength session',
  description_template = 'Complete a strength workout of at least {value} minutes.',
  base_reward_coins = 18
where code = 'strength_session_duration_beginner';

update public.task_templates set
  title_template = 'Lift {value} kg',
  description_template = 'Hit at least {value} kg on one set during a strength workout.',
  base_reward_coins = 38
where code = 'strength_max_weight_stretch';

update public.task_templates set
  title_template = 'Total volume: {value} kg',
  description_template = 'Accumulate at least {value} kg of volume in one strength session.',
  base_reward_coins = 35
where code = 'strength_volume_stretch';

update public.task_templates set
  title_template = 'Chest volume: {value} kg',
  description_template = 'Accumulate at least {value} kg of chest volume in one session.',
  base_reward_coins = 32
where code = 'strength_chest_volume_stretch';

update public.task_templates set
  title_template = 'Play {value} min of padel',
  description_template = 'Log a padel session of at least {value} minutes.',
  base_reward_coins = 18
where code = 'sport_racket_duration_beginner';

update public.task_templates set
  title_template = 'Play {value} min of football',
  description_template = 'Log a football session of at least {value} minutes.',
  base_reward_coins = 18
where code = 'sport_football_duration_beginner';

update public.task_templates set
  title_template = 'Rack up {value} min playing',
  description_template = 'Accumulate {value} minutes of sport activity this week.',
  base_reward_coins = 32
where code = 'sport_weekly_minutes_stretch';

update public.task_templates set
  title_template = 'Rack up {value} min of football',
  description_template = 'Accumulate {value} minutes playing football this week.',
  base_reward_coins = 32
where code = 'sport_football_weekly_stretch';

update public.task_templates set
  title_template = 'Burn {value} kcal in cardio',
  description_template = 'Log a cardio session of at least {value} kcal.',
  base_reward_coins = 28
where code = 'cardio_calories_stretch';

update public.task_templates set
  title_template = 'Burn {value} kcal in strength',
  description_template = 'Complete a strength workout of at least {value} kcal.',
  base_reward_coins = 28
where code = 'strength_calories_stretch';

update public.task_templates set
  title_template = 'Rack up {value} min of padel',
  description_template = 'Accumulate {value} minutes playing padel this week.',
  base_reward_coins = 32
where code = 'sport_racket_weekly_stretch';

create or replace function public._user_tasks_count_category_workouts(
  p_user_id uuid,
  p_category text,
  p_since timestamptz
)
returns int
language sql
stable
security definer
set search_path to public
as $$
  select count(*)::int
  from public.workouts w
  where w.user_id = p_user_id
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= p_since
    and (
      (p_category = 'cardio' and w.kind = 'cardio'::public.workout_kind)
      or (p_category = 'strength' and w.kind = 'strength'::public.workout_kind)
      or (p_category = 'sport' and w.kind = 'sport'::public.workout_kind)
    );
$$;

create or replace function public._user_tasks_dominant_cardio_activity(
  p_user_id uuid,
  p_since timestamptz
)
returns text
language sql
stable
security definer
set search_path to public
as $$
  select coalesce(
    (
      select coalesce(cs.activity_code, cs.modality)
      from public.workouts w
      join public.cardio_sessions cs on cs.workout_id = w.id
      where w.user_id = p_user_id
        and w.kind = 'cardio'::public.workout_kind
        and w.state = 'published'::public.workout_state
        and coalesce(w.started_at, w.created_at) >= p_since
      group by coalesce(cs.activity_code, cs.modality)
      order by count(*) desc
      limit 1
    ),
    'run'
  );
$$;

create or replace function public._user_tasks_dominant_sport(
  p_user_id uuid,
  p_since timestamptz
)
returns text
language sql
stable
security definer
set search_path to public
as $$
  select coalesce(
    (
      select ss.sport
      from public.workouts w
      join public.sport_sessions ss on ss.workout_id = w.id
      where w.user_id = p_user_id
        and w.kind = 'sport'::public.workout_kind
        and w.state = 'published'::public.workout_state
        and coalesce(w.started_at, w.created_at) >= p_since
      group by ss.sport
      order by count(*) desc
      limit 1
    ),
  'football'
  );
$$;

create or replace function public._user_tasks_dominant_muscle(
  p_user_id uuid,
  p_since timestamptz
)
returns text
language sql
stable
security definer
set search_path to public
as $$
  select coalesce(
    (
      select e.muscle_primary
      from public.workouts w
      join public.workout_exercises we on we.workout_id = w.id
      join public.exercises e on e.id = we.exercise_id
      where w.user_id = p_user_id
        and w.kind = 'strength'::public.workout_kind
        and w.state = 'published'::public.workout_state
        and coalesce(w.started_at, w.created_at) >= p_since
        and e.muscle_primary is not null
      group by e.muscle_primary
      order by count(*) desc
      limit 1
    ),
    null
  );
$$;

create or replace function public._user_tasks_pick_dynamic_template(
  p_user_id uuid,
  p_category text,
  p_exclude_ids int[],
  p_since timestamptz
)
returns public.task_templates
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_cardio text;
  v_sport text;
  v_muscle text;
  v_template public.task_templates;
begin
  v_cardio := public._user_tasks_dominant_cardio_activity(p_user_id, p_since);
  v_sport := public._user_tasks_dominant_sport(p_user_id, p_since);
  v_muscle := public._user_tasks_dominant_muscle(p_user_id, p_since);

  select t.* into v_template
  from public.task_templates t
  where t.is_active
    and t.category = p_category
    and t.generation_mode = 'dynamic_scaled'
    and (p_exclude_ids is null or not (t.id = any (p_exclude_ids)))
  order by
    case
      when p_category = 'cardio' and t.scope_activity_code = v_cardio then 0
      when p_category = 'sport' and t.scope_sport = v_sport then 0
      when p_category = 'strength' and t.scope_muscle_primary is not null
        and (t.scope_muscle_primary = v_muscle
          or t.scope_muscle_primary = replace(coalesce(v_muscle, ''), 'chest', 'pecho')
          or replace(t.scope_muscle_primary, 'pecho', 'chest') = v_muscle) then 0
      when t.scope_activity_code is null and t.scope_sport is null and t.scope_muscle_primary is null then 1
      else 2
    end,
    random()
  limit 1;

  if v_template.id is null then
    select t.* into v_template
    from public.task_templates t
    where t.is_active
      and t.category = p_category
      and t.generation_mode = 'dynamic_scaled'
      and (p_exclude_ids is null or not (t.id = any (p_exclude_ids)))
    order by random()
    limit 1;
  end if;

  return v_template;
end;
$$;

create or replace function public._user_tasks_weighted_category_slots(
  p_user_id uuid,
  p_slots int
)
returns text[]
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_since timestamptz := now() - interval '45 days';
  v_result text[] := array[]::text[];
  v_row record;
  v_i int;
  v_default text[] := array['cardio', 'strength', 'sport', 'cardio', 'strength'];
begin
  for v_row in
    select cat, cnt
    from (
      select 'cardio'::text as cat, public._user_tasks_count_category_workouts(p_user_id, 'cardio', v_since) as cnt
      union all
      select 'strength', public._user_tasks_count_category_workouts(p_user_id, 'strength', v_since)
      union all
      select 'sport', public._user_tasks_count_category_workouts(p_user_id, 'sport', v_since)
    ) x
    where cnt > 0
    order by cnt desc, cat
  loop
    for v_i in 1..greatest(1, least(v_row.cnt, 3)) loop
      v_result := array_append(v_result, v_row.cat);
    end loop;
  end loop;

  if coalesce(array_length(v_result, 1), 0) = 0 then
    return v_default[1:least(p_slots, array_length(v_default, 1))];
  end if;

  while coalesce(array_length(v_result, 1), 0) < p_slots loop
    v_result := array_append(v_result, v_result[1 + floor(random() * array_length(v_result, 1))::int]);
  end loop;

  return v_result[1:p_slots];
end;
$$;

create or replace function public._user_tasks_generate_for_category(
  p_user_id uuid,
  p_category text,
  p_week_start timestamptz,
  p_week_end timestamptz,
  p_exclude_ids int[]
)
returns int[]
language plpgsql
security definer
set search_path to public
as $$
declare
  v_since_45 timestamptz := now() - interval '45 days';
  v_since_30 timestamptz := now() - interval '30 days';
  v_template public.task_templates;
  v_cat_count int;
  v_target numeric;
  v_secondary numeric;
  v_cardio record;
  v_strength record;
  v_sport record;
  v_used int[] := coalesce(p_exclude_ids, array[]::int[]);
begin
  v_cat_count := public._user_tasks_count_category_workouts(p_user_id, p_category, v_since_45);

  if v_cat_count < 3 then
    v_template := public._user_tasks_pick_template(p_category, 'static_beginner', v_used);
    if v_template.id is null then
      return v_used;
    end if;
    v_target := case v_template.target_metric
      when 'distance_km' then 3
      when 'duration_sec' then 2700
      when 'sport_weekly_minutes' then 60
      else 3
    end;
    v_secondary := null;
  else
    v_template := public._user_tasks_pick_dynamic_template(p_user_id, p_category, v_used, v_since_45);
    if v_template.id is null then
      v_template := public._user_tasks_pick_template(p_category, 'static_beginner', v_used);
      if v_template.id is null then
        return v_used;
      end if;
      v_target := case v_template.target_metric
        when 'distance_km' then 3
        when 'duration_sec' then 2700
        when 'sport_weekly_minutes' then 60
        else 3
      end;
      v_secondary := null;
    else
      if p_category = 'cardio' then
        select * into v_cardio
        from public._user_tasks_hist_cardio_stats(p_user_id, v_template.scope_activity_code, v_since_30);
        v_target := case v_template.target_metric
          when 'distance_km' then greatest(1, round(greatest(v_cardio.avg_distance_km * 1.15, v_cardio.max_distance_km * 1.05), 1))
          when 'pace_sec_per_km' then greatest(180, round(v_cardio.avg_pace_sec_per_km * 0.95))
          when 'calories_kcal' then greatest(150, round(v_cardio.avg_calories * 1.1))
          else greatest(3, round(v_cardio.avg_distance_km * 1.15, 1))
        end;
        v_secondary := case
          when v_template.target_metric = 'pace_sec_per_km'
            then greatest(3, round(v_cardio.avg_distance_km * 0.8, 1))
          else null
        end;
      elsif p_category = 'strength' then
        select * into v_strength
        from public._user_tasks_hist_strength_stats(p_user_id, v_template.scope_muscle_primary, v_since_30);
        v_target := case v_template.target_metric
          when 'max_weight_kg' then greatest(20, round(v_strength.max_weight_kg * 1.05, 1))
          when 'volume_kg' then greatest(500, round(v_strength.avg_session_volume_kg * 1.15, 0))
          when 'calories_kcal' then greatest(150, round(v_strength.avg_calories * 1.1))
          when 'duration_sec' then greatest(1800, round(2700 * 1.0))
          else greatest(500, round(v_strength.avg_session_volume_kg * 1.1))
        end;
        v_secondary := null;
      else
        select * into v_sport
        from public._user_tasks_hist_sport_stats(p_user_id, v_template.scope_sport, v_since_30);
        v_target := case v_template.target_metric
          when 'sport_weekly_minutes' then greatest(30, round(v_sport.avg_weekly_minutes * 1.5, 0))
          when 'duration_sec' then greatest(1800, round(v_sport.avg_session_minutes * 60 * 1.1))
          else greatest(30, round(v_sport.avg_weekly_minutes * 1.5, 0))
        end;
        v_secondary := null;
      end if;
    end if;
  end if;

  perform public._user_tasks_insert_from_template(
    p_user_id, v_template, p_week_start, p_week_end, v_target, v_secondary
  );
  v_used := array_append(v_used, v_template.id);
  return v_used;
end;
$$;

create or replace function public._user_tasks_generate_batch(
  p_user_id uuid,
  p_week_start timestamptz,
  p_week_end timestamptz
)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_categories text[];
  v_cat text;
  v_used int[] := array[]::int[];
  v_i int;
begin
  v_categories := public._user_tasks_weighted_category_slots(p_user_id, 5);

  foreach v_cat in array v_categories loop
    v_used := public._user_tasks_generate_for_category(
      p_user_id, v_cat, p_week_start, p_week_end, v_used
    );
  end loop;

  for v_i in 1..10 loop
    exit when (select count(*) from public.user_tasks ut
      where ut.user_id = p_user_id and ut.week_start = p_week_start and ut.status <> 'expired') >= 5;
    v_used := public._user_tasks_generate_for_category(
      p_user_id,
      v_categories[1 + floor(random() * array_length(v_categories, 1))::int],
      p_week_start,
      p_week_end,
      v_used
    );
  end loop;
end;
$$;

create or replace function public._user_tasks_top_up_batch(
  p_user_id uuid,
  p_week_start timestamptz,
  p_week_end timestamptz
)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_categories text[];
  v_used int[] := array[]::int[];
  v_existing int;
  v_i int;
  v_cat text;
begin
  select coalesce(array_agg(ut.template_id), array[]::int[]) into v_used
  from public.user_tasks ut
  where ut.user_id = p_user_id
    and ut.week_start = p_week_start
    and ut.status in ('generated', 'accepted', 'completed');

  v_categories := public._user_tasks_weighted_category_slots(p_user_id, 5);

  for v_i in 1..10 loop
    select count(*) into v_existing
    from public.user_tasks ut
    where ut.user_id = p_user_id
      and ut.week_start = p_week_start
      and ut.status in ('generated', 'accepted', 'completed');
    exit when v_existing >= 5;

    v_cat := v_categories[1 + floor(random() * array_length(v_categories, 1))::int];
    v_used := public._user_tasks_generate_for_category(
      p_user_id, v_cat, p_week_start, p_week_end, v_used
    );
  end loop;
end;
$$;

create or replace function public._user_tasks_ensure_weekly_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  ws timestamptz;
  we timestamptz;
  v_existing int;
begin
  if p_user_id is null then
    return;
  end if;

  select b.w_start, b.w_end into ws, we
  from public._challenge_week_bounds_utc(now()) as b;

  update public.user_tasks ut
  set status = 'expired'
  where ut.user_id = p_user_id
    and ut.status in ('generated', 'accepted')
    and ut.expires_at <= now();

  select count(*) into v_existing
  from public.user_tasks ut
  where ut.user_id = p_user_id
    and ut.week_start = ws
    and ut.status in ('generated', 'accepted', 'completed');

  if v_existing = 0 then
    perform public._user_tasks_generate_batch(p_user_id, ws, we);
  elsif v_existing < 5 then
    perform public._user_tasks_top_up_batch(p_user_id, ws, we);
  end if;
end;
$$;

delete from public.user_tasks ut
where ut.status = 'generated'
  and ut.week_start = (
    select b.w_start from public._challenge_week_bounds_utc(now()) as b
  );

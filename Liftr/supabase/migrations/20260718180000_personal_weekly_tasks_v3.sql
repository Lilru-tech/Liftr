alter table public.user_tasks
  add column if not exists difficulty_band text
    check (difficulty_band is null or difficulty_band in ('easy', 'medium', 'hard', 'extreme'));

create table if not exists public.user_weekly_task_refreshes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  week_start timestamptz not null,
  refresh_count int not null default 0,
  unique (user_id, week_start)
);

alter table public.user_weekly_task_refreshes enable row level security;

drop policy if exists user_weekly_task_refreshes_select_own on public.user_weekly_task_refreshes;
create policy user_weekly_task_refreshes_select_own
  on public.user_weekly_task_refreshes for select to authenticated
  using (user_id = auth.uid());

revoke insert, update, delete on public.user_weekly_task_refreshes from anon, authenticated;

update public.task_templates set base_reward_coins = base_reward_coins * 3;

insert into public.coin_reward_rules (action_type, amount, enabled) values
  ('weekly_task_refresh', 0, true)
on conflict (action_type) do nothing;

create unique index if not exists coin_tx_once_weekly_task_refresh
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'weekly_task_refresh';

create or replace function public._user_tasks_tier_multiplier(p_tier text)
returns numeric
language sql
immutable
as $$
  select case coalesce(p_tier, 'standard')
    when 'beginner' then 0.8
    when 'stretch' then 1.3
    else 1.0
  end;
$$;

create or replace function public._user_tasks_format_value(
  p_metric text,
  p_value numeric,
  p_secondary numeric default null
)
returns text
language plpgsql
stable
as $$
begin
  if p_metric = 'pace_sec_per_km' then
    return to_char(floor(p_value / 60), 'FM999') || ':'
      || lpad(to_char(floor(mod(p_value, 60)), 'FM00'), 2, '0');
  elsif p_metric = 'duration_sec' then
    return to_char(round(p_value / 60.0), 'FM999');
  elsif p_metric = 'sport_weekly_minutes' then
    return trim(to_char(round(p_value), 'FM999999'));
  elsif p_metric in ('distance_km', 'volume_kg', 'max_weight_kg') then
    return trim(to_char(p_value, 'FM9999990.0'));
  else
    return trim(to_char(round(p_value), 'FM999999'));
  end if;
end;
$$;

create or replace function public._user_tasks_template_scope_sample_count(
  p_user_id uuid,
  p_template public.task_templates,
  p_since timestamptz
)
returns int
language sql
stable
security definer
set search_path to public
as $$
  select public._user_tasks_count_subcategory_workouts(
    p_user_id,
    p_template.category,
    p_template.scope_activity_code,
    p_template.scope_sport,
    p_template.scope_muscle_primary,
    p_since
  );
$$;

create or replace function public._user_tasks_pace_sample_count(
  p_user_id uuid,
  p_activity_code text,
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
  join public.cardio_sessions cs on cs.workout_id = w.id
  where w.user_id = p_user_id
    and w.kind = 'cardio'::public.workout_kind
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= p_since
    and cs.avg_pace_sec_per_km is not null
    and cs.avg_pace_sec_per_km > 0
    and (
      p_activity_code is null
      or cs.activity_code = p_activity_code
      or cs.modality = p_activity_code
    );
$$;

create or replace function public._user_tasks_hist_cardio_best_pace(
  p_user_id uuid,
  p_activity_code text,
  p_since timestamptz
)
returns numeric
language sql
stable
security definer
set search_path to public
as $$
  select coalesce(
    min(cs.avg_pace_sec_per_km),
    0
  )
  from public.workouts w
  join public.cardio_sessions cs on cs.workout_id = w.id
  where w.user_id = p_user_id
    and w.kind = 'cardio'::public.workout_kind
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= p_since
    and cs.avg_pace_sec_per_km is not null
    and cs.avg_pace_sec_per_km > 0
    and (
      p_activity_code is null
      or cs.activity_code = p_activity_code
      or cs.modality = p_activity_code
    );
$$;

create or replace function public._user_tasks_hist_cardio_median_distance(
  p_user_id uuid,
  p_activity_code text,
  p_since timestamptz
)
returns numeric
language sql
stable
security definer
set search_path to public
as $$
  select coalesce(
    percentile_cont(0.5) within group (order by cs.distance_km),
    0
  )
  from public.workouts w
  join public.cardio_sessions cs on cs.workout_id = w.id
  where w.user_id = p_user_id
    and w.kind = 'cardio'::public.workout_kind
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= p_since
    and cs.distance_km is not null
    and cs.distance_km > 0
    and (
      p_activity_code is null
      or cs.activity_code = p_activity_code
      or cs.modality = p_activity_code
    );
$$;

create or replace function public._user_tasks_template_is_eligible(
  p_user_id uuid,
  p_template public.task_templates,
  p_since timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_scoped int;
  v_has_scope boolean;
begin
  v_has_scope := p_template.scope_activity_code is not null
    or p_template.scope_sport is not null
    or p_template.scope_muscle_primary is not null;

  if not v_has_scope then
    if p_template.target_metric = 'pace_sec_per_km' then
      return public._user_tasks_pace_sample_count(p_user_id, null, p_since) >= 3;
    end if;
    return true;
  end if;

  v_scoped := public._user_tasks_template_scope_sample_count(p_user_id, p_template, p_since);
  if v_scoped < 3 then
    return false;
  end if;

  if p_template.target_metric = 'pace_sec_per_km' then
    return public._user_tasks_pace_sample_count(p_user_id, p_template.scope_activity_code, p_since) >= 3;
  end if;

  return true;
end;
$$;

create or replace function public._user_tasks_difficulty_band(
  p_metric text,
  p_target numeric,
  p_baseline numeric,
  p_secondary_baseline numeric default null
)
returns table (band text, multiplier numeric)
language plpgsql
stable
as $$
declare
  v_ratio numeric;
begin
  if p_baseline is null or p_baseline <= 0 or p_target is null or p_target <= 0 then
    return query select 'medium'::text, 1.0::numeric;
    return;
  end if;

  if p_metric = 'pace_sec_per_km' then
    v_ratio := p_target / p_baseline;
    if v_ratio >= 0.98 then
      return query select 'easy', 0.7;
    elsif v_ratio >= 0.90 then
      return query select 'medium', 1.0;
    elsif v_ratio >= 0.80 then
      return query select 'hard', 1.5;
    else
      return query select 'extreme', 2.5;
    end if;
  elsif p_metric in ('distance_km', 'volume_kg', 'max_weight_kg', 'calories_kcal') then
    v_ratio := p_target / p_baseline;
    if v_ratio <= 1.05 then
      return query select 'easy', 0.7;
    elsif v_ratio <= 1.15 then
      return query select 'medium', 1.0;
    elsif v_ratio <= 1.30 then
      return query select 'hard', 1.5;
    else
      return query select 'extreme', 2.5;
    end if;
  elsif p_metric in ('sport_weekly_minutes', 'duration_sec') then
    v_ratio := p_target / p_baseline;
    if v_ratio <= 1.10 then
      return query select 'easy', 0.7;
    elsif v_ratio <= 1.40 then
      return query select 'medium', 1.0;
    elsif v_ratio <= 1.80 then
      return query select 'hard', 1.5;
    else
      return query select 'extreme', 2.5;
    end if;
  else
    return query select 'medium'::text, 1.0::numeric;
  end if;
end;
$$;

create or replace function public._user_tasks_scaled_rewards(
  p_template public.task_templates,
  p_difficulty_multiplier numeric default 1.0
)
returns table (reward_xp int, reward_coins int, reward_task_points int)
language sql
stable
as $$
  select
    greatest(1, round(
      p_template.base_reward_xp
      * public._user_tasks_tier_multiplier(p_template.difficulty_tier)
      * coalesce(p_difficulty_multiplier, 1.0)
    ))::int,
    greatest(1, round(
      p_template.base_reward_coins
      * public._user_tasks_tier_multiplier(p_template.difficulty_tier)
      * coalesce(p_difficulty_multiplier, 1.0)
    ))::int,
    greatest(1, round(
      p_template.base_reward_task_points
      * public._user_tasks_tier_multiplier(p_template.difficulty_tier)
      * coalesce(p_difficulty_multiplier, 1.0)
    ))::int;
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
    and public._user_tasks_template_is_eligible(p_user_id, t, p_since)
  order by
    case
      when t.scope_activity_code is null and t.scope_sport is null and t.scope_muscle_primary is null then 0
      when p_category = 'cardio'
        and public._user_tasks_template_scope_sample_count(p_user_id, t, p_since) >= 3
        and t.scope_activity_code = v_cardio then 1
      when p_category = 'sport'
        and public._user_tasks_template_scope_sample_count(p_user_id, t, p_since) >= 3
        and t.scope_sport = v_sport then 1
      when p_category = 'strength'
        and public._user_tasks_template_scope_sample_count(p_user_id, t, p_since) >= 3
        and t.scope_muscle_primary is not null
        and (t.scope_muscle_primary = v_muscle
          or replace(t.scope_muscle_primary, 'pecho', 'chest') = v_muscle) then 1
      else 2
    end,
    random()
  limit 1;

  return v_template;
end;
$$;

create or replace function public._user_tasks_insert_from_template(
  p_user_id uuid,
  p_template public.task_templates,
  p_week_start timestamptz,
  p_week_end timestamptz,
  p_target_value numeric,
  p_target_secondary numeric default null,
  p_difficulty_band text default 'medium',
  p_difficulty_multiplier numeric default 1.0
)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_rewards record;
begin
  select * into v_rewards
  from public._user_tasks_scaled_rewards(p_template, p_difficulty_multiplier);

  insert into public.user_tasks (
    user_id, template_id, week_start, title, description,
    category, target_metric, target_value, target_secondary,
    scope_activity_code, scope_sport, scope_muscle_primary,
    reward_xp, reward_coins, reward_task_points,
    difficulty_band,
    status, generated_at, expires_at
  )
  values (
    p_user_id,
    p_template.id,
    p_week_start,
    public._user_tasks_render_copy(p_template.title_template, p_template.target_metric, p_target_value, p_target_secondary),
    public._user_tasks_render_copy(p_template.description_template, p_template.target_metric, p_target_value, p_target_secondary),
    p_template.category,
    p_template.target_metric,
    p_target_value,
    p_target_secondary,
    p_template.scope_activity_code,
    p_template.scope_sport,
    p_template.scope_muscle_primary,
    v_rewards.reward_xp,
    v_rewards.reward_coins,
    v_rewards.reward_task_points,
    p_difficulty_band,
    'generated',
    now(),
    p_week_end
  )
  on conflict (user_id, week_start, template_id) do nothing;
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
  v_hist_scope text;
  v_best_pace numeric;
  v_median_km numeric;
  v_baseline numeric;
  v_diff record;
  v_attempt int;
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
    select * into v_diff from public._user_tasks_difficulty_band(v_template.target_metric, v_target, v_target, null);
  else
    v_template := null;
    for v_attempt in 1..8 loop
      v_template := public._user_tasks_pick_dynamic_template(p_user_id, p_category, v_used, v_since_45);
      exit when v_template.id is not null;
    end loop;

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
      select * into v_diff from public._user_tasks_difficulty_band(v_template.target_metric, v_target, v_target, null);
    else
      v_hist_scope := case
        when public._user_tasks_template_scope_sample_count(p_user_id, v_template, v_since_30) >= 3
          then v_template.scope_activity_code
        else null
      end;

      if p_category = 'cardio' then
        select * into v_cardio
        from public._user_tasks_hist_cardio_stats(p_user_id, v_hist_scope, v_since_30);

        if v_template.target_metric = 'pace_sec_per_km' then
          v_best_pace := public._user_tasks_hist_cardio_best_pace(
            p_user_id,
            coalesce(v_hist_scope, v_template.scope_activity_code),
            v_since_30
          );
          if v_best_pace <= 0 then
            return v_used;
          end if;
          v_target := greatest(round(v_best_pace * 0.97), round(v_best_pace * 0.90));
          v_secondary := greatest(1, round(greatest(v_cardio.avg_distance_km * 0.8, v_cardio.max_distance_km * 0.5), 1));
          v_baseline := v_best_pace;
        elsif v_template.target_metric = 'distance_km' then
          v_median_km := public._user_tasks_hist_cardio_median_distance(p_user_id, v_hist_scope, v_since_30);
          v_target := greatest(
            round(greatest(1, v_median_km * 0.8), 1),
            round(greatest(v_cardio.avg_distance_km * 1.15, v_cardio.max_distance_km * 1.05), 1)
          );
          v_secondary := null;
          v_baseline := greatest(v_cardio.max_distance_km, v_median_km, 1);
        elsif v_template.target_metric = 'calories_kcal' then
          v_target := greatest(150, round(v_cardio.avg_calories * 1.1));
          v_secondary := null;
          v_baseline := greatest(v_cardio.avg_calories, 150);
        else
          v_target := greatest(3, round(v_cardio.avg_distance_km * 1.15, 1));
          v_secondary := null;
          v_baseline := greatest(v_cardio.max_distance_km, 1);
        end if;
      elsif p_category = 'strength' then
        select * into v_strength
        from public._user_tasks_hist_strength_stats(p_user_id, v_template.scope_muscle_primary, v_since_30);
        v_target := case v_template.target_metric
          when 'max_weight_kg' then greatest(20, round(v_strength.max_weight_kg * 1.05, 1))
          when 'volume_kg' then greatest(500, round(v_strength.avg_session_volume_kg * 1.15, 0))
          when 'calories_kcal' then greatest(150, round(v_strength.avg_calories * 1.1))
          when 'duration_sec' then greatest(1800, round(2700 * 1.0))
          else greatest(500, round(v_strength.avg_session_volume_kg * 1.15, 0))
        end;
        v_secondary := null;
        v_baseline := case v_template.target_metric
          when 'max_weight_kg' then greatest(v_strength.max_weight_kg, 20)
          when 'volume_kg' then greatest(v_strength.avg_session_volume_kg, 500)
          when 'calories_kcal' then greatest(v_strength.avg_calories, 150)
          else greatest(v_strength.avg_session_volume_kg, 500)
        end;
      else
        select * into v_sport
        from public._user_tasks_hist_sport_stats(p_user_id, v_template.scope_sport, v_since_30);
        v_target := case v_template.target_metric
          when 'sport_weekly_minutes' then greatest(30, round(v_sport.avg_weekly_minutes * 1.5, 0))
          when 'duration_sec' then greatest(1800, round(v_sport.avg_session_minutes * 60 * 1.1))
          else greatest(30, round(v_sport.avg_weekly_minutes * 1.5, 0))
        end;
        v_secondary := null;
        v_baseline := case v_template.target_metric
          when 'duration_sec' then greatest(v_sport.avg_session_minutes * 60, 1800)
          else greatest(v_sport.avg_weekly_minutes, 30)
        end;
      end if;

      select * into v_diff
      from public._user_tasks_difficulty_band(v_template.target_metric, v_target, v_baseline, null);
    end if;
  end if;

  perform public._user_tasks_insert_from_template(
    p_user_id,
    v_template,
    p_week_start,
    p_week_end,
    v_target,
    v_secondary,
    v_diff.band,
    v_diff.multiplier
  );
  v_used := array_append(v_used, v_template.id);
  return v_used;
end;
$$;

create or replace function public._user_tasks_refresh_meta_for_user(
  p_user_id uuid,
  p_week_start timestamptz
)
returns table (
  refresh_count int,
  free_refresh_available boolean,
  next_refresh_cost_coins int
)
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_count int := 0;
begin
  select coalesce(r.refresh_count, 0) into v_count
  from public.user_weekly_task_refreshes r
  where r.user_id = p_user_id
    and r.week_start = p_week_start;

  return query
  select
    v_count,
    v_count = 0,
    case v_count
      when 0 then 0
      when 1 then 100
      when 2 then 150
      else null
    end::int;
end;
$$;

drop function if exists public.list_my_weekly_tasks_v1();

create or replace function public.list_my_weekly_tasks_v1()
returns table (
  task_id uuid,
  title text,
  description text,
  category text,
  target_metric text,
  target_value numeric,
  target_secondary numeric,
  reward_xp int,
  reward_coins int,
  reward_task_points int,
  difficulty_band text,
  status text,
  generated_at timestamptz,
  expires_at timestamptz,
  accepted_at timestamptz,
  completed_at timestamptz,
  progress_value numeric,
  week_start timestamptz,
  week_end timestamptz,
  accepted_count int,
  accept_slots_remaining int,
  refresh_count int,
  free_refresh_available boolean,
  next_refresh_cost_coins int
)
language plpgsql
volatile
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  ws timestamptz;
  we timestamptz;
  v_accepted int;
  v_refresh_count int;
  v_free_refresh boolean;
  v_next_cost int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  perform public._user_tasks_ensure_weekly_for_user(v_uid);

  select b.w_start, b.w_end into ws, we
  from public._challenge_week_bounds_utc(now()) as b;

  select count(*)::int into v_accepted
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status in ('accepted', 'completed');

  select m.refresh_count, m.free_refresh_available, m.next_refresh_cost_coins
  into v_refresh_count, v_free_refresh, v_next_cost
  from public._user_tasks_refresh_meta_for_user(v_uid, ws) as m;

  return query
  select
    ut.id,
    ut.title,
    ut.description,
    ut.category,
    ut.target_metric,
    ut.target_value,
    ut.target_secondary,
    ut.reward_xp,
    ut.reward_coins,
    ut.reward_task_points,
    ut.difficulty_band,
    ut.status,
    ut.generated_at,
    ut.expires_at,
    ut.accepted_at,
    ut.completed_at,
    public._user_tasks_progress_value(ut),
    ws,
    we,
    v_accepted,
    greatest(0, 3 - v_accepted),
    v_refresh_count,
    v_free_refresh,
    v_next_cost
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status <> 'expired'
  order by
    case ut.status
      when 'accepted' then 0
      when 'completed' then 1
      when 'generated' then 2
      else 3
    end,
    ut.generated_at;
end;
$$;

create or replace function public.unaccept_user_task_v1(p_task_id uuid)
returns public.user_tasks
language plpgsql
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  ws timestamptz;
  v_task public.user_tasks%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select b.w_start into ws from public._challenge_week_bounds_utc(now()) as b;

  update public.user_tasks ut
  set status = 'generated',
      accepted_at = null
  where ut.id = p_task_id
    and ut.user_id = v_uid
    and ut.status = 'accepted'
    and ut.week_start = ws
    and now() < ut.expires_at
  returning * into v_task;

  if not found then
    raise exception 'user_task_not_unacceptable';
  end if;

  return v_task;
end;
$$;

create or replace function public.refresh_my_weekly_tasks_v1()
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  ws timestamptz;
  we timestamptz;
  v_refresh_row public.user_weekly_task_refreshes%rowtype;
  v_cost int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  perform public._user_tasks_ensure_weekly_for_user(v_uid);

  select b.w_start, b.w_end into ws, we
  from public._challenge_week_bounds_utc(now()) as b;

  insert into public.user_weekly_task_refreshes (user_id, week_start, refresh_count)
  values (v_uid, ws, 0)
  on conflict (user_id, week_start) do nothing;

  select * into v_refresh_row
  from public.user_weekly_task_refreshes r
  where r.user_id = v_uid
    and r.week_start = ws
  for update;

  if v_refresh_row.refresh_count >= 3 then
    raise exception 'weekly_task_refresh_cap';
  end if;

  v_cost := case v_refresh_row.refresh_count
    when 0 then 0
    when 1 then 100
    when 2 then 150
    else null
  end;

  if v_cost is null then
    raise exception 'weekly_task_refresh_cap';
  end if;

  if v_cost > 0 then
    if not public.apply_liftr_coin_transaction(
      v_uid,
      -v_cost,
      'weekly_task_refresh',
      v_refresh_row.id
    ) then
      raise exception 'insufficient_coins';
    end if;
  end if;

  delete from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status = 'generated';

  update public.user_weekly_task_refreshes
  set refresh_count = refresh_count + 1
  where id = v_refresh_row.id;

  perform public._user_tasks_top_up_batch(v_uid, ws, we);

  return jsonb_build_object(
    'refresh_count', v_refresh_row.refresh_count + 1,
    'cost_coins', v_cost
  );
end;
$$;

delete from public.user_tasks ut
where ut.status in ('generated', 'accepted')
  and ut.week_start = (
    select b.w_start from public._challenge_week_bounds_utc(now()) as b
  );

revoke all on function public.unaccept_user_task_v1(uuid) from public, anon;
grant execute on function public.unaccept_user_task_v1(uuid) to authenticated;

revoke all on function public.refresh_my_weekly_tasks_v1() from public, anon;
grant execute on function public.refresh_my_weekly_tasks_v1() to authenticated;

revoke all on function public.list_my_weekly_tasks_v1() from public, anon;
grant execute on function public.list_my_weekly_tasks_v1() to authenticated;

begin;

create table if not exists public.task_templates (
  id serial primary key,
  code text not null unique,
  category text not null check (category in ('cardio', 'strength', 'sport')),
  target_metric text not null check (target_metric in (
    'distance_km', 'pace_sec_per_km', 'volume_kg', 'max_weight_kg',
    'duration_sec', 'calories_kcal', 'sport_weekly_minutes'
  )),
  generation_mode text not null check (generation_mode in ('static_beginner', 'dynamic_scaled')),
  title_template text not null,
  description_template text not null,
  scope_activity_code text,
  scope_sport text,
  scope_muscle_primary text,
  base_reward_xp int not null default 50,
  base_reward_coins int not null default 15,
  base_reward_task_points int not null default 10,
  difficulty_tier text not null default 'standard'
    check (difficulty_tier in ('beginner', 'standard', 'stretch')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.user_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  template_id int references public.task_templates (id) on delete set null,
  week_start timestamptz not null,
  title text not null,
  description text not null,
  category text not null check (category in ('cardio', 'strength', 'sport')),
  target_metric text not null,
  target_value numeric not null,
  target_secondary numeric,
  scope_activity_code text,
  scope_sport text,
  scope_muscle_primary text,
  reward_xp int not null,
  reward_coins int not null,
  reward_task_points int not null,
  status text not null default 'generated'
    check (status in ('generated', 'accepted', 'completed', 'expired')),
  generated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  completed_at timestamptz,
  completed_workout_id bigint references public.workouts (id) on delete set null,
  unique (user_id, week_start, template_id)
);

create index if not exists idx_user_tasks_user_week_status
  on public.user_tasks (user_id, week_start, status);

create index if not exists idx_user_tasks_user_status
  on public.user_tasks (user_id, status);

alter table public.profiles
  add column if not exists task_points_total int not null default 0;

create or replace function public.allow_profiles_task_points_update()
returns void
language sql
security definer
set search_path to public
as $$
  select set_config('app.allow_task_points_update', 'true', true);
$$;

create or replace function public.protect_profiles_task_points_total()
returns trigger
language plpgsql
set search_path to public
as $$
begin
  if old.task_points_total is distinct from new.task_points_total
     and current_setting('app.allow_task_points_update', true) is distinct from 'true' then
    raise exception 'task_points_total_is_server_managed';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_profiles_task_points_total on public.profiles;
create trigger trg_protect_profiles_task_points_total
  before update on public.profiles
  for each row
  execute function public.protect_profiles_task_points_total();

insert into public.coin_reward_rules (action_type, amount, enabled) values
  ('user_task_completed', 0, true)
on conflict (action_type) do nothing;

create unique index if not exists coin_tx_once_user_task_completed
  on public.coin_transactions (user_id, reference_id, action_type)
  where action_type = 'user_task_completed' and amount > 0;

insert into public.task_templates (
  code, category, target_metric, generation_mode,
  title_template, description_template,
  scope_activity_code, scope_sport, scope_muscle_primary,
  base_reward_xp, base_reward_coins, base_reward_task_points, difficulty_tier
) values
  ('cardio_run_distance_beginner', 'cardio', 'distance_km', 'static_beginner',
   'Registra una carrera de {value} km', 'Completa una carrera de al menos {value} km esta semana.',
   'run', null, null, 40, 10, 8, 'beginner'),
  ('cardio_run_distance_stretch', 'cardio', 'distance_km', 'dynamic_scaled',
   'Amplía tu distancia: {value} km', 'Registra una carrera de al menos {value} km en una sola sesión.',
   'run', null, null, 60, 20, 15, 'stretch'),
  ('cardio_run_pace_stretch', 'cardio', 'pace_sec_per_km', 'dynamic_scaled',
   'Ritmo exigente: {value} min/km', 'Corre al menos {secondary} km manteniendo un ritmo de {value} min/km o mejor.',
   'run', null, null, 70, 25, 18, 'stretch'),
  ('cardio_walk_distance_beginner', 'cardio', 'distance_km', 'static_beginner',
   'Camina {value} km', 'Registra una caminata de al menos {value} km.',
   'walk', null, null, 35, 8, 7, 'beginner'),
  ('strength_session_duration_beginner', 'strength', 'duration_sec', 'static_beginner',
   'Sesión de fuerza de {value} min', 'Completa una sesión de fuerza de al menos {value} minutos.',
   null, null, null, 40, 10, 8, 'beginner'),
  ('strength_max_weight_stretch', 'strength', 'max_weight_kg', 'dynamic_scaled',
   'Supera {value} kg', 'Levanta al menos {value} kg en una serie durante un entreno de fuerza.',
   null, null, null, 65, 22, 16, 'stretch'),
  ('strength_volume_stretch', 'strength', 'volume_kg', 'dynamic_scaled',
   'Volumen total: {value} kg', 'Acumula al menos {value} kg de volumen en una sesión de fuerza.',
   null, null, null, 60, 20, 15, 'stretch'),
  ('strength_chest_volume_stretch', 'strength', 'volume_kg', 'dynamic_scaled',
   'Volumen de pecho: {value} kg', 'Acumula al menos {value} kg de volumen de pecho en una sesión.',
   null, null, 'pecho', 55, 18, 14, 'stretch'),
  ('sport_racket_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Juega {value} min de pádel', 'Registra una sesión de pádel de al menos {value} minutos.',
   null, 'racket', null, 40, 10, 8, 'beginner'),
  ('sport_football_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Juega {value} min de fútbol', 'Registra una sesión de fútbol de al menos {value} minutos.',
   null, 'football', null, 40, 10, 8, 'beginner'),
  ('sport_weekly_minutes_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Suma {value} min jugando', 'Acumula {value} minutos de actividad deportiva esta semana.',
   null, null, null, 55, 18, 14, 'stretch'),
  ('sport_football_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Suma {value} min de fútbol', 'Acumula {value} minutos jugando a fútbol esta semana.',
   null, 'football', null, 55, 18, 14, 'stretch'),
  ('cardio_calories_stretch', 'cardio', 'calories_kcal', 'dynamic_scaled',
   'Quema {value} kcal en cardio', 'Registra una sesión de cardio de al menos {value} kcal.',
   null, null, null, 50, 15, 12, 'standard'),
  ('strength_calories_stretch', 'strength', 'calories_kcal', 'dynamic_scaled',
   'Quema {value} kcal en fuerza', 'Completa un entreno de fuerza de al menos {value} kcal.',
   null, null, null, 50, 15, 12, 'standard'),
  ('sport_racket_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Suma {value} min de pádel', 'Acumula {value} minutos jugando a pádel esta semana.',
   null, 'racket', null, 55, 18, 14, 'stretch')
on conflict (code) do nothing;

create or replace function public._user_tasks_tier_multiplier(p_tier text)
returns numeric
language sql
immutable
as $$
  select case coalesce(p_tier, 'standard')
    when 'beginner' then 1.0
    when 'stretch' then 1.2
    else 1.1
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
  elsif p_metric in ('duration_sec', 'sport_weekly_minutes') then
    return to_char(round(p_value / 60.0), 'FM999');
  elsif p_metric in ('distance_km', 'volume_kg', 'max_weight_kg') then
    return trim(to_char(p_value, 'FM9999990.0'));
  else
    return trim(to_char(round(p_value), 'FM999999'));
  end if;
end;
$$;

create or replace function public._user_tasks_render_copy(
  p_template text,
  p_metric text,
  p_value numeric,
  p_secondary numeric default null
)
returns text
language plpgsql
stable
as $$
declare
  v_value text := public._user_tasks_format_value(p_metric, p_value, p_secondary);
  v_secondary text := case
    when p_secondary is null then ''
    else public._user_tasks_format_value(
      case when p_metric = 'pace_sec_per_km' then 'distance_km' else p_metric end,
      p_secondary,
      null
    )
  end;
begin
  return replace(
    replace(coalesce(p_template, ''), '{value}', v_value),
    '{secondary}',
    v_secondary
  );
end;
$$;

create or replace function public._user_tasks_count_subcategory_workouts(
  p_user_id uuid,
  p_category text,
  p_scope_activity_code text,
  p_scope_sport text,
  p_scope_muscle_primary text,
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
      (p_category = 'cardio' and w.kind = 'cardio'::public.workout_kind
        and exists (
          select 1 from public.cardio_sessions cs
          where cs.workout_id = w.id
            and (p_scope_activity_code is null
              or cs.activity_code = p_scope_activity_code
              or cs.modality = p_scope_activity_code)
        ))
      or (p_category = 'strength' and w.kind = 'strength'::public.workout_kind
        and (
          p_scope_muscle_primary is null
          or exists (
            select 1
            from public.workout_exercises we
            join public.exercises e on e.id = we.exercise_id
            where we.workout_id = w.id
              and (e.muscle_primary = p_scope_muscle_primary
                or e.muscle_primary = replace(p_scope_muscle_primary, 'pecho', 'chest'))
          )
        ))
      or (p_category = 'sport' and w.kind = 'sport'::public.workout_kind
        and exists (
          select 1 from public.sport_sessions ss
          where ss.workout_id = w.id
            and (p_scope_sport is null or ss.sport = p_scope_sport)
        ))
    );
$$;

create or replace function public._user_tasks_hist_cardio_stats(
  p_user_id uuid,
  p_activity_code text,
  p_since timestamptz
)
returns table (
  avg_distance_km numeric,
  avg_pace_sec_per_km numeric,
  max_distance_km numeric,
  avg_calories numeric
)
language sql
stable
security definer
set search_path to public
as $$
  select
    coalesce(avg(cs.distance_km), 0),
    coalesce(avg(cs.avg_pace_sec_per_km), 0),
    coalesce(max(cs.distance_km), 0),
    coalesce(avg(w.calories_kcal), 0)
  from public.workouts w
  join public.cardio_sessions cs on cs.workout_id = w.id
  where w.user_id = p_user_id
    and w.state = 'published'::public.workout_state
    and coalesce(w.started_at, w.created_at) >= p_since
    and (p_activity_code is null
      or cs.activity_code = p_activity_code
      or cs.modality = p_activity_code);
$$;

create or replace function public._user_tasks_hist_strength_stats(
  p_user_id uuid,
  p_muscle_primary text,
  p_since timestamptz
)
returns table (
  max_weight_kg numeric,
  avg_session_volume_kg numeric,
  avg_calories numeric
)
language sql
stable
security definer
set search_path to public
as $$
  with sessions as (
    select w.id as workout_id, coalesce(w.calories_kcal, 0) as calories_kcal
    from public.workouts w
    where w.user_id = p_user_id
      and w.kind = 'strength'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_since
  ),
  set_rows as (
    select
      s.workout_id,
      s.calories_kcal,
      coalesce(es.weight_kg, 0) as weight_kg,
      coalesce(es.reps, 0) as reps
    from sessions s
    join public.workout_exercises we on we.workout_id = s.workout_id
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where coalesce(es.is_completed, true)
      and (
        p_muscle_primary is null
        or e.muscle_primary = p_muscle_primary
        or e.muscle_primary = replace(p_muscle_primary, 'pecho', 'chest')
      )
  ),
  per_session as (
    select workout_id, max(weight_kg) as max_w, sum(reps * weight_kg) as vol, max(calories_kcal) as cal
    from set_rows
    group by workout_id
  )
  select
    coalesce(max(ps.max_w), 0),
    coalesce(avg(ps.vol), 0),
    coalesce(avg(ps.cal), 0)
  from per_session ps;
$$;

create or replace function public._user_tasks_hist_sport_stats(
  p_user_id uuid,
  p_sport text,
  p_since timestamptz
)
returns table (
  avg_weekly_minutes numeric,
  avg_session_minutes numeric
)
language sql
stable
security definer
set search_path to public
as $$
  with sessions as (
    select
      date_trunc('week', coalesce(w.started_at, w.created_at)) as wk,
      coalesce(ss.duration_sec, 0) / 60.0 as minutes
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_user_id
      and w.kind = 'sport'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_since
      and (p_sport is null or ss.sport = p_sport)
  ),
  weekly as (
    select wk, sum(minutes) as week_minutes
    from sessions
    group by wk
  )
  select
    coalesce((select avg(week_minutes) from weekly), 0),
    coalesce((select avg(minutes) from sessions), 0);
$$;

create or replace function public._user_tasks_scaled_rewards(
  p_template public.task_templates
)
returns table (reward_xp int, reward_coins int, reward_task_points int)
language sql
stable
as $$
  select
    round(p_template.base_reward_xp * public._user_tasks_tier_multiplier(p_template.difficulty_tier))::int,
    round(p_template.base_reward_coins * public._user_tasks_tier_multiplier(p_template.difficulty_tier))::int,
    round(p_template.base_reward_task_points * public._user_tasks_tier_multiplier(p_template.difficulty_tier))::int;
$$;

create or replace function public._user_tasks_pick_template(
  p_category text,
  p_mode text,
  p_exclude_ids int[]
)
returns public.task_templates
language sql
stable
security definer
set search_path to public
as $$
  select t.*
  from public.task_templates t
  where t.is_active
    and t.category = p_category
    and t.generation_mode = p_mode
    and (p_exclude_ids is null or not (t.id = any (p_exclude_ids)))
  order by random()
  limit 1;
$$;

create or replace function public._user_tasks_insert_from_template(
  p_user_id uuid,
  p_template public.task_templates,
  p_week_start timestamptz,
  p_week_end timestamptz,
  p_target_value numeric,
  p_target_secondary numeric default null
)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  v_rewards record;
begin
  select * into v_rewards from public._user_tasks_scaled_rewards(p_template);

  insert into public.user_tasks (
    user_id, template_id, week_start, title, description,
    category, target_metric, target_value, target_secondary,
    scope_activity_code, scope_sport, scope_muscle_primary,
    reward_xp, reward_coins, reward_task_points,
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
  v_count int;
  v_target numeric;
  v_secondary numeric;
  v_cardio record;
  v_strength record;
  v_sport record;
  v_used int[] := coalesce(p_exclude_ids, array[]::int[]);
begin
  v_template := public._user_tasks_pick_template(p_category, 'static_beginner', v_used);
  if v_template.id is null then
    v_template := public._user_tasks_pick_template(p_category, 'dynamic_scaled', v_used);
  end if;
  if v_template.id is null then
    return v_used;
  end if;

  v_count := public._user_tasks_count_subcategory_workouts(
    p_user_id,
    p_category,
    v_template.scope_activity_code,
    v_template.scope_sport,
    v_template.scope_muscle_primary,
    v_since_45
  );

  if v_count < 3 or v_template.generation_mode = 'static_beginner' then
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
    v_template := public._user_tasks_pick_template(p_category, 'dynamic_scaled', v_used);
    if v_template.id is null then
      return v_used;
    end if;

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
        else greatest(30, round(v_strength.avg_session_volume_kg * 1.15, 0))
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
  v_categories text[] := array['cardio', 'strength', 'sport', 'cardio', 'strength'];
  v_cat text;
  v_used int[] := array[]::int[];
  v_i int;
begin
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
      (array['cardio', 'strength', 'sport'])[1 + floor(random() * 3)::int],
      p_week_start,
      p_week_end,
      v_used
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
  end if;
end;
$$;

create or replace function public.apply_liftr_xp_reward(
  p_user_id uuid,
  p_amount int,
  p_reference_id uuid default null,
  p_workout_id bigint default null
)
returns boolean
language plpgsql
security definer
set search_path to public
as $$
begin
  if p_user_id is null or p_amount is null or p_amount <= 0 then
    return false;
  end if;

  begin
    insert into public.xp_events (user_id, amount, workout_id, created_at)
    values (p_user_id, p_amount, p_workout_id, now());
    return true;
  exception
    when undefined_column then
      begin
        insert into public.xp_events (user_id, xp_delta, workout_id, created_at)
        values (p_user_id, p_amount, p_workout_id, now());
        return true;
      exception
        when others then
          return false;
      end;
    when unique_violation then
      return false;
    when others then
      begin
        insert into public.xp_events (user_id, xp, workout_id, created_at)
        values (p_user_id, p_amount, p_workout_id, now());
        return true;
      exception
        when others then
          return false;
      end;
  end;
end;
$$;

create or replace function public.complete_user_task(
  p_task_id uuid,
  p_user_id uuid,
  p_workout_id bigint
)
returns boolean
language plpgsql
security definer
set search_path to public
as $$
declare
  v_task public.user_tasks%rowtype;
begin
  select * into v_task
  from public.user_tasks ut
  where ut.id = p_task_id
    and ut.user_id = p_user_id
    and ut.status = 'accepted'
  for update;

  if not found then
    return false;
  end if;

  update public.user_tasks
  set status = 'completed',
      completed_at = now(),
      completed_workout_id = p_workout_id
  where id = p_task_id;

  perform public.apply_liftr_xp_reward(p_user_id, v_task.reward_xp, p_task_id, p_workout_id);

  perform public.apply_liftr_coin_reward(
    p_user_id,
    v_task.reward_coins,
    'user_task_completed',
    p_task_id
  );

  perform public.allow_profiles_task_points_update();
  update public.profiles
  set task_points_total = coalesce(task_points_total, 0) + v_task.reward_task_points
  where user_id = p_user_id;

  return true;
end;
$$;

create or replace function public._user_task_workout_satisfies(
  p_task public.user_tasks,
  p_workout_id bigint
)
returns boolean
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_w public.workouts%rowtype;
  v_distance numeric;
  v_pace numeric;
  v_volume numeric;
  v_max_weight numeric;
  v_duration_sec numeric;
  v_calories numeric;
  v_sport_week_minutes numeric;
begin
  select * into v_w
  from public.workouts w
  where w.id = p_workout_id
    and w.user_id = p_task.user_id
    and w.state = 'published'::public.workout_state;

  if not found then
    return false;
  end if;

  if p_task.target_metric = 'sport_weekly_minutes' then
    select coalesce(sum(ss.duration_sec), 0) / 60.0 into v_sport_week_minutes
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at
      and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    return v_sport_week_minutes >= p_task.target_value;
  end if;

  if p_task.category = 'cardio' and v_w.kind <> 'cardio'::public.workout_kind then
    return false;
  elsif p_task.category = 'strength' and v_w.kind <> 'strength'::public.workout_kind then
    return false;
  elsif p_task.category = 'sport' and v_w.kind <> 'sport'::public.workout_kind then
    return false;
  end if;

  if p_task.target_metric = 'distance_km' then
    select cs.distance_km into v_distance
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
      and (p_task.scope_activity_code is null
        or cs.activity_code = p_task.scope_activity_code
        or cs.modality = p_task.scope_activity_code);
    return coalesce(v_distance, 0) >= p_task.target_value;
  elsif p_task.target_metric = 'pace_sec_per_km' then
    select cs.distance_km, cs.avg_pace_sec_per_km
    into v_distance, v_pace
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
      and (p_task.scope_activity_code is null
        or cs.activity_code = p_task.scope_activity_code
        or cs.modality = p_task.scope_activity_code);
    return coalesce(v_distance, 0) >= coalesce(p_task.target_secondary, 3)
      and coalesce(v_pace, 1e9) <= p_task.target_value;
  elsif p_task.target_metric = 'max_weight_kg' then
    select max(es.weight_kg) into v_max_weight
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where we.workout_id = p_workout_id
      and coalesce(es.is_completed, true)
      and (
        p_task.scope_muscle_primary is null
        or e.muscle_primary = p_task.scope_muscle_primary
        or e.muscle_primary = replace(p_task.scope_muscle_primary, 'pecho', 'chest')
      );
    return coalesce(v_max_weight, 0) >= p_task.target_value;
  elsif p_task.target_metric = 'volume_kg' then
    select coalesce(sum(es.reps * es.weight_kg), 0) into v_volume
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where we.workout_id = p_workout_id
      and coalesce(es.is_completed, true)
      and (
        p_task.scope_muscle_primary is null
        or e.muscle_primary = p_task.scope_muscle_primary
        or e.muscle_primary = replace(p_task.scope_muscle_primary, 'pecho', 'chest')
      );
    return v_volume >= p_task.target_value;
  elsif p_task.target_metric = 'duration_sec' then
    if p_task.category = 'sport' then
      select coalesce(ss.duration_sec, 0) into v_duration_sec
      from public.sport_sessions ss
      where ss.workout_id = p_workout_id
        and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    else
      v_duration_sec := coalesce(v_w.duration_min, 0) * 60;
    end if;
    return v_duration_sec >= p_task.target_value;
  elsif p_task.target_metric = 'calories_kcal' then
    return coalesce(v_w.calories_kcal, 0) >= p_task.target_value;
  end if;

  return false;
end;
$$;

create or replace function public._user_tasks_progress_value(
  p_task public.user_tasks
)
returns numeric
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_minutes numeric;
begin
  if p_task.status not in ('accepted', 'completed') then
    return null;
  end if;

  if p_task.target_metric = 'sport_weekly_minutes' then
    select coalesce(sum(ss.duration_sec), 0) / 60.0 into v_minutes
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at
      and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    return v_minutes;
  end if;

  return null;
end;
$$;

create or replace function public.evaluate_user_tasks_for_user(
  p_user_id uuid,
  p_workout_id bigint default null
)
returns void
language plpgsql
security definer
set search_path to public
as $$
declare
  r record;
  v_workout_id bigint := p_workout_id;
begin
  if p_user_id is null then
    return;
  end if;

  perform public._user_tasks_ensure_weekly_for_user(p_user_id);

  if v_workout_id is null then
    select w.id into v_workout_id
    from public.workouts w
    where w.user_id = p_user_id
      and w.state = 'published'::public.workout_state
    order by coalesce(w.updated_at, w.created_at) desc
    limit 1;
  end if;

  if v_workout_id is null then
    return;
  end if;

  for r in
    select ut.*
    from public.user_tasks ut
    where ut.user_id = p_user_id
      and ut.status = 'accepted'
      and now() >= ut.week_start
      and now() < ut.expires_at
    for update
  loop
    if public._user_task_workout_satisfies(r, v_workout_id) then
      perform public.complete_user_task(r.id, p_user_id, v_workout_id);
    end if;
  end loop;
end;
$$;

create or replace function public._workouts_evaluate_user_tasks_after_publish()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if tg_op = 'INSERT' then
    if new.state = 'published'::public.workout_state then
      perform public.evaluate_user_tasks_for_user(new.user_id, new.id);
    end if;
  elsif tg_op = 'UPDATE' then
    if new.state = 'published'::public.workout_state
       and (old.state is distinct from 'published'::public.workout_state) then
      perform public.evaluate_user_tasks_for_user(new.user_id, new.id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tr_workouts_evaluate_user_tasks_after_publish on public.workouts;
create trigger tr_workouts_evaluate_user_tasks_after_publish
  after insert or update of state on public.workouts
  for each row
  execute function public._workouts_evaluate_user_tasks_after_publish();

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
  status text,
  generated_at timestamptz,
  expires_at timestamptz,
  accepted_at timestamptz,
  completed_at timestamptz,
  progress_value numeric,
  week_start timestamptz,
  week_end timestamptz,
  accepted_count int,
  accept_slots_remaining int
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
    ut.status,
    ut.generated_at,
    ut.expires_at,
    ut.accepted_at,
    ut.completed_at,
    public._user_tasks_progress_value(ut),
    ws,
    we,
    v_accepted,
    greatest(0, 3 - v_accepted)
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

create or replace function public.accept_user_task_v1(p_task_id uuid)
returns public.user_tasks
language plpgsql
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  ws timestamptz;
  v_accepted int;
  v_task public.user_tasks%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  perform public._user_tasks_ensure_weekly_for_user(v_uid);

  select b.w_start into ws from public._challenge_week_bounds_utc(now()) as b;

  select count(*)::int into v_accepted
  from public.user_tasks ut
  where ut.user_id = v_uid
    and ut.week_start = ws
    and ut.status in ('accepted', 'completed');

  if v_accepted >= 3 then
    raise exception 'user_task_accept_cap_reached';
  end if;

  update public.user_tasks ut
  set status = 'accepted',
      accepted_at = now()
  where ut.id = p_task_id
    and ut.user_id = v_uid
    and ut.status = 'generated'
    and ut.week_start = ws
    and now() < ut.expires_at
  returning * into v_task;

  if not found then
    raise exception 'user_task_not_acceptable';
  end if;

  return v_task;
end;
$$;

create or replace function public.get_user_task_detail_v1(p_task_id uuid)
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
  status text,
  progress_value numeric,
  week_start timestamptz,
  week_end timestamptz
)
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  v_task public.user_tasks%rowtype;
  we timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_task
  from public.user_tasks ut
  where ut.id = p_task_id
    and ut.user_id = v_uid;

  if not found then
    raise exception 'user_task_not_found';
  end if;

  select b.w_end into we from public._challenge_week_bounds_utc(v_task.week_start) as b;

  return query
  select
    v_task.id,
    v_task.title,
    v_task.description,
    v_task.category,
    v_task.target_metric,
    v_task.target_value,
    v_task.target_secondary,
    v_task.reward_xp,
    v_task.reward_coins,
    v_task.reward_task_points,
    v_task.status,
    public._user_tasks_progress_value(v_task),
    v_task.week_start,
    we;
end;
$$;

create or replace function public.get_task_points_leaderboard_v1(
  p_scope text,
  p_limit integer default 100,
  p_sex text default null,
  p_age_band text default null
)
returns table (
  rank integer,
  user_id uuid,
  username text,
  avatar_url text,
  task_points_total integer
)
language plpgsql
stable
security definer
set search_path to public
as $$
begin
  return query
  with scoped as (
    select
      pr.user_id as uid,
      pr.task_points_total as pts
    from public.profiles pr
    where pr.task_points_total > 0
      and (p_sex is null or p_sex = '' or pr.sex = p_sex::public.sex)
      and (
        p_age_band is null or p_age_band = ''
        or (
          case p_age_band
            when '18-24' then extract(year from age(current_date, pr.date_of_birth)) between 18 and 24
            when '25-34' then extract(year from age(current_date, pr.date_of_birth)) between 25 and 34
            when '35-44' then extract(year from age(current_date, pr.date_of_birth)) between 35 and 44
            when '45-54' then extract(year from age(current_date, pr.date_of_birth)) between 45 and 54
            when '55+' then extract(year from age(current_date, pr.date_of_birth)) >= 55
            else true
          end
        )
      )
      and (
        coalesce(p_scope, 'global') = 'global'
        or pr.user_id = auth.uid()
        or exists (
          select 1
          from public.follows f
          where f.follower_id = auth.uid()
            and f.followee_id = pr.user_id
        )
      )
  ),
  ordered as (
    select
      s.uid,
      s.pts,
      row_number() over (order by s.pts desc, s.uid) as rnk
    from scoped s
  )
  select
    o.rnk::integer,
    o.uid,
    pr.username,
    pr.avatar_url,
    o.pts
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  where o.rnk <= greatest(1, coalesce(p_limit, 100))
  order by o.rnk;
end;
$$;

create or replace view public.vw_user_task_points_rollup as
select
  ut.user_id,
  count(*) filter (where ut.status = 'completed') as tasks_completed,
  coalesce(sum(ut.reward_task_points) filter (where ut.status = 'completed'), 0)::int as task_points_from_tasks
from public.user_tasks ut
group by ut.user_id;

alter table public.task_templates enable row level security;
alter table public.user_tasks enable row level security;

drop policy if exists task_templates_select_authenticated on public.task_templates;
create policy task_templates_select_authenticated
  on public.task_templates for select to authenticated using (true);

drop policy if exists user_tasks_select_own on public.user_tasks;
create policy user_tasks_select_own
  on public.user_tasks for select to authenticated
  using (user_id = auth.uid());

revoke insert, update, delete on public.task_templates from anon, authenticated;
revoke insert, update, delete on public.user_tasks from anon, authenticated;

revoke all on function public._user_tasks_ensure_weekly_for_user(uuid) from public;
grant execute on function public._user_tasks_ensure_weekly_for_user(uuid) to postgres, service_role;

revoke all on function public.evaluate_user_tasks_for_user(uuid, bigint) from public;
grant execute on function public.evaluate_user_tasks_for_user(uuid, bigint) to postgres, service_role;

revoke all on function public.list_my_weekly_tasks_v1() from public, anon;
grant execute on function public.list_my_weekly_tasks_v1() to authenticated;

revoke all on function public.accept_user_task_v1(uuid) from public, anon;
grant execute on function public.accept_user_task_v1(uuid) to authenticated;

revoke all on function public.get_user_task_detail_v1(uuid) from public, anon;
grant execute on function public.get_user_task_detail_v1(uuid) to authenticated;

revoke all on function public.get_task_points_leaderboard_v1(text, integer, text, text) from public, anon;
grant execute on function public.get_task_points_leaderboard_v1(text, integer, text, text) to authenticated;

commit;

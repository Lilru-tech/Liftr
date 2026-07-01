begin;

alter table public.task_templates
  drop constraint if exists task_templates_target_metric_check;

alter table public.task_templates
  add constraint task_templates_target_metric_check check (target_metric in (
    'distance_km', 'pace_sec_per_km', 'volume_kg', 'max_weight_kg',
    'duration_sec', 'calories_kcal', 'sport_weekly_minutes',
    'total_reps', 'total_sets', 'routes_sent', 'problems_sent',
    'hyrox_weekly_minutes', 'sport_sessions_weekly'
  ));

update public.task_templates
set scope_sport = 'padel',
    title_template = 'Play {value} min of padel',
    description_template = 'Log a padel session of at least {value} minutes.'
where code = 'sport_racket_duration_beginner';

update public.task_templates
set scope_sport = 'padel',
    title_template = 'Rack up {value} min of padel',
    description_template = 'Accumulate {value} minutes playing padel this week.'
where code = 'sport_racket_weekly_stretch';

insert into public.task_templates (
  code, category, target_metric, generation_mode,
  title_template, description_template,
  scope_activity_code, scope_sport, scope_muscle_primary,
  base_reward_xp, base_reward_coins, base_reward_task_points, difficulty_tier
) values
  ('cardio_treadmill_distance_beginner', 'cardio', 'distance_km', 'static_beginner',
   'Treadmill {value} km', 'Log a treadmill session of at least {value} km.',
   'treadmill', null, null, 35, 16, 7, 'beginner'),
  ('cardio_treadmill_distance_stretch', 'cardio', 'distance_km', 'dynamic_scaled',
   'Treadmill push: {value} km', 'Log a treadmill run of at least {value} km in one session.',
   'treadmill', null, null, 60, 32, 15, 'stretch'),
  ('cardio_treadmill_calories_stretch', 'cardio', 'calories_kcal', 'dynamic_scaled',
   'Burn {value} kcal on the treadmill', 'Log a treadmill session of at least {value} kcal.',
   'treadmill', null, null, 55, 30, 14, 'standard'),
  ('cardio_treadmill_duration_beginner', 'cardio', 'duration_sec', 'static_beginner',
   '{value} min on the treadmill', 'Complete a treadmill session of at least {value} minutes.',
   'treadmill', null, null, 38, 16, 8, 'beginner'),
  ('cardio_indoor_cycling_distance_beginner', 'cardio', 'distance_km', 'static_beginner',
   'Indoor cycling {value} km', 'Log an indoor cycling session of at least {value} km.',
   'indoor_cycling', null, null, 38, 16, 8, 'beginner'),
  ('cardio_indoor_cycling_distance_stretch', 'cardio', 'distance_km', 'dynamic_scaled',
   'Indoor cycling: {value} km', 'Log an indoor cycling session of at least {value} km.',
   'indoor_cycling', null, null, 58, 30, 14, 'stretch'),
  ('cardio_walk_calories_stretch', 'cardio', 'calories_kcal', 'dynamic_scaled',
   'Burn {value} kcal walking', 'Log a walk of at least {value} kcal.',
   'walk', null, null, 48, 26, 12, 'standard'),
  ('cardio_walk_duration_beginner', 'cardio', 'duration_sec', 'static_beginner',
   'Walk {value} min', 'Log a walk of at least {value} minutes.',
   'walk', null, null, 35, 14, 7, 'beginner'),
  ('cardio_run_duration_beginner', 'cardio', 'duration_sec', 'static_beginner',
   'Run {value} min', 'Log a run of at least {value} minutes.',
   'run', null, null, 40, 16, 8, 'beginner'),
  ('strength_total_reps_stretch', 'strength', 'total_reps', 'dynamic_scaled',
   'Hit {value} reps in one session', 'Complete at least {value} reps across all sets in one strength workout.',
   null, null, null, 58, 32, 14, 'stretch'),
  ('strength_total_sets_stretch', 'strength', 'total_sets', 'dynamic_scaled',
   'Complete {value} sets', 'Finish at least {value} working sets in one strength session.',
   null, null, null, 55, 30, 14, 'stretch'),
  ('sport_padel_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of padel', 'Log a padel session of at least {value} minutes.',
   null, 'padel', null, 40, 16, 8, 'beginner'),
  ('sport_padel_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of padel', 'Accumulate {value} minutes playing padel this week.',
   null, 'padel', null, 55, 30, 14, 'stretch'),
  ('sport_tennis_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of tennis', 'Log a tennis session of at least {value} minutes.',
   null, 'tennis', null, 40, 16, 8, 'beginner'),
  ('sport_tennis_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of tennis', 'Accumulate {value} minutes playing tennis this week.',
   null, 'tennis', null, 55, 30, 14, 'stretch'),
  ('sport_basketball_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of basketball', 'Log a basketball session of at least {value} minutes.',
   null, 'basketball', null, 40, 16, 8, 'beginner'),
  ('sport_basketball_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of basketball', 'Accumulate {value} minutes playing basketball this week.',
   null, 'basketball', null, 55, 30, 14, 'stretch'),
  ('sport_badminton_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of badminton', 'Log a badminton session of at least {value} minutes.',
   null, 'badminton', null, 40, 16, 8, 'beginner'),
  ('sport_squash_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of squash', 'Log a squash session of at least {value} minutes.',
   null, 'squash', null, 40, 16, 8, 'beginner'),
  ('sport_table_tennis_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of table tennis', 'Log a table tennis session of at least {value} minutes.',
   null, 'table_tennis', null, 40, 16, 8, 'beginner'),
  ('sport_volleyball_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of volleyball', 'Log a volleyball session of at least {value} minutes.',
   null, 'volleyball', null, 40, 16, 8, 'beginner'),
  ('sport_handball_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of handball', 'Log a handball session of at least {value} minutes.',
   null, 'handball', null, 40, 16, 8, 'beginner'),
  ('sport_hockey_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of hockey', 'Log a hockey session of at least {value} minutes.',
   null, 'hockey', null, 40, 16, 8, 'beginner'),
  ('sport_rugby_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Play {value} min of rugby', 'Log a rugby session of at least {value} minutes.',
   null, 'rugby', null, 40, 16, 8, 'beginner'),
  ('sport_ski_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Ski {value} min', 'Log a ski session of at least {value} minutes.',
   null, 'ski', null, 40, 16, 8, 'beginner'),
  ('sport_hyrox_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Hyrox session: {value} min', 'Log a Hyrox session of at least {value} minutes.',
   null, 'hyrox', null, 42, 18, 9, 'beginner'),
  ('sport_hyrox_duration_stretch', 'sport', 'duration_sec', 'dynamic_scaled',
   'Hyrox push: {value} min', 'Log a Hyrox session of at least {value} minutes.',
   null, 'hyrox', null, 62, 34, 16, 'stretch'),
  ('sport_hyrox_weekly_stretch', 'sport', 'hyrox_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of Hyrox', 'Accumulate {value} minutes of Hyrox training this week.',
   null, 'hyrox', null, 58, 32, 15, 'stretch'),
  ('sport_hyrox_sessions_weekly_stretch', 'sport', 'sport_sessions_weekly', 'dynamic_scaled',
   'Complete {value} Hyrox sessions', 'Log {value} Hyrox sessions this week.',
   null, 'hyrox', null, 60, 34, 16, 'stretch'),
  ('sport_climbing_duration_beginner', 'sport', 'duration_sec', 'static_beginner',
   'Climb {value} min', 'Log a climbing session of at least {value} minutes.',
   null, 'climbing', null, 42, 18, 9, 'beginner'),
  ('sport_climbing_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min climbing', 'Accumulate {value} minutes climbing this week.',
   null, 'climbing', null, 58, 32, 15, 'stretch'),
  ('sport_climbing_routes_sent_stretch', 'sport', 'routes_sent', 'dynamic_scaled',
   'Send {value} routes', 'Send at least {value} routes in one climbing session.',
   null, 'climbing', null, 62, 34, 16, 'stretch'),
  ('sport_climbing_problems_sent_stretch', 'sport', 'problems_sent', 'dynamic_scaled',
   'Send {value} problems', 'Send at least {value} boulder problems in one climbing session.',
   null, 'climbing', null, 62, 34, 16, 'stretch'),
  ('sport_football_weekly_stretch_v4', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of football', 'Accumulate {value} minutes playing football this week.',
   null, 'football', null, 55, 30, 14, 'stretch'),
  ('sport_badminton_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of badminton', 'Accumulate {value} minutes playing badminton this week.',
   null, 'badminton', null, 55, 30, 14, 'stretch'),
  ('sport_squash_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of squash', 'Accumulate {value} minutes playing squash this week.',
   null, 'squash', null, 55, 30, 14, 'stretch'),
  ('sport_volleyball_weekly_stretch', 'sport', 'sport_weekly_minutes', 'dynamic_scaled',
   'Rack up {value} min of volleyball', 'Accumulate {value} minutes playing volleyball this week.',
   null, 'volleyball', null, 55, 30, 14, 'stretch'),
  ('cardio_walk_distance_stretch', 'cardio', 'distance_km', 'dynamic_scaled',
   'Walk farther: {value} km', 'Log a walk of at least {value} km in one session.',
   'walk', null, null, 52, 28, 13, 'stretch')
on conflict (code) do nothing;

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
  elsif p_metric in (
    'sport_weekly_minutes', 'hyrox_weekly_minutes',
    'total_reps', 'total_sets', 'routes_sent', 'problems_sent', 'sport_sessions_weekly'
  ) then
    return trim(to_char(round(p_value), 'FM999999'));
  elsif p_metric in ('distance_km', 'volume_kg', 'max_weight_kg') then
    return trim(to_char(p_value, 'FM9999990.0'));
  else
    return trim(to_char(round(p_value), 'FM999999'));
  end if;
end;
$$;

create or replace function public._user_tasks_hist_strength_reps_sets(
  p_user_id uuid,
  p_muscle text,
  p_since timestamptz
)
returns table (
  avg_total_reps numeric,
  max_total_reps numeric,
  avg_total_sets numeric,
  max_total_sets numeric
)
language sql
stable
security definer
set search_path to public
as $$
  with per_workout as (
    select
      w.id,
      coalesce(sum(es.reps), 0)::numeric as total_reps,
      count(*) filter (where coalesce(es.is_completed, true))::numeric as total_sets
    from public.workouts w
    join public.workout_exercises we on we.workout_id = w.id
    join public.exercise_sets es on es.workout_exercise_id = we.id
    left join public.exercises e on e.id = we.exercise_id
    where w.user_id = p_user_id
      and w.kind = 'strength'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_since
      and coalesce(es.is_completed, true)
      and (
        p_muscle is null
        or e.muscle_primary = p_muscle
        or e.muscle_primary = replace(p_muscle, 'pecho', 'chest')
      )
    group by w.id
  )
  select
    coalesce(avg(total_reps), 0),
    coalesce(max(total_reps), 0),
    coalesce(avg(total_sets), 0),
    coalesce(max(total_sets), 0)
  from per_workout;
$$;

create or replace function public._user_tasks_hist_climbing_stats(
  p_user_id uuid,
  p_since timestamptz
)
returns table (
  avg_routes_sent numeric,
  max_routes_sent numeric,
  avg_problems_sent numeric,
  max_problems_sent numeric,
  avg_session_minutes numeric,
  avg_weekly_minutes numeric
)
language sql
stable
security definer
set search_path to public
as $$
  with sessions as (
    select
      coalesce(cls.routes_sent, 0)::numeric as routes_sent,
      coalesce(cls.problems_sent, 0)::numeric as problems_sent,
      coalesce(ss.duration_sec, 0) / 60.0 as session_minutes,
      date_trunc('week', coalesce(w.started_at, w.created_at)) as wk
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    left join public.climbing_session_stats cls on cls.session_id = ss.id
    where w.user_id = p_user_id
      and w.kind = 'sport'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and ss.sport = 'climbing'
      and coalesce(w.started_at, w.created_at) >= p_since
  ),
  weekly as (
    select wk, sum(session_minutes) as week_minutes
    from sessions
    group by wk
  )
  select
    coalesce(avg(s.routes_sent), 0),
    coalesce(max(s.routes_sent), 0),
    coalesce(avg(s.problems_sent), 0),
    coalesce(max(s.problems_sent), 0),
    coalesce(avg(s.session_minutes), 0),
    coalesce((select avg(week_minutes) from weekly), 0)
  from sessions s;
$$;

create or replace function public._user_tasks_hist_hyrox_stats(
  p_user_id uuid,
  p_since timestamptz
)
returns table (
  avg_session_minutes numeric,
  avg_weekly_minutes numeric,
  avg_weekly_sessions numeric
)
language sql
stable
security definer
set search_path to public
as $$
  with sessions as (
    select
      coalesce(ss.duration_sec, 0) / 60.0 as session_minutes,
      date_trunc('week', coalesce(w.started_at, w.created_at)) as wk
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_user_id
      and w.kind = 'sport'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and ss.sport = 'hyrox'
      and coalesce(w.started_at, w.created_at) >= p_since
  ),
  weekly as (
    select wk, sum(session_minutes) as week_minutes, count(*)::numeric as session_count
    from sessions
    group by wk
  )
  select
    coalesce((select avg(s.session_minutes) from sessions s), 0),
    coalesce((select avg(week_minutes) from weekly), 0),
    coalesce((select avg(session_count) from weekly), 0);
$$;

create or replace function public._user_tasks_weighted_pick_cardio_activity(
  p_user_id uuid,
  p_since timestamptz
)
returns text
language sql
stable
security definer
set search_path to public
as $$
  with counts as (
    select coalesce(cs.activity_code, cs.modality) as activity, count(*)::numeric as cnt
    from public.workouts w
    join public.cardio_sessions cs on cs.workout_id = w.id
    where w.user_id = p_user_id
      and w.kind = 'cardio'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_since
      and coalesce(cs.activity_code, cs.modality) is not null
    group by 1
  ),
  weighted as (
    select activity, cnt,
      sum(cnt) over () as total,
      sum(cnt) over (order by activity) as cum
    from counts
  )
  select coalesce(
    (
      select activity
      from weighted
      where total > 0
        and random() * total < cum
      order by cum
      limit 1
    ),
    public._user_tasks_dominant_cardio_activity(p_user_id, p_since)
  );
$$;

create or replace function public._user_tasks_weighted_pick_sport(
  p_user_id uuid,
  p_since timestamptz
)
returns text
language sql
stable
security definer
set search_path to public
as $$
  with counts as (
    select ss.sport as sport, count(*)::numeric as cnt
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_user_id
      and w.kind = 'sport'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_since
    group by ss.sport
  ),
  weighted as (
    select sport, cnt,
      sum(cnt) over () as total,
      sum(cnt) over (order by sport) as cum
    from counts
  )
  select coalesce(
    (
      select sport
      from weighted
      where total > 0
        and random() * total < cum
      order by cum
      limit 1
    ),
    public._user_tasks_dominant_sport(p_user_id, p_since)
  );
$$;

create or replace function public._user_tasks_weighted_pick_muscle(
  p_user_id uuid,
  p_since timestamptz
)
returns text
language sql
stable
security definer
set search_path to public
as $$
  with counts as (
    select e.muscle_primary as muscle, count(*)::numeric as cnt
    from public.workouts w
    join public.workout_exercises we on we.workout_id = w.id
    join public.exercises e on e.id = we.exercise_id
    where w.user_id = p_user_id
      and w.kind = 'strength'::public.workout_kind
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_since
      and e.muscle_primary is not null
    group by e.muscle_primary
  ),
  weighted as (
    select muscle, cnt,
      sum(cnt) over () as total,
      sum(cnt) over (order by muscle) as cum
    from counts
  )
  select (
    select muscle
    from weighted
    where total > 0
      and random() * total < cum
    order by cum
    limit 1
  );
$$;

create or replace function public._user_tasks_weighted_menu_slots(
  p_user_id uuid,
  p_slots int default 5
)
returns table (
  slot_index int,
  category text,
  scope_activity_code text,
  scope_sport text,
  scope_muscle_primary text
)
language plpgsql
volatile
security definer
set search_path to public
as $$
declare
  v_since timestamptz := now() - interval '45 days';
  v_total int;
  v_cold boolean;
  v_alloc record;
  v_remaining int;
  v_slot int := 0;
  v_cat text;
  v_defaults text[] := array['cardio', 'strength', 'sport', 'cardio', 'strength'];
  v_i int;
begin
  select
    public._user_tasks_count_category_workouts(p_user_id, 'cardio', v_since)
    + public._user_tasks_count_category_workouts(p_user_id, 'strength', v_since)
    + public._user_tasks_count_category_workouts(p_user_id, 'sport', v_since)
  into v_total;

  v_cold := coalesce(v_total, 0) < 3;

  if v_cold then
    for v_i in 1..least(p_slots, array_length(v_defaults, 1)) loop
      v_cat := v_defaults[v_i];
      slot_index := v_i;
      category := v_cat;
      scope_activity_code := case when v_cat = 'cardio' then
        case v_i when 1 then 'walk' when 4 then 'run' else null end
      else null end;
      scope_sport := case when v_cat = 'sport' then 'football' else null end;
      scope_muscle_primary := null;
      return next;
    end loop;
    return;
  end if;

  create temp table if not exists _tmp_menu_alloc (
    category text primary key,
    base_slots int not null default 0,
    remainder numeric not null default 0
  ) on commit drop;

  truncate _tmp_menu_alloc;

  insert into _tmp_menu_alloc (category, base_slots, remainder)
  select
    cat,
    floor((cnt::numeric / v_total::numeric) * p_slots)::int,
    (cnt::numeric / v_total::numeric) * p_slots - floor((cnt::numeric / v_total::numeric) * p_slots)
  from (
    select 'cardio'::text as cat, public._user_tasks_count_category_workouts(p_user_id, 'cardio', v_since) as cnt
    union all
    select 'strength', public._user_tasks_count_category_workouts(p_user_id, 'strength', v_since)
    union all
    select 'sport', public._user_tasks_count_category_workouts(p_user_id, 'sport', v_since)
  ) x
  where cnt > 0;

  select p_slots - coalesce(sum(t.base_slots), 0) into v_remaining from _tmp_menu_alloc t;

  for v_alloc in
    select a.category
    from _tmp_menu_alloc a
    where a.remainder > 0
    order by a.remainder desc, a.category
    limit greatest(v_remaining, 0)
  loop
    update _tmp_menu_alloc t
    set base_slots = t.base_slots + 1,
        remainder = -1
    where t.category = v_alloc.category;
    v_remaining := v_remaining - 1;
  end loop;

  for v_alloc in
    select a.category, a.base_slots
    from _tmp_menu_alloc a
    where a.base_slots > 0
    order by a.category
  loop
    for v_i in 1..v_alloc.base_slots loop
      v_slot := v_slot + 1;
      slot_index := v_slot;
      category := v_alloc.category;
      if v_alloc.category = 'cardio' then
        scope_activity_code := public._user_tasks_weighted_pick_cardio_activity(p_user_id, v_since);
        scope_sport := null;
        scope_muscle_primary := null;
      elsif v_alloc.category = 'sport' then
        scope_activity_code := null;
        scope_sport := public._user_tasks_weighted_pick_sport(p_user_id, v_since);
        scope_muscle_primary := null;
      else
        scope_activity_code := null;
        scope_sport := null;
        scope_muscle_primary := public._user_tasks_weighted_pick_muscle(p_user_id, v_since);
      end if;
      return next;
    end loop;
  end loop;

  while v_slot < p_slots loop
    v_slot := v_slot + 1;
    select a.category into v_cat from _tmp_menu_alloc a order by a.base_slots desc, a.category limit 1;
    slot_index := v_slot;
    category := coalesce(v_cat, 'cardio');
    scope_activity_code := case when coalesce(v_cat, 'cardio') = 'cardio'
      then public._user_tasks_weighted_pick_cardio_activity(p_user_id, v_since) else null end;
    scope_sport := case when v_cat = 'sport'
      then public._user_tasks_weighted_pick_sport(p_user_id, v_since) else null end;
    scope_muscle_primary := case when v_cat = 'strength'
      then public._user_tasks_weighted_pick_muscle(p_user_id, v_since) else null end;
    return next;
  end loop;
end;
$$;

create or replace function public._user_tasks_signature(
  p_category text,
  p_metric text,
  p_activity text,
  p_sport text,
  p_muscle text
)
returns text
language sql
immutable
as $$
  select lower(coalesce(p_category, '')) || '|'
    || lower(coalesce(p_metric, '')) || '|'
    || coalesce(p_activity, '') || '|'
    || coalesce(p_sport, '') || '|'
    || coalesce(p_muscle, '');
$$;

create or replace function public._user_tasks_template_scope_match_score(
  p_template public.task_templates,
  p_activity text,
  p_sport text,
  p_muscle text
)
returns int
language sql
immutable
as $$
  select
    case when p_template.scope_activity_code is not null
      and p_template.scope_activity_code = coalesce(p_activity, p_template.scope_activity_code) then 0 else 1 end
    + case when p_template.scope_sport is not null
      and p_template.scope_sport = coalesce(p_sport, p_template.scope_sport) then 0 else 1 end
    + case when p_template.scope_muscle_primary is not null
      and (
        p_template.scope_muscle_primary = coalesce(p_muscle, p_template.scope_muscle_primary)
        or replace(p_template.scope_muscle_primary, 'pecho', 'chest') = coalesce(p_muscle, p_template.scope_muscle_primary)
      ) then 0 else 1 end
    + case when p_template.scope_activity_code is not null
      and p_activity is not null
      and p_template.scope_activity_code <> p_activity then 4 else 0 end
    + case when p_template.scope_sport is not null
      and p_sport is not null
      and p_template.scope_sport <> p_sport then 4 else 0 end
    + case when p_template.scope_muscle_primary is not null
      and p_muscle is not null
      and p_template.scope_muscle_primary <> p_muscle
      and replace(p_template.scope_muscle_primary, 'pecho', 'chest') <> p_muscle then 4 else 0 end;
$$;

create or replace function public._user_tasks_pick_template_for_slot(
  p_user_id uuid,
  p_category text,
  p_activity text,
  p_sport text,
  p_muscle text,
  p_exclude_ids int[],
  p_exclude_sigs text[],
  p_since timestamptz,
  p_prefer_beginner boolean default false
)
returns public.task_templates
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_template public.task_templates;
  v_sig text;
begin
  select t.* into v_template
  from public.task_templates t
  where t.is_active
    and t.category = p_category
    and (
      p_prefer_beginner and t.generation_mode = 'static_beginner'
      or not p_prefer_beginner and t.generation_mode = 'dynamic_scaled'
    )
    and (p_exclude_ids is null or not (t.id = any (p_exclude_ids)))
    and (
      p_exclude_sigs is null
      or not (
        public._user_tasks_signature(
          t.category, t.target_metric, t.scope_activity_code, t.scope_sport, t.scope_muscle_primary
        ) = any (p_exclude_sigs)
      )
    )
    and public._user_tasks_template_scope_match_score(t, p_activity, p_sport, p_muscle) < 8
    and (
      p_prefer_beginner
      or public._user_tasks_template_is_eligible(p_user_id, t, p_since)
    )
  order by
    public._user_tasks_template_scope_match_score(t, p_activity, p_sport, p_muscle),
  random()
  limit 1;

  if v_template.id is not null then
    return v_template;
  end if;

  if not p_prefer_beginner then
    return public._user_tasks_pick_template_for_slot(
      p_user_id, p_category, p_activity, p_sport, p_muscle,
      p_exclude_ids, p_exclude_sigs, p_since, true
    );
  end if;

  return v_template;
end;
$$;

create or replace function public._user_tasks_generate_for_slot(
  p_user_id uuid,
  p_category text,
  p_activity text,
  p_sport text,
  p_muscle text,
  p_week_start timestamptz,
  p_week_end timestamptz,
  p_exclude_ids int[],
  p_exclude_sigs text[]
)
returns table (used_ids int[], used_sigs text[])
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
  v_climbing record;
  v_hyrox record;
  v_reps_sets record;
  v_used int[] := coalesce(p_exclude_ids, array[]::int[]);
  v_sigs text[] := coalesce(p_exclude_sigs, array[]::text[]);
  v_hist_scope text;
  v_best_pace numeric;
  v_median_km numeric;
  v_baseline numeric;
  v_diff record;
  v_sig text;
  v_attempt int;
  v_cold boolean;
begin
  v_cat_count := public._user_tasks_count_category_workouts(p_user_id, p_category, v_since_45);
  v_cold := (
    public._user_tasks_count_category_workouts(p_user_id, 'cardio', v_since_45)
    + public._user_tasks_count_category_workouts(p_user_id, 'strength', v_since_45)
    + public._user_tasks_count_category_workouts(p_user_id, 'sport', v_since_45)
  ) < 3;

  v_template := null;
  for v_attempt in 1..6 loop
    v_template := public._user_tasks_pick_template_for_slot(
      p_user_id, p_category, p_activity, p_sport, p_muscle,
      v_used, v_sigs, v_since_45, v_cold or v_cat_count < 3
    );
    exit when v_template.id is not null;
    v_used := array_append(v_used, -v_attempt);
  end loop;

  if v_template.id is null then
    used_ids := v_used;
    used_sigs := v_sigs;
    return next;
    return;
  end if;

  v_sig := public._user_tasks_signature(
    v_template.category, v_template.target_metric,
    v_template.scope_activity_code, v_template.scope_sport, v_template.scope_muscle_primary
  );

  if v_cold or v_cat_count < 3 then
    v_target := case v_template.target_metric
      when 'distance_km' then 3
      when 'duration_sec' then 2700
      when 'sport_weekly_minutes' then 60
      when 'hyrox_weekly_minutes' then 60
      when 'sport_sessions_weekly' then 2
      when 'total_reps' then 80
      when 'total_sets' then 12
      when 'routes_sent' then 3
      when 'problems_sent' then 3
      else 3
    end;
    v_secondary := null;
    select * into v_diff from public._user_tasks_difficulty_band(v_template.target_metric, v_target, v_target, null);
  else
    v_hist_scope := case
      when public._user_tasks_template_scope_sample_count(p_user_id, v_template, v_since_30) >= 3
        then coalesce(v_template.scope_activity_code, p_activity)
      else null
    end;

    if p_category = 'cardio' then
      select * into v_cardio
      from public._user_tasks_hist_cardio_stats(p_user_id, coalesce(v_hist_scope, p_activity), v_since_30);

      if v_template.target_metric = 'pace_sec_per_km' then
        v_best_pace := public._user_tasks_hist_cardio_best_pace(
          p_user_id, coalesce(v_hist_scope, v_template.scope_activity_code, p_activity), v_since_30
        );
        if v_best_pace <= 0 then
          used_ids := v_used;
          used_sigs := v_sigs;
          return next;
          return;
        end if;
        v_target := greatest(round(v_best_pace * 0.97), round(v_best_pace * 0.90));
        v_secondary := greatest(1, round(greatest(v_cardio.avg_distance_km * 0.8, v_cardio.max_distance_km * 0.5), 1));
        v_baseline := v_best_pace;
      elsif v_template.target_metric = 'distance_km' then
        v_median_km := public._user_tasks_hist_cardio_median_distance(
          p_user_id, coalesce(v_hist_scope, p_activity), v_since_30
        );
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
      elsif v_template.target_metric = 'duration_sec' then
        v_target := greatest(1800, round(2700 * 1.05));
        v_secondary := null;
        v_baseline := 2700;
      else
        v_target := greatest(3, round(v_cardio.avg_distance_km * 1.15, 1));
        v_secondary := null;
        v_baseline := greatest(v_cardio.max_distance_km, 1);
      end if;
    elsif p_category = 'strength' then
      select * into v_strength
      from public._user_tasks_hist_strength_stats(
        p_user_id, coalesce(v_template.scope_muscle_primary, p_muscle), v_since_30
      );
      select * into v_reps_sets
      from public._user_tasks_hist_strength_reps_sets(
        p_user_id, coalesce(v_template.scope_muscle_primary, p_muscle), v_since_30
      );

      v_target := case v_template.target_metric
        when 'max_weight_kg' then greatest(20, round(v_strength.max_weight_kg * 1.05, 1))
        when 'volume_kg' then greatest(500, round(v_strength.avg_session_volume_kg * 1.15, 0))
        when 'calories_kcal' then greatest(150, round(v_strength.avg_calories * 1.1))
        when 'duration_sec' then greatest(1800, round(2700 * 1.0))
        when 'total_reps' then greatest(50, round(v_reps_sets.avg_total_reps * 1.15, 0))
        when 'total_sets' then greatest(10, round(v_reps_sets.avg_total_sets * 1.15, 0))
        else greatest(500, round(v_strength.avg_session_volume_kg * 1.15, 0))
      end;
      v_secondary := null;
      v_baseline := case v_template.target_metric
        when 'max_weight_kg' then greatest(v_strength.max_weight_kg, 20)
        when 'volume_kg' then greatest(v_strength.avg_session_volume_kg, 500)
        when 'calories_kcal' then greatest(v_strength.avg_calories, 150)
        when 'total_reps' then greatest(v_reps_sets.avg_total_reps, 50)
        when 'total_sets' then greatest(v_reps_sets.avg_total_sets, 10)
        else greatest(v_strength.avg_session_volume_kg, 500)
      end;
    else
      if coalesce(v_template.scope_sport, p_sport) = 'climbing' then
        select * into v_climbing
        from public._user_tasks_hist_climbing_stats(p_user_id, v_since_30);
        v_target := case v_template.target_metric
          when 'routes_sent' then greatest(2, round(v_climbing.avg_routes_sent * 1.2, 0))
          when 'problems_sent' then greatest(2, round(v_climbing.avg_problems_sent * 1.2, 0))
          when 'sport_weekly_minutes' then greatest(30, round(v_climbing.avg_weekly_minutes * 1.5, 0))
          when 'duration_sec' then greatest(1800, round(v_climbing.avg_session_minutes * 60 * 1.1))
          else greatest(30, round(v_climbing.avg_weekly_minutes * 1.5, 0))
        end;
        v_baseline := case v_template.target_metric
          when 'routes_sent' then greatest(v_climbing.max_routes_sent, 2)
          when 'problems_sent' then greatest(v_climbing.max_problems_sent, 2)
          when 'duration_sec' then greatest(v_climbing.avg_session_minutes * 60, 1800)
          else greatest(v_climbing.avg_weekly_minutes, 30)
        end;
      elsif coalesce(v_template.scope_sport, p_sport) = 'hyrox' then
        select * into v_hyrox
        from public._user_tasks_hist_hyrox_stats(p_user_id, v_since_30);
        v_target := case v_template.target_metric
          when 'hyrox_weekly_minutes' then greatest(30, round(v_hyrox.avg_weekly_minutes * 1.5, 0))
          when 'sport_sessions_weekly' then greatest(1, round(v_hyrox.avg_weekly_sessions * 1.2, 0))
          when 'duration_sec' then greatest(1800, round(v_hyrox.avg_session_minutes * 60 * 1.1))
          else greatest(30, round(v_hyrox.avg_weekly_minutes * 1.5, 0))
        end;
        v_baseline := case v_template.target_metric
          when 'sport_sessions_weekly' then greatest(v_hyrox.avg_weekly_sessions, 1)
          when 'duration_sec' then greatest(v_hyrox.avg_session_minutes * 60, 1800)
          else greatest(v_hyrox.avg_weekly_minutes, 30)
        end;
      else
        select * into v_sport
        from public._user_tasks_hist_sport_stats(
          p_user_id, coalesce(v_template.scope_sport, p_sport), v_since_30
        );
        v_target := case v_template.target_metric
          when 'sport_weekly_minutes' then greatest(30, round(v_sport.avg_weekly_minutes * 1.5, 0))
          when 'duration_sec' then greatest(1800, round(v_sport.avg_session_minutes * 60 * 1.1))
          else greatest(30, round(v_sport.avg_weekly_minutes * 1.5, 0))
        end;
        v_baseline := case v_template.target_metric
          when 'duration_sec' then greatest(v_sport.avg_session_minutes * 60, 1800)
          else greatest(v_sport.avg_weekly_minutes, 30)
        end;
      end if;
      v_secondary := null;
    end if;

    select * into v_diff
    from public._user_tasks_difficulty_band(v_template.target_metric, v_target, v_baseline, null);
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
  v_sigs := array_append(v_sigs, v_sig);
  used_ids := v_used;
  used_sigs := v_sigs;
  return next;
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
  v_slot record;
  v_used int[] := array[]::int[];
  v_sigs text[] := array[]::text[];
  v_result record;
begin
  for v_slot in
    select * from public._user_tasks_weighted_menu_slots(p_user_id, 5)
    order by slot_index
  loop
    select * into v_result
    from public._user_tasks_generate_for_slot(
      p_user_id,
      v_slot.category,
      v_slot.scope_activity_code,
      v_slot.scope_sport,
      v_slot.scope_muscle_primary,
      p_week_start,
      p_week_end,
      v_used,
      v_sigs
    );
    v_used := v_result.used_ids;
    v_sigs := v_result.used_sigs;
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
  v_slot record;
  v_used int[] := array[]::int[];
  v_sigs text[] := array[]::text[];
  v_result record;
  v_existing int;
  v_i int;
begin
  select coalesce(array_agg(ut.template_id), array[]::int[]) into v_used
  from public.user_tasks ut
  where ut.user_id = p_user_id
    and ut.week_start = p_week_start
    and ut.status in ('generated', 'accepted', 'completed');

  select coalesce(array_agg(distinct public._user_tasks_signature(
    ut.category, ut.target_metric, ut.scope_activity_code, ut.scope_sport, ut.scope_muscle_primary
  )), array[]::text[]) into v_sigs
  from public.user_tasks ut
  where ut.user_id = p_user_id
    and ut.week_start = p_week_start
    and ut.status in ('generated', 'accepted', 'completed');

  for v_i in 1..10 loop
    select count(*) into v_existing
    from public.user_tasks ut
    where ut.user_id = p_user_id
      and ut.week_start = p_week_start
      and ut.status in ('generated', 'accepted', 'completed');
    exit when v_existing >= 5;

    for v_slot in
      select * from public._user_tasks_weighted_menu_slots(p_user_id, 5)
      order by slot_index
    loop
      select count(*) into v_existing
      from public.user_tasks ut
      where ut.user_id = p_user_id
        and ut.week_start = p_week_start
        and ut.status in ('generated', 'accepted', 'completed');
      exit when v_existing >= 5;

      select * into v_result
      from public._user_tasks_generate_for_slot(
        p_user_id,
        v_slot.category,
        v_slot.scope_activity_code,
        v_slot.scope_sport,
        v_slot.scope_muscle_primary,
        p_week_start,
        p_week_end,
        v_used,
        v_sigs
      );
      v_used := v_result.used_ids;
      v_sigs := v_result.used_sigs;

      select count(*) into v_existing
      from public.user_tasks ut
      where ut.user_id = p_user_id
        and ut.week_start = p_week_start
        and ut.status in ('generated', 'accepted', 'completed');
      exit when v_existing >= 5;
    end loop;
  end loop;
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
  v_hyrox_week_minutes numeric;
  v_sport_sessions numeric;
  v_total_reps numeric;
  v_total_sets numeric;
  v_routes_sent int;
  v_problems_sent int;
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

  if p_task.target_metric = 'hyrox_weekly_minutes' then
    select coalesce(sum(ss.duration_sec), 0) / 60.0 into v_hyrox_week_minutes
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and ss.sport = 'hyrox'
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at;
    return v_hyrox_week_minutes >= p_task.target_value;
  end if;

  if p_task.target_metric = 'sport_sessions_weekly' then
    select count(*)::numeric into v_sport_sessions
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at
      and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    return v_sport_sessions >= p_task.target_value;
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
  elsif p_task.target_metric = 'total_reps' then
    select coalesce(sum(es.reps), 0) into v_total_reps
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
    return v_total_reps >= p_task.target_value;
  elsif p_task.target_metric = 'total_sets' then
    select count(*)::numeric into v_total_sets
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
    return v_total_sets >= p_task.target_value;
  elsif p_task.target_metric in ('routes_sent', 'problems_sent') then
    select cls.routes_sent, cls.problems_sent
    into v_routes_sent, v_problems_sent
    from public.sport_sessions ss
    left join public.climbing_session_stats cls on cls.session_id = ss.id
    where ss.workout_id = p_workout_id
      and ss.sport = 'climbing'
      and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    if p_task.target_metric = 'routes_sent' then
      return coalesce(v_routes_sent, 0) >= p_task.target_value;
    end if;
    return coalesce(v_problems_sent, 0) >= p_task.target_value;
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
  v_sessions numeric;
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

  if p_task.target_metric = 'hyrox_weekly_minutes' then
    select coalesce(sum(ss.duration_sec), 0) / 60.0 into v_minutes
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and ss.sport = 'hyrox'
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at;
    return v_minutes;
  end if;

  if p_task.target_metric = 'sport_sessions_weekly' then
    select count(*)::numeric into v_sessions
    from public.workouts w
    join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = p_task.user_id
      and w.state = 'published'::public.workout_state
      and coalesce(w.started_at, w.created_at) >= p_task.week_start
      and coalesce(w.started_at, w.created_at) < p_task.expires_at
      and (p_task.scope_sport is null or ss.sport = p_task.scope_sport);
    return v_sessions;
  end if;

  return null;
end;
$$;

delete from public.user_tasks ut
where ut.status in ('generated', 'accepted')
  and ut.week_start = (
    select b.w_start from public._challenge_week_bounds_utc(now()) as b
  );

commit;

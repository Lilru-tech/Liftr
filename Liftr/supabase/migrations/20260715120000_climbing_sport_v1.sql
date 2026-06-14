begin;

do $$ begin
  create type public.climbing_environment as enum ('indoor', 'outdoor');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.climbing_style as enum ('boulder', 'top_rope', 'lead', 'trad', 'mixed');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.climbing_grade_system as enum ('v_scale', 'font', 'french', 'yds');
exception when duplicate_object then null;
end $$;

create table if not exists public.climbing_session_stats (
  session_id bigint primary key references public.sport_sessions(id) on delete cascade,
  environment public.climbing_environment,
  primary_style public.climbing_style,
  routes_sent integer,
  routes_attempted integer,
  problems_sent integer,
  problems_attempted integer,
  highest_grade_system public.climbing_grade_system,
  highest_grade_value text,
  highest_grade_normalized numeric,
  total_vertical_m integer,
  moving_time_sec integer,
  paused_time_sec integer,
  venue_name text,
  weather text,
  avg_hr integer,
  max_hr integer,
  falls integer,
  flashes integer,
  created_at timestamptz not null default now()
);

create table if not exists public.climbing_session_routes (
  id bigserial primary key,
  session_id bigint not null references public.sport_sessions(id) on delete cascade,
  route_order smallint not null default 1,
  route_name text,
  style public.climbing_style,
  grade_system public.climbing_grade_system,
  grade_value text,
  grade_normalized numeric,
  attempts integer,
  sent boolean not null default false,
  flash boolean not null default false,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists climbing_session_routes_session_id_idx
  on public.climbing_session_routes(session_id, route_order);

create or replace function public.climbing_grade_normalize(
  p_system text,
  p_value text
) returns numeric
language plpgsql
immutable
as $function$
declare
  s text := lower(btrim(coalesce(p_system, '')));
  v text := btrim(coalesce(p_value, ''));
  v_upper text := upper(v);
  m text[];
  major int;
  minor text;
  suffix int := 0;
begin
  if v = '' then
    return null;
  end if;

  if s = 'v_scale' then
    v_upper := regexp_replace(v_upper, '^V', '', 'i');
    if v_upper ~ '^[0-9]+(\.[0-9]+)?$' then
      return v_upper::numeric;
    end if;
    return null;
  end if;

  if s = 'font' then
    v_upper := regexp_replace(v_upper, '\s', '', 'g');
    m := regexp_match(v_upper, '^([0-9])([A-C])(\+?)$');
    if m is not null then
      major := m[1]::int;
      minor := m[2];
      suffix := case when m[3] = '+' then 1 else 0 end;
      return (major * 10)::numeric
        + case minor when 'A' then 0 when 'B' then 1 when 'C' then 2 else 0 end
        + suffix * 0.5;
    end if;
    return null;
  end if;

  if s = 'french' then
    v := regexp_replace(lower(v), '\s', '', 'g');
    m := regexp_match(v, '^([3-9])([a-c])(\+?)$');
    if m is not null then
      major := m[1]::int;
      minor := m[2];
      suffix := case when m[3] = '+' then 1 else 0 end;
      return (major * 10)::numeric
        + case minor when 'a' then 0 when 'b' then 1 when 'c' then 2 else 0 end
        + suffix * 0.5;
    end if;
    return null;
  end if;

  if s = 'yds' then
    v := regexp_replace(v, '\s', '', 'g');
    m := regexp_match(v, '^5\.([0-9]{1,2})([A-Da-d])?$');
    if m is not null then
      major := m[1]::int;
      minor := upper(coalesce(m[2], ''));
      return (500 + major)::numeric
        + case minor
          when 'A' then 0.0 when 'B' then 0.33 when 'C' then 0.66 when 'D' then 0.99
          else 0.0
          end;
    end if;
    return null;
  end if;

  return null;
end;
$function$;

create or replace function public.apply_climbing_sport_stats(
  p_session_id bigint,
  p_stats jsonb,
  p_replace_routes boolean default true
) returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_route jsonb;
  v_route_order smallint := 0;
  v_routes_sent int := 0;
  v_routes_attempted int := 0;
  v_problems_sent int := 0;
  v_problems_attempted int := 0;
  v_flashes int := 0;
  v_falls int := 0;
  v_highest_norm numeric := null;
  v_highest_system public.climbing_grade_system;
  v_highest_value text;
  v_grade_norm numeric;
  v_moving_sec int;
  v_paused_sec int;
  v_has_routes boolean := false;
begin
  if p_stats is null then
    return;
  end if;

  v_moving_sec := nullif(p_stats->>'moving_time_sec', '')::int;
  v_paused_sec := nullif(p_stats->>'paused_time_sec', '')::int;

  if p_replace_routes then
    delete from public.climbing_session_routes where session_id = p_session_id;
  end if;

  if jsonb_typeof(p_stats->'routes') = 'array' then
    v_has_routes := jsonb_array_length(p_stats->'routes') > 0;
    for v_route in
      select value from jsonb_array_elements(p_stats->'routes')
    loop
      v_route_order := v_route_order + 1;
      v_grade_norm := public.climbing_grade_normalize(
        nullif(v_route->>'grade_system', ''),
        nullif(v_route->>'grade_value', '')
      );

      if coalesce((nullif(v_route->>'sent', ''))::boolean, false) then
        v_routes_sent := v_routes_sent + 1;
        if coalesce((nullif(v_route->>'flash', ''))::boolean, false) then
          v_flashes := v_flashes + 1;
        end if;
        if v_grade_norm is not null and (v_highest_norm is null or v_grade_norm > v_highest_norm) then
          v_highest_norm := v_grade_norm;
          v_highest_system := nullif(v_route->>'grade_system', '')::public.climbing_grade_system;
          v_highest_value := nullif(v_route->>'grade_value', '');
        end if;
      end if;

      if nullif(v_route->>'attempts', '') is not null then
        v_routes_attempted := v_routes_attempted + greatest(0, (v_route->>'attempts')::int);
      elsif coalesce((nullif(v_route->>'sent', ''))::boolean, false) then
        v_routes_attempted := v_routes_attempted + 1;
      end if;

      if lower(coalesce(v_route->>'style', '')) = 'boulder' then
        if coalesce((nullif(v_route->>'sent', ''))::boolean, false) then
          v_problems_sent := v_problems_sent + 1;
        end if;
        if nullif(v_route->>'attempts', '') is not null then
          v_problems_attempted := v_problems_attempted + greatest(0, (v_route->>'attempts')::int);
        elsif coalesce((nullif(v_route->>'sent', ''))::boolean, false) then
          v_problems_attempted := v_problems_attempted + 1;
        end if;
      end if;

      insert into public.climbing_session_routes (
        session_id, route_order, route_name, style, grade_system, grade_value,
        grade_normalized, attempts, sent, flash, notes
      ) values (
        p_session_id,
        coalesce(nullif(v_route->>'route_order', '')::smallint, v_route_order),
        nullif(v_route->>'route_name', ''),
        nullif(v_route->>'style', '')::public.climbing_style,
        nullif(v_route->>'grade_system', '')::public.climbing_grade_system,
        nullif(v_route->>'grade_value', ''),
        v_grade_norm,
        nullif(v_route->>'attempts', '')::int,
        coalesce((nullif(v_route->>'sent', ''))::boolean, false),
        coalesce((nullif(v_route->>'flash', ''))::boolean, false),
        nullif(v_route->>'notes', '')
      );
    end loop;
  end if;

  if not v_has_routes then
    v_routes_sent := coalesce(nullif(p_stats->>'routes_sent', '')::int, 0);
    v_routes_attempted := coalesce(nullif(p_stats->>'routes_attempted', '')::int, 0);
    v_problems_sent := coalesce(nullif(p_stats->>'problems_sent', '')::int, 0);
    v_problems_attempted := coalesce(nullif(p_stats->>'problems_attempted', '')::int, 0);
    v_flashes := coalesce(nullif(p_stats->>'flashes', '')::int, 0);
    v_falls := coalesce(nullif(p_stats->>'falls', '')::int, 0);
    v_highest_system := nullif(p_stats->>'highest_grade_system', '')::public.climbing_grade_system;
    v_highest_value := nullif(p_stats->>'highest_grade_value', '');
    v_highest_norm := public.climbing_grade_normalize(
      nullif(p_stats->>'highest_grade_system', ''),
      nullif(p_stats->>'highest_grade_value', '')
    );
  else
    v_falls := coalesce(nullif(p_stats->>'falls', '')::int, 0);
  end if;

  insert into public.climbing_session_stats (
    session_id, environment, primary_style,
    routes_sent, routes_attempted, problems_sent, problems_attempted,
    highest_grade_system, highest_grade_value, highest_grade_normalized,
    total_vertical_m, moving_time_sec, paused_time_sec,
    venue_name, weather, avg_hr, max_hr, falls, flashes
  ) values (
    p_session_id,
    nullif(p_stats->>'environment', '')::public.climbing_environment,
    nullif(p_stats->>'primary_style', '')::public.climbing_style,
    v_routes_sent,
    v_routes_attempted,
    v_problems_sent,
    v_problems_attempted,
    v_highest_system,
    v_highest_value,
    v_highest_norm,
    nullif(p_stats->>'total_vertical_m', '')::int,
    v_moving_sec,
    v_paused_sec,
    nullif(p_stats->>'venue_name', ''),
    nullif(p_stats->>'weather', ''),
    nullif(p_stats->>'avg_hr', '')::int,
    nullif(p_stats->>'max_hr', '')::int,
    v_falls,
    v_flashes
  )
  on conflict (session_id) do update set
    environment = coalesce(excluded.environment, public.climbing_session_stats.environment),
    primary_style = coalesce(excluded.primary_style, public.climbing_session_stats.primary_style),
    routes_sent = coalesce(excluded.routes_sent, public.climbing_session_stats.routes_sent),
    routes_attempted = coalesce(excluded.routes_attempted, public.climbing_session_stats.routes_attempted),
    problems_sent = coalesce(excluded.problems_sent, public.climbing_session_stats.problems_sent),
    problems_attempted = coalesce(excluded.problems_attempted, public.climbing_session_stats.problems_attempted),
    highest_grade_system = coalesce(excluded.highest_grade_system, public.climbing_session_stats.highest_grade_system),
    highest_grade_value = coalesce(excluded.highest_grade_value, public.climbing_session_stats.highest_grade_value),
    highest_grade_normalized = coalesce(excluded.highest_grade_normalized, public.climbing_session_stats.highest_grade_normalized),
    total_vertical_m = coalesce(excluded.total_vertical_m, public.climbing_session_stats.total_vertical_m),
    moving_time_sec = coalesce(excluded.moving_time_sec, public.climbing_session_stats.moving_time_sec),
    paused_time_sec = coalesce(excluded.paused_time_sec, public.climbing_session_stats.paused_time_sec),
    venue_name = coalesce(excluded.venue_name, public.climbing_session_stats.venue_name),
    weather = coalesce(excluded.weather, public.climbing_session_stats.weather),
    avg_hr = coalesce(excluded.avg_hr, public.climbing_session_stats.avg_hr),
    max_hr = coalesce(excluded.max_hr, public.climbing_session_stats.max_hr),
    falls = coalesce(excluded.falls, public.climbing_session_stats.falls),
    flashes = coalesce(excluded.flashes, public.climbing_session_stats.flashes);
end;
$function$;

do $$
declare
  cfg record;
  parent_table text;
begin
  for cfg in
    select * from (values
      ('climbing_session_stats', 'sport_sessions'),
      ('climbing_session_routes', 'sport_sessions')
    ) as t(child, parent)
  loop
    execute format('alter table public.%I enable row level security', cfg.child);

    execute format('drop policy if exists "%s_select_via_session" on public.%I', cfg.child, cfg.child);
    execute format($p$
      create policy "%1$s_select_via_session"
        on public.%1$I for select to anon, authenticated
        using (exists (select 1 from public.%2$I p where p.id = %1$I.session_id))
    $p$, cfg.child, cfg.parent);

    execute format('drop policy if exists "%s_modify_owner" on public.%I', cfg.child, cfg.child);
    execute format($p$
      create policy "%1$s_modify_owner"
        on public.%1$I as permissive for all to authenticated
        using (
          exists (
            select 1 from public.%2$I p
            join public.workouts w on w.id = p.workout_id
            where p.id = %1$I.session_id and w.user_id = (select auth.uid())
          )
        )
        with check (
          exists (
            select 1 from public.%2$I p
            join public.workouts w on w.id = p.workout_id
            where p.id = %1$I.session_id and w.user_id = (select auth.uid())
          )
        )
    $p$, cfg.child, cfg.parent);
  end loop;
end $$;

create or replace function public.score_climbing_v1(p_workout_id bigint)
returns numeric
language plpgsql
as $function$
declare
  v_user uuid;
  v_int public.intensity;
  v_mult numeric := 1.0;
  v_sex_mult numeric := 1.0;
  v_mins numeric := 0;
  v_total numeric := 0;
  v_stats record;
begin
  select w.user_id, w.perceived_intensity
  into v_user, v_int
  from public.workouts w
  where w.id = p_workout_id;

  v_mult := coalesce(public.intensity_factor(v_int), 1.0);
  v_sex_mult := public.sex_factor(public.get_user_sex(v_user));

  select
    greatest(0, coalesce(ss.duration_sec, 0)) / 60.0 as mins,
    coalesce(cs.routes_sent, 0) as routes_sent,
    coalesce(cs.flashes, 0) as flashes,
    coalesce(cs.total_vertical_m, 0) as vertical_m,
    coalesce(cs.highest_grade_normalized, 0) as grade_norm
  into v_stats
  from public.sport_sessions ss
  left join public.climbing_session_stats cs on cs.session_id = ss.id
  where ss.workout_id = p_workout_id
  order by ss.id
  limit 1;

  v_mins := coalesce(v_stats.mins, 0);
  v_total :=
    (v_mins * public.sport_factor('climbing'))
    + (coalesce(v_stats.routes_sent, 0) * 8.0)
    + (coalesce(v_stats.flashes, 0) * 5.0)
    + (coalesce(v_stats.vertical_m, 0) / 50.0)
    + (coalesce(v_stats.grade_norm, 0) * 0.5);

  return greatest(0, v_total * v_mult * v_sex_mult);
end;
$function$;

create or replace function public.score_sport_v2(p_workout_id bigint)
returns numeric
language plpgsql
as $function$
declare
  v_has_hyrox boolean := false;
  v_has_climbing boolean := false;
  v_user uuid;
  v_int intensity;
  v_total numeric := 0.0;
  v_mult numeric := 1.0;
  v_sex_mult numeric := 1.0;
  rec record;
  base_per_min numeric;
  res_bonus numeric;
  diff_bonus numeric;
  mins numeric;
  s text;
begin
  select exists (
    select 1 from public.sport_sessions
    where workout_id = p_workout_id and lower(sport) = 'hyrox'
  ) into v_has_hyrox;

  if v_has_hyrox then
    return public.score_hyrox_v1(p_workout_id);
  end if;

  select exists (
    select 1 from public.sport_sessions
    where workout_id = p_workout_id and lower(sport) = 'climbing'
  ) into v_has_climbing;

  if v_has_climbing then
    return public.score_climbing_v1(p_workout_id);
  end if;

  select user_id, perceived_intensity into v_user, v_int
  from public.workouts where id = p_workout_id;

  v_mult := coalesce(intensity_factor(v_int), 1.0);
  v_sex_mult := sex_factor(get_user_sex(v_user));

  for rec in
    select sport, duration_sec, match_result::text, score_for, score_against
    from public.sport_sessions
    where workout_id = p_workout_id
  loop
    s := lower(coalesce(rec.sport, ''));
    mins := greatest(0, coalesce(rec.duration_sec,0)) / 60.0;

    base_per_min :=
      case
        when s = 'ski' then public.sport_factor_ski('ski')
        else public.sport_factor(s)
      end;

    res_bonus := 0;
    diff_bonus := 0;

    case lower(coalesce(rec.match_result, ''))
      when 'win'  then res_bonus := 50;
      when 'draw' then res_bonus := 20;
      else res_bonus := 0;
    end case;

    if rec.score_for is not null and rec.score_against is not null then
      diff_bonus := abs(rec.score_for - rec.score_against) * 5;
    end if;

    v_total := v_total + (mins * base_per_min) + res_bonus + diff_bonus;
  end loop;

  return greatest(0, v_total * v_mult * v_sex_mult);
end;
$function$;

create or replace function public.sport_factor(sport_code text)
returns numeric
language plpgsql
as $function$
declare
  f numeric := 1.0;
begin
  case lower(sport_code)
    when 'football'      then f := 1.20;
    when 'basketball'    then f := 1.15;
    when 'padel'         then f := 1.10;
    when 'tennis'        then f := 1.10;
    when 'badminton'     then f := 1.05;
    when 'squash'        then f := 1.10;
    when 'table_tennis'  then f := 1.00;
    when 'volleyball'    then f := 1.05;
    when 'handball'      then f := 1.15;
    when 'hockey'        then f := 1.20;
    when 'rugby'         then f := 1.25;
    when 'ski'           then f := 1.30;
    when 'climbing'      then f := 1.15;
    else f := 1.00;
  end case;
  return f;
end;
$function$;

create or replace function public.get_climbing_routes_sent_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit integer default 100,
  p_sex text default null,
  p_age_band text default null,
  p_environment text default null
)
returns table(
  rank integer,
  user_id uuid,
  username text,
  avatar_url text,
  total_routes_sent integer,
  sessions_cnt integer
)
language sql
stable
security definer
set search_path to 'public'
as $function$
with bounds as (
  select
    case lower(coalesce(p_period, 'week'))
      when 'day'   then date_trunc('day', now())
      when 'week'  then date_trunc('week', now())
      when 'month' then date_trunc('month', now())
      when 'all'   then '1970-01-01'::timestamptz
      else date_trunc('week', now())
    end as t_start,
    now() as t_end
),
agg as (
  select
    w.user_id as uid,
    sum(coalesce(cs.routes_sent, 0))::int as total_routes_sent,
    count(distinct w.id)::int as sessions_cnt
  from public.workouts w
  inner join public.sport_sessions ss on ss.workout_id = w.id
  inner join public.climbing_session_stats cs on cs.session_id = ss.id
  cross join bounds b
  where w.kind::text = 'sport'
    and w.state = 'published'::public.workout_state
    and lower(coalesce(ss.sport::text, '')) = 'climbing'
    and coalesce(w.started_at, w.created_at) >= b.t_start
    and coalesce(w.started_at, w.created_at) < b.t_end
    and (
      p_environment is null or p_environment = ''
      or cs.environment::text = lower(p_environment)
    )
  group by w.user_id
  having sum(coalesce(cs.routes_sent, 0)) > 0
),
scoped as (
  select a.uid, a.total_routes_sent, a.sessions_cnt
  from agg a
  inner join public.profiles pr on pr.user_id = a.uid
  where
    (p_sex is null or p_sex = '' or pr.sex = p_sex::public.sex)
    and (
      p_age_band is null or p_age_band = ''
      or (
        case p_age_band
          when '18-24' then extract(year from age(current_date, pr.date_of_birth)) between 18 and 24
          when '25-34' then extract(year from age(current_date, pr.date_of_birth)) between 25 and 34
          when '35-44' then extract(year from age(current_date, pr.date_of_birth)) between 35 and 44
          when '45-54' then extract(year from age(current_date, pr.date_of_birth)) between 45 and 54
          when '55+'   then extract(year from age(current_date, pr.date_of_birth)) >= 55
          else true
        end
      )
    )
    and (
      coalesce(p_scope, 'global') = 'global'
      or pr.user_id = auth.uid()
      or exists (
        select 1 from public.follows f
        where f.follower_id = auth.uid() and f.followee_id = pr.user_id
      )
    )
),
ordered as (
  select s.uid, s.total_routes_sent, s.sessions_cnt,
    row_number() over (order by s.total_routes_sent desc, s.sessions_cnt desc, s.uid) as rnk
  from scoped s
)
select o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_routes_sent, o.sessions_cnt
from ordered o
inner join public.profiles pr on pr.user_id = o.uid
where o.rnk <= greatest(1, coalesce(p_limit, 100))
order by o.rnk;
$function$;

insert into public.achievements (code, name, description, category, requirement_type, requirement_value)
select v.code, v.name, v.description, 'sport', 'count', v.requirement_value
from (values
  ('climbing_sessions_1', 'First Send Session', 'Log your first climbing workout.', 1),
  ('climbing_sessions_5', 'Regular Climber', 'Log 5 climbing workouts.', 5),
  ('climbing_sessions_10', 'Wall Regular', 'Log 10 climbing workouts.', 10),
  ('climbing_sessions_25', 'Dedicated Climber', 'Log 25 climbing workouts.', 25),
  ('climbing_sessions_50', 'Crag Veteran', 'Log 50 climbing workouts.', 50),
  ('climbing_routes_sent_10', 'Ten Sends', 'Send 10 routes across all sessions.', 10),
  ('climbing_routes_sent_50', 'Fifty Sends', 'Send 50 routes across all sessions.', 50),
  ('climbing_routes_sent_100', 'Century Sends', 'Send 100 routes across all sessions.', 100),
  ('climbing_vertical_m_500', 'Vertical 500', 'Climb 500 meters total vertical.', 500),
  ('climbing_vertical_m_2000', 'Vertical 2000', 'Climb 2000 meters total vertical.', 2000),
  ('climbing_vertical_m_5000', 'Vertical 5000', 'Climb 5000 meters total vertical.', 5000),
  ('climbing_indoor_sessions_5', 'Gym Rat', 'Log 5 indoor climbing sessions.', 5),
  ('climbing_outdoor_sessions_5', 'Crag Explorer', 'Log 5 outdoor climbing sessions.', 5),
  ('climbing_grade_v5', 'V5 Milestone', 'Send a V5 / equivalent grade.', 1),
  ('climbing_grade_7a', '7a Milestone', 'Send a French 7a / equivalent grade.', 1),
  ('climbing_grade_5_11', '5.11 Milestone', 'Send a YDS 5.11 / equivalent grade.', 1)
) as v(code, name, description, requirement_value)
where not exists (select 1 from public.achievements a where a.code = v.code);

commit;


-- Patch create_sport_workout_v2: add climbing branch after ski
do $patch$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'create_sport_workout_v2'
  limit 1;

  if v_def is null then
    raise exception 'create_sport_workout_v2 not found';
  end if;

  if v_def not like '%v_sport = ''climbing''%' then
    v_def := replace(
      v_def,
      $needle$        NULLIF(p_stats->>'weather', '')
      );
    END IF;
  END IF;$needle$,
      $needle$        NULLIF(p_stats->>'weather', '')
      );

    -- Climbing
    ELSIF v_sport = 'climbing' THEN
      PERFORM public.apply_climbing_sport_stats(v_session_id, p_stats, true);
    END IF;
  END IF;$needle$
    );
    execute v_def;
  end if;
end $patch$;

-- Patch update_sport_workout_v2: add climbing branch before final END IF
do $patch$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'update_sport_workout_v2'
  limit 1;

  if v_def is null then
    raise exception 'update_sport_workout_v2 not found';
  end if;

  if v_def not like '%v_sport = ''climbing''%' then
    v_def := replace(
      v_def,
      $needle$      red_cards               = COALESCE(EXCLUDED.red_cards,               public.rugby_session_stats.red_cards);

  END IF;

  PERFORM upsert_workout_score_v2(p_workout_id);$needle$,
      $needle$      red_cards               = COALESCE(EXCLUDED.red_cards,               public.rugby_session_stats.red_cards);

  ELSIF v_sport = 'climbing' THEN
    PERFORM public.apply_climbing_sport_stats(v_session_id, p_stats, true);

  END IF;

  PERFORM upsert_workout_score_v2(p_workout_id);$needle$
    );
    execute v_def;
  end if;
end $patch$;

begin;

create or replace function public.unlock_climbing_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_sessions int := 0;
  v_routes_sent int := 0;
  v_vertical int := 0;
  v_indoor int := 0;
  v_outdoor int := 0;
  v_best_grade numeric := 0;
begin
  if to_regclass('public.climbing_session_stats') is null then
    return;
  end if;

  select
    count(*)::int,
    coalesce(sum(coalesce(cs.routes_sent, 0)), 0)::int,
    coalesce(sum(coalesce(cs.total_vertical_m, 0)), 0)::int,
    count(*) filter (where cs.environment = 'indoor')::int,
    count(*) filter (where cs.environment = 'outdoor')::int,
    coalesce(max(cs.highest_grade_normalized), 0)
  into v_sessions, v_routes_sent, v_vertical, v_indoor, v_outdoor, v_best_grade
  from public.sport_sessions ss
  join public.workouts w on w.id = ss.workout_id
  join public.climbing_session_stats cs on cs.session_id = ss.id
  where w.user_id = p_user_id
    and w.state = 'published'
    and ss.sport = 'climbing';

  if v_sessions >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_sessions_1'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_sessions >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_sessions_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_sessions >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_sessions_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_sessions >= 25 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_sessions_25'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_sessions >= 50 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_sessions_50'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_routes_sent >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_routes_sent_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_routes_sent >= 50 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_routes_sent_50'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_routes_sent >= 100 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_routes_sent_100'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_vertical >= 500 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_vertical_m_500'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_vertical >= 2000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_vertical_m_2000'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_vertical >= 5000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_vertical_m_5000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_indoor >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_indoor_sessions_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_outdoor >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_outdoor_sessions_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_best_grade >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_grade_v5'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_best_grade >= 70.5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_grade_7a'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_best_grade >= 511.0 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'climbing_grade_5_11'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

do $patch$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'check_and_unlock_achievements_for'
  limit 1;

  if v_def is not null and v_def not like '%unlock_climbing_achievements%' then
    v_def := replace(
      v_def,
      $needle$  sig  := 'public.unlock_ranking_achievements(uuid)';$needle$,
      $needle$  sig  := 'public.unlock_climbing_achievements(uuid)';
  call := 'SELECT public.unlock_climbing_achievements($1)';
  if to_regprocedure(sig) is not null then execute call using p_user_id; end if;

  sig  := 'public.unlock_ranking_achievements(uuid)';$needle$
    );
    execute v_def;
  end if;
end $patch$;

create or replace function public.trg_recalc_calories_from_climbing_stats()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_workout_id bigint;
  v_session_id bigint;
begin
  if tg_op = 'DELETE' then
    v_session_id := old.session_id;
  else
    v_session_id := new.session_id;
  end if;

  select s.workout_id into v_workout_id
  from public.sport_sessions s
  where s.id = v_session_id;

  if v_workout_id is not null then
    perform public.recalc_workout_calories(v_workout_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_recalc_calories_from_climbing_stats on public.climbing_session_stats;
create trigger trg_recalc_calories_from_climbing_stats
after insert or update or delete on public.climbing_session_stats
for each row
execute function public.trg_recalc_calories_from_climbing_stats();

do $patch$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'recalc_workout_calories'
  limit 1;

  if v_def is null then
    raise exception 'recalc_workout_calories not found';
  end if;

  if v_def not like '%v_sport = ''climbing''%' then
    v_def := replace(
      v_def,
      $needle$        v_met := case v_intensity
          when 'easy'::public.intensity then 4.0
          when 'moderate'::public.intensity then 5.0
          when 'hard'::public.intensity then 6.0
          when 'max'::public.intensity then 7.0
          else 5.0
        end;
      else$needle$,
      $needle$        v_met := case v_intensity
          when 'easy'::public.intensity then 4.0
          when 'moderate'::public.intensity then 5.0
          when 'hard'::public.intensity then 6.0
          when 'max'::public.intensity then 7.0
          else 5.0
        end;
      elsif v_sport = 'climbing' then
        select
          (coalesce(cs.moving_time_sec, 0) + coalesce(cs.paused_time_sec, 0))::int,
          coalesce(cs.paused_time_sec, 0)::int
        into v_eff_sec, v_pause_sec
        from public.sport_sessions s
        join public.climbing_session_stats cs on cs.session_id = s.id
        where s.workout_id = p_workout_id
        order by s.id
        limit 1;

        if v_eff_sec is not null and v_eff_sec > 0 then
          v_duration_sec := greatest(0, (v_eff_sec - coalesce(v_pause_sec, 0)) + (coalesce(v_pause_sec, 0) * 0.25));
        end if;

        v_met := case v_intensity
          when 'easy'::public.intensity then 4.5
          when 'moderate'::public.intensity then 5.5
          when 'hard'::public.intensity then 6.5
          when 'max'::public.intensity then 7.5
          else 5.5
        end;
      else$needle$
    );

    v_def := replace(
      v_def,
      $needle$        || case when v_kind = 'sport'::public.workout_kind and v_sport = 'ski' then '_ski_effective' else '' end,$needle$,
      $needle$        || case
          when v_kind = 'sport'::public.workout_kind and v_sport = 'ski' then '_ski_effective'
          when v_kind = 'sport'::public.workout_kind and v_sport = 'climbing' then '_climbing_effective'
          else ''
        end,$needle$
    );

    execute v_def;
  end if;
end $patch$;

commit;

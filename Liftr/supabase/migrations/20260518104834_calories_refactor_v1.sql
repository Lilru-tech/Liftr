create or replace function public.recalc_workout_calories(p_workout_id bigint)
returns void
language plpgsql
set search_path to 'public'
as $function$
declare
  v_kind public.workout_kind;
  v_state public.workout_state;
  v_user_id uuid;
  v_started_at timestamptz;
  v_ended_at timestamptz;
  v_duration_min int;
  v_paused_sec int;
  v_duration_sec numeric;
  v_duration_hours numeric;
  v_weight_kg numeric;
  v_intensity public.intensity;
  v_met numeric;
  v_method text;
  v_existing_calories numeric;
  v_activity_type text;
  v_activity_code text;
  v_avg_hr int;
  v_max_hr int;
  v_distance_km numeric;
  v_avg_pace_sec_per_km int;
  v_elev_gain_m int;
  v_cardio_duration_sec int;
  v_has_cardio_session boolean := false;
  v_sport text;
  v_sport_duration_sec int;
  v_eff_sec int;
  v_pause_sec int;
begin
  select kind, state, user_id, started_at, ended_at, duration_min, paused_sec, perceived_intensity, calories_method, calories_kcal
  into v_kind, v_state, v_user_id, v_started_at, v_ended_at, v_duration_min, v_paused_sec, v_intensity, v_method, v_existing_calories
  from public.workouts
  where id = p_workout_id;

  if not found then
    return;
  end if;

  if v_method = 'healthkit_active_energy' and v_existing_calories is not null and v_existing_calories > 0 then
    update public.workouts
    set calories_updated_at = coalesce(calories_updated_at, now())
    where id = p_workout_id
      and calories_updated_at is null;
    return;
  end if;

  if v_state is distinct from 'published'::public.workout_state then
    update public.workouts
    set calories_kcal = null,
        calories_method = null,
        calories_weight_kg = null,
        calories_updated_at = null
    where id = p_workout_id
      and (
        calories_kcal is not null
        or calories_method is not null
        or calories_weight_kg is not null
        or calories_updated_at is not null
      );
    return;
  end if;

  if v_started_at is not null and v_ended_at is not null then
    v_duration_sec := greatest(0, extract(epoch from (v_ended_at - v_started_at)) - greatest(coalesce(v_paused_sec, 0), 0));
  elsif v_duration_min is not null then
    v_duration_sec := greatest(0, v_duration_min * 60);
  else
    v_duration_sec := null;
  end if;

  select weight_kg
  into v_weight_kg
  from public.profiles
  where user_id = v_user_id;

  if v_weight_kg is null then
    select weight_kg
    into v_weight_kg
    from public.body_metrics
    where user_id = v_user_id
    order by measured_at desc
    limit 1;
  end if;

  if v_duration_sec is null or v_duration_sec <= 0 or v_weight_kg is null or v_weight_kg <= 0 then
    update public.workouts
    set calories_kcal = null,
        calories_method = null,
        calories_weight_kg = null,
        calories_updated_at = null
    where id = p_workout_id
      and (
        calories_kcal is not null
        or calories_method is not null
        or calories_weight_kg is not null
        or calories_updated_at is not null
      );
    return;
  end if;

  case v_kind
    when 'strength'::public.workout_kind, 'mixed'::public.workout_kind then
      v_met := case v_intensity
        when 'easy'::public.intensity then 3.5
        when 'moderate'::public.intensity then 5.0
        when 'hard'::public.intensity then 6.5
        when 'max'::public.intensity then 8.0
        else 5.0
      end;

    when 'sport'::public.workout_kind then
      select lower(coalesce(s.sport, '')), s.duration_sec
      into v_sport, v_sport_duration_sec
      from public.sport_sessions s
      where s.workout_id = p_workout_id
      order by s.id
      limit 1;

      if v_sport_duration_sec is not null and v_sport_duration_sec > 0 then
        v_duration_sec := v_sport_duration_sec;
      end if;

      if v_sport = 'ski' then
        select
          (coalesce(ss.moving_time_sec, 0) + coalesce(ss.paused_time_sec, 0))::int,
          coalesce(ss.paused_time_sec, 0)::int
        into v_eff_sec, v_pause_sec
        from public.sport_sessions s
        join public.ski_session_stats ss on ss.session_id = s.id
        where s.workout_id = p_workout_id
        order by s.id
        limit 1;

        if v_eff_sec is not null and v_eff_sec > 0 then
          v_duration_sec := greatest(0, (v_eff_sec - coalesce(v_pause_sec, 0)) + (coalesce(v_pause_sec, 0) * 0.25));
        end if;

        v_met := case v_intensity
          when 'easy'::public.intensity then 4.0
          when 'moderate'::public.intensity then 5.0
          when 'hard'::public.intensity then 6.0
          when 'max'::public.intensity then 7.0
          else 5.0
        end;
      else
        v_met := case v_intensity
          when 'easy'::public.intensity then 5.0
          when 'moderate'::public.intensity then 6.5
          when 'hard'::public.intensity then 8.0
          when 'max'::public.intensity then 10.0
          else 6.5
        end;
      end if;

    when 'cardio'::public.workout_kind then
      select
        cs.activity_type,
        cs.activity_code,
        cs.avg_hr,
        cs.max_hr,
        cs.distance_km,
        cs.avg_pace_sec_per_km,
        coalesce(cs.elevation_gain_m, cs.elev_gain_m),
        cs.duration_sec
      into
        v_activity_type,
        v_activity_code,
        v_avg_hr,
        v_max_hr,
        v_distance_km,
        v_avg_pace_sec_per_km,
        v_elev_gain_m,
        v_cardio_duration_sec
      from public.cardio_sessions cs
      where cs.workout_id = p_workout_id
      order by cs.id
      limit 1;

      v_has_cardio_session := found;

      if v_cardio_duration_sec is not null and v_cardio_duration_sec > 0 then
        v_duration_sec := v_cardio_duration_sec;
      end if;

      if v_has_cardio_session and v_avg_hr is not null and v_avg_hr > 0 then
        v_met := case
          when v_avg_hr < 100 then 2.6
          when v_avg_hr < 115 then 3.2
          when v_avg_hr < 130 then 4.0
          when v_avg_hr < 145 then 5.2
          when v_avg_hr < 160 then 6.5
          else 7.8
        end;

        v_met := v_met + case
          when v_elev_gain_m is not null and v_elev_gain_m >= 250 then 0.6
          when v_elev_gain_m is not null and v_elev_gain_m >= 150 then 0.3
          else 0
        end;

        v_met := v_met + case v_intensity
          when 'hard'::public.intensity then 0.4
          when 'max'::public.intensity then 0.8
          else 0
        end;
      elsif v_has_cardio_session then
        if lower(coalesce(v_activity_type, v_activity_code, '')) like '%walk%'
           or lower(coalesce(v_activity_type, v_activity_code, '')) like '%hike%'
           or lower(coalesce(v_activity_type, v_activity_code, '')) like '%trek%' then
          v_met := case v_intensity
            when 'easy'::public.intensity then 2.6
            when 'moderate'::public.intensity then 3.3
            when 'hard'::public.intensity then 3.9
            when 'max'::public.intensity then 4.4
            else 3.3
          end;
        elsif lower(coalesce(v_activity_type, v_activity_code, '')) like '%run%'
           or lower(coalesce(v_activity_type, v_activity_code, '')) like '%jog%' then
          v_met := case v_intensity
            when 'easy'::public.intensity then 6.0
            when 'moderate'::public.intensity then 7.2
            when 'hard'::public.intensity then 8.5
            when 'max'::public.intensity then 10.0
            else 7.2
          end;
        else
          v_met := case v_intensity
            when 'easy'::public.intensity then 3.0
            when 'moderate'::public.intensity then 5.0
            when 'hard'::public.intensity then 7.0
            when 'max'::public.intensity then 9.0
            else 5.0
          end;
        end if;
      else
        v_met := case v_intensity
          when 'easy'::public.intensity then 3.0
          when 'moderate'::public.intensity then 5.0
          when 'hard'::public.intensity then 7.0
          when 'max'::public.intensity then 9.0
          else 5.0
        end;
      end if;

    else
      return;
  end case;

  if v_duration_sec is null or v_duration_sec <= 0 or v_met is null then
    update public.workouts
    set calories_kcal = null,
        calories_method = null,
        calories_weight_kg = null,
        calories_updated_at = null
    where id = p_workout_id
      and (
        calories_kcal is not null
        or calories_method is not null
        or calories_weight_kg is not null
        or calories_updated_at is not null
      );
    return;
  end if;

  v_duration_hours := v_duration_sec / 3600.0;

  update public.workouts
  set calories_kcal = round(v_met * v_weight_kg * v_duration_hours, 1),
      calories_method =
        v_kind::text
        || '_met'
        || case when v_kind = 'cardio'::public.workout_kind and v_has_cardio_session then '_cardio_sessions' else '' end
        || case when v_kind = 'cardio'::public.workout_kind and v_avg_hr is not null then '_hr' else '' end
        || case when v_kind = 'sport'::public.workout_kind and v_sport = 'ski' then '_ski_effective' else '' end,
      calories_weight_kg = v_weight_kg,
      calories_updated_at = now()
  where id = p_workout_id;
end;
$function$;

create or replace function public.trg_recalc_calories_on_workout()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if (new.state is distinct from old.state)
     or new.ended_at is distinct from old.ended_at
     or new.perceived_intensity is distinct from old.perceived_intensity
     or new.started_at is distinct from old.started_at
     or new.paused_sec is distinct from old.paused_sec then
    perform public.recalc_workout_calories(new.id);
  end if;

  return new;
end;
$function$;

create or replace function public.trg_recalc_calories_on_workout_insert()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  perform public.recalc_workout_calories(new.id);
  return new;
end;
$function$;

create or replace function public.trg_recalc_calories_from_cardio_session()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_workout_id bigint;
begin
  if tg_op = 'DELETE' then
    v_workout_id := old.workout_id;
  else
    v_workout_id := new.workout_id;
  end if;
  if v_workout_id is not null then
    perform public.recalc_workout_calories(v_workout_id);
  end if;
  return null;
end;
$function$;

create or replace function public.trg_recalc_calories_from_sport_session()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_workout_id bigint;
begin
  if tg_op = 'DELETE' then
    v_workout_id := old.workout_id;
  else
    v_workout_id := new.workout_id;
  end if;
  if v_workout_id is not null then
    perform public.recalc_workout_calories(v_workout_id);
  end if;
  return null;
end;
$function$;

create or replace function public.trg_recalc_calories_from_ski_stats()
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

  select s.workout_id
  into v_workout_id
  from public.sport_sessions s
  where s.id = v_session_id;

  if v_workout_id is not null then
    perform public.recalc_workout_calories(v_workout_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_recalc_calories_from_cardio_session on public.cardio_sessions;
create trigger trg_recalc_calories_from_cardio_session
after insert or update or delete on public.cardio_sessions
for each row
execute function public.trg_recalc_calories_from_cardio_session();

drop trigger if exists trg_recalc_calories_from_sport_session on public.sport_sessions;
create trigger trg_recalc_calories_from_sport_session
after insert or update or delete on public.sport_sessions
for each row
execute function public.trg_recalc_calories_from_sport_session();

drop trigger if exists trg_recalc_calories_from_ski_stats on public.ski_session_stats;
create trigger trg_recalc_calories_from_ski_stats
after insert or update or delete on public.ski_session_stats
for each row
execute function public.trg_recalc_calories_from_ski_stats();

create or replace function public.create_cardio_workout_v2(p jsonb)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid := nullif(p->>'p_user_id', '')::uuid;
  v_activity_code text := nullif(p->>'p_activity_code', '');
  v_title text := nullif(p->>'p_title', '');
  v_started_at timestamptz := nullif(p->>'p_started_at', '')::timestamptz;
  v_ended_at timestamptz := nullif(p->>'p_ended_at', '')::timestamptz;
  v_notes text := nullif(p->>'p_notes', '');
  v_distance_km numeric := nullif(p->>'p_distance_km', '')::numeric;
  v_duration_sec integer := nullif(p->>'p_duration_sec', '')::integer;
  v_avg_hr integer := nullif(p->>'p_avg_hr', '')::integer;
  v_max_hr integer := nullif(p->>'p_max_hr', '')::integer;
  v_avg_pace_sec_per_km integer := nullif(p->>'p_avg_pace_sec_per_km', '')::integer;
  v_elevation_gain_m integer := nullif(p->>'p_elevation_gain_m', '')::integer;
  v_perceived_intensity text := nullif(p->>'p_perceived_intensity', '');
  v_state workout_state := nullif(p->>'p_state', '')::workout_state;
  v_stats jsonb := coalesce(p->'p_stats', '{}'::jsonb);
  v_healthkit_uuid text := nullif(p->>'p_healthkit_uuid', '');
  v_route_geojson text := nullif(p->>'p_route_geojson', '');
  v_calories_kcal numeric := nullif(p->>'p_calories_kcal', '')::numeric;
  v_calories_method text := nullif(p->>'p_calories_method', '');
  v_workout_id bigint;
  v_session_id bigint;
begin
  insert into public.workouts
    (user_id, title, started_at, ended_at, notes, perceived_intensity, state, kind, healthkit_uuid)
  values
    (v_user_id, v_title, v_started_at, v_ended_at, v_notes, v_perceived_intensity, coalesce(v_state, 'published'::public.workout_state), 'cardio', v_healthkit_uuid)
  returning id into v_workout_id;

  insert into public.cardio_sessions(
    workout_id, modality, activity_code, distance_km, duration_sec, avg_hr, max_hr,
    avg_pace_sec_per_km, elevation_gain_m, notes, route_geojson
  )
  values (
    v_workout_id,
    'cardio',
    v_activity_code,
    v_distance_km, v_duration_sec, v_avg_hr, v_max_hr,
    v_avg_pace_sec_per_km, v_elevation_gain_m, v_notes, v_route_geojson
  )
  returning id into v_session_id;

  if v_stats is not null and v_stats <> '{}'::jsonb then
    insert into public.cardio_session_stats(session_id, stats)
    values (v_session_id, v_stats);
  end if;

  if v_calories_method = 'healthkit_active_energy' and v_calories_kcal is not null and v_calories_kcal > 0 then
    update public.workouts
    set calories_kcal = round(v_calories_kcal, 1),
        calories_method = 'healthkit_active_energy',
        calories_weight_kg = null,
        calories_updated_at = now()
    where id = v_workout_id;
  else
    perform public.recalc_workout_calories(v_workout_id);
  end if;

  perform public.competition_attach_workout(v_workout_id);

  return v_workout_id;
end;
$function$;

select public.recalc_workout_calories(w.id)
from public.workouts w
where coalesce(w.calories_method, '') <> 'healthkit_active_energy';

update public.competition_workouts cw
set calories_snapshot = w.calories_kcal,
    score_snapshot = ws.score,
    updated_at = now()
from public.workouts w
left join public.workout_scores ws on ws.workout_id = w.id
where cw.workout_id = w.id
  and cw.status = 'accepted';

do $$
declare
  r record;
begin
  for r in
    select distinct user_id, week_start
    from public.weekly_goals
  loop
    perform public.refresh_week_goal_results(r.user_id, r.week_start);
    perform public.recompute_weekly_goal_results(r.user_id, r.week_start);
  end loop;
end $$;

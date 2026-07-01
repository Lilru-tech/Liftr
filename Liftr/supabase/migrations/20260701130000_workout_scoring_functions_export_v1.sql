begin;

create or replace function public.intensity_factor(p intensity)
returns numeric
language sql
as $function$
  select case lower(coalesce(p::text, 'moderate'))
           when 'easy'     then 0.85
           when 'moderate' then 1.00
           when 'hard'     then 1.15
           when 'max'      then 1.30
           else 1.00
         end::numeric
$function$;

create or replace function public.sex_factor(p_sex text)
returns numeric
language plpgsql
as $function$
begin
  case lower(coalesce(p_sex, ''))
    when 'female' then return 0.96;
    when 'male'   then return 1.00;
    else return 1.00;
  end case;
end;
$function$;

create or replace function public.strength_superset_factor(p_group_size integer)
returns numeric
language sql
immutable
as $function$
  select case
    when p_group_size is null or p_group_size <= 1 then 1.00
    when p_group_size = 2 then 1.15
    when p_group_size = 3 then 1.25
    else 1.30
  end::numeric;
$function$;

create or replace function public.sport_factor_ski(p_sport text)
returns numeric
language plpgsql
as $function$
declare
  s text := lower(coalesce(p_sport, ''));
begin
  if s = 'ski' then
    return 0.9;
  end if;

  return public.sport_factor(s);
end;
$function$;

create or replace function public.upsert_workout_score_v2(p_workout_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  k text;
  u uuid;
begin
  select kind, user_id into k, u
  from public.workouts
  where id = p_workout_id;

  if k is null then
    return;
  end if;

  if k = 'strength' then
    with z as (
      select public.score_strength_v2(p_workout_id) as val
    )
    insert into public.workout_scores(workout_id, score, algorithm, calculated_at)
    select p_workout_id, val, 'strength_v2', now()
    from z
    where val is not null
    on conflict (workout_id, algorithm) do update
      set score = excluded.score,
          calculated_at = now();

  elsif k = 'sport' then
    with z as (
      select public.score_sport_v2(p_workout_id) as val
    )
    insert into public.workout_scores(workout_id, score, algorithm, calculated_at)
    select p_workout_id, val, 'sport_v2', now()
    from z
    where val is not null
    on conflict (workout_id, algorithm) do update
      set score = excluded.score,
          calculated_at = now();

  elsif k = 'cardio' then
    insert into public.workout_scores(workout_id, score, algorithm, calculated_at)
    select
      p_workout_id,
      public.score_cardio_v2(
        u,
        cs.modality,
        cs.activity_code,
        cs.distance_km,
        cs.duration_sec,
        cs.elevation_gain_m,
        cs.avg_hr,
        (select perceived_intensity from public.workouts where id = p_workout_id)
      ),
      'cardio_v2:' || cs.id::text,
      now()
    from public.cardio_sessions cs
    where cs.workout_id = p_workout_id
    on conflict (workout_id, algorithm) do update
      set score = excluded.score,
          calculated_at = now();
  end if;
end;
$function$;

create or replace function public.score_cardio_v2(
  p_user_id uuid,
  p_modality text,
  p_activity_code text,
  p_distance_km numeric,
  p_duration_sec integer,
  p_elevation_gain_m integer,
  p_avg_hr integer,
  p_intensity intensity
)
returns numeric
language plpgsql
as $function$
declare
    minutes numeric := greatest(0, coalesce(p_duration_sec,0)) / 60.0;
    km      numeric := greatest(0, coalesce(p_distance_km,0));
    elev_m  integer := coalesce(p_elevation_gain_m,0);
    base_factor numeric := 0.80;
    dist_bonus  numeric := 0.0;
    elev_bonus  numeric := 0.0;
    eff_bonus   numeric := 0.0;
    hr_bonus    numeric := 0.0;
    intens_mult numeric := coalesce(intensity_factor(p_intensity), 1.0);
    pace_sec_per_km numeric;
    pace_100m_sec   numeric;
    act text := lower(coalesce(p_activity_code, p_modality));
    a int := age_years(p_user_id);
    s text := get_user_sex(p_user_id);
    sex_mult numeric := sex_factor(s);
    hr_max int;
begin
    if a is not null then hr_max := 220 - a; end if;

    case act
        when 'trail_run'       then base_factor := 1.15;
        when 'run'             then base_factor := 1.00;
        when 'treadmill'       then base_factor := 0.95;
        when 'bike'            then base_factor := 0.80;
        when 'indoor_cycling'  then base_factor := 0.85;
        when 'mtb'             then base_factor := 0.90;
        when 'rowerg', 'rower' then base_factor := 0.90;
        when 'elliptical'      then base_factor := 0.70;
        when 'stair_climber'   then base_factor := 1.00;
        when 'walk', 'hike'    then base_factor := 0.70;
        when 'swim_openwater'  then base_factor := 1.20;
        when 'swim_pool'       then base_factor := 1.10;
        else base_factor := 0.80;
    end case;

    case act
        when 'trail_run'                     then dist_bonus := 2.2 * km;
        when 'run', 'treadmill'              then dist_bonus := 2.0 * km;
        when 'mtb'                           then dist_bonus := 1.4 * km;
        when 'bike', 'indoor_cycling'        then dist_bonus := 1.2 * km;
        when 'walk'                          then dist_bonus := 0.7 * km;
        when 'hike'                          then dist_bonus := 1.0 * km;
        when 'rowerg', 'rower'               then dist_bonus := 1.5 * km;
        when 'swim_pool', 'swim_openwater'   then dist_bonus := 3.0 * km;
        else dist_bonus := 1.0 * km;
    end case;

    case act
        when 'trail_run'     then elev_bonus := (elev_m / 100.0) * 1.5;
        when 'run'           then elev_bonus := (elev_m / 100.0) * 1.0;
        when 'hike'          then elev_bonus := (elev_m / 100.0) * 2.0;
        when 'bike', 'mtb'   then elev_bonus := (elev_m / 100.0) * 0.5;
        else elev_bonus := 0.0;
    end case;

    if km > 0 then
        pace_sec_per_km := nullif(p_duration_sec,0) / nullif(km,0);
        if act in ('run','trail_run','treadmill') then
            if pace_sec_per_km is not null then
                if pace_sec_per_km < 5*60 then
                    eff_bonus := 10;
                elsif pace_sec_per_km < 6*60 then
                    eff_bonus := 5;
                end if;
            end if;
        elsif act in ('swim_pool','swim_openwater') then
            pace_100m_sec := nullif(p_duration_sec,0) / nullif(km*10.0,0);
            if pace_100m_sec is not null then
                if pace_100m_sec < 105 then
                    eff_bonus := 12;
                elsif pace_100m_sec < 120 then
                    eff_bonus := 8;
                end if;
            end if;
        end if;
    end if;

    if hr_max is not null and p_avg_hr is not null then
        if p_avg_hr >= hr_max*0.9 then
            hr_bonus := 12;
        elsif p_avg_hr >= hr_max*0.8 then
            hr_bonus := 8;
        elsif p_avg_hr >= hr_max*0.7 then
            hr_bonus := 4;
        end if;
    end if;

    return greatest(0,
        (minutes * base_factor) * intens_mult * sex_mult
        + dist_bonus + elev_bonus + eff_bonus + hr_bonus
    );
end;
$function$;

create or replace function public.score_hyrox_v1(p_workout_id bigint)
returns numeric
language plpgsql
as $function$
declare
  v_user uuid;
  v_int public.intensity;
  v_sex text;
  v_mult numeric := 1.0;
  v_sex_mult numeric := 1.0;
  v_calibration numeric := 1.20;
  v_total numeric := 0.0;

  v_session_id bigint;
  v_session_dur_sec int;
  v_official_time_sec int;
  v_penalty_time_sec int;
  v_no_reps int;
  v_duration_min int;

  rec record;
  v_row numeric;
  c text;

  d_ numeric;
  t_ numeric;
  r_ numeric;
  w_ numeric;
  h_ numeric;
  im_ numeric;
begin
  select w.user_id, w.perceived_intensity, w.duration_min
  into v_user, v_int, v_duration_min
  from public.workouts w
  where w.id = p_workout_id;

  if not found then
    return 0;
  end if;

  v_mult := coalesce(public.intensity_factor(v_int), 1.0);
  v_sex := public.get_user_sex(v_user);
  v_sex_mult := public.sex_factor(v_sex);

  select s.id, s.duration_sec
  into v_session_id, v_session_dur_sec
  from public.sport_sessions s
  where s.workout_id = p_workout_id
    and lower(s.sport) = 'hyrox'
  limit 1;

  if v_session_id is null then
    return 0;
  end if;

  select official_time_sec, penalty_time_sec, no_reps
  into v_official_time_sec, v_penalty_time_sec, v_no_reps
  from public.hyrox_session_stats
  where session_id = v_session_id;

  if (v_duration_min is null or v_duration_min <= 0)
     and v_session_dur_sec is not null
     and v_session_dur_sec > 0 then
    v_duration_min := greatest(1, ceil(v_session_dur_sec::numeric / 60.0))::int;
  end if;

  if v_duration_min is not null and v_duration_min > 0 then
    v_total := v_total + least(v_duration_min * 0.10, 18);
  end if;

  if v_official_time_sec is not null
     and v_official_time_sec > 0
     and v_official_time_sec <= 20000 then
    v_total := v_total + least(
      greatest(0, (5400 - v_official_time_sec) / 60.0) * 0.38,
      20
    );
  end if;

  for rec in
    select
      exercise_code,
      distance_m,
      reps,
      weight_kg,
      duration_sec,
      height_cm,
      implement_count
    from public.hyrox_session_exercises
    where session_id = v_session_id
    order by exercise_order
  loop
    c := lower(coalesce(rec.exercise_code, ''));
    v_row := 0;

    if c = 'run' then
      v_row := least(coalesce(rec.distance_m, 0) / 1000.0 * 7.5, 18)
             + least(coalesce(rec.duration_sec, 0) / 60.0 * 0.28, 6);
      v_row := least(v_row, 24);

    elsif c in ('skierg', 'row') then
      v_row := least(coalesce(rec.distance_m, 0) / 1000.0 * 9.0, 22)
             + least(coalesce(rec.duration_sec, 0) / 60.0 * 0.32, 7);
      v_row := least(v_row, 28);

    elsif c = 'burpee_broad_jump' then
      v_row := least(coalesce(rec.distance_m, 0) / 10.0 * 1.5, 22);

    elsif c in ('sled_push', 'sled_pull') then
      v_row := least(coalesce(rec.distance_m, 0) / 10.0 * 1.85, 14)
             + least(coalesce(rec.weight_kg, 0) * 0.22, 14);
      v_row := least(v_row, 24);

    elsif c = 'atlas_carry' then
      v_row := least(coalesce(rec.distance_m, 0) / 10.0 * 1.35, 12)
             + least(coalesce(rec.weight_kg, 0) * 0.22, 14);
      v_row := least(v_row, 22);

    elsif c = 'farmer_carry' then
      v_row := least(coalesce(rec.distance_m, 0) / 10.0 * 1.45, 14)
             + least(
                 coalesce(rec.weight_kg, 0) * 0.14 * coalesce(rec.implement_count, 2),
                 12
               );
      v_row := least(v_row, 24);

    elsif c = 'sandbag_lunges' then
      v_row := least(coalesce(rec.distance_m, 0) / 10.0 * 1.4, 14)
             + least(coalesce(rec.weight_kg, 0) * 0.22, 12);
      v_row := least(v_row, 24);

    elsif c = 'box_jump_over' then
      v_row := least(coalesce(rec.reps, 0) * 0.42, 20)
             + least(coalesce(rec.height_cm, 0) * 0.025, 6);
      v_row := least(v_row, 24);

    elsif c = 'dead_ball_over_trunk' then
      v_row := least(coalesce(rec.reps, 0) * 0.48, 20)
             + least(coalesce(rec.weight_kg, 0) * 0.20, 10)
             + least(coalesce(rec.height_cm, 0) * 0.018, 5);
      v_row := least(v_row, 28);

    elsif c = 'wall_ball' then
      v_row := least(coalesce(rec.reps, 0) * 0.45, 22)
             + least(coalesce(rec.weight_kg, 0) * 0.28, 10);
      v_row := least(v_row, 28);

    elsif c = 'custom' then
      d_ := least(greatest(coalesce(rec.distance_m, 0), 0) / 1000.0 * 5.0, 12);
      t_ := least(greatest(coalesce(rec.duration_sec, 0), 0) / 60.0 * 0.22, 9);
      r_ := least(greatest(coalesce(rec.reps, 0), 0) * 0.26, 16);
      w_ := least(greatest(coalesce(rec.weight_kg, 0), 0) * 0.16, 12);
      h_ := least(greatest(coalesce(rec.height_cm, 0), 0) * 0.020, 6);
      im_ := least(greatest(coalesce(rec.implement_count, 0), 0) * 0.10, 5);
      v_row := least(d_ + t_ + r_ + w_ + h_ + im_, 34);

    else
      d_ := least(greatest(coalesce(rec.distance_m, 0), 0) / 1000.0 * 5.0, 12);
      t_ := least(greatest(coalesce(rec.duration_sec, 0), 0) / 60.0 * 0.22, 9);
      r_ := least(greatest(coalesce(rec.reps, 0), 0) * 0.26, 16);
      w_ := least(greatest(coalesce(rec.weight_kg, 0), 0) * 0.16, 12);
      h_ := least(greatest(coalesce(rec.height_cm, 0), 0) * 0.020, 6);
      im_ := least(greatest(coalesce(rec.implement_count, 0), 0) * 0.10, 5);
      v_row := least(d_ + t_ + r_ + w_ + h_ + im_, 34);
    end if;

    v_total := v_total + v_row;
  end loop;

  v_total := v_total
    - coalesce(v_no_reps, 0) * 0.15
    - coalesce(v_penalty_time_sec, 0) / 60.0 * 1.00;

  return greatest(0, round(v_total * v_calibration * v_mult * v_sex_mult, 2));
end;
$function$;

create or replace function public.score_strength_v2(p_workout_id bigint)
returns numeric
language plpgsql
as $body$
declare
  v_user uuid;
  v_bw numeric;
  v_int public.intensity;
  v_sex text;

  v_minutes      numeric;
  v_eff_minutes  numeric;

  v_weighted_volume numeric;
  v_top_rel         numeric;
  v_exercises       int;

  vol_norm     numeric;
  dens_norm    numeric;
  top_norm     numeric;
  variety_norm numeric;

  v_base      numeric;
  v_sex_mod   numeric := 1.0;
  v_int_mult  numeric := 1.0;
  v_dur_bonus numeric;
  v_score     numeric;
begin
  select w.user_id,
         w.perceived_intensity,
         extract(epoch from (w.ended_at - w.started_at)) / 60.0
  into v_user, v_int, v_minutes
  from public.workouts w
  where w.id = p_workout_id;

  v_eff_minutes := case
    when v_minutes is null or v_minutes <= 0 then 45
    when v_minutes < 30 then 30
    when v_minutes > 90 then 90
    else v_minutes
  end;

  select weight_kg into v_bw
  from public.vw_latest_weight
  where user_id = v_user;

  v_sex := public.get_user_sex(v_user);

  with groups as (
    select
      we.superset_group_id,
      count(distinct we.id)::int as group_size
    from public.workout_exercises we
    where we.workout_id = p_workout_id
      and we.superset_group_id is not null
    group by we.superset_group_id
  ),
  s as (
    select
      we.id,
      coalesce(es.set_number, 1) as set_number,
      z.seg_idx,
      coalesce((z.seg->>'reps')::int, 0)::numeric as reps,
      coalesce((z.seg->>'weight_kg')::numeric, 0) as weight_kg,
      lower(coalesce(ex.muscle_primary, '')) as mp,
      g.group_size as ss_group_size
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    join public.exercises ex on ex.id = we.exercise_id
    left join groups g on g.superset_group_id = we.superset_group_id
    cross join lateral jsonb_array_elements(
      public.strength_set_segments_expand(es.reps, es.weight_kg, es.weight_segments)
    ) with ordinality as z(seg, seg_idx)
    where we.workout_id = p_workout_id
  ),
  factors as (
    select
      id, reps, weight_kg, set_number, seg_idx,
      case
        when mp in (
          'quadriceps', 'hamstrings', 'glutes', 'legs',
          'cuádriceps', 'isquiotibiales', 'glúteos', 'piernas',
          'aductores', 'abductores'
        ) then 1.10
        when mp in (
          'chest', 'back',
          'pecho', 'espalda'
        ) then 1.00
        when mp in (
          'shoulders',
          'hombros'
        ) then 0.90
        when mp in ('core') then 0.85
        when mp in (
          'triceps', 'biceps', 'forearms', 'arms',
          'tríceps', 'bíceps', 'antebrazos', 'brazos'
        ) then 0.75
        else 0.95
      end as m_fac,
      least(
        1.0 + 0.50 * ln(
          greatest(
            least(coalesce(set_number, 1) + seg_idx - 1, 40)::numeric,
            1::numeric
          )
        ),
        1.60
      ) as s_fac,
      coalesce(public.strength_superset_factor(ss_group_size), 1.0) as ss_fac
    from s
  )
  select
    coalesce(sum(reps * weight_kg * m_fac * s_fac * ss_fac), 0),
    coalesce(max(weight_kg * m_fac), 0)
  into v_weighted_volume, v_top_rel
  from factors;

  if v_bw is null or v_bw <= 0 then
    v_bw := 70;
  end if;

  v_top_rel := v_top_rel / v_bw;

  vol_norm  := 100 * (1 - exp(- (v_weighted_volume / v_bw) / 50.0));
  dens_norm := 100 * (1 - exp(- ((v_weighted_volume / v_bw) / greatest(v_eff_minutes, 1)) / 1.0));
  top_norm  := 100 * (1 - exp(- v_top_rel / 1.0));

  select count(distinct we.id)
  into v_exercises
  from public.workout_exercises we
  where we.workout_id = p_workout_id;

  variety_norm := 100 * (1 - exp(- v_exercises / 6.0));

  v_base := 0.45 * vol_norm
         + 0.30 * dens_norm
         + 0.10 * top_norm
         + 0.15 * variety_norm;

  v_sex_mod := case when v_sex = 'female' then 1.25 else 1.00 end;

  begin
    v_int_mult := public.intensity_factor(v_int);
  exception when others then
    v_int_mult := 1.0;
  end;

  v_dur_bonus := 40 * (1 - exp(- coalesce(v_minutes, 0) / 60.0));

  v_score := v_base * 2.0 * v_int_mult * v_sex_mod + v_dur_bonus;

  return round(v_score, 0);
end;
$body$;

commit;

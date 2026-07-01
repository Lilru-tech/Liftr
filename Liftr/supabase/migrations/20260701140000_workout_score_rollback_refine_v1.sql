begin;

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
    sex_mult numeric := sex_factor(get_user_sex(p_user_id));
    hr_max int;
    v_score numeric;
begin
    if a is not null then hr_max := 220 - a; end if;

    case act
        when 'trail_run'       then base_factor := 1.15;
        when 'run'             then base_factor := 1.00;
        when 'treadmill'       then base_factor := 1.15;
        when 'bike'            then base_factor := 0.80;
        when 'indoor_cycling'  then base_factor := 1.00;
        when 'mtb'             then base_factor := 0.90;
        when 'rowerg', 'rower' then base_factor := 0.90;
        when 'elliptical'      then base_factor := 0.70;
        when 'stair_climber'   then base_factor := 1.00;
        when 'walk'            then base_factor := 1.05;
        when 'hike'            then base_factor := 1.05;
        when 'swim_openwater'  then base_factor := 1.20;
        when 'swim_pool'       then base_factor := 1.10;
        else base_factor := 0.80;
    end case;

    case act
        when 'trail_run'                     then dist_bonus := 2.2 * km;
        when 'run', 'treadmill'              then dist_bonus := 2.0 * km;
        when 'mtb'                           then dist_bonus := 1.4 * km;
        when 'bike', 'indoor_cycling'        then dist_bonus := 1.2 * km;
        when 'walk'                          then dist_bonus := 1.0 * km;
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

    v_score := greatest(0,
        (minutes * base_factor) * intens_mult * sex_mult
        + dist_bonus + elev_bonus + eff_bonus + hr_bonus
    );

    return round(v_score, 2);
end;
$function$;

commit;

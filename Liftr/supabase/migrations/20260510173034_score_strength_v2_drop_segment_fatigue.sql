begin;

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

  with s as (
    select
      we.id,
      coalesce(es.set_number, 1) as set_number,
      z.seg_idx,
      coalesce((z.seg->>'reps')::int, 0)::numeric as reps,
      coalesce((z.seg->>'weight_kg')::numeric, 0) as weight_kg,
      lower(coalesce(ex.muscle_primary, '')) as mp
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    join public.exercises ex on ex.id = we.exercise_id
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
      ) as s_fac
    from s
  )
  select
    coalesce(sum(reps * weight_kg * m_fac * s_fac), 0),
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

-- Optional one-time backfill (run manually in SQL Editor / psql during a maintenance window if desired):
-- DO $rb$
-- DECLARE r record;
-- BEGIN
--   FOR r IN
--     SELECT w.id AS wid
--     FROM public.workouts w
--     WHERE w.kind = 'strength'
--   LOOP
--     PERFORM public.upsert_workout_score_v2(r.wid);
--   END LOOP;
-- END;
-- $rb$;

commit;

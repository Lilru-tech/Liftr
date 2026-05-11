begin;
create or replace function public.calc_strength_score_v1(p_workout_id bigint)
returns numeric
language sql
as $function$
  with vol as (
    select sum(
      coalesce((z.seg->>'reps')::int, 0)::numeric
      * coalesce((z.seg->>'weight_kg')::numeric, 0)
      * public.exercise_weight_factor(we.exercise_id)
    ) as volume_w
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    cross join lateral (
      select jsonb_array_elements(
        public.strength_set_segments_expand(es.reps, es.weight_kg, es.weight_segments)
      ) as seg
    ) z
    where we.workout_id = p_workout_id
  ),
  dur as (
    select coalesce(duration_min, 0)::numeric as minutes
    from public.workouts w
    where w.id = p_workout_id
  )
  select coalesce((select volume_w from vol), 0) / 20.0
       + coalesce((select minutes from dur), 0) * 2.0;
$function$;

create or replace function public.score_strength_v2(p_workout_id bigint)
returns numeric
language plpgsql
as $function$
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
      coalesce((z.seg->>'reps')::int, 0)::numeric as reps,
      coalesce((z.seg->>'weight_kg')::numeric, 0) as weight_kg,
      lower(coalesce(ex.muscle_primary, '')) as mp
    from public.workout_exercises we
    join public.exercise_sets es on es.workout_exercise_id = we.id
    join public.exercises ex on ex.id = we.exercise_id
    cross join lateral (
      select jsonb_array_elements(
        public.strength_set_segments_expand(es.reps, es.weight_kg, es.weight_segments)
      ) as seg
    ) z
    where we.workout_id = p_workout_id
  ),
  factors as (
    select
      id, reps, weight_kg, set_number,
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
      least(1.0 + 0.50 * ln(greatest(set_number, 1)), 1.60) as s_fac
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
$function$;

create or replace function public.rebuild_strength_prs_for_user(p_user_id uuid)
returns void
language plpgsql
as $function$
declare
  r record;
begin
  delete from public.personal_records
  where user_id = p_user_id
    and metric in ('max_weight_kg', 'max_reps', 'best_set_volume_kg', 'est_1rm_kg');

  for r in
    select we.exercise_id, w.user_id, w.started_at as achieved_at,
           (seg.elem->>'reps')::int as reps,
           (seg.elem->>'weight_kg')::numeric as weight_kg,
           (coalesce((seg.elem->>'reps')::int, 0)::numeric * coalesce((seg.elem->>'weight_kg')::numeric, 0)) as volume,
           (case when (seg.elem->>'reps')::int is not null and (seg.elem->>'weight_kg')::numeric is not null
                  and (seg.elem->>'reps')::int > 0 and (seg.elem->>'weight_kg')::numeric > 0
                 then (seg.elem->>'weight_kg')::numeric * (1 + (seg.elem->>'reps')::numeric / 30) end) as est1rm
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    join public.workouts w on w.id = we.workout_id
    cross join lateral (
      select jsonb_array_elements(
        public.strength_set_segments_expand(es.reps, es.weight_kg, es.weight_segments)
      ) as elem
    ) seg
    where w.user_id = p_user_id
  loop
    if r.weight_kg is not null and r.weight_kg > 0 then
      perform public.upsert_personal_record(p_user_id, r.exercise_id, 'max_weight_kg', r.weight_kg, r.achieved_at);
    end if;
    if r.reps is not null and r.reps > 0 then
      perform public.upsert_personal_record(p_user_id, r.exercise_id, 'max_reps', r.reps, r.achieved_at);
    end if;
    if r.volume is not null and r.volume > 0 then
      perform public.upsert_personal_record(p_user_id, r.exercise_id, 'best_set_volume_kg', r.volume, r.achieved_at);
    end if;
    if r.est1rm is not null and r.est1rm > 0 then
      perform public.upsert_personal_record(p_user_id, r.exercise_id, 'est_1rm_kg', r.est1rm, r.achieved_at);
    end if;
  end loop;
end;
$function$;

create or replace function public.trg_strength_pr_from_set()
returns trigger
language plpgsql
as $function$
declare
  v_user_id     uuid;
  v_exercise_id bigint;
  v_reps        int;
  v_weight      numeric;
  v_volume      numeric;
  v_est1rm      numeric;
  v_when        timestamptz;
  v_started_at  timestamptz;
  segs          jsonb;
  i             int;
  seg           jsonb;
begin
  select w.user_id, we.exercise_id, w.started_at
  into v_user_id, v_exercise_id, v_started_at
  from public.workout_exercises we
  join public.workouts w on w.id = we.workout_id
  where we.id = new.workout_exercise_id;

  v_when := coalesce(v_started_at, now());

  segs := public.strength_set_segments_expand(new.reps, new.weight_kg, new.weight_segments);
  for i in 0 .. coalesce(jsonb_array_length(segs), 0) - 1 loop
    seg := segs->i;
    v_reps := (seg->>'reps')::int;
    v_weight := (seg->>'weight_kg')::numeric;

    if v_weight is not null and v_weight > 0 then
      perform public.upsert_personal_record(v_user_id, v_exercise_id, 'max_weight_kg', v_weight, v_when);
    end if;

    if v_reps is not null and v_reps > 0 then
      perform public.upsert_personal_record(v_user_id, v_exercise_id, 'max_reps', v_reps, v_when);
    end if;

    v_volume := coalesce(v_reps, 0) * coalesce(v_weight, 0);
    if v_volume > 0 then
      perform public.upsert_personal_record(v_user_id, v_exercise_id, 'best_set_volume_kg', v_volume, v_when);
    end if;

    if v_weight is not null and v_weight > 0 and v_reps is not null and v_reps > 0 then
      v_est1rm := v_weight * (1 + (v_reps::numeric / 30));
      perform public.upsert_personal_record(v_user_id, v_exercise_id, 'est_1rm_kg', v_est1rm, v_when);
    end if;
  end loop;

  return new;
end;
$function$;

create or replace function public.unlock_strength_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_workouts     int := 0;
  v_total_volume numeric := 0;
  v_total_reps   bigint := 0;
  v_max_weight   numeric := 0;
  v_max_est_1rm  numeric := 0;
  v_pr_count     int := 0;
  v_bodyweight   numeric := null;
  v_streak_max   int := 0;
  has_es_wid     boolean := false;
begin
  select count(*) into v_workouts
  from public.workouts w
  where w.user_id = p_user_id and w.kind = 'strength';

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'exercise_sets' and column_name = 'workout_id'
  ) into has_es_wid;

  if has_es_wid then
    select
      coalesce(sum(public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)), 0),
      coalesce(sum(public.exercise_set_segment_reps_sum(es.reps, es.weight_segments)), 0)
    into v_total_volume, v_total_reps
    from public.exercise_sets es
    join public.workouts w on w.id = es.workout_id
    where w.user_id = p_user_id;
  else
    select
      coalesce(sum(public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)), 0),
      coalesce(sum(public.exercise_set_segment_reps_sum(es.reps, es.weight_segments)), 0)
    into v_total_volume, v_total_reps
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    join public.workouts w on w.id = we.workout_id
    where w.user_id = p_user_id;
  end if;

  select coalesce(max(
    public.exercise_set_segment_max_weight_kg(es.weight_kg, es.weight_segments)
  ), 0) into v_max_weight
  from public.exercise_sets es
  join public.workout_exercises we on we.id = es.workout_exercise_id
  join public.workouts w on w.id = we.workout_id
  where w.user_id = p_user_id;

  select coalesce(max(value), 0) into v_max_est_1rm
  from public.vw_user_prs
  where user_id = p_user_id and kind = 'strength' and metric = 'est_1rm_kg';

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'weight_kg'
  ) then
    select weight_kg into v_bodyweight
    from public.profiles
    where user_id = p_user_id
    order by updated_at desc nulls last
    limit 1;
  end if;

  with days as (
    select distinct (w.started_at at time zone 'Europe/Madrid')::date as d
    from public.workouts w
    where w.user_id = p_user_id and w.kind = 'strength'
  ),
  seq as (
    select d, d - (row_number() over (order by d))::int as grp from days
  ),
  agg as (
    select count(*) as streak_len from seq group by grp
  )
  select coalesce(max(streak_len), 0) into v_streak_max from agg;

  if v_workouts >= 10 then insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_workouts_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_workouts >= 25 then insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_workouts_25'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_workouts >= 50 then insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_workouts_50'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_workouts >= 100 then insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_workouts_100'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_total_volume >= 1000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_volume_1k' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_volume >= 10000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_volume_10k' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_volume >= 50000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_volume_50k' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_volume >= 100000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_volume_100k' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_volume >= 500000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_volume_500k' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_volume >= 1000000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_volume_1m' on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_total_reps >= 500 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_reps_500' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_reps >= 1000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_reps_1000' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_reps >= 5000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_reps_5000' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_total_reps >= 10000 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'total_reps_10000' on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_max_weight >= 50 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'max_weight_50' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_max_weight >= 100 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'max_weight_100' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_max_weight >= 150 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'max_weight_150' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_max_weight >= 200 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'max_weight_200' on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_max_est_1rm >= 100 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'est_1rm_100' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_max_est_1rm >= 150 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'est_1rm_150' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_max_est_1rm >= 200 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'est_1rm_200' on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_bodyweight is not null and v_bodyweight > 0 and v_max_est_1rm >= v_bodyweight then
    insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'strength_1rm_bodyweight'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if to_regclass('public.strength_personal_records') is not null then
    select count(*) into v_pr_count from public.strength_personal_records where user_id = p_user_id;
  elsif to_regclass('public.user_personal_records') is not null then
    select count(*) into v_pr_count from public.user_personal_records where user_id = p_user_id and domain = 'strength';
  end if;

  if v_pr_count >= 5 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'strength_pr_5' on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_pr_count >= 25 then insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'strength_pr_25' on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_streak_max >= 7 then
    insert into public.user_achievements(user_id, achievement_id, unlocked_at) select p_user_id, id, now() from public.achievements where code = 'strength_session_streak_7'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

create or replace function public.create_strength_workout(
  p_user_id uuid,
  p_items jsonb,
  p_started_at timestamp with time zone,
  p_ended_at timestamp with time zone default null::timestamp with time zone,
  p_title text default null::text,
  p_notes text default null::text,
  p_perceived_intensity text default null::text,
  p_state text default null::text
)
returns void
language plpgsql
as $function$
declare
  v_workout_id int;
  r_item record;
  r_set  record;
  v_workout_notes text := nullif(p_notes, '');
  v_title         text := nullif(p_title, '');
  v_pi            text := nullif(p_perceived_intensity, '');
  v_state public.workout_state :=
    coalesce(nullif(p_state, '')::public.workout_state, 'published'::public.workout_state);
begin
  if not exists (select 1 from public.profiles where user_id = p_user_id) then
    raise exception 'profile not found for user_id=%', p_user_id using errcode = '23503';
  end if;

  insert into public.workouts (user_id, kind, title, notes, started_at, ended_at, perceived_intensity, state)
  values (
    p_user_id,
    'strength',
    v_title,
    v_workout_notes,
    p_started_at,
    p_ended_at,
    nullif(v_pi, '')::public.intensity,
    v_state
  )
  returning id into v_workout_id;

  for r_item in
    select
      (elem->>'exercise_id')::bigint as exercise_id,
      coalesce((elem->>'order_index')::int, 1) as order_index,
      nullif(elem->>'notes', '') as notes,
      nullif(elem->>'custom_name', '') as custom_name,
      elem->'sets' as sets
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) elem
  loop
    insert into public.workout_exercises (workout_id, exercise_id, order_index, notes, custom_name)
    values (v_workout_id, r_item.exercise_id, r_item.order_index, r_item.notes, r_item.custom_name)
    returning id into r_item.exercise_id;

    if r_item.sets is not null then
      for r_set in
        select j as set_json from jsonb_array_elements(coalesce(r_item.sets, '[]'::jsonb)) t(j)
      loop
        insert into public.exercise_sets
          (workout_exercise_id, set_number, reps, weight_kg, rpe, rest_sec, notes, weight_segments)
        values
          (
            r_item.exercise_id,
            coalesce((r_set.set_json->>'set_number')::int, 1),
            case
              when r_set.set_json ? 'reps' and r_set.set_json->>'reps' is not null and btrim(r_set.set_json->>'reps') <> '' then (r_set.set_json->>'reps')::int
              else null
            end,
            case
              when r_set.set_json ? 'weight_kg' and r_set.set_json->>'weight_kg' is not null and btrim(r_set.set_json->>'weight_kg') <> '' then (r_set.set_json->>'weight_kg')::numeric
              else null
            end,
            case
              when r_set.set_json ? 'rpe' and r_set.set_json->>'rpe' is not null and btrim(r_set.set_json->>'rpe') <> '' then (r_set.set_json->>'rpe')::numeric
              else null
            end,
            case
              when r_set.set_json ? 'rest_sec' and r_set.set_json->>'rest_sec' is not null and btrim(r_set.set_json->>'rest_sec') <> '' then (r_set.set_json->>'rest_sec')::int
              else null
            end,
            nullif(btrim(coalesce(r_set.set_json->>'notes', '')), ''),
            case
              when r_set.set_json ? 'weight_segments'
                and jsonb_typeof(r_set.set_json->'weight_segments') = 'array'
                and jsonb_array_length(r_set.set_json->'weight_segments') >= 2
              then r_set.set_json->'weight_segments'
              else null::jsonb
            end
          );
      end loop;
    end if;
  end loop;

  perform public.competition_attach_workout(v_workout_id);
end;
$function$;

create or replace function public.plan_strength_squad_programs(
  p_programs jsonb,
  p_title text,
  p_notes text,
  p_started_at text,
  p_perceived_intensity text,
  p_state text default 'planned'::text,
  p_ended_at text default null::text
)
returns bigint[]
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_planner uuid := auth.uid();
  v_started timestamptz;
  v_ended timestamptz;
  v_state text;
  v_group_id uuid := gen_random_uuid();
  program jsonb;
  owner_uuid uuid;
  wid bigint;
  new_we_id bigint;
  item jsonb;
  all_ids bigint[] := '{}';
  all_owners uuid[] := '{}';
  i int;
  j int;
  v_perceived text;
begin
  if v_planner is null then
    raise exception 'not_authenticated';
  end if;

  if jsonb_typeof(p_programs) is distinct from 'array' or jsonb_array_length(p_programs) < 1 then
    raise exception 'invalid_programs';
  end if;

  if jsonb_array_length(p_programs) > 3 then
    raise exception 'too_many_programs';
  end if;

  if (p_programs->0->>'owner_user_id')::uuid is distinct from v_planner then
    raise exception 'first_owner_must_be_caller';
  end if;

  if (
    select count(distinct (e->>'owner_user_id')::uuid)
    from jsonb_array_elements(p_programs) as e
  ) is distinct from jsonb_array_length(p_programs) then
    raise exception 'duplicate_owner';
  end if;

  begin
    v_started := p_started_at::timestamptz;
  exception when others then
    raise exception 'invalid_started_at';
  end;

  v_state := lower(btrim(coalesce(p_state, 'planned')));
  if v_state not in ('planned', 'published') then
    raise exception 'invalid_state';
  end if;

  v_ended := null::timestamptz;
  if p_ended_at is not null and btrim(p_ended_at) <> '' then
    begin
      v_ended := p_ended_at::timestamptz;
    exception when others then
      raise exception 'invalid_ended_at';
    end;
  end if;

  v_perceived := nullif(btrim(coalesce(p_perceived_intensity, '')), '');

  for program in select * from jsonb_array_elements(p_programs)
  loop
    owner_uuid := (program->>'owner_user_id')::uuid;
    if owner_uuid is null then
      raise exception 'invalid_owner';
    end if;

    insert into public.workouts (
      user_id,
      kind,
      title,
      notes,
      started_at,
      ended_at,
      state,
      perceived_intensity,
      calories_kcal,
      calories_method,
      calories_weight_kg,
      calories_updated_at,
      healthkit_uuid,
      dual_linked_workout_id,
      dual_host_user_id,
      strength_planning_group_id
    ) values (
      owner_uuid,
      'strength'::workout_kind,
      nullif(btrim(p_title), ''),
      nullif(btrim(p_notes), ''),
      v_started,
      v_ended,
      v_state,
      v_perceived,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      v_group_id
    ) returning id into wid;

    all_ids := array_append(all_ids, wid);
    all_owners := array_append(all_owners, owner_uuid);

    if jsonb_typeof(program->'items') is distinct from 'array' then
      raise exception 'invalid_items';
    end if;

    for item in select * from jsonb_array_elements(program->'items')
    loop
      insert into public.workout_exercises (
        workout_id,
        exercise_id,
        order_index,
        notes,
        custom_name
      ) values (
        wid,
        (item->>'exercise_id')::bigint,
        coalesce((item->>'order_index')::int, 1),
        nullif(btrim(coalesce(item->>'notes', '')), ''),
        nullif(btrim(coalesce(item->>'custom_name', '')), '')
      ) returning id into new_we_id;

      for s in
        select j as set_json from jsonb_array_elements(coalesce(item->'sets', '[]'::jsonb)) t(j)
      loop
        insert into public.exercise_sets (
          workout_exercise_id,
          set_number,
          reps,
          weight_kg,
          rpe,
          rest_sec,
          notes,
          weight_segments
        ) values (
          new_we_id,
          coalesce((s.set_json->>'set_number')::int, 1),
          case
            when s.set_json ? 'reps' and s.set_json->>'reps' is not null and btrim(s.set_json->>'reps') <> '' then (s.set_json->>'reps')::int
            else null
          end,
          case
            when s.set_json ? 'weight_kg' and jsonb_typeof(s.set_json->'weight_kg') = 'number' then (s.set_json->>'weight_kg')::double precision
            when s.set_json ? 'weight_kg' and s.set_json->>'weight_kg' is not null and btrim(s.set_json->>'weight_kg') <> '' then (s.set_json->>'weight_kg')::double precision
            else null
          end,
          case
            when s.set_json ? 'rpe' and jsonb_typeof(s.set_json->'rpe') = 'number' then (s.set_json->>'rpe')::double precision
            when s.set_json ? 'rpe' and s.set_json->>'rpe' is not null and btrim(s.set_json->>'rpe') <> '' then (s.set_json->>'rpe')::double precision
            else null
          end,
          case
            when s.set_json ? 'rest_sec' and s.set_json->>'rest_sec' is not null and btrim(s.set_json->>'rest_sec') <> '' then (s.set_json->>'rest_sec')::int
            else null
          end,
          nullif(btrim(coalesce(s.set_json->>'notes', '')), ''),
          case
            when s.set_json ? 'weight_segments'
              and jsonb_typeof(s.set_json->'weight_segments') = 'array'
              and jsonb_array_length(s.set_json->'weight_segments') >= 2
            then s.set_json->'weight_segments'
            else null::jsonb
          end
        );
      end loop;
    end loop;
  end loop;

  for i in 1 .. coalesce(array_length(all_ids, 1), 0)
  loop
    for j in 1 .. coalesce(array_length(all_owners, 1), 0)
    loop
      continue when all_owners[i] = all_owners[j];
      insert into public.workout_participants (workout_id, user_id)
      select all_ids[i], all_owners[j]
      where not exists (
        select 1
        from public.workout_participants wp
        where wp.workout_id = all_ids[i]
          and wp.user_id = all_owners[j]
      );
    end loop;
  end loop;

  return all_ids;
end;
$function$;

create or replace function public.fetch_dual_linked_strength_workout_data(p_workout_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  allowed boolean;
  exercises_json jsonb;
  sets_json jsonb;
begin
  select exists (
    select 1
    from public.workouts w
    where w.id = p_workout_id
      and (
        w.user_id = auth.uid()
        or exists (
          select 1
          from public.workouts h
          where h.user_id = auth.uid()
            and h.dual_linked_workout_id is not distinct from w.id
        )
        or exists (
          select 1
          from public.workouts h
          where h.user_id = auth.uid()
            and h.id is not distinct from w.dual_linked_workout_id
        )
      )
  )
  into allowed;

  if not allowed then
    raise exception 'not_allowed_to_read_workout'
      using errcode = '42501',
            message = 'not_allowed_to_read_workout';
  end if;

  select coalesce(jsonb_agg(row_data order by ord1, ord2), '[]'::jsonb)
  into exercises_json
  from (
    select
      jsonb_build_object(
        'id', we.id,
        'exercise_id', we.exercise_id,
        'order_index', we.order_index,
        'notes', we.notes,
        'custom_name', we.custom_name,
        'target_sets', null::int,
        'exercises', jsonb_build_object('name', ex.name)
      ) as row_data,
      we.order_index as ord1,
      we.id as ord2
    from public.workout_exercises we
    join public.exercises ex on ex.id = we.exercise_id
    where we.workout_id = p_workout_id
  ) t;

  select coalesce(jsonb_agg(row_data order by ord1, ord2), '[]'::jsonb)
  into sets_json
  from (
    select
      jsonb_build_object(
        'id', es.id,
        'workout_exercise_id', es.workout_exercise_id,
        'set_number', es.set_number,
        'reps', es.reps,
        'weight_kg', es.weight_kg,
        'rpe', es.rpe,
        'rest_sec', es.rest_sec,
        'weight_segments', es.weight_segments
      ) as row_data,
      es.workout_exercise_id as ord1,
      es.id as ord2
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    where we.workout_id = p_workout_id
  ) s;

  return jsonb_build_object(
    'exercises', exercises_json,
    'sets', sets_json
  );
end;
$function$;

create or replace function public.create_linked_strength_workout_copy(p_source_workout_id bigint, p_target_user_id uuid)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  src public.workouts%rowtype;
  guest public.workouts%rowtype;
  new_id bigint;
  existing_other bigint;
  squad_partner_id bigint;
  we_rec public.workout_exercises%rowtype;
  new_we_id bigint;
  es_rec public.exercise_sets%rowtype;
begin
  select * into strict src
  from public.workouts
  where id = p_source_workout_id;

  if src.user_id is distinct from auth.uid()
     and not exists (
       select 1
       from public.workout_participants wp
       where wp.workout_id = p_source_workout_id
         and wp.user_id = auth.uid()
     ) then
    raise exception 'not_owner_or_participant';
  end if;

  if lower(btrim(src.kind::text)) is distinct from 'strength' then
    raise exception 'not_strength';
  end if;

  if not exists (
    select 1
    from public.workout_participants wp
    where wp.workout_id = p_source_workout_id
      and wp.user_id = p_target_user_id
  ) then
    raise exception 'not_participant';
  end if;

  if src.strength_planning_group_id is not null
     and src.dual_linked_workout_id is null then
    select w.id into squad_partner_id
    from public.workouts w
    where w.user_id = p_target_user_id
      and w.strength_planning_group_id is not distinct from src.strength_planning_group_id
      and w.id is distinct from p_source_workout_id
      and w.ended_at is null
      and lower(btrim(w.state::text)) in ('planned', 'published')
    order by w.id
    limit 1;

    if squad_partner_id is not null then
      update public.workouts
      set
        started_at = src.started_at,
        dual_host_user_id = coalesce(dual_host_user_id, auth.uid())
      where id = squad_partner_id;

      update public.workouts
      set dual_linked_workout_id = squad_partner_id
      where id = p_source_workout_id
        and dual_linked_workout_id is null;

      update public.workouts
      set dual_linked_workout_id = p_source_workout_id
      where id = squad_partner_id;

      return squad_partner_id;
    end if;
  end if;

  if src.dual_linked_workout_id is not null then
    select * into guest
    from public.workouts
    where id = src.dual_linked_workout_id;

    if not found then
      update public.workouts
      set dual_linked_workout_id = null
      where id = p_source_workout_id;

      select * into strict src
      from public.workouts
      where id = p_source_workout_id;

    elsif guest.user_id = p_target_user_id
      and guest.dual_linked_workout_id is not distinct from p_source_workout_id
      and guest.ended_at is null
      and src.ended_at is null
    then
      return src.dual_linked_workout_id;

    elsif guest.user_id = p_target_user_id
      and guest.dual_linked_workout_id is not distinct from p_source_workout_id
    then
      update public.workouts
      set dual_linked_workout_id = null,
          dual_host_user_id = null
      where id = guest.id;

      update public.workouts
      set dual_linked_workout_id = null
      where id = p_source_workout_id;

      select * into strict src
      from public.workouts
      where id = p_source_workout_id;

    elsif guest.user_id is distinct from p_target_user_id then
      select w2.id into existing_other
      from public.workouts w2
      where w2.user_id = p_target_user_id
        and w2.ended_at is null
        and src.ended_at is null
        and (
          w2.dual_linked_workout_id is not distinct from p_source_workout_id
          or (
            src.strength_planning_group_id is not null
            and w2.strength_planning_group_id is not distinct from src.strength_planning_group_id
            and w2.id is distinct from p_source_workout_id
            and lower(btrim(w2.state::text)) in ('planned', 'published')
          )
        )
      order by w2.id desc
      limit 1;

      if existing_other is not null then
        update public.workouts
        set
          started_at = src.started_at,
          dual_linked_workout_id = p_source_workout_id,
          dual_host_user_id = coalesce(dual_host_user_id, auth.uid())
        where id = existing_other;
        return existing_other;
      end if;

    else
      raise exception 'already_linked';
    end if;
  end if;

  insert into public.workouts (
    user_id,
    kind,
    title,
    notes,
    started_at,
    ended_at,
    state,
    perceived_intensity,
    calories_kcal,
    calories_method,
    calories_weight_kg,
    calories_updated_at,
    healthkit_uuid,
    dual_linked_workout_id,
    dual_host_user_id
  )
  select
    p_target_user_id,
    coalesce(
      nullif(btrim(w.kind::text), '')::workout_kind,
      'strength'::workout_kind
    ),
    w.title,
    w.notes,
    w.started_at,
    null::timestamptz,
    w.state,
    w.perceived_intensity,
    w.calories_kcal,
    w.calories_method,
    w.calories_weight_kg,
    w.calories_updated_at,
    null::text,
    null::bigint,
    auth.uid()
  from public.workouts w
  where w.id = p_source_workout_id
  returning id into new_id;

  for we_rec in
    select * from public.workout_exercises
    where workout_id = p_source_workout_id
    order by order_index asc, id asc
  loop
    insert into public.workout_exercises (
      workout_id,
      exercise_id,
      order_index,
      notes,
      custom_name
    ) values (
      new_id,
      we_rec.exercise_id,
      we_rec.order_index,
      we_rec.notes,
      we_rec.custom_name
    )
    returning id into new_we_id;

    for es_rec in
      select * from public.exercise_sets
      where workout_exercise_id = we_rec.id
      order by id asc
    loop
      insert into public.exercise_sets (
        workout_exercise_id,
        set_number,
        reps,
        weight_kg,
        rpe,
        rest_sec,
        notes,
        weight_segments
      )
      values (
        new_we_id,
        es_rec.set_number,
        es_rec.reps,
        es_rec.weight_kg,
        es_rec.rpe,
        es_rec.rest_sec,
        es_rec.notes,
        es_rec.weight_segments
      );
    end loop;
  end loop;

  update public.workouts
  set dual_linked_workout_id = new_id
  where id = p_source_workout_id
    and dual_linked_workout_id is null;

  update public.workouts
  set dual_linked_workout_id = p_source_workout_id
  where id = new_id;

  return new_id;
end;
$function$;

create or replace function public.apply_strength_workout_finish_as_dual_host(p_workout_id bigint, p_payload jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  w public.workouts%rowtype;
  item jsonb;
  blk jsonb;
  we_id int;
  v_seg jsonb;
begin
  select * into strict w from public.workouts where id = p_workout_id for update;

  if w.user_id = auth.uid() then
    null;
  elsif w.dual_host_user_id is not distinct from auth.uid() then
    if not exists (
      select 1 from public.workouts h
      where h.id = w.dual_linked_workout_id
        and h.user_id = auth.uid()
    ) then
      raise exception 'forbidden_guest';
    end if;
  else
    raise exception 'forbidden';
  end if;

  for item in select * from jsonb_array_elements(coalesce(p_payload, '[]'::jsonb))
  loop
    we_id := (item->>'workout_exercise_id')::int;

    if not exists (
      select 1 from public.workout_exercises we
      where we.id = we_id and we.workout_id = p_workout_id
    ) then
      raise exception 'invalid_exercise %', we_id;
    end if;

    delete from public.exercise_sets es
    where es.workout_exercise_id = we_id;

    for blk in
      select j as block_json from jsonb_array_elements(coalesce(item->'blocks', '[]'::jsonb)) t(j)
    loop
      v_seg := case
        when blk.block_json ? 'weight_segments'
          and jsonb_typeof(blk.block_json->'weight_segments') = 'array'
          and jsonb_array_length(blk.block_json->'weight_segments') >= 2
        then blk.block_json->'weight_segments'
        else null::jsonb
      end;
      insert into public.exercise_sets (
        workout_exercise_id,
        set_number,
        reps,
        weight_kg,
        rpe,
        rest_sec,
        weight_segments
      )
      values (
        we_id,
        coalesce((blk.block_json->>'set_number')::int, 0),
        case when blk.block_json ? 'reps' and blk.block_json->'reps' is not null and jsonb_typeof(blk.block_json->'reps') = 'number'
          then (blk.block_json->>'reps')::int else null end,
        case when blk.block_json ? 'weight_kg' and blk.block_json->'weight_kg' is not null and jsonb_typeof(blk.block_json->'weight_kg') = 'number'
          then (blk.block_json->>'weight_kg')::numeric else null end,
        case when blk.block_json ? 'rpe' and blk.block_json->'rpe' is not null and jsonb_typeof(blk.block_json->'rpe') = 'number'
          then (blk.block_json->>'rpe')::numeric else null end,
        case when blk.block_json ? 'rest_sec' and blk.block_json->'rest_sec' is not null and jsonb_typeof(blk.block_json->'rest_sec') = 'number'
          then (blk.block_json->>'rest_sec')::int else null end,
        v_seg
      );
    end loop;
  end loop;

  update public.workouts
  set ended_at = timezone('utc', now())
  where id = p_workout_id;
end;
$function$;

create or replace function public.get_challenge_my_progress_v1(p_instance_id uuid)
returns table(progress_value numeric, target_value numeric, secondary_cap numeric, metric_kind text, is_eligible boolean)
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  r record;
  pv numeric;
  elig boolean := false;
begin
  if uid is null then
    return;
  end if;

  select t.metric_kind, t.threshold_numeric, t.threshold_secondary,
         ci.period_start, ci.period_end,
         t.scope_activity_code, t.scope_sport, t.scope_muscle_primary
  into r
  from public.challenge_instances ci
  join public.challenge_templates t on t.id = ci.template_id
  where ci.id = p_instance_id
  limit 1;

  if not found then
    return;
  end if;

  if r.metric_kind = 'cumulative_cardio_km' then
    select coalesce(sum(cs.distance_km), 0::numeric) into pv
    from public.workouts w
    join public.cardio_sessions cs on cs.workout_id = w.id
    where w.user_id = uid
      and w.kind::text = 'cardio'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end
      and (
        r.scope_activity_code is null
        or lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
      );
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'single_set_max_kg' then
    select coalesce(max(sw), 0::numeric) into pv
    from (
      select public.exercise_set_segment_max_weight_kg(es.weight_kg, es.weight_segments) as sw
      from public.workouts w
      join public.workout_exercises we on we.workout_id = w.id
      join public.exercise_sets es on es.workout_exercise_id = we.id
      join public.exercises ex on ex.id = we.exercise_id
      where w.user_id = uid
        and w.kind::text = 'strength'
        and w.state = 'published'::public.workout_state
        and w.started_at >= r.period_start
        and w.started_at < r.period_end
        and (
          r.scope_muscle_primary is null
          or lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
        )
    ) q;
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'cardio_session_pace_gate' then
    select coalesce(max(cs.distance_km), 0::numeric) into pv
    from public.workouts w
    join public.cardio_sessions cs on cs.workout_id = w.id
    where w.user_id = uid
      and w.kind::text = 'cardio'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end
      and coalesce(cs.duration_sec, 99999999) <= coalesce(r.threshold_secondary, 3600)
      and (
        r.scope_activity_code is null
        or lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
      );
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'cumulative_sport_sessions' then
    select count(*)::numeric into pv
    from public.workouts w
    inner join public.sport_sessions ss on ss.workout_id = w.id
    where w.user_id = uid
      and w.kind::text = 'sport'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end
      and (
        r.scope_sport is null
        or lower(btrim(ss.sport::text)) = lower(btrim(r.scope_sport))
      );
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'cumulative_strength_workouts' then
    select count(*)::numeric into pv
    from public.workouts w
    where w.user_id = uid
      and w.kind::text = 'strength'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end;
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'cumulative_strength_reps' then
    select coalesce(sum(public.exercise_set_segment_reps_sum(es.reps, es.weight_segments)), 0)::numeric into pv
    from public.workouts w
    join public.workout_exercises we on we.workout_id = w.id
    join public.exercise_sets es on es.workout_exercise_id = we.id
    join public.exercises ex on ex.id = we.exercise_id
    where w.user_id = uid
      and w.kind::text = 'strength'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end
      and (
        r.scope_muscle_primary is null
        or lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
      );
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'cumulative_strength_sets' then
    select count(*)::numeric into pv
    from public.workouts w
    join public.workout_exercises we on we.workout_id = w.id
    join public.exercise_sets es on es.workout_exercise_id = we.id
    join public.exercises ex on ex.id = we.exercise_id
    where w.user_id = uid
      and w.kind::text = 'strength'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end
      and (
        public.exercise_set_segment_reps_sum(es.reps, es.weight_segments) > 0
        or public.exercise_set_segment_max_weight_kg(es.weight_kg, es.weight_segments) > 0
      )
      and (
        r.scope_muscle_primary is null
        or lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
      );
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'cumulative_strength_volume_kg' then
    select coalesce(sum(public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)), 0::numeric) into pv
    from public.workouts w
    join public.workout_exercises we on we.workout_id = w.id
    join public.exercise_sets es on es.workout_exercise_id = we.id
    join public.exercises ex on ex.id = we.exercise_id
    where w.user_id = uid
      and w.kind::text = 'strength'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end
      and (
        r.scope_muscle_primary is null
        or lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
      );
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'single_set_max_reps' then
    select coalesce(max(sr), 0)::numeric into pv
    from (
      select public.exercise_set_segment_max_reps(es.reps, es.weight_segments) as sr
      from public.workouts w
      join public.workout_exercises we on we.workout_id = w.id
      join public.exercise_sets es on es.workout_exercise_id = we.id
      join public.exercises ex on ex.id = we.exercise_id
      where w.user_id = uid
        and w.kind::text = 'strength'
        and w.state = 'published'::public.workout_state
        and w.started_at >= r.period_start
        and w.started_at < r.period_end
        and (
          r.scope_muscle_primary is null
          or lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
        )
    ) q;
    elig := pv >= r.threshold_numeric;

  elsif r.metric_kind = 'strength_workouts_touching_muscle' then
    select count(*)::numeric into pv
    from public.workouts w
    where w.user_id = uid
      and w.kind::text = 'strength'
      and w.state = 'published'::public.workout_state
      and w.started_at >= r.period_start
      and w.started_at < r.period_end
      and r.scope_muscle_primary is not null
      and exists (
        select 1
        from public.workout_exercises we2
        inner join public.exercises ex2 on ex2.id = we2.exercise_id
        where we2.workout_id = w.id
          and lower(btrim(ex2.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
      );
    elig := pv >= r.threshold_numeric;
  end if;

  progress_value := pv;
  target_value := r.threshold_numeric;
  secondary_cap := r.threshold_secondary;
  metric_kind := r.metric_kind;
  is_eligible := elig;
  return next;
end;
$function$;

commit;

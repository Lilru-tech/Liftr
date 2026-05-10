begin;

alter table public.exercise_sets
  add column if not exists weight_segments jsonb null;

alter table public.strength_routine_sets
  add column if not exists weight_segments jsonb null;

alter table public.exercise_sets drop constraint if exists exercise_sets_weight_segments_len_chk;
alter table public.exercise_sets
  add constraint exercise_sets_weight_segments_len_chk
  check (
    weight_segments is null
    or (
      jsonb_typeof(weight_segments) = 'array'
      and jsonb_array_length(weight_segments) >= 2
    )
  );

alter table public.strength_routine_sets drop constraint if exists strength_routine_sets_weight_segments_len_chk;
alter table public.strength_routine_sets
  add constraint strength_routine_sets_weight_segments_len_chk
  check (
    weight_segments is null
    or (
      jsonb_typeof(weight_segments) = 'array'
      and jsonb_array_length(weight_segments) >= 2
    )
  );

create or replace function public.strength_set_segments_expand(p_reps int, p_weight_kg numeric, p_segments jsonb)
returns jsonb
language sql
immutable
parallel safe
as $f$
  select case
    when p_segments is not null
      and jsonb_typeof(p_segments) = 'array'
      and jsonb_array_length(p_segments) >= 2
    then p_segments
    else jsonb_build_array(jsonb_build_object('reps', p_reps, 'weight_kg', p_weight_kg))
  end;
$f$;

create or replace function public.exercise_set_segment_volume_kg(p_reps int, p_weight_kg numeric, p_segments jsonb)
returns numeric
language sql
immutable
parallel safe
as $f$
  select coalesce(sum(
    coalesce((elem->>'reps')::int, 0)::numeric
    * coalesce((elem->>'weight_kg')::numeric, 0)
  ), 0)
  from jsonb_array_elements(public.strength_set_segments_expand(p_reps, p_weight_kg, p_segments)) elem;
$f$;

create or replace function public.exercise_set_segment_reps_sum(p_reps int, p_segments jsonb)
returns bigint
language sql
immutable
parallel safe
as $f$
  select coalesce(sum(coalesce((elem->>'reps')::int, 0)), 0)::bigint
  from jsonb_array_elements(public.strength_set_segments_expand(p_reps, null::numeric, p_segments)) elem;
$f$;

create or replace function public.exercise_set_segment_max_weight_kg(p_weight_kg numeric, p_segments jsonb)
returns numeric
language sql
immutable
parallel safe
as $f$
  select coalesce(max(coalesce((elem->>'weight_kg')::numeric, 0)), 0)
  from jsonb_array_elements(public.strength_set_segments_expand(null::int, p_weight_kg, p_segments)) elem;
$f$;

create or replace function public.exercise_set_segment_max_reps(p_reps int, p_segments jsonb)
returns int
language sql
immutable
parallel safe
as $f$
  select coalesce(max(coalesce((elem->>'reps')::int, 0)), 0)::int
  from jsonb_array_elements(public.strength_set_segments_expand(p_reps, null::numeric, p_segments)) elem;
$f$;

create or replace view public.vw_workout_volume as
select
  w.id as workout_id,
  w.user_id,
  coalesce(
    sum(public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)),
    0::numeric
  )::numeric(12, 3) as total_volume_kg
from public.workouts w
left join public.workout_exercises we on we.workout_id = w.id
left join public.exercise_sets es on es.workout_exercise_id = we.id
where w.kind = any (array['strength'::public.workout_kind, 'mixed'::public.workout_kind])
group by w.id, w.user_id;

create or replace function public.recompute_strength_score(p_workout_id integer)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_kind         text;
  v_started      timestamptz;
  v_ended        timestamptz;
  v_duration_min numeric;
  v_volume_kg    numeric;
  v_density      numeric;
  v_score        numeric;
begin
  select kind, started_at, ended_at, duration_min
  into v_kind, v_started, v_ended, v_duration_min
  from public.workouts
  where id = p_workout_id;

  if not found then
    return;
  end if;

  if v_kind is null or lower(v_kind) <> 'strength' then
    delete from public.workout_scores
    where workout_id = p_workout_id
      and algorithm = 'strength_vd1';
    return;
  end if;

  select coalesce(sum(public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)), 0)
  into v_volume_kg
  from public.workout_exercises we
  join public.exercise_sets es on es.workout_exercise_id = we.id
  where we.workout_id = p_workout_id;

  if v_duration_min is null then
    if v_started is not null and v_ended is not null then
      v_duration_min := greatest(0, extract(epoch from (v_ended - v_started)) / 60.0);
    else
      v_duration_min := null;
    end if;
  end if;

  if v_duration_min is null or v_duration_min <= 0 then
    v_density := null;
  else
    v_density := v_volume_kg / v_duration_min;
  end if;

  if v_density is null then
    v_score := (v_volume_kg / 120.0) * 0.9;
  else
    v_score := (v_volume_kg / 120.0) * (0.8 + least(0.6, v_density / 40.0));
  end if;

  v_score := round(v_score::numeric, 2);

  delete from public.workout_scores
  where workout_id = p_workout_id
    and algorithm = 'strength_vd1';

  insert into public.workout_scores(workout_id, score, algorithm, calculated_at)
  values (p_workout_id, v_score, 'strength_vd1', now());

  insert into public.score_recalc_audit(source, workout_id, extra)
  values ('func:recompute_strength_score', p_workout_id, jsonb_build_object('algo', 'strength_vd1'));

end;
$function$;

create or replace function public.get_strength_volume_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit integer default 100,
  p_sex text default null::text,
  p_age_band text default null::text,
  p_muscle_primary text default null::text
)
returns table(rank integer, user_id uuid, username text, avatar_url text, total_volume_kg numeric, workouts_cnt integer)
language plpgsql
stable
set search_path to 'public'
as $function$
begin
  return query
  with bounds as (
    select
      case lower(coalesce(p_period, 'week'))
        when 'day' then date_trunc('day', now())
        when 'week' then date_trunc('week', now())
        when 'month' then date_trunc('month', now())
        when 'all' then '1970-01-01'::timestamptz
        else date_trunc('week', now())
      end as t_start,
      now() as t_end
  ),
  bw as (
    select w.id, w.user_id
    from public.workouts w
    cross join bounds b
    where w.kind::text = 'strength'
      and w.state is distinct from 'planned'::public.workout_state
      and w.started_at >= b.t_start
      and w.started_at < b.t_end
  ),
  vol as (
    select
      bw.user_id as uid,
      count(distinct bw.id)::int as workouts_cnt,
      sum(
        public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)
      )::numeric as total_volume_kg
    from bw
    inner join public.workout_exercises we on we.workout_id = bw.id
    inner join public.exercises ex on ex.id = we.exercise_id
    inner join public.exercise_sets es on es.workout_exercise_id = we.id
    where
      (p_muscle_primary is null or p_muscle_primary = ''
        or lower(btrim(ex.muscle_primary)) = lower(btrim(p_muscle_primary)))
    group by bw.user_id
    having sum(
      public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)
    ) > 0
  ),
  scoped as (
    select v.uid, v.workouts_cnt, v.total_volume_kg
    from vol v
    inner join public.profiles pr on pr.user_id = v.uid
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
      s.workouts_cnt,
      s.total_volume_kg,
      row_number() over (order by s.total_volume_kg desc, s.workouts_cnt desc, s.uid) as rnk
    from scoped s
  )
  select
    o.rnk::int as rank,
    o.uid as user_id,
    pr.username,
    pr.avatar_url,
    o.total_volume_kg,
    o.workouts_cnt
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  where o.rnk <= greatest(1, coalesce(p_limit, 100))
  order by o.rnk;
end;
$function$;

create or replace function public.get_strength_max_set_weight_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit integer default 100,
  p_sex text default null::text,
  p_age_band text default null::text,
  p_muscle_primary text default null::text
)
returns table(rank integer, user_id uuid, username text, avatar_url text, max_weight_kg numeric, workouts_cnt integer)
language sql
stable
set search_path to 'public'
as $function$
with bounds as (
    select
      case lower(coalesce(p_period, 'week'))
        when 'day' then date_trunc('day', now())
        when 'week' then date_trunc('week', now())
        when 'month' then date_trunc('month', now())
        when 'all' then '1970-01-01'::timestamptz
        else date_trunc('week', now())
      end as t_start,
      now() as t_end
  ),
  bw as (
    select w.id, w.user_id
    from public.workouts w
    cross join bounds b
    where w.kind::text = 'strength'
      and w.state is distinct from 'planned'::public.workout_state
      and w.started_at >= b.t_start
      and w.started_at < b.t_end
  ),
  per_set as (
    select bw.user_id as uid, bw.id as wid,
      public.exercise_set_segment_max_weight_kg(es.weight_kg, es.weight_segments) as wkg
    from bw
    inner join public.workout_exercises we on we.workout_id = bw.id
    inner join public.exercises ex on ex.id = we.exercise_id
    inner join public.exercise_sets es on es.workout_exercise_id = we.id
    where public.exercise_set_segment_max_reps(es.reps, es.weight_segments) > 0
      and public.exercise_set_segment_max_weight_kg(es.weight_kg, es.weight_segments) > 0
      and (
        p_muscle_primary is null or p_muscle_primary = ''
        or lower(btrim(ex.muscle_primary)) = lower(btrim(p_muscle_primary))
      )
  ),
  agg as (
    select
      p.uid,
      count(distinct p.wid)::int as workouts_cnt,
      max(p.wkg)::numeric as max_weight_kg
    from per_set p
    group by p.uid
    having max(p.wkg) is not null
  ),
  scoped as (
    select a.uid, a.workouts_cnt, a.max_weight_kg
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
            when '55+' then extract(year from age(current_date, pr.date_of_birth)) >= 55
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
    select s.uid, s.workouts_cnt, s.max_weight_kg,
      row_number() over (order by s.max_weight_kg desc, s.workouts_cnt desc, s.uid) as rnk
    from scoped s
  )
  select o.rnk::int, o.uid, pr.username, pr.avatar_url, o.max_weight_kg, o.workouts_cnt
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  where o.rnk <= greatest(1, coalesce(p_limit, 100))
  order by o.rnk;
$function$;

create or replace function public.get_strength_total_reps_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit integer default 100,
  p_sex text default null::text,
  p_age_band text default null::text,
  p_muscle_primary text default null::text
)
returns table(rank integer, user_id uuid, username text, avatar_url text, total_reps bigint, workouts_cnt integer)
language sql
stable
set search_path to 'public'
as $function$
with bounds as (
    select
      case lower(coalesce(p_period, 'week'))
        when 'day' then date_trunc('day', now())
        when 'week' then date_trunc('week', now())
        when 'month' then date_trunc('month', now())
        when 'all' then '1970-01-01'::timestamptz
        else date_trunc('week', now())
      end as t_start,
      now() as t_end
  ),
  bw as (
    select w.id, w.user_id
    from public.workouts w
    cross join bounds b
    where w.kind::text = 'strength'
      and w.state is distinct from 'planned'::public.workout_state
      and w.started_at >= b.t_start
      and w.started_at < b.t_end
  ),
  agg as (
    select
      bw.user_id as uid,
      count(distinct bw.id)::int as workouts_cnt,
      sum(public.exercise_set_segment_reps_sum(es.reps, es.weight_segments))::bigint as total_reps
    from bw
    inner join public.workout_exercises we on we.workout_id = bw.id
    inner join public.exercises ex on ex.id = we.exercise_id
    inner join public.exercise_sets es on es.workout_exercise_id = we.id
    where
      (p_muscle_primary is null or p_muscle_primary = ''
        or lower(btrim(ex.muscle_primary)) = lower(btrim(p_muscle_primary)))
    group by bw.user_id
    having sum(public.exercise_set_segment_reps_sum(es.reps, es.weight_segments)) > 0
  ),
  scoped as (
    select a.uid, a.workouts_cnt, a.total_reps
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
            when '55+' then extract(year from age(current_date, pr.date_of_birth)) >= 55
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
    select s.uid, s.workouts_cnt, s.total_reps,
      row_number() over (order by s.total_reps desc, s.workouts_cnt desc, s.uid) as rnk
    from scoped s
  )
  select o.rnk::int, o.uid, pr.username, pr.avatar_url, o.total_reps, o.workouts_cnt
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  where o.rnk <= greatest(1, coalesce(p_limit, 100))
  order by o.rnk;
$function$;
commit;

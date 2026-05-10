begin;

insert into public.achievements (code, name, description, category, requirement_type, requirement_value, created_at)
values
  (
    'strength_drop_first',
    'Into the Drop',
    'Log your first strength set with a drop (multiple weight segments in one set).',
    'strength',
    'count',
    1,
    now()
  ),
  (
    'strength_drop_sets_10',
    'Drop Set Starter',
    'Log 10 drop sets across your strength training.',
    'strength',
    'count',
    10,
    now()
  ),
  (
    'strength_drop_sets_50',
    'Drop Set Regular',
    'Log 50 drop sets across your strength training.',
    'strength',
    'count',
    50,
    now()
  ),
  (
    'strength_drop_sets_200',
    'Drop Set Veteran',
    'Log 200 drop sets across your strength training.',
    'strength',
    'count',
    200,
    now()
  ),
  (
    'strength_drop_triple_first',
    'Triple Drop',
    'Log a strength set with at least three weight segments (triple drop or more).',
    'strength',
    'count',
    1,
    now()
  )
on conflict (code) do nothing;

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
  v_drop_sets    bigint := 0;
  v_drop_triple  boolean := false;
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

    select count(*) into v_drop_sets
    from public.exercise_sets es
    join public.workouts w on w.id = es.workout_id
    where w.user_id = p_user_id
      and es.weight_segments is not null
      and jsonb_typeof(es.weight_segments) = 'array'
      and jsonb_array_length(es.weight_segments) >= 2;

    select exists (
      select 1
      from public.exercise_sets es
      join public.workouts w on w.id = es.workout_id
      where w.user_id = p_user_id
        and es.weight_segments is not null
        and jsonb_typeof(es.weight_segments) = 'array'
        and jsonb_array_length(es.weight_segments) >= 3
    ) into v_drop_triple;
  else
    select
      coalesce(sum(public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)), 0),
      coalesce(sum(public.exercise_set_segment_reps_sum(es.reps, es.weight_segments)), 0)
    into v_total_volume, v_total_reps
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    join public.workouts w on w.id = we.workout_id
    where w.user_id = p_user_id;

    select count(*) into v_drop_sets
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    join public.workouts w on w.id = we.workout_id
    where w.user_id = p_user_id
      and es.weight_segments is not null
      and jsonb_typeof(es.weight_segments) = 'array'
      and jsonb_array_length(es.weight_segments) >= 2;

    select exists (
      select 1
      from public.exercise_sets es
      join public.workout_exercises we on we.id = es.workout_exercise_id
      join public.workouts w on w.id = we.workout_id
      where w.user_id = p_user_id
        and es.weight_segments is not null
        and jsonb_typeof(es.weight_segments) = 'array'
        and jsonb_array_length(es.weight_segments) >= 3
    ) into v_drop_triple;
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

  if v_drop_sets >= 1 then
    insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_drop_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_drop_sets >= 10 then
    insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_drop_sets_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_drop_sets >= 50 then
    insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_drop_sets_50'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_drop_sets >= 200 then
    insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_drop_sets_200'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_drop_triple then
    insert into public.user_achievements(user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'strength_drop_triple_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

commit;

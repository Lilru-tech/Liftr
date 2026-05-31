begin;

create or replace function public.strength_set_multiplicity(
  p_set_number int,
  p_sorted_set_numbers int[]
)
returns int
language sql
immutable
parallel safe
set search_path to 'pg_catalog', 'public'
as $f$
  select case
    when coalesce(cardinality(p_sorted_set_numbers), 0) = 0 then 1
    when p_sorted_set_numbers = (
      select coalesce(array_agg(s.i order by s.i), array[]::int[])
      from generate_series(1, cardinality(p_sorted_set_numbers)) as s(i)
    )
    then 1
    else greatest(coalesce(p_set_number, 1), 1)
  end;
$f$;

create or replace view public.vw_workout_volume as
with exercise_set_numbers as (
  select
    we.id as workout_exercise_id,
    array_agg(es.set_number order by coalesce(es.order_index, 2147483647), es.id) as sorted_set_numbers
  from public.workout_exercises we
  join public.exercise_sets es on es.workout_exercise_id = we.id
  group by we.id
),
per_set as (
  select
    we.workout_id,
    public.exercise_set_segment_volume_kg(es.reps, es.weight_kg, es.weight_segments)
      * public.strength_set_multiplicity(es.set_number, esn.sorted_set_numbers) as effective_volume
  from public.workout_exercises we
  join public.exercise_sets es on es.workout_exercise_id = we.id
  join exercise_set_numbers esn on esn.workout_exercise_id = we.id
)
select
  w.id as workout_id,
  w.user_id,
  coalesce(sum(ps.effective_volume), 0)::numeric(12, 3) as total_volume_kg
from public.workouts w
left join per_set ps on ps.workout_id = w.id
where w.kind = any (array['strength'::public.workout_kind, 'mixed'::public.workout_kind])
group by w.id, w.user_id;

alter view public.vw_workout_volume set (security_invoker = true);

commit;

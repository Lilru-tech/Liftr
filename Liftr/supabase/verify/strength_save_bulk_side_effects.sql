-- Verify strength save bulk side-effect guards (run in Supabase SQL editor as workout owner).
--
-- Prerequisites:
-- 1. Migration 20260630120000_strength_save_bulk_side_effect_guards_v1 applied.
-- 2. A strength workout you own with 15+ sets across multiple exercises.
--
-- Steps:
-- 1. Note workout id (WID) and exercise ids in the payload.
-- 2. Call update_strength_workout_v1 with the current edited payload (same as app save).
-- 3. Assert RPC returns JSON with workout_id = WID (no statement timeout).
-- 4. Assert personal_records still exist for exercises in the workout.
-- 5. Assert workout_scores has a recent strength_v2 row for WID.
--
-- Example (replace placeholders; must run as the workout owner via PostgREST / SQL editor with user JWT):
--
-- select public.update_strength_workout_v1(
--   p_workout_id := 2936,
--   p_title := 'Espalda + bíceps',
--   p_notes := null,
--   p_started_at := '2026-06-30 08:42:55.341+00'::timestamptz,
--   p_ended_at := '2026-06-30 10:08:42.008+00'::timestamptz,
--   p_perceived_intensity := 'hard',
--   p_exercises := (
--     select jsonb_agg(
--       jsonb_build_object(
--         'workout_exercise_id', we.id,
--         'exercise_id', we.exercise_id,
--         'order_index', we.order_index,
--         'notes', we.notes,
--         'custom_name', we.custom_name,
--         'sets', (
--           select coalesce(jsonb_agg(
--             jsonb_build_object(
--               'set_number', es.set_number,
--               'reps', es.reps,
--               'weight_kg', es.weight_kg,
--               'rpe', es.rpe,
--               'rest_sec', es.rest_sec,
--               'weight_segments', es.weight_segments
--             ) order by es.set_number
--           ), '[]'::jsonb)
--           from public.exercise_sets es
--           where es.workout_exercise_id = we.id
--         )
--       ) order by we.order_index
--     )
--     from public.workout_exercises we
--     where we.workout_id = 2936
--   )
-- );
--
-- Post-checks:
select
  w.id as workout_id,
  count(distinct we.id) as exercises,
  count(es.id) as sets,
  (
    select ws.score
    from public.workout_scores ws
    where ws.workout_id = w.id
      and ws.algorithm = 'strength_v2'
    order by ws.calculated_at desc nulls last, ws.id desc
    limit 1
  ) as latest_strength_score
from public.workouts w
left join public.workout_exercises we on we.workout_id = w.id
left join public.exercise_sets es on es.workout_exercise_id = we.id
where w.id = 2936
group by w.id;

select count(*) as pr_rows_for_workout_exercises
from public.personal_records pr
where pr.user_id = (select user_id from public.workouts where id = 2936)
  and pr.exercise_id in (
    select distinct we.exercise_id
    from public.workout_exercises we
    where we.workout_id = 2936
  )
  and pr.metric in ('max_weight_kg', 'max_reps', 'best_set_volume_kg', 'est_1rm_kg');

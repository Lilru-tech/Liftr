begin;

alter table public.hyrox_session_exercises
  add column if not exists calories_kcal numeric(8,1);

alter table public.hyrox_routine_exercises
  add column if not exists calories_kcal numeric(8,1);

alter table public.hyrox_session_exercises
  drop constraint if exists hyrox_session_exercises_calories_kcal_check;

alter table public.hyrox_session_exercises
  add constraint hyrox_session_exercises_calories_kcal_check
  check (calories_kcal is null or (calories_kcal >= 1 and calories_kcal <= 5000));

alter table public.hyrox_routine_exercises
  drop constraint if exists hyrox_routine_exercises_calories_kcal_check;

alter table public.hyrox_routine_exercises
  add constraint hyrox_routine_exercises_calories_kcal_check
  check (calories_kcal is null or (calories_kcal >= 1 and calories_kcal <= 5000));

commit;

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

  if v_def not like '%calories_kcal%' then
    v_def := replace(
      v_def,
      $needle$          INSERT INTO public.hyrox_session_exercises (
            session_id,
            exercise_code,
            exercise_order,
            distance_m,
            reps,
            weight_kg,
            duration_sec,
            height_cm,
            implement_count,
            notes
          ) VALUES (
            v_session_id,
            lower(coalesce(NULLIF(v_hyrox_exercise.value->>'exercise_code', ''), '')),
            COALESCE(NULLIF(v_hyrox_exercise.value->>'exercise_order', '')::smallint, v_hyrox_exercise_order),
            NULLIF(v_hyrox_exercise.value->>'distance_m', '')::int,
            NULLIF(v_hyrox_exercise.value->>'reps', '')::int,
            NULLIF(v_hyrox_exercise.value->>'weight_kg', '')::numeric,
            NULLIF(v_hyrox_exercise.value->>'duration_sec', '')::int,
            NULLIF(v_hyrox_exercise.value->>'height_cm', '')::int,
            NULLIF(v_hyrox_exercise.value->>'implement_count', '')::smallint,
            NULLIF(v_hyrox_exercise.value->>'notes', '')
          );$needle$,
      $needle$          INSERT INTO public.hyrox_session_exercises (
            session_id,
            exercise_code,
            exercise_order,
            distance_m,
            reps,
            weight_kg,
            duration_sec,
            height_cm,
            implement_count,
            calories_kcal,
            notes
          ) VALUES (
            v_session_id,
            lower(coalesce(NULLIF(v_hyrox_exercise.value->>'exercise_code', ''), '')),
            COALESCE(NULLIF(v_hyrox_exercise.value->>'exercise_order', '')::smallint, v_hyrox_exercise_order),
            NULLIF(v_hyrox_exercise.value->>'distance_m', '')::int,
            NULLIF(v_hyrox_exercise.value->>'reps', '')::int,
            NULLIF(v_hyrox_exercise.value->>'weight_kg', '')::numeric,
            NULLIF(v_hyrox_exercise.value->>'duration_sec', '')::int,
            NULLIF(v_hyrox_exercise.value->>'height_cm', '')::int,
            NULLIF(v_hyrox_exercise.value->>'implement_count', '')::smallint,
            NULLIF(v_hyrox_exercise.value->>'calories_kcal', '')::numeric,
            NULLIF(v_hyrox_exercise.value->>'notes', '')
          );$needle$
    );
    execute v_def;
  end if;
end $patch$;

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

  if v_def not like '%calories_kcal%' then
    v_def := replace(
      v_def,
      $needle$        INSERT INTO public.hyrox_session_exercises (
          session_id,
          exercise_code,
          exercise_order,
          distance_m,
          reps,
          weight_kg,
          duration_sec,
          height_cm,
          implement_count,
          notes
        )
        VALUES (
          v_session_id,
          NULLIF(rec->>'exercise_code', ''),
          COALESCE(NULLIF(rec->>'exercise_order', '')::int, 1),
          NULLIF(rec->>'distance_m', '')::int,
          NULLIF(rec->>'reps', '')::int,
          NULLIF(rec->>'weight_kg', '')::numeric,
          NULLIF(rec->>'duration_sec', '')::int,
          NULLIF(rec->>'height_cm', '')::int,
          NULLIF(rec->>'implement_count', '')::int,
          NULLIF(rec->>'notes', '')
        );$needle$,
      $needle$        INSERT INTO public.hyrox_session_exercises (
          session_id,
          exercise_code,
          exercise_order,
          distance_m,
          reps,
          weight_kg,
          duration_sec,
          height_cm,
          implement_count,
          calories_kcal,
          notes
        )
        VALUES (
          v_session_id,
          NULLIF(rec->>'exercise_code', ''),
          COALESCE(NULLIF(rec->>'exercise_order', '')::int, 1),
          NULLIF(rec->>'distance_m', '')::int,
          NULLIF(rec->>'reps', '')::int,
          NULLIF(rec->>'weight_kg', '')::numeric,
          NULLIF(rec->>'duration_sec', '')::int,
          NULLIF(rec->>'height_cm', '')::int,
          NULLIF(rec->>'implement_count', '')::int,
          NULLIF(rec->>'calories_kcal', '')::numeric,
          NULLIF(rec->>'notes', '')
        );$needle$
    );
    execute v_def;
  end if;
end $patch$;

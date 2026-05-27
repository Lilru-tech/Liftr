begin;

alter table public.exercise_sets
  add column if not exists is_completed boolean not null default false;

update public.exercise_sets
set is_completed = true
where is_completed = false;

create or replace function public._liftr_purge_incomplete_strength_workout(p_workout_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (
    select 1
    from public.workouts w
    where w.id = p_workout_id
      and lower(coalesce(w.kind::text, '')) = 'strength'
  ) then
    return;
  end if;

  delete from public.exercise_sets es
  using public.workout_exercises we
  where we.workout_id = p_workout_id
    and es.workout_exercise_id = we.id
    and coalesce(es.is_completed, false) = false;

  delete from public.workout_exercises we
  where we.workout_id = p_workout_id
    and not exists (
      select 1
      from public.exercise_sets es
      where es.workout_exercise_id = we.id
    );
end;
$function$;

create or replace function public._liftr_replace_strength_exercise_sets(
  p_workout_id bigint,
  p_exercises jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_item jsonb;
  v_set jsonb;
  v_we_id int;
  v_seg jsonb;
begin
  for v_item in
    select value
    from jsonb_array_elements(coalesce(p_exercises, '[]'::jsonb))
  loop
    v_we_id := (v_item->>'workout_exercise_id')::int;

    if not exists (
      select 1
      from public.workout_exercises we
      where we.id = v_we_id
        and we.workout_id = p_workout_id
    ) then
      raise exception 'invalid workout exercise % for workout %', v_we_id, p_workout_id;
    end if;

    delete from public.exercise_sets es
    where es.workout_exercise_id = v_we_id;

    for v_set in
      select value
      from jsonb_array_elements(coalesce(v_item->'sets', '[]'::jsonb))
    loop
      v_seg := case
        when v_set ? 'weight_segments'
          and jsonb_typeof(v_set->'weight_segments') = 'array'
          and jsonb_array_length(v_set->'weight_segments') >= 2
        then v_set->'weight_segments'
        else null::jsonb
      end;

      insert into public.exercise_sets (
        workout_exercise_id,
        set_number,
        reps,
        weight_kg,
        rpe,
        rest_sec,
        weight_segments,
        is_completed
      )
      values (
        v_we_id,
        greatest(coalesce((v_set->>'set_number')::int, 1), 1),
        case
          when v_set ? 'reps' and v_set->'reps' is not null and jsonb_typeof(v_set->'reps') = 'number'
            then (v_set->>'reps')::int
          else null
        end,
        case
          when v_set ? 'weight_kg' and v_set->'weight_kg' is not null and jsonb_typeof(v_set->'weight_kg') = 'number'
            then (v_set->>'weight_kg')::numeric
          else null
        end,
        case
          when v_set ? 'rpe' and v_set->'rpe' is not null and jsonb_typeof(v_set->'rpe') = 'number'
            then (v_set->>'rpe')::numeric
          else null
        end,
        case
          when v_set ? 'rest_sec' and v_set->'rest_sec' is not null and jsonb_typeof(v_set->'rest_sec') = 'number'
            then (v_set->>'rest_sec')::int
          else null
        end,
        v_seg,
        true
      );
    end loop;
  end loop;
end;
$function$;

create or replace function public._liftr_finish_strength_workout_core(
  p_workout_id bigint,
  p_ended_at timestamptz,
  p_paused_sec integer,
  p_exercises jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.workouts%rowtype;
  v_end timestamptz;
  v_state public.workout_state;
begin
  v_row := public._liftr_assert_strength_workout_finish_access(p_workout_id);

  if lower(coalesce(v_row.kind::text, '')) <> 'strength' then
    raise exception 'workout % is not strength', p_workout_id;
  end if;

  perform set_config('liftr.bulk_strength_replace', 'on', true);
  begin
    perform public._liftr_replace_strength_exercise_sets(p_workout_id, p_exercises);
    perform set_config('liftr.bulk_strength_replace', 'off', true);
  exception
    when others then
      perform set_config('liftr.bulk_strength_replace', 'off', true);
      raise;
  end;

  perform public._liftr_purge_incomplete_strength_workout(p_workout_id);

  v_end := coalesce(p_ended_at, timezone('utc', now()));
  if v_row.started_at is not null and v_end < v_row.started_at then
    v_end := v_row.started_at;
  end if;

  v_state := v_row.state;
  if v_state = 'planned'::public.workout_state then
    v_state := 'published'::public.workout_state;
  end if;

  update public.workouts
  set ended_at = v_end,
      paused_sec = greatest(coalesce(p_paused_sec, 0), 0),
      state = v_state
  where id = p_workout_id;

  perform public.upsert_workout_score_v2(p_workout_id::int);

  return public._liftr_strength_workout_save_result(p_workout_id);
end;
$function$;

create or replace function public.trg_purge_incomplete_strength_on_workout_finalize()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if lower(coalesce(NEW.kind::text, '')) = 'strength'
     and NEW.ended_at is not null
     and OLD.ended_at is null
  then
    perform public._liftr_purge_incomplete_strength_workout(NEW.id);
  end if;
  return NEW;
end;
$function$;

drop trigger if exists purge_incomplete_strength_on_workout_finalize on public.workouts;
create trigger purge_incomplete_strength_on_workout_finalize
  before update of ended_at on public.workouts
  for each row
  execute function public.trg_purge_incomplete_strength_on_workout_finalize();

commit;

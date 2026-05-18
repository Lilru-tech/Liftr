begin;

create or replace function public.update_strength_workout_v1(
  p_workout_id bigint,
  p_title text,
  p_notes text,
  p_started_at timestamp with time zone,
  p_ended_at timestamp with time zone default null,
  p_perceived_intensity text default null,
  p_exercises jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.workouts%rowtype;
  v_item jsonb;
  v_we_id int;
  v_exercise_id bigint;
begin
  select * into strict v_row
  from public.workouts
  where id = p_workout_id
  for update;

  if v_row.user_id is distinct from auth.uid() then
    raise exception 'forbidden';
  end if;

  if lower(coalesce(v_row.kind::text, '')) <> 'strength' then
    raise exception 'workout % is not strength', p_workout_id;
  end if;

  update public.workouts
  set title = nullif(btrim(coalesce(p_title, '')), ''),
      notes = nullif(btrim(coalesce(p_notes, '')), ''),
      started_at = p_started_at,
      ended_at = p_ended_at,
      perceived_intensity = nullif(btrim(coalesce(p_perceived_intensity, '')), '')::public.intensity
  where id = p_workout_id;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(p_exercises, '[]'::jsonb))
  loop
    v_we_id := (v_item->>'workout_exercise_id')::int;
    v_exercise_id := (v_item->>'exercise_id')::bigint;

    if not exists (
      select 1
      from public.workout_exercises we
      where we.id = v_we_id
        and we.workout_id = p_workout_id
    ) then
      raise exception 'invalid workout exercise % for workout %', v_we_id, p_workout_id;
    end if;

    update public.workout_exercises
    set exercise_id = v_exercise_id,
        order_index = coalesce(nullif(v_item->>'order_index', '')::int, order_index),
        notes = nullif(btrim(coalesce(v_item->>'notes', '')), ''),
        custom_name = nullif(btrim(coalesce(v_item->>'custom_name', '')), '')
    where id = v_we_id;
  end loop;

  perform set_config('liftr.bulk_strength_replace', 'on', true);
  begin
    perform public._liftr_replace_strength_exercise_sets(p_workout_id, p_exercises);
    perform set_config('liftr.bulk_strength_replace', 'off', true);
  exception
    when others then
      perform set_config('liftr.bulk_strength_replace', 'off', true);
      raise;
  end;

  perform public.upsert_workout_score_v2(p_workout_id::int);

  return public._liftr_strength_workout_save_result(p_workout_id);
end;
$function$;

commit;

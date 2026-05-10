begin;

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

commit;


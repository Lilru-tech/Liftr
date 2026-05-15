begin;

create or replace function public._liftr_bulk_strength_replace_active()
returns boolean
language sql
stable
set search_path to 'public'
as $function$
  select coalesce(nullif(current_setting('liftr.bulk_strength_replace', true), ''), 'off') = 'on';
$function$;

create or replace function public.trg_exercise_sets_recalc()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_wid int;
begin
  if public._liftr_bulk_strength_replace_active() then
    return null;
  end if;

  if tg_op = 'DELETE' then
    select workout_id into v_wid
    from public.workout_exercises
    where id = old.workout_exercise_id;
  else
    select workout_id into v_wid
    from public.workout_exercises
    where id = new.workout_exercise_id;
  end if;

  if v_wid is not null then
    perform public.upsert_workout_score_v2(v_wid);
    insert into public.score_recalc_audit(source, workout_id, extra)
    values ('trigger:exercise_sets_recalc', v_wid, null);
  end if;

  return null;
end;
$function$;

create or replace function public.trg_rescore_from_set()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_we_id bigint;
  v_wid bigint;
begin
  if public._liftr_bulk_strength_replace_active() then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    v_we_id := old.workout_exercise_id;
  else
    v_we_id := new.workout_exercise_id;
  end if;

  select we.workout_id into v_wid
  from public.workout_exercises we
  where we.id = v_we_id;

  if v_wid is not null then
    perform public.upsert_workout_score_v2(v_wid);
    insert into public.score_recalc_audit(source, workout_id, extra)
    values ('trigger:exercise_sets', v_wid, null);
  end if;

  return coalesce(new, old);
end;
$function$;

create or replace function public._liftr_strength_workout_save_result(p_workout_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.workouts%rowtype;
  v_score numeric;
begin
  select * into strict v_row
  from public.workouts
  where id = p_workout_id;

  select ws.score into v_score
  from public.workout_scores ws
  where ws.workout_id = p_workout_id
    and ws.algorithm = 'strength_v2'
  order by ws.calculated_at desc nulls last, ws.id desc
  limit 1;

  return jsonb_build_object(
    'workout_id', v_row.id,
    'user_id', v_row.user_id,
    'kind', v_row.kind::text,
    'title', v_row.title,
    'started_at', v_row.started_at,
    'ended_at', v_row.ended_at,
    'state', v_row.state::text,
    'score', v_score
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
        weight_segments
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
        v_seg
      );
    end loop;
  end loop;
end;
$function$;

create or replace function public._liftr_assert_strength_workout_finish_access(p_workout_id bigint)
returns public.workouts
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row public.workouts%rowtype;
begin
  select * into strict v_row
  from public.workouts
  where id = p_workout_id
  for update;

  if v_row.user_id = auth.uid() then
    return v_row;
  end if;

  if v_row.dual_host_user_id is not distinct from auth.uid() then
    if exists (
      select 1
      from public.workouts host_w
      where host_w.id = v_row.dual_linked_workout_id
        and host_w.user_id = auth.uid()
    ) then
      return v_row;
    end if;
    raise exception 'forbidden_guest';
  end if;

  raise exception 'forbidden';
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

create or replace function public.finish_strength_workout_v1(
  p_workout_id bigint,
  p_ended_at timestamp with time zone,
  p_paused_sec integer default 0,
  p_exercises jsonb default '[]'::jsonb,
  p_linked jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_out jsonb := '[]'::jsonb;
  v_link jsonb;
  v_link_workout_id bigint;
begin
  v_out := v_out || jsonb_build_array(
    public._liftr_finish_strength_workout_core(
      p_workout_id,
      p_ended_at,
      p_paused_sec,
      p_exercises
    )
  );

  for v_link in
    select value
    from jsonb_array_elements(coalesce(p_linked, '[]'::jsonb))
  loop
    v_link_workout_id := (v_link->>'workout_id')::bigint;
    v_out := v_out || jsonb_build_array(
      public._liftr_finish_strength_workout_core(
        v_link_workout_id,
        p_ended_at,
        p_paused_sec,
        coalesce(v_link->'exercises', '[]'::jsonb)
      )
    );
  end loop;

  return v_out;
end;
$function$;

grant execute on function public.update_strength_workout_v1(
  bigint,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  text,
  jsonb
) to authenticated;

grant execute on function public.finish_strength_workout_v1(
  bigint,
  timestamp with time zone,
  integer,
  jsonb,
  jsonb
) to authenticated;

commit;

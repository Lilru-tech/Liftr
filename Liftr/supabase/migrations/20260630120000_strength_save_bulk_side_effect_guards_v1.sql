begin;

create or replace function public._liftr_rebuild_strength_prs_for_exercises(
  p_user_id uuid,
  p_exercise_ids bigint[]
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
  v_exercise_ids bigint[];
begin
  v_exercise_ids := coalesce(p_exercise_ids, array[]::bigint[]);
  if coalesce(array_length(v_exercise_ids, 1), 0) = 0 then
    return;
  end if;

  delete from public.personal_records
  where user_id = p_user_id
    and exercise_id = any(v_exercise_ids)
    and metric in ('max_weight_kg', 'max_reps', 'best_set_volume_kg', 'est_1rm_kg');

  for r in
    select
      we.exercise_id,
      w.started_at as achieved_at,
      (seg.elem->>'reps')::int as reps,
      (seg.elem->>'weight_kg')::numeric as weight_kg,
      (coalesce((seg.elem->>'reps')::int, 0)::numeric
        * coalesce((seg.elem->>'weight_kg')::numeric, 0)) as volume,
      (case
        when (seg.elem->>'reps')::int is not null
         and (seg.elem->>'weight_kg')::numeric is not null
         and (seg.elem->>'reps')::int > 0
         and (seg.elem->>'weight_kg')::numeric > 0
        then (seg.elem->>'weight_kg')::numeric * (1 + (seg.elem->>'reps')::numeric / 30)
      end) as est1rm
    from public.exercise_sets es
    join public.workout_exercises we on we.id = es.workout_exercise_id
    join public.workouts w on w.id = we.workout_id
    cross join lateral (
      select jsonb_array_elements(
        public.strength_set_segments_expand(es.reps, es.weight_kg, es.weight_segments)
      ) as elem
    ) seg
    where w.user_id = p_user_id
      and we.exercise_id = any(v_exercise_ids)
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

create or replace function public._liftr_finalize_strength_bulk_side_effects(
  p_workout_id bigint,
  p_user_id uuid,
  p_exercises jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_exercise_ids bigint[];
begin
  select coalesce(
    array_agg(distinct (value->>'exercise_id')::bigint)
      filter (where nullif(value->>'exercise_id', '') is not null),
    array[]::bigint[]
  )
  into v_exercise_ids
  from jsonb_array_elements(coalesce(p_exercises, '[]'::jsonb));

  perform public._liftr_rebuild_strength_prs_for_exercises(p_user_id, v_exercise_ids);
  perform public.check_and_unlock_achievements_for(p_user_id);
end;
$function$;

create or replace function public.trg_strength_pr_from_set()
returns trigger
language plpgsql
set search_path to 'public'
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
  if public._liftr_bulk_strength_replace_active() then
    return new;
  end if;

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

create or replace function public.check_and_unlock_achievements()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user  uuid;
  v_owner uuid;
  v_we_id bigint;
  v_wid   bigint;
begin
  if tg_table_name = 'exercise_sets'
     and public._liftr_bulk_strength_replace_active()
  then
    return coalesce(new, old);
  end if;

  if tg_table_name = 'exercise_sets' then
    v_we_id := coalesce(new.workout_exercise_id, old.workout_exercise_id);
    select w.user_id
      into v_user
      from public.workout_exercises we
      join public.workouts w on w.id = we.workout_id
     where we.id = v_we_id;

    if v_user is not null then
      perform public.check_and_unlock_achievements_for(v_user);
    end if;
    return coalesce(new, old);
  end if;

  if tg_table_name in ('cardio_sessions', 'sport_sessions') then
    v_wid := coalesce(new.workout_id, old.workout_id);
    select w.user_id into v_user from public.workouts w where w.id = v_wid;
    if v_user is not null then
      perform public.check_and_unlock_achievements_for(v_user);
    end if;
    return coalesce(new, old);
  end if;

  if tg_table_name = 'workouts' then
    v_user := coalesce(new.user_id, old.user_id);
    if v_user is not null then
      perform public.check_and_unlock_achievements_for(v_user);
    end if;
    return coalesce(new, old);
  end if;

  if tg_table_name = 'workout_likes' then
    v_user := coalesce(new.user_id, old.user_id);
    v_wid := coalesce(new.workout_id, old.workout_id);
    select w.user_id into v_owner from public.workouts w where w.id = v_wid;

    if v_user is not null then perform public.check_and_unlock_achievements_for(v_user); end if;
    if v_owner is not null then perform public.check_and_unlock_achievements_for(v_owner); end if;
    return coalesce(new, old);
  end if;

  if tg_table_name = 'workout_comment_likes' then
    v_user := coalesce(new.user_id, old.user_id);
    select wc.user_id
      into v_owner
      from public.workout_comments wc
     where wc.id = coalesce(new.comment_id, old.comment_id);

    if v_user is not null then perform public.check_and_unlock_achievements_for(v_user); end if;
    if v_owner is not null then perform public.check_and_unlock_achievements_for(v_owner); end if;
    return coalesce(new, old);
  end if;

  if tg_table_name = 'workout_comments' then
    v_user := coalesce(new.user_id, old.user_id);
    select w.user_id
      into v_owner
      from public.workouts w
     where w.id = coalesce(new.workout_id, old.workout_id);

    if v_user is not null then perform public.check_and_unlock_achievements_for(v_user); end if;
    if v_owner is not null then perform public.check_and_unlock_achievements_for(v_owner); end if;
    return coalesce(new, old);
  end if;

  if tg_table_name = 'follows' then
    if tg_op = 'INSERT' then
      if new.follower_id is not null then perform public.check_and_unlock_achievements_for(new.follower_id); end if;
      if new.followee_id is not null then perform public.check_and_unlock_achievements_for(new.followee_id); end if;
    else
      if old.follower_id is not null then perform public.check_and_unlock_achievements_for(old.follower_id); end if;
      if old.followee_id is not null then perform public.check_and_unlock_achievements_for(old.followee_id); end if;
    end if;
    return coalesce(new, old);
  end if;

  begin
    v_user := coalesce(new.user_id, old.user_id);
  exception
    when others then
      v_user := null;
  end;
  if v_user is not null then
    perform public.check_and_unlock_achievements_for(v_user);
  end if;

  return coalesce(new, old);
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
  perform set_config('statement_timeout', '30s', true);

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

  perform public._liftr_finalize_strength_bulk_side_effects(p_workout_id, v_row.user_id, p_exercises);

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
  v_finalize boolean;
  v_state public.workout_state;
begin
  perform set_config('statement_timeout', '30s', true);

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

  v_finalize := p_ended_at is not null and v_row.ended_at is null;

  perform set_config('liftr.strength_edit_save', 'on', true);
  begin
    update public.workouts
    set title = nullif(btrim(coalesce(p_title, '')), ''),
        notes = nullif(btrim(coalesce(p_notes, '')), ''),
        started_at = p_started_at,
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

    perform public._liftr_finalize_strength_bulk_side_effects(p_workout_id, v_row.user_id, p_exercises);

    if v_finalize then
      perform public._liftr_purge_incomplete_strength_workout(p_workout_id);
      v_state := v_row.state;
      if v_state = 'planned'::public.workout_state then
        v_state := 'published'::public.workout_state;
      end if;
      update public.workouts
      set ended_at = p_ended_at,
          state = v_state
      where id = p_workout_id;
    elsif p_ended_at is distinct from v_row.ended_at then
      update public.workouts
      set ended_at = p_ended_at
      where id = p_workout_id;
    end if;

    perform public.upsert_workout_score_v2(p_workout_id::int);
    perform set_config('liftr.strength_edit_save', 'off', true);
  exception
    when others then
      perform set_config('liftr.strength_edit_save', 'off', true);
      raise;
  end;

  return public._liftr_strength_workout_save_result(p_workout_id);
end;
$function$;

commit;

create table if not exists public.territory_capture_takeovers (
  workout_id bigint not null references public.workouts (id) on delete cascade,
  victim_user_id uuid not null references auth.users (id) on delete cascade,
  taker_user_id uuid not null references auth.users (id) on delete cascade,
  cells_taken integer not null,
  victim_total_before integer not null,
  share_taken_pct numeric(5, 1) not null,
  created_at timestamptz not null default now(),
  primary key (workout_id, victim_user_id)
);

create index if not exists territory_capture_takeovers_victim_idx
  on public.territory_capture_takeovers (victim_user_id, created_at desc);

create index if not exists territory_capture_takeovers_taker_idx
  on public.territory_capture_takeovers (taker_user_id, created_at desc);

alter table public.territory_capture_takeovers enable row level security;

drop policy if exists territory_capture_takeovers_select on public.territory_capture_takeovers;
create policy territory_capture_takeovers_select
  on public.territory_capture_takeovers
  for select
  to authenticated
  using (true);

alter table public.user_notification_settings
  add column if not exists push_territory_capture_from_user boolean not null default true,
  add column if not exists push_territory_lost_to_user boolean not null default true;

create or replace function public._liftr_apply_territory_capture_for_workout (
  p_workout_id bigint,
  p_emit_notifications boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  w_user uuid;
  w_captured_at timestamptz;
  activity_code text;
  route_text text;
  route_geog geography;
  capture_geog geography;
  route_kind text;
  cells_gained integer := 0;
  cells_taken integer := 0;
  min_lat double precision;
  min_lon double precision;
  max_lat double precision;
  max_lon double precision;
  existing_event record;
  duration_sec integer;
  max_speed_mps double precision;
  takeover_row record;
  taker_username text;
  victim_username text;
begin
  select
    e.*
  into existing_event
  from public.territory_capture_events e
  where e.workout_id = p_workout_id;

  if found then
    return public._liftr_territory_capture_summary_json(
      existing_event.route_kind,
      existing_event.cells_gained,
      existing_event.cells_taken,
      existing_event.bbox_min_lat,
      existing_event.bbox_min_lon,
      existing_event.bbox_max_lat,
      existing_event.bbox_max_lon,
      true
    );
  end if;

  select
    w.user_id,
    coalesce(w.ended_at, w.started_at, now())
  into w_user, w_captured_at
  from public.workouts w
  where w.id = p_workout_id;

  if w_user is null then
    raise exception 'workout_not_found';
  end if;

  select
    coalesce(nullif(trim(cs.activity_code), ''), nullif(trim(cs.modality), ''), '')
  into activity_code
  from public.cardio_sessions cs
  where cs.workout_id = p_workout_id
  order by cs.id nulls last
  limit 1;

  if not public._liftr_territory_outdoor_activity(activity_code) then
    return jsonb_build_object('ok', false, 'reason', 'activity_not_eligible');
  end if;

  route_text := public._liftr_workout_route_geojson_text(p_workout_id);
  route_geog := public._liftr_territory_route_geog_from_geojson(route_text);
  if route_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'missing_route');
  end if;

  if st_length(route_geog) < 500.0 then
    return jsonb_build_object('ok', false, 'reason', 'route_too_short');
  end if;

  select
    coalesce(cs.duration_sec, 0)
  into duration_sec
  from public.cardio_sessions cs
  where cs.workout_id = p_workout_id
  order by cs.id nulls last
  limit 1;

  if duration_sec > 0 then
    max_speed_mps := st_length(route_geog) / duration_sec::double precision;
    if max_speed_mps > 25.0 then
      return jsonb_build_object('ok', false, 'reason', 'speed_unrealistic');
    end if;
  end if;

  capture_geog := public._liftr_territory_capture_geom(route_geog);
  if capture_geog is null then
    return jsonb_build_object('ok', false, 'reason', 'capture_geom_failed');
  end if;

  route_kind := public._liftr_territory_route_kind(route_geog);

  create temp table _liftr_capture_cells on commit drop as
  select
    c.cell_id,
    c.cell_geog
  from public._liftr_territory_hex_cells_from_geog(capture_geog) c;

  select
    count(*)::integer
  into cells_gained
  from _liftr_capture_cells;

  if cells_gained = 0 then
    return jsonb_build_object('ok', false, 'reason', 'no_cells');
  end if;

  select
    count(*)::integer
  into cells_taken
  from _liftr_capture_cells nc
    join public.territory_cells tc on tc.cell_id = nc.cell_id
  where tc.owner_user_id <> w_user;

  create temp table _liftr_victim_takeover on commit drop as
  select
    tc.owner_user_id as victim_user_id,
    count(*)::integer as cells_taken_from_victim,
    (
      select count(*)::integer
      from public.territory_cells all_cells
      where all_cells.owner_user_id = tc.owner_user_id
    ) as victim_total_before
  from _liftr_capture_cells nc
    join public.territory_cells tc on tc.cell_id = nc.cell_id
  where tc.owner_user_id <> w_user
  group by tc.owner_user_id;

  select
    min(st_ymin(nc.cell_geog::geometry)),
    min(st_xmin(nc.cell_geog::geometry)),
    max(st_ymax(nc.cell_geog::geometry)),
    max(st_xmax(nc.cell_geog::geometry))
  into min_lat, min_lon, max_lat, max_lon
  from _liftr_capture_cells nc;

  insert into public.territory_cells (
    cell_id,
    cell_geog,
    owner_user_id,
    captured_at,
    last_workout_id,
    last_activity_code
  )
  select
    nc.cell_id,
    nc.cell_geog,
    w_user,
    w_captured_at,
    p_workout_id,
    activity_code
  from _liftr_capture_cells nc
  on conflict (cell_id) do update
    set
      owner_user_id = excluded.owner_user_id,
      captured_at = excluded.captured_at,
      last_workout_id = excluded.last_workout_id,
      last_activity_code = excluded.last_activity_code;

  insert into public.territory_capture_events (
    workout_id,
    user_id,
    route_kind,
    cells_gained,
    cells_taken,
    bbox_min_lat,
    bbox_min_lon,
    bbox_max_lat,
    bbox_max_lon,
    applied_at
  )
  values (
    p_workout_id,
    w_user,
    route_kind,
    cells_gained,
    cells_taken,
    min_lat,
    min_lon,
    max_lat,
    max_lon,
    w_captured_at
  );

  insert into public.territory_capture_takeovers (
    workout_id,
    victim_user_id,
    taker_user_id,
    cells_taken,
    victim_total_before,
    share_taken_pct
  )
  select
    p_workout_id,
    vt.victim_user_id,
    w_user,
    vt.cells_taken_from_victim,
    vt.victim_total_before,
    round(100.0 * vt.cells_taken_from_victim::numeric / greatest(vt.victim_total_before, 1), 1)
  from _liftr_victim_takeover vt
  on conflict (workout_id, victim_user_id) do nothing;

  if p_emit_notifications then
    select coalesce(p.username, 'Someone')
    into taker_username
    from public.profiles p
    where p.user_id = w_user;

    for takeover_row in
      select
        vt.victim_user_id,
        vt.cells_taken_from_victim,
        vt.victim_total_before,
        round(100.0 * vt.cells_taken_from_victim::numeric / greatest(vt.victim_total_before, 1), 1) as share_taken_pct
      from _liftr_victim_takeover vt
    loop
      select coalesce(p.username, 'Someone')
      into victim_username
      from public.profiles p
      where p.user_id = takeover_row.victim_user_id;

      insert into public.notifications (user_id, type, title, body, data)
      values (
        w_user,
        'territory_capture_from_user',
        'Territory captured',
        format('You took %s%% of @%s''s territory', takeover_row.share_taken_pct, victim_username),
        jsonb_build_object(
          'workout_id', p_workout_id,
          'other_user_id', takeover_row.victim_user_id,
          'cells_taken', takeover_row.cells_taken_from_victim,
          'share_taken_pct', takeover_row.share_taken_pct,
          'bbox_min_lat', min_lat,
          'bbox_min_lon', min_lon,
          'bbox_max_lat', max_lat,
          'bbox_max_lon', max_lon
        )
      );

      insert into public.notifications (user_id, type, title, body, data)
      values (
        takeover_row.victim_user_id,
        'territory_lost_to_user',
        'Territory lost',
        format('@%s took %s%% of your territory', taker_username, takeover_row.share_taken_pct),
        jsonb_build_object(
          'workout_id', p_workout_id,
          'other_user_id', w_user,
          'cells_taken', takeover_row.cells_taken_from_victim,
          'share_taken_pct', takeover_row.share_taken_pct,
          'bbox_min_lat', min_lat,
          'bbox_min_lon', min_lon,
          'bbox_max_lat', max_lat,
          'bbox_max_lon', max_lon
        )
      );
    end loop;
  end if;

  return public._liftr_territory_capture_summary_json(
    route_kind,
    cells_gained,
    cells_taken,
    min_lat,
    min_lon,
    max_lat,
    max_lon,
    false
  );
end;
$$;

create or replace function public.apply_territory_capture_v1 (p_workout_id bigint)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  w_user uuid;
begin
  if auth.uid () is null then
    raise exception 'not_authenticated';
  end if;

  select
    w.user_id
  into w_user
  from public.workouts w
  where w.id = p_workout_id;

  if w_user is null then
    raise exception 'workout_not_found';
  end if;

  if w_user <> auth.uid () then
    raise exception 'not_owner';
  end if;

  return public._liftr_apply_territory_capture_for_workout(p_workout_id, true);
end;
$$;

create or replace function public._liftr_backfill_territory_captures_global_batch (p_limit integer default 5)
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  workout_row record;
  processed integer := 0;
begin
  for workout_row in
    select
      w.id
    from public.workouts w
    where
      lower(coalesce(w.kind::text, '')) = 'cardio'
      and w.ended_at is not null
      and public._liftr_workout_route_geojson_text(w.id) is not null
      and not exists (
        select 1
        from public.territory_capture_events e
        where e.workout_id = w.id
      )
    order by coalesce(w.ended_at, w.started_at), w.id
    limit greatest(least(coalesce(p_limit, 5), 25), 1)
  loop
    begin
      perform public._liftr_apply_territory_capture_for_workout(workout_row.id, false);
      processed := processed + 1;
    exception
      when others then
        null;
    end;
  end loop;

  return processed;
end;
$$;

create or replace function public.backfill_my_territory_captures_v1 (p_limit integer default 5)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  workout_row record;
  processed integer := 0;
  cells_gained_total integer := 0;
  cells_taken_total integer := 0;
  apply_result jsonb;
  has_more boolean := false;
begin
  if auth.uid () is null then
    raise exception 'not_authenticated';
  end if;

  for workout_row in
    select
      w.id
    from public.workouts w
    where
      w.user_id = auth.uid ()
      and lower(coalesce(w.kind::text, '')) = 'cardio'
      and w.ended_at is not null
      and public._liftr_workout_route_geojson_text(w.id) is not null
      and not exists (
        select 1
        from public.territory_capture_events e
        where e.workout_id = w.id
      )
    order by coalesce(w.ended_at, w.started_at), w.id
    limit greatest(least(coalesce(p_limit, 5), 25), 1)
  loop
    begin
      apply_result := public._liftr_apply_territory_capture_for_workout(workout_row.id, false);
      processed := processed + 1;
      if coalesce((apply_result ->> 'ok')::boolean, false) then
        cells_gained_total := cells_gained_total + coalesce((apply_result ->> 'cells_gained')::integer, 0);
        cells_taken_total := cells_taken_total + coalesce((apply_result ->> 'cells_taken')::integer, 0);
      end if;
    exception
      when others then
        null;
    end;
  end loop;

  select
    exists (
      select 1
      from public.workouts w
      where
        w.user_id = auth.uid ()
        and lower(coalesce(w.kind::text, '')) = 'cardio'
        and w.ended_at is not null
        and public._liftr_workout_route_geojson_text(w.id) is not null
        and not exists (
          select 1
          from public.territory_capture_events e
          where e.workout_id = w.id
        )
    )
  into has_more;

  return jsonb_build_object(
    'ok', true,
    'processed', processed,
    'cells_gained', cells_gained_total,
    'cells_taken', cells_taken_total,
    'has_more', has_more
  );
end;
$$;

create or replace function public.get_territory_share_leaderboard_v1 (
  p_scope text,
  p_limit integer default 100
)
returns table (
  rank integer,
  user_id uuid,
  username text,
  avatar_url text,
  owned_cells integer,
  territory_share_pct numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  return query
  with global_total as (
    select count(*)::numeric as total_cells
    from public.territory_cells
  ),
  owned as (
    select
      tc.owner_user_id as uid,
      count(*)::integer as owned_cells
    from public.territory_cells tc
    group by tc.owner_user_id
  ),
  scoped as (
    select
      o.uid,
      o.owned_cells,
      gt.total_cells
    from owned o
    cross join global_total gt
    inner join public.profiles pr on pr.user_id = o.uid
    where
      coalesce(p_scope, 'global') = 'global'
      or pr.user_id = auth.uid()
      or exists (
        select 1
        from public.follows f
        where f.follower_id = auth.uid()
          and f.followee_id = pr.user_id
      )
  ),
  ordered as (
    select
      s.uid,
      s.owned_cells,
      round(100.0 * s.owned_cells::numeric / greatest(s.total_cells, 1), 2) as territory_share_pct,
      row_number() over (
        order by s.owned_cells desc, s.uid
      ) as rnk
    from scoped s
  )
  select
    o.rnk::integer as rank,
    o.uid as user_id,
    pr.username,
    pr.avatar_url,
    o.owned_cells,
    o.territory_share_pct
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  order by o.rnk
  limit greatest(least(coalesce(p_limit, 100), 200), 1);
end;
$$;

grant execute on function public.get_territory_share_leaderboard_v1 (text, integer) to authenticated;

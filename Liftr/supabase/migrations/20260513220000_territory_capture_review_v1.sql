comment on table public.territory_city_regions is
  'Deprecated grid-era city metadata. Prefer territory_municipalities and pending geocode buckets.';

create or replace function public._liftr_territory_push_enabled (
  p_user_id uuid,
  p_kind text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public
as $$
  select coalesce(
    (
      select case p_kind
        when 'territory_capture_from_user' then uns.push_territory_capture_from_user
        when 'territory_lost_to_user' then uns.push_territory_lost_to_user
        else true
      end
      from public.user_notification_settings uns
      where uns.user_id = p_user_id
    ),
    true
  );
$$;

create or replace function public._liftr_emit_territory_takeover_notifications (
  p_workout_id bigint,
  p_taker_user_id uuid,
  p_bbox_min_lat double precision,
  p_bbox_min_lon double precision,
  p_bbox_max_lat double precision,
  p_bbox_max_lon double precision
)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  takeover_row record;
  taker_username text;
  victim_username text;
begin
  select coalesce(p.username, 'Someone')
  into taker_username
  from public.profiles p
  where p.user_id = p_taker_user_id;

  for takeover_row in
    select
      t.victim_user_id,
      t.cells_taken,
      t.victim_total_before,
      t.share_taken_pct
    from public.territory_capture_takeovers t
    where t.workout_id = p_workout_id
  loop
    select coalesce(p.username, 'Someone')
    into victim_username
    from public.profiles p
    where p.user_id = takeover_row.victim_user_id;

    if public._liftr_territory_push_enabled(p_taker_user_id, 'territory_capture_from_user') then
      insert into public.notifications (user_id, type, title, body, data)
      values (
        p_taker_user_id,
        'territory_capture_from_user',
        'Territory captured',
        format('You took %s%% of @%s''s territory', takeover_row.share_taken_pct, victim_username),
        jsonb_build_object(
          'workout_id', p_workout_id,
          'other_user_id', takeover_row.victim_user_id,
          'cells_taken', takeover_row.cells_taken,
          'share_taken_pct', takeover_row.share_taken_pct,
          'bbox_min_lat', p_bbox_min_lat,
          'bbox_min_lon', p_bbox_min_lon,
          'bbox_max_lat', p_bbox_max_lat,
          'bbox_max_lon', p_bbox_max_lon
        )
      );
    end if;

    if public._liftr_territory_push_enabled(takeover_row.victim_user_id, 'territory_lost_to_user') then
      insert into public.notifications (user_id, type, title, body, data)
      values (
        takeover_row.victim_user_id,
        'territory_lost_to_user',
        'Territory lost',
        format('@%s took %s%% of your territory', taker_username, takeover_row.share_taken_pct),
        jsonb_build_object(
          'workout_id', p_workout_id,
          'other_user_id', p_taker_user_id,
          'cells_taken', takeover_row.cells_taken,
          'share_taken_pct', takeover_row.share_taken_pct,
          'bbox_min_lat', p_bbox_min_lat,
          'bbox_min_lon', p_bbox_min_lon,
          'bbox_max_lat', p_bbox_max_lat,
          'bbox_max_lon', p_bbox_max_lon
        )
      );
    end if;
  end loop;
end;
$$;

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
    last_activity_code,
    city_key
  )
  select
    nc.cell_id,
    nc.cell_geog,
    w_user,
    w_captured_at,
    p_workout_id,
    activity_code,
    public._liftr_territory_city_key_for_point(
      st_y(st_centroid(nc.cell_geog::geometry)),
      st_x(st_centroid(nc.cell_geog::geometry))
    )
  from _liftr_capture_cells nc
  on conflict (cell_id) do update
    set
      owner_user_id = excluded.owner_user_id,
      captured_at = excluded.captured_at,
      last_workout_id = excluded.last_workout_id,
      last_activity_code = excluded.last_activity_code,
      city_key = excluded.city_key;

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
    perform public._liftr_emit_territory_takeover_notifications(
      p_workout_id,
      w_user,
      min_lat,
      min_lon,
      max_lat,
      max_lon
    );
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

create or replace function public.list_territory_geocode_queue_v1 (
  p_limit integer default 25
)
  returns table (
    bucket_lat numeric,
    bucket_lon numeric,
    sample_lat double precision,
    sample_lon double precision,
    attempts integer
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  select
    q.bucket_lat,
    q.bucket_lon,
    q.sample_lat,
    q.sample_lon,
    q.attempts
  from public.territory_city_geocode_queue q
    left join lateral (
      select count(*)::integer as unassigned_cells
      from public.territory_cells tc
        cross join lateral public._liftr_territory_city_geocode_bucket(
          st_y(st_centroid(tc.cell_geog::geometry)),
          st_x(st_centroid(tc.cell_geog::geometry))
        ) bucket
      where
        bucket.bucket_lat = q.bucket_lat
        and bucket.bucket_lon = q.bucket_lon
        and (
          tc.city_key is null
          or tc.city_key like 'grid:%'
        )
    ) stats on true
  where q.attempts < 8
  order by coalesce(stats.unassigned_cells, 0) desc, q.queued_at
  limit greatest(least(coalesce(p_limit, 25), 100), 1);
$$;

create or replace function public.mark_territory_geocode_queue_error_v1 (
  p_bucket_lat numeric,
  p_bucket_lon numeric,
  p_error text
)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  update public.territory_city_geocode_queue
  set
    attempts = attempts + 1,
    last_error = left(coalesce(p_error, 'unknown'), 500),
    updated_at = now()
  where
    bucket_lat = p_bucket_lat
    and bucket_lon = p_bucket_lon;

  delete from public.territory_city_geocode_queue
  where
    bucket_lat = p_bucket_lat
    and bucket_lon = p_bucket_lon
    and attempts >= 8;
end;
$$;

revoke execute on function public.backfill_territory_municipality_assignments_v1 (integer) from authenticated;
revoke execute on function public.get_territory_share_leaderboard_v1 (text, integer) from authenticated;

create index if not exists territory_cells_city_owner_idx
  on public.territory_cells (city_key, owner_user_id);

create index if not exists territory_cells_unassigned_idx
  on public.territory_cells (cell_id)
  where city_key is null or city_key like 'grid:%';

create index if not exists territory_cells_captured_at_idx
  on public.territory_cells (captured_at desc);

grant execute on function public._liftr_emit_territory_takeover_notifications (
  bigint,
  uuid,
  double precision,
  double precision,
  double precision,
  double precision
) to service_role;

create or replace function public.list_my_territory_recent_takeovers_v1 (
  p_limit integer default 5
)
  returns table (
    workout_id bigint,
    other_user_id uuid,
    other_username text,
    cells_taken integer,
    share_taken_pct numeric,
    created_at timestamptz
  )
  language sql
  stable
  security invoker
  set search_path = public
as $$
  select
    t.workout_id,
    t.victim_user_id,
    coalesce(p.username, 'user') as other_username,
    t.cells_taken,
    t.share_taken_pct,
    t.created_at
  from public.territory_capture_takeovers t
    join public.profiles p on p.user_id = t.victim_user_id
  where t.taker_user_id = auth.uid()
  order by t.created_at desc
  limit greatest(least(coalesce(p_limit, 5), 20), 1);
$$;

grant execute on function public.list_my_territory_recent_takeovers_v1 (integer) to authenticated;

select
  to_regclass('public.territory_cells') as territory_cells,
  to_regclass('public.territory_capture_events') as territory_capture_events,
  to_regclass('public.territory_capture_takeovers') as territory_capture_takeovers,
  to_regclass('public.territory_city_regions') as territory_city_regions,
  to_regclass('public.territory_municipalities') as territory_municipalities,
  to_regclass('public.territory_city_geocode_cache') as territory_city_geocode_cache,
  to_regclass('public.territory_city_geocode_queue') as territory_city_geocode_queue;

select
  p.proname
from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
where
  n.nspname = 'public'
  and p.proname in (
    'apply_territory_capture_v1',
    'preview_territory_capture_v1',
    'get_territory_map_v1',
    'get_my_territory_summary_v1',
    'get_territory_share_leaderboard_v1',
    'list_territory_city_regions_v1',
    'get_territory_city_share_leaderboard_v1',
    'backfill_my_territory_captures_v1',
    'backfill_territory_municipality_assignments_v1',
    'list_my_territory_recent_takeovers_v1',
    'list_workout_territory_takeovers_v1',
    'ingest_territory_municipality_v1',
    'list_territory_geocode_queue_v1',
    '_liftr_apply_territory_capture_for_workout',
    '_liftr_territory_city_key_for_point',
    '_liftr_territory_count_hex_cells_for_geog'
  )
order by p.proname;

select
  column_name
from information_schema.columns
where
  table_schema = 'public'
  and table_name = 'territory_cells'
  and column_name = 'city_key';

select
  column_name
from information_schema.columns
where
  table_schema = 'public'
  and table_name = 'territory_municipalities'
  and column_name in ('display_name', 'display_name_override', 'total_capture_cells')
order by column_name;

select
  column_name
from information_schema.columns
where
  table_schema = 'public'
  and table_name = 'user_notification_settings'
  and column_name in (
    'push_territory_capture_from_user',
    'push_territory_lost_to_user'
  )
order by column_name;

select
  public.preview_territory_capture_v1(
    '{"type":"LineString","coordinates":[[-3.7038,40.4168],[-3.7030,40.4172],[-3.7022,40.4168],[-3.7030,40.4164],[-3.7038,40.4168]]}'::text
  ) as closed_loop_preview;

select
  public.preview_territory_capture_v1(
    '{"type":"LineString","coordinates":[[-3.7038,40.4168],[-3.7010,40.4180],[-3.6980,40.4190]]}'::text
  ) as open_route_preview;

select
  public.preview_territory_capture_v1(
    '{"type":"LineString","coordinates":[[-3.7050,40.4150],[-3.7038,40.4168],[-3.7030,40.4172],[-3.7022,40.4168],[-3.7030,40.4164],[-3.7038,40.4168],[-3.7050,40.4150]]}'::text
  ) as loop_with_tail_preview;

select
  public._liftr_territory_route_kind(
    public._liftr_territory_route_geog_from_geojson(
      '{"type":"LineString","coordinates":[[-3.7050,40.4150],[-3.7038,40.4168],[-3.7030,40.4172],[-3.7022,40.4168],[-3.7030,40.4164],[-3.7038,40.4168],[-3.7050,40.4150]]}'
    )
  ) = 'closed' as loop_with_tail_is_closed;

select
  public._liftr_territory_polygonize_loop_faces(
    public._liftr_territory_route_geog_from_geojson(
      '{"type":"LineString","coordinates":[[-3.7050,40.4150],[-3.7038,40.4168],[-3.7030,40.4172],[-3.7022,40.4168],[-3.7030,40.4164],[-3.7038,40.4168],[-3.7050,40.4150]]}'
    )
  ) is not null as loop_with_tail_has_polygon_face;

select
  (
    select count(*)::integer
    from public._liftr_territory_hex_cells_from_geog(
      public._liftr_territory_capture_geom(
        public._liftr_territory_route_geog_from_geojson(
          '{"type":"LineString","coordinates":[[-3.710,40.410],[-3.700,40.420],[-3.690,40.420],[-3.690,40.410],[-3.700,40.410],[-3.710,40.410]]}'
        )
      )
    )
  ) > (
    select count(*)::integer
    from public._liftr_territory_hex_cells_from_geog(
      public._liftr_territory_capture_geom(
        public._liftr_territory_route_geog_from_geojson(
          '{"type":"LineString","coordinates":[[-3.710,40.410],[-3.650,40.410]]}'
        )
      )
    )
  ) as closed_loop_more_cells_than_open_line;

select
  round(public._liftr_territory_min_loop_area_m2()::numeric, 1) as min_loop_area_m2_one_hex;

select
  public._liftr_territory_route_kind(
    public._liftr_territory_route_geog_from_geojson(
      '{"type":"LineString","coordinates":[[-3.710,40.410],[-3.650,40.410],[-3.64964,40.410],[-3.64964,40.41036],[-3.6500,40.41036],[-3.6500,40.410]]}'
    )
  ) = 'closed' as small_loop_with_tail_is_closed;

select
  (
    select count(*)::integer
    from public._liftr_territory_hex_cells_from_geog(
      public._liftr_territory_capture_geom(
        public._liftr_territory_route_geog_from_geojson(
          '{"type":"LineString","coordinates":[[-3.710,40.410],[-3.650,40.410],[-3.64964,40.410],[-3.64964,40.41036],[-3.6500,40.41036],[-3.6500,40.410]]}'
        )
      )
    )
  ) > (
    select count(*)::integer
    from public._liftr_territory_hex_cells_from_geog(
      public._liftr_territory_capture_geom(
        public._liftr_territory_route_geog_from_geojson(
          '{"type":"LineString","coordinates":[[-3.710,40.410],[-3.650,40.410]]}'
        )
      )
    )
  ) as small_loop_with_tail_more_cells_than_line_only;

select
  public._liftr_territory_polygonize_loop_faces(
    public._liftr_territory_route_geog_from_geojson(
      '{"type":"LineString","coordinates":[[-3.7040,40.4160],[-3.7036,40.4160],[-3.7036,40.41636],[-3.7040,40.41636],[-3.7040,40.4160]]}'
    )
  ) is null as tiny_noise_loop_ignored;

select
  e.workout_id,
  e.route_kind,
  e.cells_gained,
  round(st_area(public._liftr_territory_capture_geom(
    public._liftr_territory_route_geog_from_geojson(
      public._liftr_workout_route_geojson_text(e.workout_id)
    )
  ))::numeric, 0) as capture_area_m2
from public.territory_capture_events e
where e.workout_id in (627, 773);

select
  m.city_key,
  public._liftr_territory_municipality_label(m.display_name, m.display_name_override) as display_name,
  count(tc.cell_id) as captured_cells,
  m.total_capture_cells,
  round(100.0 * count(tc.cell_id)::numeric / greatest(m.total_capture_cells, 1), 2) as captured_share_of_city_pct
from public.territory_municipalities m
  left join public.territory_cells tc on tc.city_key = m.city_key
group by m.city_key, m.display_name, m.display_name_override, m.total_capture_cells
order by captured_cells desc nulls last
limit 5;

select
  p.username,
  count(*) filter (where tc.city_key is null) as unassigned_cells,
  count(*) filter (where tc.city_key is not null) as assigned_cells,
  count(*) as owned_cells
from public.territory_cells tc
  join public.profiles p on p.user_id = tc.owner_user_id
where p.username = 'Lilru'
group by p.username;

select
  city_key,
  display_name,
  captured_cells,
  total_capture_cells,
  my_owned_cells
from public.list_territory_city_regions_v1(null, 200, true)
order by captured_cells desc, display_name
limit 20;

select
  count(*) filter (where city_key like 'pending:%') as pending_city_rows,
  coalesce(sum(captured_cells) filter (where city_key like 'pending:%'), 0) as pending_captured_cells
from public.list_territory_city_regions_v1(null, 200, true);

select
  count(*)::integer as geocode_queue_rows,
  count(*) filter (where last_error is not null)::integer as geocode_queue_rows_with_error
from public.territory_city_geocode_queue;

select
  bucket_lat,
  bucket_lon,
  attempts,
  last_error
from public.territory_city_geocode_queue
order by attempts desc, queued_at
limit 10;

select
  p.username,
  count(*) filter (where tc.city_key is null or tc.city_key like 'grid:%') as unassigned_or_grid_cells,
  count(*) filter (where tc.city_key like 'pending:%') as pending_key_cells,
  count(*) filter (where tc.city_key is not null and tc.city_key not like 'grid:%' and tc.city_key not like 'pending:%') as municipality_assigned_cells,
  count(*) as owned_cells
from public.territory_cells tc
  join public.profiles p on p.user_id = tc.owner_user_id
where p.username = 'Lilru'
group by p.username;

select
  has_function_privilege('authenticated', 'public.get_territory_share_leaderboard_v1(text, integer)', 'execute') as authenticated_can_call_legacy_share_rpc,
  has_function_privilege('authenticated', 'public.backfill_territory_municipality_assignments_v1(integer)', 'execute') as authenticated_can_call_assignment_backfill,
  has_function_privilege(
    'authenticated',
    'public.ingest_territory_municipality_v1(text,text,text,integer,text,double precision,double precision,double precision,double precision,double precision,double precision,text,text,numeric,numeric)',
    'execute'
  ) as authenticated_can_call_ingest_municipality,
  has_function_privilege(
    'authenticated',
    'public.assign_territory_cells_for_geocode_bucket_v1(numeric,numeric,text)',
    'execute'
  ) as authenticated_can_call_bucket_assign,
  has_function_privilege('service_role', 'public.backfill_territory_municipality_assignments_v1(integer)', 'execute') as service_role_can_call_assignment_backfill,
  has_function_privilege('authenticated', 'public._liftr_apply_territory_capture_for_workout(bigint)', 'execute') as authenticated_can_call_internal_apply_capture,
  has_function_privilege('authenticated', 'public.apply_territory_capture_v1(bigint)', 'execute') as authenticated_can_call_apply_capture;

select
  count(*)::integer as cardio_with_route_missing_capture_event
from public.workouts w
where
  lower(coalesce(w.kind::text, '')) = 'cardio'
  and w.ended_at is not null
  and public._liftr_workout_route_geojson_text(w.id) is not null
  and not exists (
    select 1
    from public.territory_capture_events e
    where e.workout_id = w.id
  );

select
  to_regprocedure('public.assign_territory_cells_for_geocode_bucket_v1(numeric,numeric,text)') is not null as has_bucket_assign_rpc;

select
  count(*)::integer as unassigned_cells,
  bucket.bucket_lat,
  bucket.bucket_lon
from public.territory_cells tc
  cross join lateral public._liftr_territory_city_geocode_bucket(
    st_y(st_centroid(tc.cell_geog::geometry)),
    st_x(st_centroid(tc.cell_geog::geometry))
  ) bucket
where
  (
    tc.city_key is null
    or tc.city_key like 'grid:%'
  )
  and bucket.bucket_lat in (36.27, 36.28, 36.29)
  and bucket.bucket_lon in (-6.10, -6.11)
group by bucket.bucket_lat, bucket.bucket_lon
order by unassigned_cells desc;

select
  public.backfill_territory_municipality_assignments_v1(1) as assignment_backfill_sample;

select
  to_regprocedure('public.list_territory_city_regions_v1(text,integer,boolean)') is not null as has_searchable_city_regions_rpc,
  to_regprocedure('public.get_territory_total_cells_leaderboard_v1(text,integer)') is not null as has_total_cells_leaderboard_rpc;

select
  city_key,
  display_name,
  my_owned_cells,
  captured_cells
from public.list_territory_city_regions_v1(null, 10, true)
order by my_owned_cells desc, captured_cells desc
limit 10;

select
  rank,
  username,
  owned_cells,
  territory_share_pct
from public.get_territory_total_cells_leaderboard_v1('global', 10);

select
  has_function_privilege('authenticated', 'public.list_territory_city_regions_v1(text,integer,boolean)', 'execute') as authenticated_can_search_city_regions,
  has_function_privilege('authenticated', 'public.get_territory_total_cells_leaderboard_v1(text,integer)', 'execute') as authenticated_can_call_total_cells_leaderboard;

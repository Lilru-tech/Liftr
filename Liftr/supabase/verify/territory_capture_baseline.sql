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
from public.list_territory_city_regions_v1()
order by captured_cells desc, display_name
limit 20;

select
  count(*) filter (where city_key like 'pending:%') as pending_city_rows,
  coalesce(sum(captured_cells) filter (where city_key like 'pending:%'), 0) as pending_captured_cells
from public.list_territory_city_regions_v1();

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
  has_function_privilege('authenticated', 'public.backfill_territory_municipality_assignments_v1(integer)', 'execute') as authenticated_can_call_assignment_backfill;

-- Run in Supabase SQL editor (or your migration tool) before the app persists routes.
-- Optional: add a check that the column exists after migration.

alter table public.cardio_sessions
  add column if not exists route_geojson text;

comment on column public.cardio_sessions.route_geojson is
  'GeoJSON LineString (WGS84 lon,lat) recorded during live GPS cardio; optional.';

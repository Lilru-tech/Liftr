revoke execute on function public.ingest_territory_municipality_v1 (
  text,
  text,
  text,
  integer,
  text,
  double precision,
  double precision,
  double precision,
  double precision,
  double precision,
  double precision,
  text,
  text,
  numeric,
  numeric
) from public, anon, authenticated;

revoke execute on function public.backfill_territory_municipality_assignments_v1 (integer) from public, anon, authenticated;

revoke execute on function public.assign_territory_cells_for_geocode_bucket_v1 (
  numeric,
  numeric,
  text
) from public, anon, authenticated;

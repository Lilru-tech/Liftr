with beceite_available as (
  select ceil(
    96897610.37 / (
      ((3 * sqrt(3) / 2) * power(25.0, 2))
      * power(cos(radians(40.8308335)), 2)
    )
  )::integer as total_cells
)
update public.territory_municipalities m
set
  center_lat = 40.8308335,
  center_lon = 0.1824413,
  total_capture_cells = greatest(coalesce(m.total_capture_cells, 0), beceite_available.total_cells),
  resolved_at = now(),
  updated_at = now()
from beceite_available
where m.city_key = 'osm:relation:339855'
  and coalesce(m.total_capture_cells, 0) < beceite_available.total_cells;

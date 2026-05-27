create or replace function public.merge_territory_municipality_keys_v1 (
  p_from_city_key text,
  p_to_city_key text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  moved_cells integer := 0;
begin
  if coalesce(trim(p_from_city_key), '') = '' or coalesce(trim(p_to_city_key), '') = '' then
    raise exception 'city_key_required';
  end if;

  if p_from_city_key = p_to_city_key then
    return jsonb_build_object('ok', true, 'moved_cells', 0, 'from_city_key', p_from_city_key, 'to_city_key', p_to_city_key);
  end if;

  update public.territory_cells
  set city_key = p_to_city_key
  where city_key = p_from_city_key;

  get diagnostics moved_cells = row_count;

  update public.territory_city_geocode_cache
  set city_key = p_to_city_key
  where city_key = p_from_city_key;

  delete from public.territory_municipalities
  where city_key = p_from_city_key;

  return jsonb_build_object(
    'ok', true,
    'moved_cells', moved_cells,
    'from_city_key', p_from_city_key,
    'to_city_key', p_to_city_key
  );
end;
$$;

revoke all on function public.merge_territory_municipality_keys_v1 (text, text) from public, anon;
grant execute on function public.merge_territory_municipality_keys_v1 (text, text) to service_role;

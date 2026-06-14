do $$
begin
  if exists (
    select 1 from pg_tables
    where schemaname = 'public' and tablename = 'spatial_ref_sys'
  ) then
    execute 'revoke all on table public.spatial_ref_sys from anon, authenticated';
    execute 'revoke all on table public.spatial_ref_sys from public';
  end if;
end
$$;

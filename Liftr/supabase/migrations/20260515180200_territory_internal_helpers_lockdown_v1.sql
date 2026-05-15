do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as proc
    from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (
        p.proname ~ '^_liftr_.*territory'
        or p.proname = '_liftr_enqueue_territory_geocode_point'
      )
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated',
      r.proc
    );
  end loop;
end;
$$;

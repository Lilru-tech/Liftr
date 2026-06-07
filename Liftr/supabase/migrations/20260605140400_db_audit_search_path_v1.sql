do $$
declare
  fn record;
begin
  for fn in
    select
      n.nspname as schema_name,
      p.proname as func_name,
      pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
      and p.proname not like 'st\_%' escape '\'
      and p.proname not like '\_st\_%' escape '\'
      and p.proname not like '\_postgis\_%' escape '\'
      and (
        p.proconfig is null
        or not exists (
          select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%'
        )
      )
  loop
    begin
      execute format(
        'alter function %I.%I(%s) set search_path = public, extensions',
        fn.schema_name,
        fn.func_name,
        fn.args
      );
    exception
      when insufficient_privilege then
        null;
    end;
  end loop;
end
$$;

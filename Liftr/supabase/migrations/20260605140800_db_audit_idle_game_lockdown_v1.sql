do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'idle_game') then
    revoke usage on schema idle_game from anon, authenticated;
    revoke all on all tables in schema idle_game from anon, authenticated;
    revoke all on all sequences in schema idle_game from anon, authenticated;
    revoke execute on all functions in schema idle_game from anon, authenticated;
  end if;
end
$$;

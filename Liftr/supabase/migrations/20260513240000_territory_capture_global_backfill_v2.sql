do $$
declare
  batch_processed integer := 1;
  total_processed integer := 0;
begin
  while batch_processed > 0 and total_processed < 10000 loop
    select public._liftr_backfill_territory_captures_global_batch(25)
    into batch_processed;
    total_processed := total_processed + batch_processed;
  end loop;
end;
$$;

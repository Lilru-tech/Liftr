do $$
declare
  pol record;
  new_qual text;
  new_check text;
begin
  for pol in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where (schemaname = 'idle_game')
       or (schemaname = 'public' and tablename in (
         'user_favorite_nutrition_ingredients',
         'user_favorite_nutrition_recipes'
       ))
       or (schemaname = 'realtime' and tablename = 'messages' and policyname = 'messages_participants_all')
  loop
    if pol.qual is not null and pol.qual like '%auth.uid()%' and pol.qual not like '%(select auth.uid())%' then
      new_qual := replace(pol.qual, 'auth.uid()', '(select auth.uid())');
      execute format(
        'alter policy %I on %I.%I using (%s)',
        pol.policyname, pol.schemaname, pol.tablename, new_qual
      );
    end if;

    if pol.with_check is not null and pol.with_check like '%auth.uid()%' and pol.with_check not like '%(select auth.uid())%' then
      new_check := replace(pol.with_check, 'auth.uid()', '(select auth.uid())');
      execute format(
        'alter policy %I on %I.%I with check (%s)',
        pol.policyname, pol.schemaname, pol.tablename, new_check
      );
    end if;
  end loop;
end
$$;

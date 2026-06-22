drop policy if exists avatar_public_read on storage.objects;

create policy avatar_public_read on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'avatars'
    and name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[0-9]+\.jpg$'
  );

drop policy if exists avatar_uploads on storage.objects;

create policy avatar_uploads on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and name ~* ('^' || (select auth.uid())::text || '-[0-9]+\.jpg$')
  );

drop policy if exists avatar_update_own on storage.objects;

create policy avatar_update_own on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and owner = (select auth.uid())
    and name ~* ('^' || (select auth.uid())::text || '-[0-9]+\.jpg$')
  )
  with check (
    bucket_id = 'avatars'
    and owner = (select auth.uid())
    and name ~* ('^' || (select auth.uid())::text || '-[0-9]+\.jpg$')
  );

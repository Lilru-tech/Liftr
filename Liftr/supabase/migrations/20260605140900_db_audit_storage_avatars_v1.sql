drop policy if exists avatar_public_read on storage.objects;

create policy avatar_public_read on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'avatars'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[0-9]+\.jpg$'
  );

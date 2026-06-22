begin;

drop trigger if exists "First workout email to d.g.sanc@gmail.com" on public.workouts;

create trigger "First workout email to d.g.sanc@gmail.com"
  after insert or update on public.workouts
  for each row
  execute function supabase_functions.http_request(
    'https://rjzhaafvkxmvlnpsikbi.supabase.co/functions/v1/notify-first-workout',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '5000'
  );

commit;

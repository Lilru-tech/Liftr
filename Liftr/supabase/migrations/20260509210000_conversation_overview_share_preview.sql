set local check_function_bodies = off;

create or replace function public.get_conversations_overview(
  p_limit  integer default 50,
  p_offset integer default 0
)
returns table (
  id                   bigint,
  kind                 text,
  title                text,
  updated_at           timestamptz,
  last_message_id      bigint,
  last_message_user_id uuid,
  last_message_body    text,
  last_message_at      timestamptz,
  unread_count         integer
)
language sql
stable
set search_path = public
as $$
  with my_convs as (
    select c.*,
           p.cleared_at_message_id as my_cleared_id
    from public.conversations c
    join public.conversation_participants p on p.conversation_id = c.id
    where p.user_id = auth.uid()
  ),
  lm as (
    select distinct on (m.conversation_id)
      m.conversation_id,
      m.id         as last_message_id,
      m.user_id    as last_message_user_id,
      left(
        case
          when nullif(
            trim(both from regexp_replace(coalesce(m.body, ''), E'[\\r\\n\\s]+', ' ', 'g')),
            ''
          ) is not null then
            trim(both from regexp_replace(coalesce(m.body, ''), E'[\\r\\n\\s]+', ' ', 'g'))
          when m.kind = 'image' then 'Sent an image'
          when m.kind = 'file' then 'Sent a file'
          when m.kind = 'workout_share' then
            coalesce(nullif(trim(both from m.metadata->>'title'), ''), 'Sent a workout')
          when m.kind = 'routine_share' then
            coalesce(nullif(trim(both from m.metadata->>'name'), ''), 'Sent a routine')
          when m.kind = 'achievement_share' then
            coalesce(nullif(trim(both from m.metadata->>'title'), ''), 'Sent an achievement')
          when m.kind = 'segment_share' then
            coalesce(nullif(trim(both from m.metadata->>'name'), ''), 'Sent a segment')
          when m.kind = 'system' then 'System message'
          else coalesce(nullif(trim(both from m.body), ''), 'Message')
        end,
        200
      ) as last_message_body,
      m.created_at as last_message_at
    from public.messages m
    join my_convs c on c.id = m.conversation_id
    where m.id > coalesce(c.my_cleared_id, 0)
    order by m.conversation_id, m.id desc
  ),
  cr as (
    select conversation_id, last_read_message_id
    from public.conversation_reads
    where user_id = auth.uid()
  )
  select
    c.id, c.kind, c.title, c.updated_at,
    lm.last_message_id, lm.last_message_user_id, lm.last_message_body, lm.last_message_at,
    coalesce((
      select count(*)::int
      from public.messages m
      where m.conversation_id = c.id
        and m.id > coalesce(cr.last_read_message_id, 0)
        and m.id > coalesce(c.my_cleared_id, 0)
        and m.user_id <> auth.uid()
    ), 0) as unread_count
  from my_convs c
  left join lm on lm.conversation_id = c.id
  left join cr on cr.conversation_id = c.id
  where c.my_cleared_id is null or lm.last_message_id is not null
  order by coalesce(lm.last_message_at, c.updated_at) desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0)
$$;

revoke all on function public.get_conversations_overview(integer, integer) from public;
grant execute on function public.get_conversations_overview(integer, integer)
  to authenticated, service_role;

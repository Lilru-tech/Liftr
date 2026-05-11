-- ============================================================================
-- Chat advanced v1
--
-- Builds on top of 20260509140000_chat_realtime_v1 to add the typical chat
-- features: reply-to, message reactions (set of 6 emojis), per-user "clear
-- conversation" cursor (WhatsApp-style: hides until a new message arrives),
-- mute toggle RPC, edit/delete RPCs, and a "Seen" indicator (peer's last
-- read becomes visible to other participants).
--
-- Idempotent: safe to re-run.
-- ============================================================================

set local check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1) Schema additions
-- ---------------------------------------------------------------------------

-- Reply-to: nullable self-FK on messages. on delete set null so that a deleted
-- target keeps the reply visible (with a "deleted" preview).
alter table public.messages
  add column if not exists reply_to_message_id bigint
    references public.messages(id) on delete set null;

create index if not exists idx_messages_reply_to_message_id
  on public.messages(reply_to_message_id)
  where reply_to_message_id is not null;

-- Per-participant cursor: messages with id <= cleared_at_message_id are hidden
-- for this user. NULL means "never cleared".
alter table public.conversation_participants
  add column if not exists cleared_at_message_id bigint;

-- Reactions table. Composite PK = (message_id, user_id, emoji), so a single
-- user can pile multiple distinct emojis on the same message but cannot stack
-- the same emoji twice.
create table if not exists public.message_reactions (
  message_id bigint not null references public.messages(id) on delete cascade,
  user_id    uuid   not null references auth.users(id)      on delete cascade,
  emoji      text   not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji),
  constraint message_reactions_emoji_check check (
    emoji in ('heart', 'haha', 'wow', 'sad', 'thumbs_up', 'thumbs_down')
  )
);

create index if not exists idx_message_reactions_message_id
  on public.message_reactions(message_id);

alter table public.message_reactions enable row level security;
alter table public.message_reactions replica identity full;

-- ---------------------------------------------------------------------------
-- 2) RLS for message_reactions
-- ---------------------------------------------------------------------------

drop policy if exists "msg_reactions_select_member" on public.message_reactions;
create policy "msg_reactions_select_member"
  on public.message_reactions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.messages m
      where m.id = message_reactions.message_id
        and public.is_conversation_member(m.conversation_id)
    )
  );

drop policy if exists "msg_reactions_insert_self" on public.message_reactions;
create policy "msg_reactions_insert_self"
  on public.message_reactions
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.messages m
      where m.id = message_reactions.message_id
        and public.is_conversation_member(m.conversation_id)
    )
  );

drop policy if exists "msg_reactions_delete_self" on public.message_reactions;
create policy "msg_reactions_delete_self"
  on public.message_reactions
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- 3) "Seen" indicator: relax conv_reads SELECT to fellow members so a
--    participant can read the peer's last_read_message_id. INSERT/UPDATE
--    remain self-only and were already correct in the previous migration.
-- ---------------------------------------------------------------------------

drop policy if exists "conv_reads_select_self"   on public.conversation_reads;
drop policy if exists "conv_reads_select_member" on public.conversation_reads;
create policy "conv_reads_select_member"
  on public.conversation_reads
  for select
  to authenticated
  using (public.is_conversation_member(conversation_id));

-- ---------------------------------------------------------------------------
-- 4) Recreate get_messages: include reply_to_message_id in output and apply
--    the per-user cleared cursor.
-- ---------------------------------------------------------------------------

drop function if exists public.get_messages(bigint, bigint, integer);

create or replace function public.get_messages(
  p_conversation_id  bigint,
  p_cursor_before_id bigint default null,
  p_limit            integer default 50
)
returns table (
  id                  bigint,
  user_id             uuid,
  kind                text,
  body                text,
  metadata            jsonb,
  reply_to_message_id bigint,
  created_at          timestamptz,
  edited_at           timestamptz,
  deleted_at          timestamptz
)
language sql
stable
set search_path = public
as $$
  with cleared as (
    select coalesce(cp.cleared_at_message_id, 0) as min_id
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id
      and cp.user_id = auth.uid()
  )
  select
    m.id, m.user_id, m.kind, m.body, m.metadata,
    m.reply_to_message_id,
    m.created_at, m.edited_at, m.deleted_at
  from public.messages m
  where m.conversation_id = p_conversation_id
    and (p_cursor_before_id is null or m.id < p_cursor_before_id)
    and m.id > coalesce((select min_id from cleared), 0)
  order by m.id desc
  limit greatest(p_limit, 1)
$$;

revoke all on function public.get_messages(bigint, bigint, integer) from public;
grant execute on function public.get_messages(bigint, bigint, integer)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) Recreate get_conversations_overview: hide rows that the user has
--    cleared until a brand-new message (id > cleared_at_message_id) arrives.
--    Same return shape as before.
-- ---------------------------------------------------------------------------

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
      m.body       as last_message_body,
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
  -- A conv shows up if either:
  --   * the user has never cleared it (my_cleared_id is null), or
  --   * there's at least one message after the clear cursor.
  where c.my_cleared_id is null or lm.last_message_id is not null
  order by coalesce(lm.last_message_at, c.updated_at) desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0)
$$;

revoke all on function public.get_conversations_overview(integer, integer) from public;
grant execute on function public.get_conversations_overview(integer, integer)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) Recreate send_message with optional p_reply_to_message_id.
-- ---------------------------------------------------------------------------

drop function if exists public.send_message(bigint, text, text, jsonb, uuid);
drop function if exists public.send_message(bigint, text, text, jsonb, uuid, bigint);

create or replace function public.send_message(
  p_conversation_id     bigint,
  p_kind                text   default 'text',
  p_body                text   default null,
  p_metadata            jsonb  default '{}'::jsonb,
  p_client_msg_id       uuid   default null,
  p_reply_to_message_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id
      and user_id         = v_me
  ) then
    raise exception 'NOT_A_PARTICIPANT';
  end if;

  if p_reply_to_message_id is not null
     and not exists (
       select 1 from public.messages
       where id              = p_reply_to_message_id
         and conversation_id = p_conversation_id
     )
  then
    raise exception 'INVALID_REPLY_TARGET';
  end if;

  -- Idempotency on client_msg_id (mirrors the previous behavior).
  if p_client_msg_id is not null then
    select id into v_id
      from public.messages
     where conversation_id = p_conversation_id
       and client_msg_id   = p_client_msg_id;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  insert into public.messages(
    conversation_id, user_id, kind, body, metadata, client_msg_id,
    reply_to_message_id
  )
  values (
    p_conversation_id, v_me, p_kind, p_body, p_metadata, p_client_msg_id,
    p_reply_to_message_id
  )
  returning id into v_id;

  return v_id;
end
$$;

revoke all on function public.send_message(bigint, text, text, jsonb, uuid, bigint) from public;
grant execute on function public.send_message(bigint, text, text, jsonb, uuid, bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7) clear_conversation(p_conversation_id): set my cursor to current max id.
-- ---------------------------------------------------------------------------

create or replace function public.clear_conversation(p_conversation_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me     uuid   := auth.uid();
  v_max_id bigint;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if not public.is_conversation_member(p_conversation_id) then
    raise exception 'NOT_A_PARTICIPANT';
  end if;

  select coalesce(max(id), 0)
    into v_max_id
  from public.messages
  where conversation_id = p_conversation_id;

  update public.conversation_participants
     set cleared_at_message_id = v_max_id
   where conversation_id = p_conversation_id
     and user_id         = v_me;
end
$$;

revoke all on function public.clear_conversation(bigint) from public;
grant execute on function public.clear_conversation(bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8) set_conversation_muted(p_conversation_id, p_muted): toggle the mute
--    flag on conversation_participants for the current user. The existing
--    notify trigger already filters cp.muted = false.
-- ---------------------------------------------------------------------------

create or replace function public.set_conversation_muted(
  p_conversation_id bigint,
  p_muted           boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  update public.conversation_participants
     set muted = coalesce(p_muted, false)
   where conversation_id = p_conversation_id
     and user_id         = v_me;

  if not found then
    raise exception 'NOT_A_PARTICIPANT';
  end if;
end
$$;

revoke all on function public.set_conversation_muted(bigint, boolean) from public;
grant execute on function public.set_conversation_muted(bigint, boolean)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9) toggle_message_reaction(p_message_id, p_emoji) — returns true if a
--    reaction was added, false if it was removed (toggle semantics).
-- ---------------------------------------------------------------------------

create or replace function public.toggle_message_reaction(
  p_message_id bigint,
  p_emoji      text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me      uuid   := auth.uid();
  v_conv_id bigint;
  v_deleted int;
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_emoji not in ('heart', 'haha', 'wow', 'sad', 'thumbs_up', 'thumbs_down') then
    raise exception 'INVALID_EMOJI';
  end if;

  select m.conversation_id
    into v_conv_id
  from public.messages m
  where m.id = p_message_id;

  if v_conv_id is null then
    raise exception 'MESSAGE_NOT_FOUND';
  end if;

  if not public.is_conversation_member(v_conv_id) then
    raise exception 'NOT_A_PARTICIPANT';
  end if;

  delete from public.message_reactions
   where message_id = p_message_id
     and user_id    = v_me
     and emoji      = p_emoji;
  get diagnostics v_deleted = row_count;

  if v_deleted > 0 then
    return false;
  end if;

  insert into public.message_reactions(message_id, user_id, emoji)
  values (p_message_id, v_me, p_emoji);

  return true;
end
$$;

revoke all on function public.toggle_message_reaction(bigint, text) from public;
grant execute on function public.toggle_message_reaction(bigint, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10) edit_message(p_message_id, p_body): only own, non-deleted, text
--     messages within 24h. Sets edited_at and lets the broadcast UPDATE
--     trigger propagate the change to subscribers.
-- ---------------------------------------------------------------------------

create or replace function public.edit_message(
  p_message_id bigint,
  p_body       text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_body is null or length(btrim(p_body)) = 0 then
    raise exception 'EMPTY_BODY';
  end if;

  update public.messages
     set body      = p_body,
         edited_at = now()
   where id         = p_message_id
     and user_id    = v_me
     and deleted_at is null
     and kind       = 'text'
     and created_at > now() - interval '24 hours';

  if not found then
    raise exception 'CANNOT_EDIT';
  end if;
end
$$;

revoke all on function public.edit_message(bigint, text) from public;
grant execute on function public.edit_message(bigint, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 11) delete_message(p_message_id): soft delete (sets deleted_at, blanks
--     body for privacy). Author-only.
-- ---------------------------------------------------------------------------

create or replace function public.delete_message(p_message_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  update public.messages
     set deleted_at = now(),
         body       = null
   where id         = p_message_id
     and user_id    = v_me
     and deleted_at is null;

  if not found then
    raise exception 'CANNOT_DELETE';
  end if;
end
$$;

revoke all on function public.delete_message(bigint) from public;
grant execute on function public.delete_message(bigint)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 12) Realtime broadcast for message_reactions on topic
--     "conversation:<conv_id>:reactions". The function joins to messages to
--     resolve conversation_id (since reactions don't carry it).
-- ---------------------------------------------------------------------------

create or replace function public.message_reactions_broadcast_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_msg_id  bigint := coalesce(new.message_id, old.message_id);
  v_conv_id bigint;
begin
  select m.conversation_id
    into v_conv_id
  from public.messages m
  where m.id = v_msg_id;

  if v_conv_id is not null then
    perform realtime.broadcast_changes(
      'conversation:' || v_conv_id::text || ':reactions',
      tg_op,
      tg_op,
      tg_table_name,
      tg_table_schema,
      new,
      old
    );
  end if;
  return coalesce(new, old);
end
$$;

drop trigger if exists message_reactions_broadcast_changes on public.message_reactions;
create trigger message_reactions_broadcast_changes
  after insert or update or delete on public.message_reactions
  for each row
  execute function public.message_reactions_broadcast_trigger();

-- The trigger function is internal-only; revoke EXECUTE so it cannot be
-- invoked via /rest/v1/rpc (Supabase advisor warning).
revoke execute on function public.message_reactions_broadcast_trigger() from public;
revoke execute on function public.message_reactions_broadcast_trigger() from authenticated;
revoke execute on function public.message_reactions_broadcast_trigger() from anon;

-- ---------------------------------------------------------------------------
-- 13) Notes on existing trg_messages_after_insert_notify.
--
-- The notify trigger already filters `cp.muted = false`, so set_conversation
-- _muted plugs into push delivery automatically. The broadcast goes through
-- regardless of mute (mute only affects push). reply_to_message_id is
-- intentionally NOT exposed in the notification payload: a reply still
-- produces a single dm_message and the body preview already conveys
-- enough context.
-- ---------------------------------------------------------------------------

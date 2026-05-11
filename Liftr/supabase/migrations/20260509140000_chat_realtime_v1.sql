-- ============================================================================
-- Chat realtime v1
-- Fixes RLS bug on chat tables, restricts DMs to mutual followers, wires the
-- realtime broadcast trigger on messages, and produces a `dm_message`
-- notification per recipient so the existing send-notifications edge function
-- delivers the push.
--
-- Idempotent: safe to re-run.
-- ============================================================================

set local check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1) Fix RLS policies on chat tables.
--
-- Several existing policies compare `me.conversation_id = me.conversation_id`
-- (alias to itself), which is always true, effectively granting access to
-- every authenticated user. Drop the broken policies and replace them with
-- correct ones that join through the target row's conversation_id.
--
-- We use is_conversation_member(conv_id) (already defined as STABLE
-- SECURITY DEFINER) inside the policy bodies to avoid recursive RLS lookups
-- against conversation_participants itself.
-- ---------------------------------------------------------------------------

-- public.messages
drop policy if exists "messages_select_participant" on public.messages;
drop policy if exists "messages_select_participants" on public.messages;
drop policy if exists "messages_insert_participant" on public.messages;
drop policy if exists "messages_update_own" on public.messages;
drop policy if exists "messages_delete_own" on public.messages;

create policy "messages_select_participant"
  on public.messages
  for select
  to authenticated
  using (public.is_conversation_member(conversation_id));

create policy "messages_insert_participant"
  on public.messages
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_conversation_member(conversation_id)
  );

create policy "messages_update_own"
  on public.messages
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "messages_delete_own"
  on public.messages
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

-- public.conversation_participants
drop policy if exists "conv_part_select_self" on public.conversation_participants;
drop policy if exists "cp_self_select" on public.conversation_participants;
drop policy if exists "conv_part_insert_owner_or_self" on public.conversation_participants;
drop policy if exists "conv_part_delete_owner_or_self" on public.conversation_participants;
drop policy if exists "conv_part_select_member" on public.conversation_participants;

-- A participant can see other participants of the same conversation (so the
-- client can render avatars / titles for groups in future iterations).
create policy "conv_part_select_member"
  on public.conversation_participants
  for select
  to authenticated
  using (public.is_conversation_member(conversation_id));

-- INSERT: row inserted with user_id = me, OR I am owner/admin of the conv.
create policy "conv_part_insert_owner_or_self"
  on public.conversation_participants
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    or exists (
      select 1
      from public.conversation_participants me
      where me.conversation_id = conversation_participants.conversation_id
        and me.user_id = (select auth.uid())
        and me.role in ('owner', 'admin')
    )
  );

-- DELETE: I can leave (delete my own row), or I am owner/admin and I'm
-- removing somebody else.
create policy "conv_part_delete_owner_or_self"
  on public.conversation_participants
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1
      from public.conversation_participants me
      where me.conversation_id = conversation_participants.conversation_id
        and me.user_id = (select auth.uid())
        and me.role in ('owner', 'admin')
    )
  );

-- public.conversation_reads
drop policy if exists "conv_reads_select_participant" on public.conversation_reads;
drop policy if exists "conv_reads_upsert_self" on public.conversation_reads;
drop policy if exists "conv_reads_update_self" on public.conversation_reads;

create policy "conv_reads_select_self"
  on public.conversation_reads
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "conv_reads_upsert_self"
  on public.conversation_reads
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_conversation_member(conversation_id)
  );

create policy "conv_reads_update_self"
  on public.conversation_reads
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- public.message_attachments (already correct, but harden idempotently).
drop policy if exists "msg_att_select_participant" on public.message_attachments;
create policy "msg_att_select_participant"
  on public.message_attachments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.messages m
      where m.id = message_attachments.message_id
        and public.is_conversation_member(m.conversation_id)
    )
  );

-- public.conversations
drop policy if exists "conversations_select_participant" on public.conversations;
drop policy if exists "conversations_insert_self" on public.conversations;
drop policy if exists "conversations_update_admin" on public.conversations;

create policy "conversations_select_participant"
  on public.conversations
  for select
  to authenticated
  using (public.is_conversation_member(id));

create policy "conversations_insert_self"
  on public.conversations
  for insert
  to authenticated
  with check (created_by = (select auth.uid()));

create policy "conversations_update_admin"
  on public.conversations
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.conversation_participants p
      where p.conversation_id = conversations.id
        and p.user_id = (select auth.uid())
        and p.role in ('owner', 'admin')
    )
  );

-- ---------------------------------------------------------------------------
-- 2) Mutual-follow helper + restrict start_direct_conversation.
-- ---------------------------------------------------------------------------

create or replace function public.are_mutual_followers(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from public.follows
      where follower_id = a and followee_id = b
    )
    and exists (
      select 1 from public.follows
      where follower_id = b and followee_id = a
    );
$$;

revoke all on function public.are_mutual_followers(uuid, uuid) from public;
grant execute on function public.are_mutual_followers(uuid, uuid)
  to authenticated, service_role;

create or replace function public.start_direct_conversation(p_other uuid)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv_id bigint;
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if p_other = v_me then
    raise exception 'CANNOT_DM_SELF';
  end if;

  if not public.are_mutual_followers(v_me, p_other) then
    raise exception 'NOT_MUTUAL_FOLLOW';
  end if;

  select c.id
    into v_conv_id
  from public.conversations c
  join public.conversation_participants p1
    on p1.conversation_id = c.id and p1.user_id = v_me
  join public.conversation_participants p2
    on p2.conversation_id = c.id and p2.user_id = p_other
  where c.kind = 'direct'
  limit 1;

  if v_conv_id is not null then
    return v_conv_id;
  end if;

  insert into public.conversations(kind, created_by)
  values ('direct', v_me)
  returning id into v_conv_id;

  insert into public.conversation_participants(conversation_id, user_id, role)
  values
    (v_conv_id, v_me, 'owner'),
    (v_conv_id, p_other, 'member');

  return v_conv_id;
end
$$;

revoke all on function public.start_direct_conversation(uuid) from public;
grant execute on function public.start_direct_conversation(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Realtime broadcast trigger on messages.
--
-- The broadcast helper function already exists; we just need to bind it to
-- public.messages so clients can subscribe to the
-- "conversation:<id>:messages" topic without the noise of the CDC publication.
-- Drop any prior binding with the same name first so we are idempotent.
-- ---------------------------------------------------------------------------

drop trigger if exists messages_broadcast_changes on public.messages;
create trigger messages_broadcast_changes
  after insert or update or delete on public.messages
  for each row
  execute function public.conversation_messages_broadcast_trigger();

-- ---------------------------------------------------------------------------
-- 4) Push notifications: fan out a `dm_message` notification per recipient.
--
-- The send-notifications edge function polls `public.notifications` rows
-- with sent_at IS NULL and posts to FCM. Inserting one row per recipient
-- (excluding the sender) plugs DMs into that pipeline transparently.
-- ---------------------------------------------------------------------------

create or replace function public.trg_messages_after_insert_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_username text;
  v_preview text;
  v_title text;
begin
  -- System messages don't notify; deleted-on-arrival messages don't either.
  if new.kind = 'system' or new.deleted_at is not null then
    return new;
  end if;

  select coalesce(p.username, 'Someone')
    into v_sender_username
  from public.profiles p
  where p.user_id = new.user_id;

  v_title := coalesce(v_sender_username, 'New message');

  v_preview := case
    when new.kind = 'image' then 'Sent an image'
    when new.kind = 'file'  then 'Sent a file'
    else
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'New message'
      )
  end;

  insert into public.notifications (user_id, type, title, body, data)
  select
    cp.user_id,
    'dm_message',
    v_title,
    v_preview,
    jsonb_build_object(
      'conversation_id', new.conversation_id,
      'message_id',      new.id,
      'sender_id',       new.user_id,
      'sender_username', coalesce(v_sender_username, '')
    )
  from public.conversation_participants cp
  where cp.conversation_id = new.conversation_id
    and cp.user_id <> new.user_id
    and cp.muted = false;

  return new;
end
$$;

drop trigger if exists messages_ai_notify on public.messages;
create trigger messages_ai_notify
  after insert on public.messages
  for each row
  execute function public.trg_messages_after_insert_notify();

-- ---------------------------------------------------------------------------
-- 5) Add conversation_participants to the realtime publication so clients
--    detect new conversations live (e.g. when the other side starts the DM).
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_participants'
  ) then
    execute 'alter publication supabase_realtime add table public.conversation_participants';
  end if;
end
$$;

-- Ensure replica identity is sufficient for realtime payloads on new tables.
alter table public.conversation_participants replica identity full;
alter table public.conversation_reads replica identity full;

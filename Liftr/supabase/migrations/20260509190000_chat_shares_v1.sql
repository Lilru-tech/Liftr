-- ============================================================================
-- Chat shares v1
-- Adds push-notification previews for the new "share" message kinds:
--   workout_share, routine_share, achievement_share, segment_share
--
-- Storage shape: re-uses public.messages.kind + public.messages.metadata; no
-- schema, RLS, send_message or broadcast trigger changes are needed. The only
-- functional change here is to extend trg_messages_after_insert_notify so the
-- recipient's push title/body looks sensible even if `body` (caption) is empty.
--
-- Idempotent: safe to re-run.
-- ============================================================================

set local check_function_bodies = off;

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

  -- Body preview falls back to a per-kind canned label when the caption is
  -- empty. The text-content branch keeps the previous regexp behavior.
  v_preview := case
    when new.kind = 'image' then 'Sent an image'
    when new.kind = 'file'  then 'Sent a file'
    when new.kind = 'workout_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent a workout'
      )
    when new.kind = 'routine_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent a routine'
      )
    when new.kind = 'achievement_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent an achievement'
      )
    when new.kind = 'segment_share' then
      coalesce(
        nullif(left(regexp_replace(coalesce(new.body, ''), E'[\\r\\n\\s]+', ' ', 'g'), 140), ''),
        'Sent a segment'
      )
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

-- Re-attach is implicit: function replacement keeps the trigger binding
-- (messages_ai_notify) intact.

-- ---------------------------------------------------------------------------
-- Reference: expected metadata shape for `workout_share` (other types follow
-- the same convention with their own ids/fields).
--
-- {
--   "v": 1,
--   "type": "workout_share",
--   "workout_id": <bigint>,
--   "title": "...",
--   "kind": "strength|cardio|sport",
--   "score": <int>,
--   "kcal": <int>,
--   "performed_at": "<iso>",
--   "owner_user_id": "<uuid>",
--   "owner_username": "...",
--   "owner_avatar_url": "..."
-- }
-- ---------------------------------------------------------------------------

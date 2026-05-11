-- ============================================================================
-- messages.kind: allow share variants (workout_share, routine_share,
-- achievement_share, segment_share) alongside existing kinds.
--
-- Idempotent: safe to re-run.
-- ============================================================================

alter table public.messages
  drop constraint if exists messages_kind_check;

alter table public.messages
  add constraint messages_kind_check
  check (
    kind in (
      'text',
      'image',
      'file',
      'system',
      'workout_share',
      'routine_share',
      'achievement_share',
      'segment_share'
    )
  );

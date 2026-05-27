-- ============================================================================
-- Hotfix: allow nutrition share kinds in messages.kind
--
-- This migration is intentionally small so environments that haven't yet run
-- the full nutrition privacy + chat share migration can still send these kinds.
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
      'segment_share',
      'shared_ingredient',
      'shared_recipe'
    )
  );

notify pgrst, 'reload schema';


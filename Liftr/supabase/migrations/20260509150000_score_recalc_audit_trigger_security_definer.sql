-- After 20260509130000_security_advisor_error_fixes_v1, public.score_recalc_audit has
-- RLS + REVOKE ALL for anon/authenticated (internal audit table).
-- trg_exercise_sets_recalc and recompute_strength_score still ran as SECURITY INVOKER
-- and INSERT into score_recalc_audit, causing "permission denied" on routine/workout saves.
-- Align with other scoring triggers (already SECURITY DEFINER) so audit rows run as owner.

alter function public.trg_exercise_sets_recalc()
  security definer
  set search_path to 'pg_catalog', 'public';

alter function public.recompute_strength_score(integer)
  security definer
  set search_path to 'pg_catalog', 'public';

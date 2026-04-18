-- Same-phone dual strength: finishing the guest workout runs triggers/RPC that INSERT
-- into personal_records for the guest user_id. RLS often allows INSERT only when
-- auth.uid() = user_id, which blocks the host session. Allow inserts when the row's
-- user_id owns a workout linked from the current user's workout (dual_linked_workout_id).
--
-- Requires column personal_records.user_id (uuid). If your schema differs, adjust the policy.

DROP POLICY IF EXISTS "personal_records_insert_dual_linked_partner" ON public.personal_records;

CREATE POLICY "personal_records_insert_dual_linked_partner"
  ON public.personal_records
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.workouts w
      WHERE w.user_id = personal_records.user_id
        AND EXISTS (
          SELECT 1
          FROM public.workouts h
          WHERE h.user_id = auth.uid()
            AND h.dual_linked_workout_id IS NOT DISTINCT FROM w.id
        )
    )
  );

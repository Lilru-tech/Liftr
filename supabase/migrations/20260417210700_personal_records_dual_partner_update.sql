-- personal_records: el trigger trg_strength_pr_from_set / upsert_personal_record suele hacer
-- INSERT ... ON CONFLICT ... DO UPDATE. La política dual solo cubría INSERT; en la rama UPDATE
-- solo aplicaba personal_records_all_own (user_id = auth.uid()) → fallo al tocar PRs del guest.

CREATE POLICY "personal_records_update_dual_linked_partner"
  ON public.personal_records
  FOR UPDATE
  TO authenticated
  USING (public.dual_linked_auth_may_insert_personal_record_for(user_id))
  WITH CHECK (public.dual_linked_auth_may_insert_personal_record_for(user_id));

-- ON CONFLICT DO UPDATE necesita ver la fila conflictiva bajo las políticas SELECT del rol.
-- Sin SELECT partner, el host puede no “ver” el PR del guest y el upsert se comporta mal.
-- DELETE por si algún camino borra PRs del partner antes de reinsertar.

DROP POLICY IF EXISTS "personal_records_select_dual_linked_partner" ON public.personal_records;
CREATE POLICY "personal_records_select_dual_linked_partner"
  ON public.personal_records
  FOR SELECT
  TO authenticated
  USING (public.dual_linked_auth_may_insert_personal_record_for(user_id));

DROP POLICY IF EXISTS "personal_records_delete_dual_linked_partner" ON public.personal_records;
CREATE POLICY "personal_records_delete_dual_linked_partner"
  ON public.personal_records
  FOR DELETE
  TO authenticated
  USING (public.dual_linked_auth_may_insert_personal_record_for(user_id));

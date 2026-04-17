-- personal_records INSERT en dual same-phone: la política basada solo en dual_linked_workout_id
-- puede fallar si el enlace ya no está visible o se ha limpiado antes de que un trigger inserte el PR.
-- Centralizamos el criterio en SECURITY DEFINER (lee workouts sin re-entrar en RLS) y añadimos:
-- - enlace host → guest (h.dual_linked_workout_id = w.id)
-- - enlace guest → host (w.dual_linked_workout_id = h.id)
-- - huérfanos post-enlace: guest clonado con dual_host_user_id = auth.uid() (RPC create_linked_*)

CREATE OR REPLACE FUNCTION public.dual_linked_auth_may_insert_personal_record_for(p_pr_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    p_pr_user_id IS NOT DISTINCT FROM auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.workouts w
      WHERE w.user_id = p_pr_user_id
        AND (
          EXISTS (
            SELECT 1
            FROM public.workouts h
            WHERE h.user_id = auth.uid()
              AND h.dual_linked_workout_id IS NOT DISTINCT FROM w.id
          )
          OR EXISTS (
            SELECT 1
            FROM public.workouts h
            WHERE h.user_id = auth.uid()
              AND w.dual_linked_workout_id IS NOT DISTINCT FROM h.id
          )
          OR w.dual_host_user_id IS NOT DISTINCT FROM auth.uid()
        )
    );
$$;

REVOKE ALL ON FUNCTION public.dual_linked_auth_may_insert_personal_record_for(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dual_linked_auth_may_insert_personal_record_for(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dual_linked_auth_may_insert_personal_record_for(uuid) TO service_role;

DROP POLICY IF EXISTS "personal_records_insert_dual_linked_partner" ON public.personal_records;

CREATE POLICY "personal_records_insert_dual_linked_partner"
  ON public.personal_records
  FOR INSERT
  TO authenticated
  WITH CHECK (public.dual_linked_auth_may_insert_personal_record_for(user_id));

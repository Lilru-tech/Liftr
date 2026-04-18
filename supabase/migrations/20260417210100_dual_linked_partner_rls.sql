-- Same-phone dual strength: host may read/update the linked partner workout + child rows.
-- IMPORTANT: policies on `workouts` must NOT subquery `workouts` directly — that causes
-- Postgres error 42P17 ("infinite recursion detected in policy for relation workouts").
-- All checks go through SECURITY DEFINER helpers that read `workouts` without RLS re-entry.

CREATE OR REPLACE FUNCTION public.dual_linked_auth_hosts_partner_workout(p_partner_workout_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.workouts h
    WHERE h.user_id = auth.uid()
      AND h.dual_linked_workout_id IS NOT DISTINCT FROM p_partner_workout_id
  );
$$;

REVOKE ALL ON FUNCTION public.dual_linked_auth_hosts_partner_workout(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dual_linked_auth_hosts_partner_workout(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dual_linked_auth_hosts_partner_workout(bigint) TO service_role;

DROP POLICY IF EXISTS "dual_linked_partner_select_workouts" ON public.workouts;
CREATE POLICY "dual_linked_partner_select_workouts"
  ON public.workouts
  FOR SELECT
  TO authenticated
  USING (public.dual_linked_auth_hosts_partner_workout(public.workouts.id));

DROP POLICY IF EXISTS "dual_linked_partner_update_guest_workout" ON public.workouts;
CREATE POLICY "dual_linked_partner_update_guest_workout"
  ON public.workouts
  FOR UPDATE
  TO authenticated
  USING (public.dual_linked_auth_hosts_partner_workout(public.workouts.id))
  WITH CHECK (public.dual_linked_auth_hosts_partner_workout(public.workouts.id));

DROP POLICY IF EXISTS "dual_linked_partner_touch_workout_exercises" ON public.workout_exercises;
CREATE POLICY "dual_linked_partner_touch_workout_exercises"
  ON public.workout_exercises
  FOR ALL
  TO authenticated
  USING (public.dual_linked_auth_hosts_partner_workout(workout_exercises.workout_id))
  WITH CHECK (public.dual_linked_auth_hosts_partner_workout(workout_exercises.workout_id));

DROP POLICY IF EXISTS "dual_linked_partner_touch_exercise_sets" ON public.exercise_sets;
CREATE POLICY "dual_linked_partner_touch_exercise_sets"
  ON public.exercise_sets
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.workout_exercises we
      WHERE we.id = exercise_sets.workout_exercise_id
        AND public.dual_linked_auth_hosts_partner_workout(we.workout_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.workout_exercises we
      WHERE we.id = exercise_sets.workout_exercise_id
        AND public.dual_linked_auth_hosts_partner_workout(we.workout_id)
    )
  );

-- Parte 4/6 — RPC match manual. Ejecutar archivo COMPLETO. Requiere part02.

CREATE OR REPLACE FUNCTION public.match_segment_efforts_for_workout_v1(p_workout_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $rpc$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.workouts w
    WHERE w.id = p_workout_id
      AND w.user_id = (SELECT auth.uid())
  ) THEN
    RAISE EXCEPTION 'not_allowed' USING ERRCODE = '42501';
  END IF;

  PERFORM public._match_segments_for_workout_internal(p_workout_id);
END;
$rpc$;

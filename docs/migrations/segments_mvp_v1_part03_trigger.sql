-- Parte 3/6 — Trigger al publicar cardio. Ejecutar archivo COMPLETO. Requiere part02.

CREATE OR REPLACE FUNCTION public.trg_workouts_publish_match_segments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $trg$
BEGIN
  IF NEW.kind::text IS DISTINCT FROM 'cardio' THEN
    RETURN NEW;
  END IF;
  IF NEW.state IS DISTINCT FROM 'published'::public.workout_state THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM public._match_segments_for_workout_internal(NEW.id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.state IS DISTINCT FROM 'published'::public.workout_state THEN
      PERFORM public._match_segments_for_workout_internal(NEW.id);
    END IF;
  END IF;

  RETURN NEW;
END;
$trg$;

DROP TRIGGER IF EXISTS workouts_publish_match_segments ON public.workouts;
CREATE TRIGGER workouts_publish_match_segments
  AFTER INSERT OR UPDATE OF state ON public.workouts
  FOR EACH ROW
  EXECUTE PROCEDURE public.trg_workouts_publish_match_segments();

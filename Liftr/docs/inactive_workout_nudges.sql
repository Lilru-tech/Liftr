-- =============================================================================
-- Recordatorios: usuario sin entrenar X tipo (strength / cardio / sport)
-- Requisitos: ≥ min workouts publicados de ese tipo; último hace ≥ inactive_days;
-- no repetir si ya hubo aviso del mismo tipo en cooldown_days.
-- Inserta filas en public.notifications → el worker send-notifications envía FCM.
-- =============================================================================
-- Ajusta umbrales aquí:
--   min_published_per_kind  = 3
--   inactive_days           = 14
--   cooldown_days           = 10  (entre avisos del mismo user + mismo kind)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enqueue_workout_inactivity_nudges()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  inserted_count integer := 0;
BEGIN
  WITH params AS (
    SELECT
      3::int  AS min_published,
      14::int AS inactive_days,
      10::int AS cooldown_days
  ),
  per_user_kind AS (
    SELECT
      w.user_id,
      w.kind::text AS kind_text,
      COUNT(*) FILTER (WHERE w.state::text = 'published')::int AS pub_count,
      MAX(
        COALESCE(w.started_at, w.created_at)
      ) FILTER (WHERE w.state::text = 'published') AS last_at
    FROM public.workouts w
    GROUP BY w.user_id, w.kind::text
  ),
  eligible AS (
    SELECT p.user_id, p.kind_text, p.last_at
    FROM per_user_kind p
    CROSS JOIN params pr
    WHERE p.pub_count >= pr.min_published
      AND p.last_at IS NOT NULL
      AND p.last_at < (now() AT TIME ZONE 'utc') - (pr.inactive_days || ' days')::interval
      AND p.kind_text IN ('strength', 'cardio', 'sport')
  ),
  to_insert AS (
    SELECT e.user_id, e.kind_text, e.last_at
    FROM eligible e
    INNER JOIN public.profiles prf ON prf.user_id = e.user_id
    CROSS JOIN params pr
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.user_id = e.user_id
        AND n.type = 'workout_kind_inactive'
        AND n.data->>'workout_kind' = e.kind_text
        AND n.created_at >= (now() AT TIME ZONE 'utc') - (pr.cooldown_days || ' days')::interval
    )
  )
  INSERT INTO public.notifications (user_id, type, title, body, data)
  SELECT
    t.user_id,
    'workout_kind_inactive',
    CASE t.kind_text
      WHEN 'strength' THEN '¿Tiempo de fuerza?'
      WHEN 'cardio'   THEN '¿Un poco de cardio?'
      WHEN 'sport'    THEN '¿Vuelves al deporte?'
      ELSE 'Liftr'
    END,
    CASE t.kind_text
      WHEN 'strength' THEN 'Llevas bastante sin registrar un entreno de fuerza. ¡Un empujón y lo tienes!'
      WHEN 'cardio'   THEN 'Llevas bastante sin registrar cardio. Un paseo o una sesión suave cuenta.'
      WHEN 'sport'    THEN 'Llevas bastante sin registrar deporte. ¡A por el siguiente!'
      ELSE 'Te echamos de menos en Liftr.'
    END,
    jsonb_build_object('workout_kind', t.kind_text)
  FROM to_insert t;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

COMMENT ON FUNCTION public.enqueue_workout_inactivity_nudges() IS
  'Encola notificaciones (tabla notifications) si el usuario tiene ≥3 workouts publicados de un kind y lleva ≥14 días sin otro del mismo kind; cooldown 10 días entre avisos iguales.';

-- Quién puede ejecutar: postgres (cron) y, si quieres pruebas manuales desde SQL editor como admin:
REVOKE ALL ON FUNCTION public.enqueue_workout_inactivity_nudges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_workout_inactivity_nudges() TO postgres;
-- Si en tu proyecto el job de pg_cron corre con otro rol y falla con “permission denied”:
-- GRANT EXECUTE ON FUNCTION public.enqueue_workout_inactivity_nudges() TO supabase_admin;

-- =============================================================================
-- CRON (pg_cron): 1 vez al día ~09:00 UTC (ajusta la hora si quieres)
-- =============================================================================
-- Primero comprueba si ya existe un job con el mismo nombre:
--   SELECT * FROM cron.job WHERE jobname = 'workout_inactivity_nudges';
--
-- Programar (descomenta):
-- SELECT cron.schedule(
--   'workout_inactivity_nudges',
--   '0 9 * * *',
--   $$SELECT public.enqueue_workout_inactivity_nudges();$$
-- );
--
-- Ver jobs:
--   SELECT * FROM cron.job;
--
-- Quitar el job (usa el jobid de cron.job):
--   SELECT cron.unschedule(<jobid>);

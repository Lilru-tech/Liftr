-- =============================================================================
-- Liftr — Challenges: upgrade cuando ya existe el MVP antiguo (title_es /
-- description_es y/o firmas distintas de los RPC).
--
-- PostgreSQL NO permite CREATE OR REPLACE si cambian las columnas del RETURNS
-- TABLE (...). Hay que DROP FUNCTION primero.
--
-- Orden recomendado en SQL Editor:
--   1) Ejecutar ESTE archivo completo.
--   2) Volver a ejecutar docs/migrations/challenges_mvp_v1.sql completo
--      (las tablas ya existentes se saltan con IF NOT EXISTS; el INSERT seed
--      hace ON CONFLICT DO UPDATE).
-- =============================================================================

-- Renombrar columnas si venías de la versión en español
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'challenge_templates' AND column_name = 'title_es'
  ) THEN
    ALTER TABLE public.challenge_templates RENAME COLUMN title_es TO title;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'challenge_templates' AND column_name = 'description_es'
  ) THEN
    ALTER TABLE public.challenge_templates RENAME COLUMN description_es TO description;
  END IF;
END $$;

-- Columna cadence (instalaciones que crearon la tabla antes de añadirla)
ALTER TABLE public.challenge_templates
  ADD COLUMN IF NOT EXISTS cadence text;

UPDATE public.challenge_templates
SET cadence = 'week'
WHERE cadence IS NULL;

ALTER TABLE public.challenge_templates
  ALTER COLUMN cadence SET DEFAULT 'week';

ALTER TABLE public.challenge_templates
  ALTER COLUMN cadence SET NOT NULL;

-- Sustituir CHECK de cadence si existía uno distinto (nombre fijo del constraint)
ALTER TABLE public.challenge_templates DROP CONSTRAINT IF EXISTS challenge_templates_cadence_check;
ALTER TABLE public.challenge_templates
  ADD CONSTRAINT challenge_templates_cadence_check
  CHECK (cadence IN ('week', 'month', 'once'));

ALTER TABLE public.challenge_templates ADD COLUMN IF NOT EXISTS scope_activity_code text;
ALTER TABLE public.challenge_templates ADD COLUMN IF NOT EXISTS scope_sport text;
ALTER TABLE public.challenge_templates ADD COLUMN IF NOT EXISTS scope_muscle_primary text;

-- Ampliar metric_kind (sport / strength session counts) antes de re-aplicar el MVP
ALTER TABLE public.challenge_templates DROP CONSTRAINT IF EXISTS challenge_templates_metric_kind_check;
ALTER TABLE public.challenge_templates ADD CONSTRAINT challenge_templates_metric_kind_check
  CHECK (metric_kind IN (
    'cumulative_cardio_km',
    'single_set_max_kg',
    'cardio_session_pace_gate',
    'cumulative_sport_sessions',
    'cumulative_strength_workouts',
    'cumulative_strength_reps',
    'cumulative_strength_sets',
    'cumulative_strength_volume_kg',
    'single_set_max_reps',
    'strength_workouts_touching_muscle'
  ));

-- RPCs con RETURNS TABLE distinto al desplegado antes (title_es → title, + cadence, etc.)
DROP FUNCTION IF EXISTS public.list_active_challenges_v1();
DROP FUNCTION IF EXISTS public.get_challenge_instance_detail_v1(uuid);

-- Tras esto, re-ejecutar challenges_mvp_v1.sql para evaluate_challenges_for_user,
-- get_challenge_my_progress_v1, seed y notification type challenge_won.

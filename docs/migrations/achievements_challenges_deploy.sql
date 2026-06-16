-- =============================================================================
-- Liftr — Achievements para Challenges (podios en retos)
--
-- Qué hace:
--   1) Inserta filas en public.achievements (códigos challenge_*).
--   2) public.unlock_challenge_achievements(p_user_id) — cuenta filas en
--      challenge_claims y desbloquea por umbrales; también hitos de 1º lugar (rank = 1).
--   3) Trigger AFTER INSERT en challenge_claims para desbloquear al instante.
--
-- Paso manual OBLIGATORIO (el orquestador no está versionado en este repo):
--   En Supabase, edita public.check_and_unlock_achievements_for(p_user_id uuid)
--   y añade, junto al resto de unlock_*:
--
--     PERFORM public.unlock_challenge_achievements(p_user_id);
--
--   Así “Recalcular logros” en la app también aplicará estos hitos.
--
-- Opcional: si tienes unlock_meta_achievements con totales fijos (p. ej. “desbloquea
-- 200 logros”), sube el número o pásalo a COUNT(*) del catálogo.
--
-- Ejecutar en SQL Editor (un solo lote). Revisar: SELECT code FROM achievements WHERE code LIKE 'challenge_%';
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Catálogo
-- ---------------------------------------------------------------------------
INSERT INTO public.achievements (code, name, description, category, requirement_type, requirement_value)
VALUES
  ('challenge_podium_1', 'Challenge contender', 'Claim a podium slot on any challenge', 'general', 'count', 1),
  ('challenge_podium_5', 'Challenge regular', 'Claim 5 challenge podium slots (all-time)', 'general', 'count', 5),
  ('challenge_podium_10', 'Challenge hunter', 'Claim 10 challenge podium slots (all-time)', 'general', 'count', 10),
  ('challenge_podium_25', 'Challenge collector', 'Claim 25 challenge podium slots (all-time)', 'general', 'count', 25),
  ('challenge_podium_50', 'Challenge legend', 'Claim 50 challenge podium slots (all-time)', 'general', 'count', 50),
  ('challenge_first_1', 'Challenge winner', 'Finish 1st on at least one challenge', 'general', 'count', 1),
  ('challenge_first_5', 'Top of the pack', 'Finish 1st on 5 different challenges', 'general', 'count', 5),
  ('challenge_first_10', 'Unstoppable', 'Finish 1st on 10 different challenges', 'general', 'count', 10)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2) Desbloqueo (SECURITY DEFINER como otros unlock_* del proyecto)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.unlock_challenge_achievements(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_total int := 0;
  v_first int := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COUNT(*)::int INTO v_total
  FROM public.challenge_claims cc
  WHERE cc.user_id = p_user_id;

  SELECT COUNT(*)::int INTO v_first
  FROM public.challenge_claims cc
  WHERE cc.user_id = p_user_id AND cc.rank = 1;

  IF v_total >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_podium_1'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_total >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_podium_5'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_total >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_podium_10'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_total >= 25 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_podium_25'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_total >= 50 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_podium_50'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;

  IF v_first >= 1 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_first_1'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_first >= 5 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_first_5'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
  IF v_first >= 10 THEN
    INSERT INTO public.user_achievements (user_id, achievement_id, unlocked_at)
    SELECT p_user_id, id, NOW() FROM public.achievements WHERE code = 'challenge_first_10'
    ON CONFLICT (user_id, achievement_id) DO NOTHING;
  END IF;
END;
$fn$;

COMMENT ON FUNCTION public.unlock_challenge_achievements(uuid) IS
  'Desbloquea achievements challenge_* según filas en challenge_claims (total podios y veces en 1º lugar).';

-- ---------------------------------------------------------------------------
-- 3) Trigger: al conseguir claim, recalcular logros de challenges para ese usuario
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._tr_challenge_claims_unlock_achievements()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $tr$
BEGIN
  PERFORM public.unlock_challenge_achievements(NEW.user_id);
  RETURN NEW;
END;
$tr$;

DROP TRIGGER IF EXISTS tr_challenge_claims_unlock_achievements ON public.challenge_claims;
CREATE TRIGGER tr_challenge_claims_unlock_achievements
  AFTER INSERT ON public.challenge_claims
  FOR EACH ROW
  EXECUTE FUNCTION public._tr_challenge_claims_unlock_achievements();

COMMIT;

-- ---------------------------------------------------------------------------
-- 4) Backfill retroactivo (claims creados ANTES del trigger, o si saltaste este paso)
-- Idempotente: ON CONFLICT DO NOTHING en user_achievements.
-- Ejecuta esto en SQL Editor si los logros challenge_* no aparecen pese a tener claims.
-- ---------------------------------------------------------------------------
DO $backfill$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT DISTINCT user_id FROM public.challenge_claims
  LOOP
    PERFORM public.unlock_challenge_achievements(r.user_id);
  END LOOP;
END;
$backfill$;

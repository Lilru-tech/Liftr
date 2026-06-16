-- =============================================================================
-- Liftr — xp_events: permitir leer el historial XP al visitar el perfil de otro usuario.
--
-- Síntoma: en UserLevelDetail (iOS/Android) la lista y el snapshot usan
--   SELECT ... FROM xp_events WHERE user_id = <perfil visitado>
-- Si RLS solo permite user_id = auth.uid(), esas filas devuelven 0 para terceros.
--
-- Antes de aplicar, inspecciona políticas actuales:
--   SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
--   FROM pg_policies WHERE tablename = 'xp_events';
--
-- En PostgreSQL, varias políticas PERMISSIVE para el mismo comando se combinan con OR.
-- Esta migración AÑADE una política de lectura; no borra las existentes salvo que elijas
-- la variante “solo sustituir” al final (comentada).
-- =============================================================================

BEGIN;

-- Opción A (recomendada si cualquier usuario autenticado puede abrir el perfil / nivel de otro):
-- cualquier sesión autenticada puede leer filas de xp_events (la app sigue filtrando por user_id).
DROP POLICY IF EXISTS "xp_events_select_authenticated_read" ON public.xp_events;

CREATE POLICY "xp_events_select_authenticated_read"
ON public.xp_events
FOR SELECT
TO authenticated
USING (true);

COMMIT;

-- -----------------------------------------------------------------------------
-- Opción B (más restrictiva): solo tú o usuarios a los que sigues (paridad rough con
-- leaderboards “friends” en ranking_goals_duels_leaderboard_v1.sql: follower_id → followee_id).
-- Descomenta y sustituye si NO quieres lectura global; primero DROP la política de Opción A.
--
-- BEGIN;
-- DROP POLICY IF EXISTS "xp_events_select_authenticated_read" ON public.xp_events;
-- CREATE POLICY "xp_events_select_self_or_followee"
-- ON public.xp_events
-- FOR SELECT
-- TO authenticated
-- USING (
--   user_id = (SELECT auth.uid())
--   OR EXISTS (
--     SELECT 1
--     FROM public.follows f
--     WHERE f.follower_id = (SELECT auth.uid())
--       AND f.followee_id = xp_events.user_id
--   )
-- );
-- COMMIT;
--
-- Nota: con Opción B, perfiles que no sigues seguirán sin historial XP en pantalla.
-- -----------------------------------------------------------------------------

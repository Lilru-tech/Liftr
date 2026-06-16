-- =============================================================================
-- Liftr — Extender get_user_achievements con progress_current (barra / % en app).
-- Basado en la definición real de producción (mismo SELECT, orden, tipos).
--
-- IMPORTANTE — error 42P13 "cannot change return type of existing function":
--   En PostgreSQL, CREATE OR REPLACE no puede cambiar el tipo de retorno (OUT).
--   Añadir la columna progress_current cambia el tipo de fila ⇒ hace falta
--   DROP FUNCTION y luego CREATE FUNCTION.
--
-- Antes de ejecutar en producción:
--   1) Opcional: guardar los GRANT actuales:
--        SELECT pg_get_functiondef(p.oid) ...  -- no incluye GRANT
--        \df+ get_user_achievements   -- en psql, o:
--      SELECT grantee, privilege_type
--      FROM information_schema.routine_privileges
--      WHERE routine_schema = 'public'
--        AND routine_name = 'get_user_achievements';
--   2) Si DROP falla por dependencias, ver el mensaje; en casos raros:
--        DROP FUNCTION ... CASCADE   (solo si sabéis qué se rompe).
--
-- progress_current:
--   - Desbloqueado: requirement_value en double (barra 100 % en clientes).
--   - Bloqueado: NULL salvo métricas que ya calculamos aquí (p. ej. cardio_sessions_*).
--     Misma base que el conteo típico de desbloqueo: workouts publicados con fila en cardio_sessions.
--
-- community_pct_unlocked / community_sample_size (benchmark barato):
--   - % de usuarios con ≥1 workout publicado que tienen fila en user_achievements para ese logro.
--   - Si el denominador < min_publishing_users (CTE achievement_community_threshold abajo), ambas NULL.
--   - Producción con masa de usuarios: 50–100 típico. Beta con ~4 usuarios publicando: hay que bajar
--     ese valor (p. ej. 3) o seguirás viendo NULL en la app — no es fallo del cliente.
--
-- Inspección de la función en psql/Supabase (si pg_get_function_identity_arguments no cuadra):
--   SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE p.proname = 'get_user_achievements';
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_user_achievements(uuid);

CREATE FUNCTION public.get_user_achievements(p_user_id uuid)
RETURNS TABLE(
    achievement_id bigint,
    code text,
    title text,
    description text,
    category text,
    requirement_type text,
    requirement_value integer,
    icon_url text,
    user_id uuid,
    unlocked_at timestamp with time zone,
    is_unlocked boolean,
    progress_current double precision,
    community_pct_unlocked double precision,
    community_sample_size integer
)
LANGUAGE sql
STABLE
AS $function$
  WITH published_cardio_workouts AS (
    SELECT COUNT(DISTINCT w.id)::double precision AS n
    FROM public.workouts w
    JOIN public.cardio_sessions cs ON cs.workout_id = w.id
    WHERE w.user_id = p_user_id
      AND w.state = 'published'
  ),
  active_community AS (
    SELECT COUNT(DISTINCT w.user_id)::bigint AS n
    FROM public.workouts w
    WHERE w.state = 'published'
  ),
  unlocks_by_achievement AS (
    SELECT ua.achievement_id,
           COUNT(DISTINCT ua.user_id)::bigint AS unlocked_n
    FROM public.user_achievements ua
    GROUP BY ua.achievement_id
  ),
  achievement_community_threshold AS (
    SELECT 100::bigint AS min_publishing_users
    -- Beta interna (pocos usuarios con workouts publicados): sustituir 100 por 3–10 para ver el bloque en app.
    -- Producción: mantener 50–100 según política de privacidad.
  ),
  community_stats AS (
    SELECT
      a.id AS achievement_id,
      CASE
        WHEN ac.n < th.min_publishing_users THEN NULL::double precision
        ELSE ROUND(
          (100.0 * COALESCE(u.unlocked_n, 0)::numeric / NULLIF(ac.n, 0)::numeric),
          1
        )::double precision
      END AS pct_unlocked,
      CASE
        WHEN ac.n < th.min_publishing_users THEN NULL::integer
        ELSE ac.n::integer
      END AS sample_size
    FROM public.achievements a
    CROSS JOIN active_community ac
    CROSS JOIN achievement_community_threshold th
    LEFT JOIN unlocks_by_achievement u ON u.achievement_id = a.id
  )
  SELECT
    a.id AS achievement_id,
    a.code,
    a.name AS title,
    a.description,
    a.category,
    a.requirement_type,
    a.requirement_value,
    a.icon_url,
    ua.user_id,
    ua.unlocked_at,
    (ua.user_id IS NOT NULL) AS is_unlocked,
    CASE
        WHEN ua.user_id IS NOT NULL THEN a.requirement_value::double precision
        WHEN a.requirement_type = 'count'
         AND a.code LIKE 'cardio_sessions_%'
        THEN (SELECT n FROM published_cardio_workouts)
        ELSE NULL::double precision
    END AS progress_current,
    c.pct_unlocked AS community_pct_unlocked,
    c.sample_size AS community_sample_size
  FROM public.achievements a
  LEFT JOIN public.user_achievements ua
    ON ua.achievement_id = a.id
   AND ua.user_id = p_user_id
  LEFT JOIN community_stats c ON c.achievement_id = a.id
  ORDER BY (ua.user_id IS NOT NULL) DESC, a.category, title
$function$;

COMMENT ON FUNCTION public.get_user_achievements(uuid) IS
'Catálogo de achievements por usuario: progress_current (meta + cardio_sessions_*); community_* si usuarios con ≥1 workout publicado ≥ umbral (achievement_community_threshold en el cuerpo).';

-- Permisos típicos en Supabase (ajustad si vuestro proyecto difiere).
GRANT EXECUTE ON FUNCTION public.get_user_achievements(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_user_achievements(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_achievements(uuid) TO service_role;

COMMIT;

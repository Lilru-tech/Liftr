# Notas al ejecutar SQL (PostgreSQL / clientes)

## DbVisualizer (u otros) que no aceptan `$$`

- Si el cliente falla con **dollar-quoting** (`$$` o `$tag$`), usa el script alternativo **[migrations/achievements_extra_sports_deploy_dbvisualizer.sql](migrations/achievements_extra_sports_deploy_dbvisualizer.sql)**: cuerpo `AS '<cuerpo con ''comillas'' duplicadas>';` — es SQL estándar, sin `$`.
- **Ranking goals/duels:** [migrations/ranking_goals_duels_leaderboard_v1.sql](migrations/ranking_goals_duels_leaderboard_v1.sql) ya va con `AS '...'` (sin `$$`) por la misma razón.
- Sigue siendo **una sola sentencia** por `CREATE FUNCTION`: no cortar en el primer `;` dentro del literal (el cuerpo entero va entre comillas).
- El script principal **[migrations/achievements_extra_sports_deploy.sql](migrations/achievements_extra_sports_deploy.sql)** mantiene `$$` para Supabase / `psql`.

## Dollar quoting: otras herramientas

En **psql** o **Supabase SQL Editor** suelen aceptar tanto `$$` como otras etiquetas.

**Alternativas (equivalentes en PostgreSQL):**

1. **Otra etiqueta de dollar-quoting** (recomendado), por ejemplo `$mig$` o `$body$`:

```sql
CREATE OR REPLACE FUNCTION public.ejemplo(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $MIG$
BEGIN
  -- cuerpo
  NULL;
END;
$MIG$;
```

2. **Misma etiqueta al inicio y al final**; puede ser cualquier string sin espacios, p. ej. `$function$` … `$function$`.

3. **Editor SQL de Supabase** o `psql` en terminal: suelen aceptar `$$` sin problema.

4. Cuerpos **muy grandes**: guardar el script en un archivo y ejecutar con `psql -f script.sql` evita limitaciones de pegar en el IDE.

Nada de esto cambia la semántica del SQL; solo el **delimitador** del literal del cuerpo de la función.

## Funciones y achievements

- Las migraciones o scripts que definan `CREATE OR REPLACE FUNCTION` para el proyecto Liftr pueden versionarse bajo `docs/migrations/` (si añadís convención) o pegarse en Supabase; mantener el mismo `SECURITY DEFINER` y `search_path` que el resto de funciones del proyecto.

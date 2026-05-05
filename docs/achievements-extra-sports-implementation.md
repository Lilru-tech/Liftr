# Implementación: achievements handball, hockey, rugby, ski

Guía de trabajo para añadir logros que faltan **sin modificar** `unlock_sport_achievements` (se mantiene como está). Delimitación de cuerpos SQL: si tu cliente no acepta `$$`, usa otra etiqueta; ver [postgres-sql-execution-notes.md](postgres-sql-execution-notes.md).

**Antes de escribir INSERT/función:** ejecuta y guarda resultados de [achievements-extra-sports-discovery.sql](achievements-extra-sports-discovery.sql) (esquema, colisiones de códigos, volumen de datos, `unlock_meta_achievements`, orquestador).

**Script de despliegue listo (57 filas + función + orquestador):** [migrations/achievements_extra_sports_deploy.sql](migrations/achievements_extra_sports_deploy.sql) — cuerpos con `$$` (Supabase / psql). Si **DbVisualizer** no acepta `$$`, usa **[migrations/achievements_extra_sports_deploy_dbvisualizer.sql](migrations/achievements_extra_sports_deploy_dbvisualizer.sql)** (`AS ' ... '` con `''` en strings internos). Total de filas de catálogo: **355** (298 + 57).

## Objetivo

- **Handball, hockey, rugby:** mismo patrón que padel/football (partidos + victorias + rachas) y metas de stats acumuladas (goles / tries).
- **Ski:** sin cadena de victorias; sesiones, km acumulados, carreras y bajada vertical (datos en `ski_session_stats`).

## 1) Catálogo: `INSERT` en `public.achievements`

Asegúrate de que `code` sea **único**. Columnas mínimas según tu esquema: `code`, `name`, `description`, `category`, `requirement_type`, `requirement_value`, `icon_url` (puede ser NULL), `created_at` (puede ser `NOW()`).

**Convención de códigos (ejemplos, alinear títulos/descriptions al tono de las otras filas en inglés):**

| Deporte  | Tipo        | Códigos sugeridos (patrón) |
|----------|-------------|----------------------------|
| handball | played      | `handball_played_10`, `handball_played_50`, `handball_played_100` |
| handball | wins        | `handball_win_1` … `handball_win_50` (mismos umbrales que fútbol) |
| handball | streaks     | `handball_win_streak_3`, `handball_win_streak_5` |
| handball | goles acum. | `handball_goals_1`, `handball_goals_10`, `handball_goals_50` |
| hockey   | played/wins/streaks | `hockey_played_*`, `hockey_win_*`, `hockey_win_streak_*` |
| hockey   | goles acum. | `hockey_goals_1`, `hockey_goals_10`, `hockey_goals_50` |
| rugby    | played/wins/streaks | `rugby_played_*`, `rugby_win_*`, `rugby_win_streak_*` |
| rugby    | tries acum. | `rugby_tries_1`, `rugby_tries_10`, `rugby_tries_50` (o 25) |
| ski      | sesiones     | `ski_sessions_1`, `ski_sessions_5`, `ski_sessions_10`, `ski_sessions_25`, `ski_sessions_50` |
| ski      | km acum.     | `ski_total_km_10`, `ski_total_km_25`, `ski_total_km_50`, `ski_total_km_100` (o el escalón que elijas) |
| ski      | carreras acum. | `ski_runs_10`, `ski_runs_50`, `ski_runs_100` (SUM `runs_count`) |
| ski      | vertical     | `ski_vertical_m_5000`, `ski_vertical_m_10000` (SUM `vertical_drop_m`, opcional) |

- Categoría `sport` para handball, hockey, rugby. Para **ski** puedes usar `sport` o `cardio` según cómo quieras filtrar en la app (el resto de “modalidades” de nieve suelen mostrarse como actividad al aire libre; si en la app `ski` se lista en deporte, usa `sport`).
- `requirement_type` / `requirement_value`: replicar el criterio de otras filas (p. ej. `count` + `10` para `*_played_10`) o `custom` con `1` en los de ski si seguís el patrón de `double_session`.

Cuenta total: **anota cuántas filas nuevas son**; el contador “298” en textos pasa a **298 + N** o conviene que el cliente muestre total dinámico (ya lo hace el RPC al contar filas).

## 2) Función `unlock_extra_sport_achievements(p_user_id uuid)`

- **Crear** en `public`, `LANGUAGE plpgsql`, `SECURITY DEFINER`, `SET search_path TO 'public'`, mismo estilo que `unlock_sport_achievements`.
- Reutilizar la **misma lógica de victoria** que allí:  
  `COALESCE(ss.won,false) OR ss.match_result = 'win' OR (score_for > score_against con ambos NOT NULL)`.
- Solo `workouts.state = 'published'` y `workouts.user_id = p_user_id`.
- **Por deporte (handball, hockey, rugby):** para cada uno, un bloque como el de `volleyball` (COUNT partidos, COUNT victorias, y CTE con racha de victorias ordenada por `w.started_at`); `INSERT INTO user_achievements SELECT p_user_id, id, NOW() FROM achievements WHERE code = '...' ON CONFLICT DO NOTHING`.
- **Agregados de stats (tras `to_regclass` o join directo):**
  - `SUM(handball_session_stats.goals)` con join `handball_session_stats` → `sport_sessions` → `workouts` filtrado por `ss.sport = 'handball'`.
  - `SUM(hockey_session_stats.goals)` con `hockey` + `hockey_session_stats`.
  - `SUM(rugby_session_stats.tries)` con `rugby` + `rugby_session_stats`.
- **Ski:**
  - `COUNT(*)` de sesiones con `ss.sport = 'ski'`.
  - `SUM(ski_session_stats.total_distance_km)` (cuidar NULLs: `COALESCE` por fila o en suma).
  - `SUM(runs_count)` y `SUM(vertical_drop_m)` si activaste esos códigos de logro.
- Cuerpo en dollar-quoting, p. ej. `$MIG$` … `$MIG$` (ver [postgres-sql-execution-notes.md](postgres-sql-execution-notes.md)), **no** `$$` si DbVisualizer lo rechaza.

## 3) Orquestador: `check_and_unlock_achievements_for`

- Tras el bloque que invoca `unlock_sport_achievements`, añadir:

```text
IF to_regprocedure('public.unlock_extra_sport_achievements(uuid)') IS NOT NULL THEN
  PERFORM public.unlock_extra_sport_achievements(p_user_id);
END IF;
```

(o `EXECUTE 'SELECT public.unlock_extra_sport_achievements($1)' USING p_user_id` para coincidir con vuestro estilo de `EXECUTE` con `p_user_id`).

- Desplegar con `CREATE OR REPLACE FUNCTION` sobre la definición completa de `check_and_unlock_achievements_for` (copiar desde Supabase, pegar, editar, aplicar en SQL Editor o migración versionada).

## 4) Meta-achievements

- `unlock_meta_achievements` suele contar filas en `user_achievements` / catálogo. Comprueba en su **definición** si el umbral “desbloquea 100 / 200 logros” usa el **count de filas del catálogo** o de desbloqueos. Si fija 298 a mano, habrá que **subir** ese número o pasar a `SELECT COUNT(*) FROM achievements`.

## 5) Comprobaciones en producción o staging

1. `SELECT COUNT(*) FROM achievements;` (nuevo total esperado).  
2. Elegir un `user_id` con datos de prueba: `SELECT public.check_and_unlock_achievements_for('…'::uuid);`  
3. `SELECT code, is_unlocked FROM get_user_achievements('…'::uuid) WHERE code LIKE 'handball_%' OR code LIKE 'ski_%' …` (o listar códigos nuevos).  
4. Insertar fila de prueba en un workout de ski / handball y comprobar que al guardar o al refrescar achievements se rellenan `user_achievements`.

## 6) Aplicación (Liftr iOS / Android)

- Los prefijos `handball_`, `hockey_`, `rugby_`, `ski_` deberían mapear a icono en [AchievementSymbol.kt](android/app/src/main/java/com/lilru/liftr/ui/achievements/AchievementSymbol.kt) y [AchievementsGridView.swift](Liftr/AchievementsGridView.swift) (revisar si añadís códigos nuevos sin prefijo estándar).
- Añadir constante de RPC en `BackendContracts` **solo** si en el futuro se llama a una función distinta desde el cliente; **ahora** no hace falta: el desbloqueo sigue siendo el mismo `check_and_unlock_achievements_for` ya usado.
- [docs/backend-contracts.md](backend-contracts.md): una línea bajo Achievements diciendo que existen códigos extra para `handball`, `hockey`, `rugby`, `ski` (opcional, cuando desplegado).

## 7) Changelog / comunicación

- [Liftr/changelog.md](Liftr/changelog.md): versión de app o nota de backend con “nuevos achievements para …” (cuando toque release).

## Orden recomendado de tareas (checklist)

1. Redactar lista final de códigos + nombres + descripciones (y si ski usa categoría `sport` o `cardio`).  
2. Ejecutar `INSERT` masivo o migración.  
3. Desplegar `CREATE OR REPLACE FUNCTION public.unlock_extra_sport_achievements ...`.  
4. Desplegar `CREATE OR REPLACE` de `check_and_unlock_achievements_for` con la llamada extra.  
5. Revisar y si hace falta ajustar `unlock_meta_achievements`.  
6. Probar con un usuario.  
7. Ajuste de UI (totales, iconos) y nota de changelog.  

Con esto tenéis el plan de implementación cerrado; el SQL concreto de `INSERT` y de la función es trabajo de copia del patrón de `volleyball` / `football` / sumas, ya con los códigos que fijéis en el paso 1.

# Backend contracts (iOS source of truth)

Este documento cierra el **paso 1 del plan**: congelar contratos con Supabase antes de portar más pantallas a Android.

## Regla de trabajo

- iOS (`Liftr/*.swift`) es la fuente de verdad actual de contratos.
- Android debe referenciar nombres de tablas/vistas/RPC mediante `BackendContracts`:
  - `android/app/src/main/java/com/lilru/liftr/data/BackendContracts.kt`
- No introducir strings sueltos en consultas nuevas de Android.

## Inventario de tablas/vistas detectadas en iOS

Tablas:

- `avatars`
- `basketball_session_stats`
- `cardio_sessions`
- `cardio_session_stats`
- `competitions`
- `competition_blocks`
- `competition_goals`
- `competition_workouts`
- `contact_messages`
- `exercises`
- `exercise_sets`
- `feature_requests`
- `feature_request_comments`
- `feature_request_votes`
- `follows`
- `football_session_stats`
- `handball_session_stats`
- `hockey_session_stats`
- `hyrox_session_exercises`
- `hyrox_session_stats`
- `level_thresholds`
- `notifications`
- `profiles`
- `racket_session_stats`
- `rugby_session_stats`
- `ski_session_stats`
- `sport_sessions`
- `strength_routines`
- `strength_routine_exercises`
- `strength_routine_folders`
- `strength_routine_sets`
- `user_favorite_exercises`
- `volleyball_session_stats`
- `weekly_goals`
- `weekly_goal_results`
- `workouts`
- `workout_comments`
- `workout_comment_likes`
- `workout_exercises`
- `workout_likes`
- `workout_participants`
- `workout_scores`
- `xp_events`
- `achievements` (catálogo; filas y reglas de desbloqueo principales vía `check_and_unlock_achievements_for` en la BD)
- `user_achievements` (desbloqueos por `user_id`)

Vistas:

- `vw_feature_request_comments`
- `vw_feature_requests`
- `vw_profile_counts`
- `vw_sport_session_full`
- `vw_user_prs`
- `vw_workout_volume`

## Inventario de RPC detectadas en iOS

- `add_workout_participant`
- `can_compare_workout_v1`
- `check_and_unlock_achievements_for`
- `clear_user_search_recent`
- `create_cardio_workout_v2`
- `create_linked_strength_workout_copy`
- `create_sport_workout_v2`
- `create_strength_workout`
- `delete_my_account`
- `fetch_dual_linked_strength_workout_data`
- `get_best_workouts_leaderboard_v1`
- `get_calories_leaderboard_v1`
- `get_duels_won_leaderboard_v1`
- `get_exercises_usage`
- `get_goal_stats`
- `get_goals_completed_leaderboard_v1`
- `get_period_training_compare_v1` (helpers internas `_period_training_compare_summary`, `_period_training_compare_breakdown`; ver `docs/migrations/period_training_compare_v1.sql`)
- `get_leaderboard_v1`
- `get_level_leaderboard_v1`
- `get_user_achievements`
- `get_user_level`
- `get_weekly_goal_recommendation`
- `list_comparable_workouts_v1`
- `plan_strength_squad_programs`
- `precheck_signup`
- `recompute_weekly_goal_results`
- `record_search`
- `review_competition_workout`
- `submit_workout_to_competition`
- `trending_search_queries_24h`
- `update_sport_workout_v2`
- `user_search_recent_list`

## Achievements (contrato cliente y operación en BD)

### Uso en app

- Los clientes **no** hacen `select` crudo al catálogo en el flujo de UI: llaman al RPC `get_user_achievements` con `p_user_id` (uuid) y reciben filas con al menos: `achievement_id`, `code`, `title`, `description`, `category`, `icon_url`, `user_id`, `unlocked_at`, `is_unlocked`.
- `check_and_unlock_achievements_for` con el mismo `p_user_id` recalcula desbloqueos; también puede invocarse vía **triggers** al crear workouts, seguir, like, comentar, etc. (ver definición y triggers en el proyecto Supabase).
- Mapeo de **icono por prefijo de `code` y categoría** (sustituto local si `icon_url` falla o es nulo): iOS en `Liftr/AchievementsGridView.swift` (`symbolForAchievement`, `prettySubtype`), Android en `ui/achievements/AchievementSymbol.kt`. Convención recomendable para códigos nuevos: `disciplina_umbral` (p. ej. `ski_distance_50k`) alineada con el resto de prefijos de catálogo.

### Inspección en Supabase (sin migraciones en este repo)

- Script SQL listo para el SQL Editor: [achievements-supabase-inspection.sql](achievements-supabase-inspection.sql) (estructura de tablas, catálogo, progreso por usuario, `pg_get_functiondef` de las dos funciones, triggers, estadística opcional de desbloqueos).

### Ideas de ampliación (validar siempre con el SQL de `check_and_unlock_achievements_for`)

- **Competiciones** (`competition_workouts`, `competitions`): primer envío, N envíos, o hitos de organización.
- **Metas semanales** (`weekly_goals`, `weekly_goal_results`): rachas o hitos de cumplimiento.
- **Deportes** con tablas de stats ya en contrato (p. ej. `handball_session_stats`, `hockey_session_stats`, `ski_session_stats`, `rugby_session_stats`, `racket_session_stats`): códigos `handball_`, `hockey_`, `ski_`, `racket_`… o meta-logros de volumen por vertical.
- **Ecosistema**: `feature_request_*` (p. ej. primer voto/comentario), importación Health, si se desea; cada uno requiere que la función o un trigger tenga en cuenta el evento.

Añadir filas a `achievements` o cambiar triggers sin actualizar `check_and_unlock_achievements_for` no desbloqueará nada: la lógica vive en la base de datos.

## Cobertura Android actual (fase auth)

- Tabla: `profiles`
- RPC: `precheck_signup`

Implementadas en:

- `android/app/src/main/java/com/lilru/liftr/auth/AuthViewModel.kt`

## Política de cambios de contrato

Cuando iOS añada/elimine/renombre una tabla o RPC:

1. Actualizar `BackendContracts.kt`.
2. Actualizar este documento.
3. Adaptar Android en el mismo PR para mantener paridad de contrato.

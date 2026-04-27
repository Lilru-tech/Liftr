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
- `get_exercises_usage`
- `get_goal_stats`
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

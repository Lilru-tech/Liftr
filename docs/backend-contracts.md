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
- `competitions` (incl. `bet_amount int` default 0 — stake Liftr Coins en duelos; ver `20260612120000_competition_bet_escrow_v1.sql`)
- `competition_blocks`
- `competition_goals`
- `competition_workouts`
- `contact_messages`
- `exercises`
- `exercise_sets` (incl. `is_completed boolean` — plantilla en vivo `false`, series persistidas al finalizar `true`; ver migración `20260527120000_strength_workout_finish_purge_v1.sql`)
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
- `profiles` (incl. `coins_balance int` — server-managed cached wallet; ver [`Liftr/supabase/migrations/20260610120000_liftr_coins_ledger_v1.sql`](../Liftr/supabase/migrations/20260610120000_liftr_coins_ledger_v1.sql))
- `racket_session_stats`
- `rugby_session_stats`
- `ski_session_stats`
- `sport_sessions`
- `strength_routines`
- `strength_routine_exercises`
- `strength_routine_folders`
- `strength_routine_sets`
- `user_favorite_exercises`
- `user_subscriptions` (Premium entitlement; one row per `user_id`; written only via `service_role` / edge webhook — ver [`Liftr/supabase/migrations/20260524140000_user_subscriptions_premium_v1.sql`](../Liftr/supabase/migrations/20260524140000_user_subscriptions_premium_v1.sql))
  - Columns: `id` (uuid PK), `user_id` (uuid, unique, FK `auth.users`), `status` (`active` | `trialing` | `canceled` | `expired`), `provider` (`apple` | `google`), `original_transaction_id` (text, unique), `expires_at` (timestamptz), `created_at`, `updated_at`
  - RLS: `authenticated` may **SELECT** own row only; **INSERT/UPDATE/DELETE** revoked for `anon` and `authenticated` (writes via webhook + `service_role` only)
- `volleyball_session_stats`
- `weekly_goals`
- `weekly_goal_results`
- `workouts`
- `workout_comments` (`mentioned_user_ids uuid[]`, followee-validated; notification type `comment_mention`)
- `workout_comment_likes`
- `workout_exercises`
- `workout_likes`
- `workout_participants`
- `workout_scores`
- `xp_events`
- `coin_transactions` (ledger unificado Liftr Coins; `amount` positivo = earn, negativo = futuro spend; ver migración `20260610120000_liftr_coins_ledger_v1.sql`)
  - Columns: `id` (uuid PK), `user_id` (uuid FK `auth.users`), `amount` (int), `action_type` (text), `reference_id` (uuid nullable), `created_at` (timestamptz)
  - RLS: `authenticated` **SELECT** own rows only; **INSERT/UPDATE/DELETE** revoked (solo triggers / `SECURITY DEFINER`)
  - Idempotencia: índices únicos parciales en `(user_id, reference_id, action_type)` para `like_given`, `user_followed`, `earned_follower`, `comment_added`, `workout_logged`, `achievement_unlocked`, `weekly_goal_perfect_week`, `workout_consistency_streak` (solo `amount > 0`)
- `coin_reward_rules` (matriz de recompensas; `action_type` PK, `amount`, `enabled`)
- `segments` (PostGIS `geography(LineString,4326)`; MVP solo creación por usuario; ver `docs/migrations/segments_mvp_v1.sql` o `segments_mvp_v1_part01_*.sql`–`part06_*.sql` si el cliente parte por `;`). Tras [`Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql`](../Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql): columnas opcionales `source_workout_id`, `source_start_fraction`, `source_end_fraction`, y `geog`/`geojson` coherente con el RPC de creación.
- `segment_efforts` (match por buffer sobre `route_geojson` + tiempo estimado; ver misma migración). Tras la migración `20260509120000_segment_route_coverage_v1.sql`: columna **`route_coverage`** (0–1); trigger antes de insert/actualizar que exige ≥0.95 salvo el entreno origen.
- `achievements` (catálogo; filas y reglas de desbloqueo principales vía `check_and_unlock_achievements_for` en la BD; opcional `coin_reward_tier` `bronze` | `silver` | `gold` para recompensas Liftr Coins)
- `user_achievements` (desbloqueos por `user_id`)
- `user_tracked_achievements` (logros que el usuario sigue activamente; máx. 5 por usuario)
- `challenge_templates` (catálogo de retos; `metric_kind`, `cadence`, umbrales, ámbitos opcionales `scope_activity_code` / `scope_sport` / `scope_muscle_primary` / `scope_stat_key`; ver [`docs/migrations/challenges_mvp_v1.sql`](migrations/challenges_mvp_v1.sql) y migración `20260618194500_challenges_full_coverage_v1.sql`)
- `challenge_instances` (ventana temporal por plantilla, p. ej. semana ISO)
- `challenge_claims` (adjudicaciones: usuario, rango, `workout_id`, `adjudication_ts`)
- `nutrition_ingredients` (catálogo de ingredientes; ver [`Liftr/supabase/migrations/20260525120000_nutrition_ecosystem_v1.sql`](../Liftr/supabase/migrations/20260525120000_nutrition_ecosystem_v1.sql))
  - Columns: `id` (uuid PK), `user_id` (uuid nullable FK `auth.users` — `NULL` = ingrediente global del sistema), `name` (text), `calories_per_100g` (numeric(6,2)), `protein_per_100g`, `carbs_per_100g`, `fat_per_100g` (numeric(5,2)), `saturated_fat_per_100g`, `sugars_per_100g`, `fiber_per_100g` (numeric(5,2) default 0), `sodium_mg_per_100g` (numeric(6,2) default 0), `is_public` (boolean default false); ver migración `20260525140000_nutrition_full_profile_v1.sql`
  - RLS: `authenticated` **SELECT** si `is_public = true` OR `user_id = auth.uid()`; **INSERT/UPDATE/DELETE** solo si `user_id = auth.uid()`
- `user_favorite_nutrition_ingredients` (favoritos de ingredientes por usuario; PK `user_id`, `ingredient_id`; ver [`20260525230000_nutrition_favorites_v1.sql`](../Liftr/supabase/migrations/20260525230000_nutrition_favorites_v1.sql))
  - RLS: `authenticated` **SELECT/INSERT/DELETE** solo `user_id = auth.uid()`
- `user_favorite_nutrition_recipes` (favoritos de recetas por usuario; PK `user_id`, `recipe_id`; misma migración)
  - RLS: `authenticated` **SELECT/INSERT/DELETE** solo `user_id = auth.uid()`
- `nutrition_recipes` (recetas del usuario + catálogo global del sistema)
  - Columns: `id`, `user_id` (uuid nullable FK `auth.users` — `NULL` = receta preset del catálogo), `name`, `description` (text nullable), `created_at`
  - RLS: `authenticated` **SELECT** si `user_id IS NULL` OR `user_id = auth.uid()`; **INSERT/UPDATE/DELETE** solo si `user_id = auth.uid()` (los presets del sistema se insertan vía migraciones, p. ej. [`20260525160000_nutrition_standard_recipes_catalog_v1.sql`](../Liftr/supabase/migrations/20260525160000_nutrition_standard_recipes_catalog_v1.sql))
  - Catálogo seed (8 presets): Classic Pasta Carbonara, Pisto Manchego (Veggie Stew), Spanish Tortilla (Potato & Egg), Fitness Chicken & Rice Bowl, Avocado Toast with Egg, High-Protein Yogurt Bowl, Classic Greek Salad, Healthy Beef & Broccoli Stir-Fry
- `nutrition_recipe_ingredients` (junction receta ↔ ingrediente)
  - Columns: `id`, `recipe_id`, `ingredient_id`, `weight_g`
  - RLS: **SELECT** si la receta padre es del sistema (`user_id IS NULL`) o propia; **INSERT/UPDATE/DELETE** solo vía recetas con `user_id = auth.uid()`
- `nutrition_diary_logs` (registro diario de ingesta)
  - Columns: `id`, `user_id`, `log_date` (date default `current_date`), `meal_slot` (`Breakfast` | `Lunch` | `Dinner` | `Snack`), `ingredient_id` (nullable), `recipe_id` (nullable), `quantity_g`
  - Constraint: exactamente uno de `ingredient_id` o `recipe_id` debe estar presente
  - RLS: todas las operaciones solo `user_id = auth.uid()`
- `nutrition_meal_plans` (planificación futura de comidas; desacoplada del diario)
  - Columns: `id`, `creator_id` (FK `profiles.user_id`), `plan_date`, `meal_slot`, `recipe_id` (nullable), `ingredient_id` (nullable), `created_at`
  - Constraint: XOR `recipe_id` / `ingredient_id`; `meal_slot` igual que diario
  - RLS: CRUD solo si `creator_id = auth.uid()`
- `nutrition_meal_plan_targets` (asignación por usuario + invitación)
  - Columns: `id`, `plan_id`, `target_user_id` (FK `profiles.user_id`), `quantity_g`, `ingredient_id` (nullable), `recipe_id` (nullable), `status` (`pending` | `accepted` | `rejected` | `eaten`), `accepted_at`, `created_at`, `updated_at`
  - Constraint: XOR `recipe_id` / `ingredient_id` en target (`nutrition_meal_plan_targets_source_xor`); backfill desde plan en `20260531150000_nutrition_meal_plan_per_user_v1.sql`
  - Unique: `(plan_id, target_user_id)`
  - Trigger `BEFORE INSERT` `nutrition_meal_plan_targets_auto_accept_creator`: si `target_user_id = creator_id` → `status = accepted`, `accepted_at = now()`
  - RLS: **SELECT** si `target_user_id = auth.uid()` o creador del plan padre; **INSERT/DELETE** solo creador del plan; **UPDATE** solo `target_user_id` (guard trigger `nutrition_meal_plan_targets_guard_columns`: invitee solo `status`/`accepted_at`/`updated_at` en UPDATE directo; RPCs `accept_meal_plan`, `reject_meal_plan`, `update_meal_plan_target`, `complete_meal_plan_as_eaten` setean `liftr.meal_plan_target_rpc=1` para bypass del guard; ver `20260531190000` + `20260531210000_nutrition_meal_plan_rpc_guard_bypass_v1.sql`)
  - Trigger `AFTER INSERT`: notification `meal_plan_invite` (English copy) when `target_user_id <> creator_id`; see `20260531120000_nutrition_meal_planning_social_v1.sql` and `20260531130000_nutrition_meal_plan_invite_fixes_v1.sql`
  - RLS select on `nutrition_meal_plans`: creator **or** invited target user; cross-table checks use `user_is_nutrition_meal_plan_creator` / `user_is_nutrition_meal_plan_target` (security definer) to avoid policy recursion — see `20260531130000` and `20260531140000_nutrition_meal_plan_rls_recursion_fix_v1.sql`

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
- `get_cardio_distance_leaderboard_v1` (sum `cardio_sessions.distance_km` by user; see `docs/migrations/ranking_training_metrics_leaderboard_v1.sql`)
- `get_strength_volume_leaderboard_v1` (sum `reps * weight_kg` from `exercise_sets`; optional `p_muscle_primary`)
- `get_sport_match_wins_leaderboard_v1` (wins with `sport_sessions`; optional `p_sport` filter — **replaced 5-arg overload** in `docs/migrations/ranking_training_metrics_leaderboard_v2.sql`; clients should pass `p_sport: null` or omit)
- `get_cardio_elevation_leaderboard_v1`, `get_cardio_duration_leaderboard_v1`, `get_cardio_best_pace_leaderboard_v1` (optional `p_min_distance_km`, default 1.0)
- `get_strength_total_reps_leaderboard_v1`, `get_strength_total_sets_leaderboard_v1`, `get_strength_max_set_weight_leaderboard_v1`
- `get_sport_duration_leaderboard_v1`, `get_sport_win_rate_leaderboard_v1` (optional `p_sport`, `p_min_matches` default 3)
- `get_duels_won_leaderboard_v1`
- `get_exercises_usage`
- `get_goal_stats` (totales agregados; ver [`docs/migrations/get_goal_stats_semantics_v1.sql`](migrations/get_goal_stats_semantics_v1.sql): `finished_goals` = completados, `missed_goals` = semana pasada sin completar, `finished_percent` = tasa de completitud)
- `get_goals_completed_leaderboard_v1`
- `get_period_training_compare_v1` (helpers internas `_period_training_compare_summary`, `_period_training_compare_breakdown`; ver `docs/migrations/period_training_compare_v1.sql`)
- `get_leaderboard_v1`
- `get_level_leaderboard_v1`
- `get_coins_leaderboard_v1` (`p_scope`, `p_limit`, `p_sex`, `p_age_band`) — ranking por `profiles.coins_balance`; sin periodo
- `get_pet_leaderboard_v1` (`p_metric`, `p_scope`, `p_limit`, `p_sex`, `p_age_band`) — rankings de mascotas, sin periodo (all-time). `p_metric`: `level`, `total_stats`, `health`, `strength`, `defense` (requieren mascota activa eclosionada), `battles`, `wins`, `losses`, `win_rate` (mín. 5 combates), `max_damage_dealt`, `max_damage_taken`, `total_damage_dealt`, `total_damage_taken` (de `pet_combat_user_stats`, requieren `total_battles > 0`). Devuelve `rank`, `user_id`, `username`, `avatar_url`, `value` (numeric; `win_rate` en %), `battles`, `pet_name` (custom o display name del tipo), `pet_level`
- `list_my_coin_transactions_v1` (`p_limit` default 20, max 50) — historial propio; `SECURITY DEFINER`
- `get_my_coin_sources_v1` (`p_start`, `p_end` timestamptz opcionales; ambos null = all-time) — agregación de monedas **ganadas** (`amount > 0`) por categoría (`source_key`); excluye backfills de economía; `SECURITY DEFINER`
- `clear_my_coin_history_v1` () — borra filas de `coin_transactions` del caller; **no** modifica `coins_balance`
- `get_workout_likes_received_leaderboard_v1`, `get_workout_comments_received_leaderboard_v1`, `get_group_workout_sessions_leaderboard_v1` (social / feed quality; published workouts in period)
- `get_achievements_unlocked_period_leaderboard_v1` (app metric **Achievements**; uses same workout-style period as other leaderboards). Optional in same migration file: `get_achievements_total_unlocked_leaderboard_v1` (no `p_period`) for ad-hoc / analytics, not wired in clients.
- `get_hyrox_best_official_time_leaderboard_v1`, `get_football_goals_leaderboard_v1`, `get_ski_distance_leaderboard_v1`
- `get_user_achievements`
- `toggle_tracked_achievement_v1` (`p_achievement_id` bigint) → `{ tracked, tracked_count }`; toggle seguimiento personal (máx. 5; solo logros no desbloqueados)
- `get_tracked_achievement_count_v1` (`p_user_id` uuid) → `{ count, top_progress_pct }`; resumen ligero para Home
- `get_user_prs` (`p_user_id`, optional `p_kind`, optional `p_search`) — profile/compare PR lists; bypasses own-only RLS via `SECURITY DEFINER` + authenticated read policies on PR tables; **excludes rows with `value <= 0`** (migration `20260718150000_prs_full_coverage_v1.sql`)
- `rebuild_strength_prs_for_user` (`p_user_id` uuid), `rebuild_endurance_prs_for_user` (`p_user_id` uuid), `rebuild_sport_prs_for_user` (`p_user_id` uuid) — delete + rescan PR tables from remaining workouts/sessions/sets
- `rebuild_endurance_prs_all` (), `rebuild_sport_prs_all` () — iterate users with cardio/sport workouts and call per-user rebuild
- Trigger `trg_workout_pr_rebuild_on_delete` (`AFTER DELETE ON workouts`) — rebuilds PRs for the deleted workout's owner and kind
- PR write helpers: `apply_cardio_session_prs`, `apply_sport_session_prs`; triggers `trg_cardio_pr_from_session`, `trg_sport_pr_from_session`, `trg_strength_pr_from_set`
- PR tables: `personal_records` (strength), `endurance_records` (cardio; key = `activity_code` when present), `sport_records` (sport); unified read view `vw_user_prs`
- `get_user_premium_status_v1` () → `boolean`; `auth.uid()` required; `true` iff a `user_subscriptions` row exists for the caller with `status in ('active','trialing')` and `expires_at > now()` (see migration above)
- `get_user_level`
- `get_weekly_goal_recommendation`
- `nutrition_diary_nutrient_total_v1` (`p_date` date, `p_nutrient` text) → `numeric`; suma diario de un nutriente del diario (ingredientes y recetas); `SECURITY DEFINER`; ver `20260526210000_nutrition_diary_nutrient_total_v1.sql`
- `nutrition_sex_offset_v1` (`p_sex` text) → `numeric`; Mifflin offset: **+5** (`male`/`m`), **−161** (`female`/`f`), **−80** (null, `prefer_not_to_say`, `other`, vacío)
- `nutrition_intense_training_days_per_week_v1` (`p_user_id` uuid) → `numeric`; días distintos de entreno intenso en 28 días ÷ 4.0; `state = published`; cuenta día si hay `kind` **strength** o **sport**, o **cardio** cuyo `title` no contiene `walk` / `caminata` (case-insensitive)
- `nutrition_workouts_per_week_v1` (`p_user_id` uuid) → `numeric`; alias de `nutrition_intense_training_days_per_week_v1` (días intensos/semana, no filas crudas)
- `nutrition_workout_weekly_volume_v1` (`p_user_id` uuid) → `(workouts_per_week, minutes_per_week)`; legacy v4 (analytics); ya no gobierna TDEE
- `nutrition_minutes_per_week_v1` (`p_user_id` uuid) → `numeric`; legacy v4 (analytics); ya no gobierna TDEE
- `nutrition_workout_activity_multiplier_v1` (`p_intense_days_per_week` numeric) → `numeric`; matriz por días intensos/semana: `≥ 5.5` → **1.725**; `≥ 3.5` → **1.55**; `≥ 1.5` → **1.375**; else → **1.2**
- `nutrition_compute_bmr_kcal_v1` (`p_sex`, `p_date_of_birth`, `p_height_cm`, `p_weight_kg`) → `integer`; Mifflin-St Jeor con imputación en lectura (no escribe perfil): `date_of_birth` null → edad **30**; altura/peso null o `≤ 0` → **175 cm / 75 kg** (male) o **162 cm / 60 kg** (female / no especificado); offset vía `nutrition_sex_offset_v1`; acotado 800–6000
- `nutrition_compute_dynamic_metabolic_target_v1` (`p_user_id`, `p_sex`, `p_date_of_birth`, `p_height_cm`, `p_weight_kg`) → `integer`; `round(BMR × nutrition_workout_activity_multiplier_v1(intense_days_per_week))`; acotado 800–6000
- `nutrition_resolve_base_calories_target_v1` (`p_user_id` uuid) → `integer`; si `base_calories_target_is_manual = true` → columna almacenada (800–6000, default 1700 si null); si no → `nutrition_compute_dynamic_metabolic_target_v1` con columnas del perfil
- Trigger `profiles_apply_metabolic_target` (`BEFORE INSERT OR UPDATE OF` `sex`, `date_of_birth`, `height_cm`, `weight_kg`, `base_calories_target`, `base_calories_target_is_manual`): en **UPDATE**, si cambian biometrías (`weight_kg`, `height_cm`, `date_of_birth`, `sex`) → `base_calories_target_is_manual := false` y recálculo con `nutrition_compute_dynamic_metabolic_target_v1(NEW.*)`; si no cambian biometrías y `is_manual = true` → conserva `NEW.base_calories_target`; si no manual → recálculo automático. **INSERT**: auto-calcula solo si `is_manual = false`. Ver `20260528180000_nutrition_metabolic_biometric_auto_unlock_v1.sql`.
- Trigger `trg_workouts_sync_metabolism` (`AFTER INSERT OR UPDATE OR DELETE ON workouts`): actualiza `profiles.base_calories_target` vía `nutrition_resolve_base_calories_target_v1` solo si `is_manual = false`
- `refresh_profile_metabolic_target_v1` (`p_user_id` uuid) → `integer`; recalcula y persiste para usuario no manual (p. ej. tras `body_weight_entries` / `refresh_profile_weight_kg`)
- `refresh_all_profile_metabolic_targets_v1` () → `integer` (filas actualizadas); batch no manual; job `pg_cron` `refresh_profile_metabolic_targets_daily` 03:05 UTC. Ver `20260528140000_nutrition_metabolic_auto_refresh_v1.sql`, motor v5 `20260528210000_nutrition_metabolic_intense_days_v5.sql`
- `get_daily_nutrition_recommendation_v1` (`p_date` date, default `current_date`) → `jsonb` con totales consumidos (kcal, proteína, carbs, grasa, grasa saturada, azúcares, fibra, sodio mg), `base_calories_target` (**valor resuelto**: TDEE sedentario o override manual), `total_calories_burned_active`, `remaining_calories` (= `net_calories_balance` = `base_calories_target + burned − consumed`), `recommendation_text`; `SECURITY DEFINER`; agregación vía `nutrition_diary_nutrient_total_v1`; ver `20260526200000_nutrition_daily_balance_metabolic_fix_v1.sql`, `20260526250000_nutrition_bmr_mifflin_st_jeor_v1.sql`, `20260528120000_nutrition_tdee_mifflin_st_jeor_v2.sql`
- `get_nutrition_month_balance_v1` (`p_month` date — primer día del mes) → `jsonb` array de `{ log_date, meal_log_count, remaining_calories }` por cada día del mes con entradas en `nutrition_diary_logs`; `remaining_calories` vía `get_daily_nutrition_recommendation_v1` (misma lógica BMR + actividad que el tab diario); calendario cliente: naranja si `remaining_calories ≥ 0`, rojo si `< 0`; ver `20260526260000_nutrition_month_calendar_balance_v1.sql`
- `accept_meal_plan` (`p_target_id` uuid) → `void`; invitee; `pending` → `accepted` + `accepted_at`; errores: `NOT_AUTHENTICATED`, `TARGET_NOT_FOUND`, `FORBIDDEN`, `INVALID_STATUS`
- `reject_meal_plan` (`p_target_id` uuid) → `void`; invitee; `pending` o `accepted` → `rejected` (no desde `eaten`); ver `20260531150000_nutrition_meal_plan_per_user_v1.sql`
- `update_meal_plan_target` (`p_target_id` uuid, `p_quantity_g` numeric, `p_meal_slot` text opcional) → `void`; solo `target_user_id = auth.uid()`; `status in ('pending','accepted')`; actualiza `quantity_g` y opcionalmente `nutrition_meal_plans.meal_slot` del plan del target; errores: `NOT_AUTHENTICATED`, `TARGET_NOT_FOUND`, `FORBIDDEN`, `INVALID_STATUS`, `INVALID_QUANTITY`
- `complete_meal_plan_as_eaten` (`p_target_id` uuid) → `uuid` (id del nuevo `nutrition_diary_logs`); solo `target_user_id = auth.uid()`; requiere `accepted`; food desde `coalesce(target.ingredient_id, plan.ingredient_id)` / receta análoga; inserta diario y marca `eaten`; errores adicionales: `ALREADY_EATEN`, `PLAN_NOT_FOUND`; ver `20260531120000` + `20260531150000`
- `get_smart_nutrition_recommendation_v1` (`p_start_date` date, `p_end_date` date) → `jsonb` con análisis multi-día, alertas heurísticas y promedios diarios; ventana máxima 70 días inclusive (cap silencioso en servidor); `SECURITY DEFINER`; alertas y narrativa en inglés con ejemplos de alimentos embebidos en el texto; ver `20260528260000_smart_nutrition_food_recommendations_v10.sql`
- `get_nutrition_highlights_v1` () → `jsonb` all-time personal stats from `nutrition_diary_logs` (same kcal math as smart recommendation); `SECURITY DEFINER`; ver `20260603120000_nutrition_highlights_v1.sql`. Response:
  - `days_logged`, `total_log_entries`, `first_log_date`, `last_log_date` (ISO `yyyy-MM-dd` or null)
  - `avg_kcal_per_logged_day` (numeric)
  - `peak_day`: `{ date, kcal }` or null (tie: latest date)
  - `peak_meal_slot`: `{ date, meal_slot, kcal }` or null (sum per day+slot; tie: latest date)
  - `most_used_meal_slot` (text or null)
  - `top_ingredient` / `top_recipe`: `{ id, name, log_count, total_kcal }` or null
  - `top_ingredients` / `top_recipes`: arrays (max 3) of same object shape
  - `recipe_log_share_percent` (0–100)
  - `macro_champions`: `{ top_protein_source, top_carb_source }` each `{ name, total_g }` or null (absolute grams from diary logs; recipes use weighted ingredient density)
  - `calorie_volatility`: `{ weekday_avg_kcal, weekend_avg_kcal }` (Mon–Fri vs Sat–Sun daily kcal averages on logged days)
  - `heaviest_meal`: `{ date, meal_slot, total_weight_g }` or null (max sum of `quantity_g` per day+meal slot)
  - `consistency_streak`: `{ current_streak, best_streak }` (consecutive log days; current ends at latest log if within 1 day of today)
  - Advanced fields: migration `20260604120000_nutrition_highlights_advanced_v1.sql`
- `get_nutrition_ranking_v1` (`p_ranking_type` text, `p_limit` int, `p_offset` int) → `setof jsonb` paginated all-time rankings from `nutrition_diary_logs` (same kcal/weight math as highlights); `SECURITY DEFINER`; `p_limit` clamped 1–100; ver `20260605120000_nutrition_rankings_v1.sql`. Supported `p_ranking_type`:
  - `highest_calorie_days` — unique dates by total kcal desc
  - `highest_calorie_meals` — unique `(log_date, meal_slot)` by total kcal desc
  - `most_logged_ingredients` — by log count desc, total kcal tiebreak
  - `most_logged_recipes` — by log count desc, total kcal tiebreak
  - `heaviest_meals` — unique `(log_date, meal_slot)` by total `quantity_g` desc
  - Each row: `{ rank_position, title, subtitle, value_numeric, unit_label, metadata_json }` (`unit_label`: `kcal` | `g` | `times`)
- `list_comparable_workouts_v1`
- `list_compare_average_pool_v1` (`p_baseline_workout`, `p_scope` `mine`|`global`, `p_limit`) → `workout_id`, `started_at` for compare-average pools (cardio activity / sport / strength exact primary-muscle set); see `Liftr/supabase/migrations/20260521120000_compare_average_pool_v1.sql`
- `get_home_feed_page_v1` (`p_page`, `p_page_size`, optional `p_kind`) → JSON `{ workouts, scores, likes, participants }` for authenticated home feed (one round-trip); see `Liftr/supabase/migrations/20260522140000_disk_io_optimizations_v1.sql`
- `is_workout_shared_with_user` (`p_workout_id`, optional `p_user_id`) → `boolean`; `true` when the user is a `conversation_participants` member of a non-deleted `workout_share` message referencing that workout (recipient only). Used by RLS `*_select_workout_share` on `workout_exercises`, `exercise_sets`, `cardio_sessions`, `sport_sessions` so chat recipients can read detail rows for shared drafts without exposing followees’ `planned` workouts on Home; see `20260526240000_workout_share_detail_read_v1.sql`
- `plan_strength_squad_programs`
- `precheck_signup`
- `recompute_weekly_goal_results`
- `record_search`
- `review_competition_workout`
- `rpc_create_competition` (`p_opponent_id`, `p_time_limit_at` opcional, `p_metric` `workouts`|`calories`|`score`, `p_target_value` opcional, `p_expire_hours` default 48, `p_bet_amount` default 0) → `bigint` competition id; `SECURITY DEFINER`; valida `p_bet_amount <= LEAST(creator.coins_balance, opponent.coins_balance)`; si `p_bet_amount > 0` escolta monedas del creador y fija `invite_expires_at` a 7 días; ver [`20260612120000_competition_bet_escrow_v1.sql`](../Liftr/supabase/migrations/20260612120000_competition_bet_escrow_v1.sql)
- `accept_competition` (`p_competition_id`) — escolta rival si `bet_amount > 0`; `SECURITY DEFINER`
- `decline_competition` (`p_competition_id`) — reembolso creador vía trigger de liquidación
- `cancel_competition_invite` (`p_competition_id`) — solo creador, `pending`
- `competition_get_max_bet_v1` (`p_opponent_id`) → `integer` techo de apuesta para el caller
- `get_my_competition_escrow_summary_v1` () → JSON `{ escrowed_total, pending_count, active_staked_count, staked_challenge_count }`
- `expire_stale_competition_invites_v1` () → `integer` filas expiradas (`invite_expires_at` pasado)
- `start_workout_v1` (`p_workout_id`, `p_started_at` opcional ISO8601) → JSON del workout con `started_at` y `ended_at` limpiado; owner o participante; idempotente ante reintentos
- `submit_workout_to_competition`
- `trending_search_queries_24h`
- `update_sport_workout_v2`
- `user_search_recent_list`
- `create_segment_from_workout_v1` (`p_workout_id`, `p_name`, `p_start_fraction`, `p_end_fraction`, `p_buffer_m` opcional) → `uuid` del segmento; requiere cardio publicado, dueño autenticado y `route_geojson` válido ([`segments_mvp_v1.sql`](migrations/segments_mvp_v1.sql)). Tras aplicar [`segments_mvp_v3_owner_dup_delete.sql`](migrations/segments_mvp_v3_owner_dup_delete.sql): si ya existe un segmento **publicado** geométricamente muy parecido, la función hace `RAISE EXCEPTION` con mensaje `duplicate_segment` y **`HINT`** = UUID del existente (el cliente puede abrir ese detalle). Tras [`segments_mvp_v4_segment_create_backfill_intersecting.sql`](migrations/segments_mvp_v4_segment_create_backfill_intersecting.sql): tras insertar el segmento, la BD re-matchea también otros **cardio publicados** cuya ruta está a distancia ≤ `greatest(buffer_m*3, 200)` m del nuevo segmento (`ST_DWithin`), llamando a la misma lógica que al publicar (`_match_segments_for_workout_internal` por `workout_id`).
- `get_segment_detail_v1` (`p_segment_id`) → fila con `id`, `name`, `buffer_m`, `status`, `geojson` (LineString WGS84 como texto GeoJSON); con v3 también `created_by`, `foreign_efforts_count` (efforts con `user_id` distinto del creador). Tras [`segments_mvp_v6_segment_detail_stats.sql`](migrations/segments_mvp_v6_segment_detail_stats.sql): `segment_length_m`, `center_lat`, `center_lon` (punto medio del eje), `leaderboard_effort_count`, `leaderboard_athlete_count` (solo cardio publicado, mismo criterio que el ranking), `confidence_avg` / `confidence_min` / `confidence_max`, `viewer_best_elapsed_sec` y `viewer_best_workout_id` (mejor esfuerzo del `auth.uid()` actual, o `NULL` si anónimo / sin match). Tras [`Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql`](../Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql): las agregadas `confidence_*` reflejan **`route_coverage`** (solapamiento del eje del segmento con la ruta, 0–1) solo entre esfuerzos que cumplen el umbral de ranking (≥0.95 salvo el `source_workout_id`).
- `update_my_segment_name_v1` (`p_segment_id`, `p_name`) → solo el dueño (`created_by` = `auth.uid()`); renombra el segmento.
- `delete_my_segment_v1` (`p_segment_id`) → solo el dueño y solo si **no** hay efforts de otros usuarios en ese segmento (equivalente a `foreign_efforts_count == 0`); borra segmento y efforts asociados según definición en SQL.
- `get_segment_leaderboard_v1` (`p_segment_id`, `p_limit` opcional) → filas con `rank`, `user_id`, `username`, `avatar_url`, `elapsed_sec`, `workout_id`, `matched_at`, `effort_at` (fecha del entreno: `COALESCE(started_at, created_at)`), `confidence` (métrica legacy del matcher si existe), **`route_coverage`** (0–1, solapamiento eje–ruta) e **`is_source_workout`** (bool). Tras [`segments_mvp_v5_leaderboard_cap.sql`](migrations/segments_mvp_v5_leaderboard_cap.sql): como mucho **10 efforts por usuario** (los mejores tiempos de cada uno), luego ranking global por `elapsed_sec`; solo cardio `published`. Tras [`Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql`](../Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql): solo entran esfuerzos con **`route_coverage` ≥ 0.95** o el entreno **`source_workout_id`** del segmento (forzado a 1.0); `segments` guarda `source_workout_id` y fracciones de creación.
- `list_segments_near_v1` (`p_lat`, `p_lon`, `p_radius_m` opcional, `p_limit` opcional) → segmentos publicados en radio
- `search_segments_v1` (`p_query`, `p_limit` opcional) → `id`, `name`, `buffer_m` (solo `published`; `p_query` normalizado, mínimo 2 caracteres)
- `list_my_segments_v1` (`p_limit` opcional) → segmentos creados por `auth.uid()` (`id`, `name`, `buffer_m`, `status`, `created_at`); solo `authenticated`
- `list_segments_popularity_leaderboard_v1` (`p_period` como otros rankings: `day`/`week`/`month`/`all`, `p_limit` opcional) → `rank`, `segment_id`, `name`, `efforts_count`, `buffer_m` (conteo de `segment_efforts` con workout publicado en la ventana por `matched_at`)
- `match_segment_efforts_for_workout_v1` (`p_workout_id`) → reprocesa matching para el dueño (misma lógica que el trigger al publicar)
- `get_recommended_expansion_cells_v1` (`p_user_id`, `p_current_lat`, `p_current_lng`, `p_radius_meters` opcional) → hasta 10 celdas sugeridas para expansión de territorio (`cell_id`, `cell_geojson`, `weight_priority`); ver sección **Territory (map game)**
- Tras [`segments_mvp_v7_segment_rank_notifications.sql`](migrations/segments_mvp_v7_segment_rank_notifications.sql): el matching interno llama a **`create_notification`** existente (`_user_id`, `_type`, `_title`, `_body`, `_data`) para insertar en **`notifications`** (mismo pipeline `send-notifications` + FCM). Tipos: **`segment_you_are_first`**, **`segment_lost_first`** (solo pérdida del 1º cuando el nuevo líder es el effort del `workout_id` recién matcheado). `data` incluye al menos `segment_id`, `segment_name`; en `segment_lost_first` también `overtaker_user_id`, `overtaker_username` (y `notification_id` si lo añade vuestra `create_notification`).
- `list_active_challenges_v1` () → retos con instancia activa (`instance_id`, `template_code`, `title`, `description`, `cadence` = `week` | `month` | `once`, `period_start`, `period_end`, `max_winners`, `claims_count`, `metric_kind`, `threshold_numeric`, `threshold_secondary`, `challenge_category` = `cardio` | `strength` | `sport`, `scope_activity_code`, `scope_sport`, `scope_muscle_primary` opcionales, más `viewer_rank` y `viewer_claimed` para `auth.uid()` en esa instancia). **VOLATILE** como arriba.
- `get_challenge_instance_detail_v1` (`p_instance_id` uuid) → una fila con meta del reto + `viewer_rank`, `viewer_claimed`, `viewer_workout_id` para `auth.uid()`. Misma nota **VOLATILE** que la lista.
- `get_challenge_instance_leaderboard_v1` (`p_instance_id`, `p_limit` opcional) → `rank`, `user_id`, `username`, `avatar_url`, `adjudication_ts`, `workout_id`.
- `get_challenge_my_progress_v1` (`p_instance_id`) → progreso del viewer hacia el umbral (`progress_value`, `target_value`, `secondary_cap`, `metric_kind`, `is_eligible`).
- `get_challenge_podiums_period_leaderboard_v1` (`p_scope` `global` | `friends`, `p_period` `day` | `week` | `month` | `all`, `p_limit`, `p_sex`, `p_age_band`) → `rank`, `user_id`, `username`, `avatar_url`, `podium_count` (claims con `adjudication_ts` en la ventana; mismo patrón demográfico que otros leaderboards por periodo).
- `evaluate_challenges_for_user` (`p_user_id` uuid) — **no** expuesto a `authenticated` en el SQL de referencia; se invoca vía trigger al pasar un `workout` a `published` (y opcionalmente `service_role` para replays).

## Cardio import deduplication (`create_cardio_workout_v2`)

Migración: [`Liftr/supabase/migrations/20260522160000_cardio_workout_dedupe_v1.sql`](../Liftr/supabase/migrations/20260522160000_cardio_workout_dedupe_v1.sql).

- **`workouts.healthkit_uuid`**: id externo estable (Apple Health HK UUID en minúsculas; Health Connect en Android como `hc:{metadata.id}`). Índice único parcial `(user_id, healthkit_uuid)` donde `healthkit_uuid` no es null.
- Antes de insertar, `find_cardio_workout_duplicate` busca por UUID o por coincidencia difusa (misma actividad compatible, `started_at` ±5 min, duración ±10% o ±90s).
- Si hay candidato, `merge_cardio_workout_from_import` enriquece el entreno existente (HR, ruta, calorías HealthKit, `healthkit_uuid`, stats) sin sobrescribir título/notas/distancia ya rellenados.
- El RPC sigue devolviendo `integer` (id del workout); clientes iOS detectan merge por `created_at` antiguo (>120s).

## Wearable GPS route sync (Garmin / external)

Migración: [`Liftr/supabase/migrations/20260608120000_wearable_route_jobs_v1.sql`](../Liftr/supabase/migrations/20260608120000_wearable_route_jobs_v1.sql).

- **`wearable_connections`**: tokens OAuth por `user_id` + `provider` (`garmin` | `fitbit` | `polar`). Escritura solo vía Edge Functions (`service_role`); el cliente autenticado puede `select` la fila propia.
- **`external_workout_route_jobs`**: cola de rutas GPS normalizadas (`route_points` jsonb). Unique `(user_id, provider, provider_activity_id)`. Estados: `pending`, `applied_healthkit`, `applied_liftr`, `skipped`, `failed`.
- **`apply_external_route_to_cardio_workout`**: rellena `cardio_sessions.route_geojson` solo si está vacío; usa `find_cardio_workout_duplicate` con `p_healthkit_uuid` y ventana temporal. No modifica calorías.
- **`update_external_route_job_status`**: el cliente iOS marca jobs tras escribir `HKWorkoutRoute` en HealthKit.
- Edge Functions: `wearable-oauth-start` (JWT), `wearable-oauth-callback`, `garmin-activity-webhook` (`verify_jwt = false`). Setup: [`docs/garmin-connect-developer-setup.md`](garmin-connect-developer-setup.md).

## Retos (Challenges MVP)

- **Diferencia vs logros:** los logros son hitos personales permanentes (`achievements` / `user_achievements`). Los retos son **eventos de ventana** con **plazas limitadas** (`max_winners`) e instancias por `period_start` / `period_end`. La plantilla define **`cadence`**: `week`, `month` o `once` (ventana larga para retos tipo evergreen).
- **Diferencia vs metas semanales:** `weekly_goals` es objetivo **solo para ti**. Los retos comparan orden de cumplimiento **en comunidad** (clasificación por `challenge_claims`).
- **Diferencia vs duelos:** `competitions` es 1:1; los retos del MVP son **globales** en la instancia.
- **`challenge_templates` (ámbitos opcionales):** `scope_activity_code` filtra cardio por `coalesce(cardio_sessions.activity_code, modality)`; `scope_sport` filtra por `sport_sessions.sport`; `scope_muscle_primary` restringe líneas de fuerza a `exercises.muscle_primary` vía `_challenge_muscle_matches` (pares ES/EN del catálogo); `scope_stat_key` (`goals`, `points`, `tries`) con `cumulative_sport_scoring_stat`.
- **Reglas híbridas por `metric_kind`** (ver [`challenges_mvp_v1.sql`](migrations/challenges_mvp_v1.sql) + `20260618194500_challenges_full_coverage_v1.sql`):
  - `cumulative_cardio_km` — suma km cardio en ventana (con filtro de actividad si hay `scope_activity_code`).
  - `single_set_max_kg` — primera publicación con serie ≥ umbral kg (filtro músculo opcional).
  - `cardio_session_pace_gate` — sesión que cumple distancia y tope de `duration_sec` (filtro actividad opcional).
  - `cumulative_sport_sessions` — cuenta sesiones sport publicadas (filtro `scope_sport` opcional vía join `sport_sessions`).
  - `cumulative_strength_workouts` — cuenta entrenos fuerza publicados.
  - `cumulative_strength_reps` / `cumulative_strength_sets` / `cumulative_strength_volume_kg` — acumulado de reps, de series con carga, o de volumen kg (reps × kg) en orden cronológico; filtro músculo opcional.
  - `single_set_max_reps` — primera publicación con alguna serie con reps ≥ umbral.
  - `strength_workouts_touching_muscle` — primero en alcanzar N entrenos de fuerza distintos que incluyan al menos un ejercicio con `muscle_primary` = `scope_muscle_primary` (requiere scope).
  - `cumulative_elevation_gain_m` — suma `elevation_gain_m` / `elev_gain_m` en cardio (filtro actividad opcional).
  - `hyrox_official_time_gate` — sesión Hyrox con `official_time_sec` ≤ `threshold_secondary`.
  - `cumulative_climbing_routes_sent` — suma `routes_sent` en sesiones climbing.
  - `cumulative_ski_distance_km` — suma `total_distance_km` en sesiones ski.
  - `cumulative_sport_scoring_stat` — suma goals/points/tries según `scope_sport` + `scope_stat_key`.
  - `cardio_session_rowerg_split_gate` — sesión rowerg con distancia ≥ umbral y `split_sec_per_500m` ≤ secundario (JSON en `cardio_session_stats`).
- **Notificación:** tipo **`challenge_won`** (legacy **`challenge_won_weekly`**) con `data.challenge_instance_id`, `template_code`, `workout_id` vía `create_notification`; misma cola **`send-notifications`** + FCM. Los clientes aceptan ambos tipos.

## Achievements (contrato cliente y operación en BD)

### Uso en app

- Los clientes **no** hacen `select` crudo al catálogo en el flujo de UI: llaman al RPC `get_user_achievements` con `p_user_id` (uuid) y reciben filas con al menos: `achievement_id`, `code`, `title`, `description`, `category`, `icon_url`, `user_id`, `unlocked_at`, `is_unlocked`. Tras aplicar [get_user_achievements_extend_progress_v1.sql](migrations/get_user_achievements_extend_progress_v1.sql), el RPC puede incluir también `requirement_type`, `requirement_value`, `progress_current`, agregados opcionales `community_pct_unlocked` / `community_sample_size`, y desde `20260714120000_tracked_achievements_v1.sql` también **`is_tracked`** (boolean).
- **Seguimiento personal (tracked):** tabla `user_tracked_achievements` (`user_id`, `achievement_id`, `tracked_at`); máximo **5** filas activas por usuario; RPC **`toggle_tracked_achievement_v1(p_achievement_id)`** → `{ tracked, tracked_count }`; RPC **`get_tracked_achievement_count_v1(p_user_id)`** → `{ count, top_progress_pct }` para el pill de Home; al insertar en `user_achievements` un trigger elimina la fila tracked correspondiente (auto-untrack al desbloquear).
- `check_and_unlock_achievements_for` con el mismo `p_user_id` recalcula desbloqueos; también puede invocarse vía **triggers** al crear workouts, seguir, like, comentar, etc. (ver definición y triggers en el proyecto Supabase).
- Mapeo de **icono por prefijo de `code` y categoría** (sustituto local si `icon_url` falla o es nulo): iOS en `Liftr/AchievementsGridView.swift` (`symbolForAchievement`, `prettySubtype`), Android en `ui/achievements/AchievementSymbol.kt`. Convención recomendable para códigos nuevos: `disciplina_umbral` (p. ej. `ski_distance_50k`) alineada con el resto de prefijos de catálogo.
- **Categorías de filtro en app:** `general`, `strength`, `cardio`, `sport`, `social`, `streak`, `ranking`, **`pet`**, **`coins`** (iOS `CategoryFilter`, Android `AchievementCategoryFilter`).

### Pet & Coins achievements (migración `20260628120000_pet_coin_achievements_v1.sql`)

- **32 filas** de catálogo: 20 `pet_*` + 12 `coins_*`.
- **Desbloqueo:** `unlock_pet_achievements(p_user_id)` y `unlock_coin_achievements(p_user_id)`, invocados desde `check_and_unlock_achievements_for` y triggers:
  - `trg_achievements_on_coin_tx` → `coin_transactions` (INSERT, `amount > 0`)
  - `trg_achievements_on_pet_log` → `pet_logs` (INSERT)
  - `trg_achievements_on_pet_instance` → `pet_instances` (INSERT/UPDATE de `total_feedings`, `current_level`, `evolution_stage`, `rarity`, `reroll_count`)
  - `trg_achievements_on_pet_combat_stats` → `pet_combat_user_stats` (INSERT/UPDATE)
  - `trg_achievements_on_profile_energy` → `profiles` (UPDATE de `max_energy`)
- **Progreso en UI:** `get_user_achievements` delega en `liftr_achievement_progress_current` para códigos `pet_*` y `coins_*`.
- **Coins lifetime earned:** `liftr_user_lifetime_coins_earned` — suma de `coin_transactions.amount > 0` excluyendo backfills vía `liftr_coin_source_key() IS NOT NULL`.
- **Verify:** [`Liftr/supabase/verify/pet_coin_achievements_v1.sql`](../Liftr/supabase/verify/pet_coin_achievements_v1.sql).

Códigos `pet_*` principales: `pet_incubation_first`, `pet_hatched_first`, `pet_feed_10`, `pet_feed_100`, `pet_evolve_kid`, `pet_evolve_teen`, `pet_evolve_adult`, `pet_evolve_elder`, `pet_level_50`, `pet_level_100`, `pet_rarity_rare`, `pet_rarity_epic`, `pet_rarity_mythic`, `pet_combat_first`, `pet_combat_wins_10`, `pet_combat_streak_5`, `pet_combat_all_rarities`, `pet_combat_all_species`, `pet_combat_all_stages`, `pet_coins_passive_1000`, `pet_workout_bonus_10`, `pet_egg_reroll_5`, `pet_energy_max_7`.

Códigos `coins_*` principales: `coins_earned_first`, `coins_earned_100`, `coins_earned_500`, `coins_earned_1000`, `coins_earned_5000`, `coins_earned_10000`, `coins_earned_25000`, `coins_earned_50000`, `coins_workouts_1000`, `coins_social_500`, `coins_nutrition_500`, `coins_pet_sources_1000`.

### HYROX achievements (migración `20260715130000_hyrox_achievements_sport_path_v1.sql`)

- **5 filas** de catálogo: `hyrox_sessions_1`, `hyrox_sessions_5`, `hyrox_sessions_10`, `hyrox_days_7`, `hyrox_days_30` (categoría `cardio` en catálogo; desbloqueo vía `unlock_hyrox_achievements`).
- **Fuente de datos:** sesiones **sport** publicadas con `sport_sessions.sport = 'hyrox'` (`workouts.state = 'published'`). La app registra Hyrox como deporte, no como cardio; el contador también incluye filas legacy en `cardio_sessions` con `activity_type` / `activity_code = 'hyrox'` si existieran.
- **Desbloqueo:** `unlock_hyrox_achievements(p_user_id)`, invocado desde `check_and_unlock_achievements_for` y triggers en `sport_sessions` / `workouts`. No filtra por `match_result` (p. ej. `unfinished` cuenta).
- **Progreso en UI:** `get_user_achievements` expone `progress_current` para códigos `hyrox_sessions_*` (conteo de sesiones) y `hyrox_days_*` (días UTC distintos).
- **Verify:** [`Liftr/supabase/verify/hyrox_achievements_sport_path_v1.sql`](../Liftr/supabase/verify/hyrox_achievements_sport_path_v1.sql).

### Inspección en Supabase (sin migraciones en este repo)

- Script SQL listo para el SQL Editor: [achievements-supabase-inspection.sql](achievements-supabase-inspection.sql) (estructura de tablas, catálogo, progreso por usuario, `pg_get_functiondef` de las dos funciones, triggers, estadística opcional de desbloqueos).

### Ideas de ampliación (validar siempre con el SQL de `check_and_unlock_achievements_for`)

- **Competiciones** (`competition_workouts`, `competitions`): primer envío, N envíos, o hitos de organización.
- **Metas semanales** (`weekly_goals`, `weekly_goal_results`): rachas o hitos de cumplimiento.
- **Deportes** con tablas de stats ya en contrato (p. ej. `handball_session_stats`, `hockey_session_stats`, `ski_session_stats`, `rugby_session_stats`, `racket_session_stats`): códigos `handball_`, `hockey_`, `ski_`, `racket_`… o meta-logros de volumen por vertical.
- **Ecosistema**: `feature_request_*` (p. ej. primer voto/comentario), importación Health, si se desea; cada uno requiere que la función o un trigger tenga en cuenta el evento.

Añadir filas a `achievements` o cambiar triggers sin actualizar `check_and_unlock_achievements_for` no desbloqueará nada: la lógica vive en la base de datos.

## Cobertura Android actual (fase auth)

- Tabla: `profiles` (incl. `base_calories_target` integer, default 2000 — override manual cuando `base_calories_target_is_manual`; BMR automático vía `nutrition_resolve_base_calories_target_v1` cuando `is_manual = false`)
- RPC: `precheck_signup`

Implementadas en:

- `android/app/src/main/java/com/lilru/liftr/auth/AuthViewModel.kt`

## Inicio de entreno en vivo (`start_workout_v1`)

- iOS y Android marcan `started_at` en el cliente al pulsar **Start** y abren la pantalla activa sin esperar la red.
- El RPC se encola y reintenta (≈0.5s / 2s / 5s) hasta éxito o error no recuperable; `p_started_at` puede llegar unos segundos antes que el ack del servidor.
- El programa de fuerza (ejercicios + series) se cachea al cargar el detalle y rehidrata la pantalla activa si la segunda lectura falla.
- Dual/grupo: si `create_linked_strength_workout_copy` falla, el cliente ofrece **Start solo** / **Start offline** además de reintentar.

## Fin de entreno en vivo (`finish_strength_workout_v1`)

- iOS y Android llaman al RPC **`finish_strength_workout_v1`** con `p_workout_id`, `p_ended_at`, `p_paused_sec`, `p_exercises` (todas las filas `workout_exercises` del host, incluidas las que no tienen series realizadas) y `p_linked` opcional para dual/trio.
- Si la red falla de forma recuperable, el cliente encola el mismo payload (`WorkoutFinishSync` en Android; `WorkoutFinishSync` en iOS), muestra un toast y cierra la pantalla activa.
- Los errores de **carga** del programa siguen bloqueando solo cuando no hay caché local; los errores de **finish** no reemplazan la UI del entreno en curso.

### Purga de series/ejercicios incompletos al finalizar

Migración: [`Liftr/supabase/migrations/20260527120000_strength_workout_finish_purge_v1.sql`](../Liftr/supabase/migrations/20260527120000_strength_workout_finish_purge_v1.sql).

- Columna **`exercise_sets.is_completed`** (`boolean NOT NULL DEFAULT false`): las series insertadas por el finish RPC se marcan `true`; las plantillas del entreno en curso permanecen `false`.
- **`_liftr_finish_strength_workout_core`**: tras `_liftr_replace_strength_exercise_sets`, ejecuta `_liftr_purge_incomplete_strength_workout` (borra series con `is_completed = false` y ejercicios sin series).
- **Trigger** `purge_incomplete_strength_on_workout_finalize` en `workouts` (`BEFORE UPDATE OF ended_at`): red de seguridad cuando `ended_at` pasa de NULL a NOT NULL en entrenos `strength`.
- Finalización = `ended_at` establecido + `state` `planned` → `published` (sin columna `status = completed`).

### Confirmación en cliente

- Antes de finalizar, iOS y Android calculan localmente ejercicios/series sin marcar y muestran aviso dinámico (ES: *"Tienes N ejercicios y M series sin terminar…"*).
- Si todo está completo, se usa el texto estándar de confirmación o finalización directa.

## Premium subscriptions

Migración: [`Liftr/supabase/migrations/20260524140000_user_subscriptions_premium_v1.sql`](../Liftr/supabase/migrations/20260524140000_user_subscriptions_premium_v1.sql).

### Client entitlement

- iOS y Android **no** persisten `isPremium` localmente para gating de anuncios/UI.
- Tras login o refresh de sesión, llamar al RPC `get_user_premium_status_v1` (sin parámetros) y cachear el boolean en estado global (`AppState` / `PremiumStatusStore`).
- StoreKit (iOS) y Play Billing (Android) siguen gestionando compra/restauración en UI; el acceso premium efectivo depende de la fila en `user_subscriptions`.

### Edge function `process-billing-webhook`

- Ruta: `Liftr/supabase/functions/process-billing-webhook/`
- Config local: `[functions.process-billing-webhook] verify_jwt = false` en `Liftr/supabase/config.toml` (los webhooks de tienda no envían JWT de Supabase).
- Secreto: variable de entorno `BILLING_WEBHOOK_SECRET` en el proyecto Supabase (Edge secrets).
- Autenticación del request: header `X-Billing-Signature: <secret>` **o** `Authorization: Bearer <secret>` (comparación constant-time).
- Cuerpo JSON normalizado (adaptadores Apple ASSN v2 / Google RTDN pueden transformar al formato interno antes de POST):

```json
{
  "user_id": "<uuid>",
  "status": "active",
  "provider": "apple",
  "original_transaction_id": "<store original transaction id>",
  "expires_at": "2026-06-24T12:00:00.000Z"
}
```

- `status`: `active` | `trialing` | `canceled` | `expired`
- `provider`: `apple` | `google`
- Upsert en `user_subscriptions` con `onConflict: user_id` (service role); actualiza `status`, `provider`, `original_transaction_id`, `expires_at`, `updated_at`.

### Apple App Store Server Notifications (V2)

- Función dedicada: `process-apple-app-store-notification` (no usar `process-billing-webhook` en App Store Connect).
- URL de ejemplo (proyecto `rjzhaafvkxmvlnpsikbi`):  
  `https://rjzhaafvkxmvlnpsikbi.supabase.co/functions/v1/process-apple-app-store-notification`
- Apple envía `{ "signedPayload": "<JWS>" }`. El handler decodifica la transacción y usa `appAccountToken` como `user_id` (UUID de Supabase Auth, fijado en iOS con `Product.PurchaseOption.appAccountToken` al comprar).
- Guía paso a paso en App Store Connect: [`docs/apple-premium-webhook-setup.md`](apple-premium-webhook-setup.md).

### Operación en producción

1. Configurar **App Store Server Notifications v2** (URL anterior) y **Google Play Real-time developer notifications** (adaptador → `process-billing-webhook` con secreto compartido).
2. Definir `BILLING_WEBHOOK_SECRET` y usar el mismo valor en el verificador de la tienda o en el proxy que reenvía eventos.
3. Tras desplegar la migración, verificar con `curl` en staging:

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/process-billing-webhook" \
  -H "Content-Type: application/json" \
  -H "X-Billing-Signature: $BILLING_WEBHOOK_SECRET" \
  -d '{
    "user_id": "<auth-users-uuid>",
    "status": "active",
    "provider": "apple",
    "original_transaction_id": "test-txn-001",
    "expires_at": "2099-01-01T00:00:00.000Z"
  }'
```

Luego, con sesión de ese usuario, `get_user_premium_status_v1` debe devolver `true`.

## Territory (map game)

Migraciones: `Liftr/supabase/migrations/20260513140000_territory_capture_v1.sql` y sucesivas (hex capture, municipios, map RPC).

### Tablas principales

- `territory_cells` — hexágonos capturados (`cell_id`, `cell_geog`, `owner_user_id`, `city_key`, …). Solo lectura para clientes; escritura vía RPC `apply_territory_capture_v1`.
- `territory_municipalities` — límites municipales (`city_key`, `boundary_geom`, `total_capture_cells`, …).
- `territory_capture_events`, `territory_capture_takeovers` — historial y eventos sociales.

### RPC `get_recommended_expansion_cells_v1`

Sugiere hasta **10** celdas hex prioritarias cerca de la posición del atleta para ampliar territorio (zonas calientes).

| Parámetro | Tipo | Default | Notas |
|-----------|------|---------|-------|
| `p_user_id` | uuid | — | Debe coincidir con `auth.uid()` |
| `p_current_lat` | double | — | WGS84 |
| `p_current_lng` | double | — | WGS84 |
| `p_radius_meters` | double | `12000` | Acotado en servidor a 500–25000 m; clientes deben enviar ~radio del viewport del mapa |

**Filas de respuesta:**

```json
{
  "cell_id": "12345:67890",
  "cell_geojson": { "type": "Polygon", "coordinates": [[[lon, lat], ...]] },
  "weight_priority": 1
}
```

- `weight_priority` **1**: celdas en municipios donde el usuario ya tiene capturas pero **no** es líder de ciudad (celdas enemigas; prioriza las del líder actual).
- `weight_priority` **2**: frontera adyacente (`st_touches`) a celdas del usuario — sin capturar (no existen en `territory_cells`) o propiedad de otro jugador.
- Orden final: prioridad ascendente, distancia al punto de consulta, `cell_id`.
- `SECURITY DEFINER`; `GRANT EXECUTE` a `authenticated`.

Migración: [`Liftr/supabase/migrations/20260524150000_territory_expansion_recommendations_v1.sql`](../Liftr/supabase/migrations/20260524150000_territory_expansion_recommendations_v1.sql).

### Captura de rutas circulares (loop interior)

Migración: [`Liftr/supabase/migrations/20260524200000_territory_large_loop_capture_v2.sql`](../Liftr/supabase/migrations/20260524200000_territory_large_loop_capture_v2.sql).

La geometría de captura (`_liftr_territory_capture_geom`) combina:

1. **Corredor** — `ST_Buffer` de media anchura de celda (12,5 m con hex de 25 m); siempre aplicado.
2. **Interior de bucle** — polígono por cierre inicio/fin (`_liftr_territory_start_end_loop_polygon`) y/o caras de `ST_Polygonize` en rutas que se cruzan (`_liftr_territory_polygonize_loop_faces`).

| Regla | Valor |
|-------|-------|
| Cierre dinámico inicio/fin | `least(250 m, greatest(50 m, longitud_ruta × 0,025))` — p. ej. ~225 m en una ruta de 9 km |
| Área mínima de bucle | ~1 celda hex (`_liftr_territory_min_loop_area_m2`) |
| Área máxima de interior (por cara) | **10 km²** — caras mayores se ignoran |
| Ruta mínima | 500 m |
| `route_kind` | `closed` si hay interior válido; si no, `open` (solo corredor) |

**Importante:** ya no se descarta el interior cuando el área unida (corredor + polígono) supera 2 km² (límite anterior que dejaba solo el corredor en bucles grandes).

Si `ST_MakePolygon` falla en rutas ≥ 3 km con inicio/fin dentro del umbral dinámico, se reintenta con `ST_Snap` de extremos (5 m en Web Mercator).

`apply_territory_capture_v1` es idempotente por `workout_id`; cambios de geometría en producción requieren `_liftr_reexpand_territory_capture_for_workout` (la migración v2 re-expande automáticamente workouts 1987/1988 y bucles largos previamente `open` elegibles).

Verificación SQL: [`Liftr/supabase/verify/territory_capture_baseline.sql`](../Liftr/supabase/verify/territory_capture_baseline.sql).

### Rendimiento del mapa de territorio

Migración: [`Liftr/supabase/migrations/20260524220000_territory_map_load_performance_v1.sql`](../Liftr/supabase/migrations/20260524220000_territory_map_load_performance_v1.sql).

- `get_territory_map_v1` simplifica `cell_geojson` según el tamaño del viewport (menos bytes por celda).
- `get_territory_map_v1` (migración `20260524230000`): si el reparto por rutas de otros jugadores no cabe en `p_limit`, hace fallback por celdas recientes en lugar de devolver 0 celdas ajenas.
- Clientes iOS/Android: paginación secuencial en páginas de **1000** filas (tope PostgREST), hasta `p_limit` (5000 en zoom ciudad), una sola carga al abrir (sin doble fetch), y menos hexágonos dibujados solo en zoom continental (span > 0.30). En el mapa, las celdas propias se dibujan siempre; las ajenas se recortan solo si hace falta por rendimiento.

### Visualización rápida de territorio (workout detail)

Migración: [`Liftr/supabase/migrations/20260524210000_territory_display_performance_v1.sql`](../Liftr/supabase/migrations/20260524210000_territory_display_performance_v1.sql).

| RPC | Uso |
|-----|-----|
| `get_workout_territory_display_v1(p_workout_id)` | Detalle de entreno: devuelve `capture_fill_geojson` (polígono simplificado) y `cells_count` desde `territory_capture_events`; **no** devuelve miles de hexágonos |
| `preview_territory_capture_v1(p_route_geojson, p_max_cells)` | Preview en vivo: `p_max_cells = 0` solo fill; `null` = todas las celdas (legacy); `200` = muestra + fill si hay más |

### Otros RPC de territorio (referencia)

- `get_territory_map_v1` — viewport de celdas para el mapa
- `preview_territory_capture_v1`, `apply_territory_capture_v1` — preview y aplicación de captura
- `get_my_territory_summary_v1`, `get_territory_summary_v1`
- `list_territory_city_regions_v1`, `get_territory_city_share_leaderboard_v1`, `get_territory_total_cells_leaderboard_v1`

## Nutrition (MVP)

Migraciones: [`20260525120000_nutrition_ecosystem_v1.sql`](../Liftr/supabase/migrations/20260525120000_nutrition_ecosystem_v1.sql), [`20260525140000_nutrition_full_profile_v1.sql`](../Liftr/supabase/migrations/20260525140000_nutrition_full_profile_v1.sql), [`20260525220000_nutrition_metabolism_macros_ux_v1.sql`](../Liftr/supabase/migrations/20260525220000_nutrition_metabolism_macros_ux_v1.sql), [`20260526200000_nutrition_daily_balance_metabolic_fix_v1.sql`](../Liftr/supabase/migrations/20260526200000_nutrition_daily_balance_metabolic_fix_v1.sql), [`20260526210000_nutrition_diary_nutrient_total_v1.sql`](../Liftr/supabase/migrations/20260526210000_nutrition_diary_nutrient_total_v1.sql), [`20260525230000_nutrition_favorites_v1.sql`](../Liftr/supabase/migrations/20260525230000_nutrition_favorites_v1.sql), [`20260526250000_nutrition_bmr_mifflin_st_jeor_v1.sql`](../Liftr/supabase/migrations/20260526250000_nutrition_bmr_mifflin_st_jeor_v1.sql), [`20260531120000_nutrition_meal_planning_social_v1.sql`](../Liftr/supabase/migrations/20260531120000_nutrition_meal_planning_social_v1.sql), [`20260531130000_nutrition_meal_plan_invite_fixes_v1.sql`](../Liftr/supabase/migrations/20260531130000_nutrition_meal_plan_invite_fixes_v1.sql), [`20260531140000_nutrition_meal_plan_rls_recursion_fix_v1.sql`](../Liftr/supabase/migrations/20260531140000_nutrition_meal_plan_rls_recursion_fix_v1.sql), [`20260531150000_nutrition_meal_plan_per_user_v1.sql`](../Liftr/supabase/migrations/20260531150000_nutrition_meal_plan_per_user_v1.sql), [`20260531190000_nutrition_meal_plan_guard_fix_v1.sql`](../Liftr/supabase/migrations/20260531190000_nutrition_meal_plan_guard_fix_v1.sql). Verificación: [`nutrition_meal_plan_per_user_v1.sql`](../Liftr/supabase/verify/nutrition_meal_plan_per_user_v1.sql)

| Tabla | Uso cliente |
|-------|-------------|
| `profiles` | `base_calories_target` (integer, default 2000, not null) — valor guardado cuando el usuario define override manual; `base_calories_target_is_manual` (boolean, default `false`) — `true` = usar columna; `false` = BMR Mifflin-St Jeor en servidor |
| `nutrition_ingredients` | Búsqueda/alta de alimentos (`is_public` + propios); perfiles por 100g (macros + micros). Cliente iOS/Android: **INSERT**, **UPDATE** (macros + nombre), **DELETE** solo filas con `user_id = auth.uid()` y `is_public = false`. **DELETE** elimina en cascada favoritos y `nutrition_diary_logs` con ese `ingredient_id`. |
| `nutrition_recipes` | Recetas propias + catálogo global (`user_id` null); columna opcional `description` (text). Cliente iOS/Android: **INSERT** (create), **UPDATE** (edit nombre/descripción + reemplazo de líneas en `nutrition_recipe_ingredients`), **DELETE** solo filas con `user_id = auth.uid()` y `is_public = false`. **DELETE** de receta elimina en cascada `nutrition_recipe_ingredients`, favoritos y `nutrition_diary_logs` con ese `recipe_id`. |
| `nutrition_recipe_ingredients` | Composición de receta (lectura en presets del sistema); en edición el cliente borra todas las filas del `recipe_id` e inserta de nuevo |
| `nutrition_diary_logs` | Diario por `log_date` + `meal_slot` |
| `nutrition_meal_plans` | Plan futuro (fecha, slot, receta XOR ingrediente); creador gestiona el plan |
| `nutrition_meal_plan_targets` | Por usuario: `quantity_g`, food (`ingredient_id` XOR `recipe_id`), estado de invitación; notificación `meal_plan_invite` (English, incluye `food_name`, `meal_slot`, `quantity_g` en `data`) al invitar a otro |
| `user_favorite_nutrition_ingredients` | Favoritos de ingredientes (`ingredient_id`) por `user_id` |
| `user_favorite_nutrition_recipes` | Favoritos de recetas (`recipe_id`) por `user_id` |

**Meal slots (exactos en BD):** `Breakfast`, `Lunch`, `Dinner`, `Snack`

**Planificación social (flujo):** (1) creador inserta `nutrition_meal_plans` (cabecera: fecha, slot) + una fila `nutrition_meal_plan_targets` por participante con food/grams propios (creator auto-`accepted`); (2) invitee `pending` → solo **Meal invitations**; `accept_meal_plan` / `reject_meal_plan` (`pending` o `accepted` → `rejected`); (3) `accepted` → **Planned meals** (solo fila propia; Mark as eaten + Decline); (4) `complete_meal_plan_as_eaten` solo en la fila del caller → diario + `eaten` (desaparece de planned). Cliente: no mostrar filas `pending`/`eaten` en planned ni fila del partner para actuar. RPC edición: `update_meal_plan_target`. Notificación: `type = meal_plan_invite`, `data.plan_id`, `data.target_id`, `data.food_name`, `data.meal_slot`, `data.quantity_g`.

**Perfil por 100g (`nutrition_ingredients`):** `calories_per_100g`, `protein_per_100g`, `carbs_per_100g`, `fat_per_100g`, `saturated_fat_per_100g`, `sugars_per_100g`, `fiber_per_100g`, `sodium_mg_per_100g`

**Recetas (rollup cliente/RPC):** para cada nutriente, densidad por gramo = `Σ(weight_g * nutrient_per_100g / 100) / Σ(weight_g)`; consumo diario = `quantity_g × densidad`.

**Metabolismo (motor v5):** BMR Mifflin-St Jeor con offset `nutrition_sex_offset_v1` (+5 / −161 / −80 unisex). Imputación en servidor para cálculo automático (edad 30, defaults H/W por sexo). TDEE = BMR × multiplicador por **días de entreno intenso** (28 días): `count(distinct calendar day)` ÷ 4.0 donde el día tiene al menos un workout publicado **strength** o **sport**, o **cardio** sin `walk`/`caminata` en el título; varias sesiones el mismo día cuentan como un solo día. Matriz: &lt;1.5 → 1.2; ≥1.5 → 1.375; ≥3.5 → 1.55; ≥5.5 → 1.725. **Manual override:** `is_manual = true` conserva el objetivo hasta que el usuario edite biometrías (auto-desbloqueo en trigger) o pase a auto; workout sync y `nutrition_resolve` respetan `is_manual` en lecturas RPC. Funciones: `nutrition_intense_training_days_per_week_v1`, `nutrition_workout_activity_multiplier_v1`, `nutrition_compute_dynamic_metabolic_target_v1`, `nutrition_resolve_base_calories_target_v1`. Migraciones: `20260528160000`, `20260528180000`, `20260528200000`, `20260528210000`.

**RPC `get_smart_nutrition_recommendation_v1`:** parámetros `p_start_date`, `p_end_date` (ISO `yyyy-MM-dd`). Si `p_end_date < p_start_date`, se intercambian. Si el rango supera 70 días inclusive, `p_end_date` se recorta a `p_start_date + 69`. Requiere `auth.uid()`. Agrega `nutrition_diary_logs` + `nutrition_ingredients` (promedios diarios = total ÷ días calendario) y `workouts` publicados. `base_calories_target` resuelto vía `nutrition_resolve_base_calories_target_v1`. **Segmentación por arquetipo** (ventana consultada, no rolling 28d): `v_intense_days_per_week` = días intensos distintos × 7 ÷ días calendario; día intenso = strength/sport o cardio sin walk/caminata en título.

| Arquetipo | Condición |
|-----------|-----------|
| A — Hybrid Athlete | `intense_days_per_week` ≥ 4,5 **y** `avg_daily_burned_kcal` ≥ 600 |
| B — Active Fitness | `intense_days_per_week` ≥ 1,5 y no A |
| C — Sedentary Tracker | `intense_days_per_week` &lt; 1,5 |

| Alerta / narrativa | Condición |
|-------------------|-----------|
| Registro incompleto (prepend) | días con diario ÷ días calendario &lt; 75% |
| Infracombustión crítica | `consumed − (base + burned)` ≤ −750 **y** `intense_days_per_week` ≥ 1,5; `recommendation_text` empieza con alerta de infracombustión |
| Sodio &gt; 4500 mg/día | todos los arquetipos |
| A: sodio 2300–4500 | insight electrolitos (no warning negativo) |
| A: carbs &lt; 2,5 g/kg | alerta glucógeno + post-workout 1–1,2 g/kg en 2 h |
| B: proteína &lt; 1,8 g/kg | alerta recuperación muscular |
| C: sodio &gt; 2300 | restricción estándar |
| C: azúcares &gt; 50 y fibra &lt; 20 | carbohidratos refinados |

Cuando disparan infracombustión, proteína baja (B), carbs bajos (A), patrón azúcar/fibra (C) o sodio alto (C), las cadenas de `alerts` y `recommendation_text` incluyen recomendaciones alimentarias accionables (grasas saludables, proteínas magras, carbohidratos complejos, fibra, reducción de sodio) sin cambiar la forma del JSON.

`v_net_balance` interno = `avg_daily_consumed_kcal − (base_calories_target + avg_daily_burned_kcal)`. `avg_daily_remaining_budget` = negación (positivo = presupuesto restante). Copy en inglés. Migraciones: `20260528240000` (arquetipos), `20260528250000` (copy EN), `20260528260000` (food recommendations EN). Respuesta JSON:

```json
{
  "recommendation_text": "...",
  "alerts": ["...", "..."],
  "avg_daily_consumed_kcal": 0.0,
  "avg_daily_burned_kcal": 0.0,
  "base_calories_target": 2000,
  "avg_daily_energy_out": 0.0,
  "avg_daily_remaining_budget": 0.0
}
```

**Balance metabólico (multi-día):** `avg_daily_energy_out` = `base_calories_target + avg_daily_burned_kcal`. `avg_daily_remaining_budget` = `avg_daily_energy_out − avg_daily_consumed_kcal` (misma lógica que `remaining_calories` del RPC diario). Migración UX/copy: `20260526230000_smart_nutrition_recommendation_v2_metabolic_ux.sql`.

**RPC `get_daily_nutrition_recommendation_v1`:** parámetro `p_date` (ISO `yyyy-MM-dd`). Respuesta JSON:

```json
{
  "base_calories_target": 2000,
  "total_calories_consumed": 0,
  "total_calories_burned_active": 0,
  "remaining_calories": 0,
  "net_calories_balance": 0,
  "total_protein_g_consumed": 0,
  "total_carbs_g_consumed": 0,
  "total_fat_g_consumed": 0,
  "total_saturated_fat_g_consumed": 0,
  "total_sugars_g_consumed": 0,
  "total_fiber_g_consumed": 0,
  "total_sodium_mg_consumed": 0,
  "recommendation_text": "..."
}
```

**Balance calórico:** `remaining_calories` = `net_calories_balance` = `base_calories_target + total_calories_burned_active − total_calories_consumed`. Valor positivo = kcal restantes en el presupuesto del día; negativo = por encima del objetivo + actividad. En despliegues legacy (pre-`20260526200000`), `net_calories_balance` podía ser solo `consumed − burned`; los clientes no deben usar ese campo como remaining si falta `remaining_calories` — calcular con la fórmula metabólica anterior.

**Objetivo kcal en UI:** anillo de calorías y columna “Metabolism (BMR)” usan `base_calories_target` **resuelto** del RPC (BMR automático o override manual). Perfil: mostrar BMR calculado cuando `base_calories_target_is_manual = false`; al guardar solo el campo BMR, persistir override (`is_manual = true`). Macros secundarios (proteína, carbs, grasa, micros): defaults en `BackendContracts.NutritionDisplayTargets` (150 g proteína, 250 g carbs, etc.).

Android: constantes en `BackendContracts` (`Tables`, `Rpc`, `NutritionColumns`, `NutritionRpcKeys`, `NutritionDisplayTargets`, `NutritionMealSlots`).

## Liftr Coins (economía virtual)

Moneda sin valor monetario real. Balance canónico: `profiles.coins_balance` (actualizado por trigger al insertar en `coin_transactions`). Los clientes **no** incrementan el balance localmente tras likes/comentarios; refrescar perfil desde servidor.

**`reference_id`:** UUID estable vía `liftr_coin_ref_bigint(id)` para workouts/comentarios/logros; `liftr_coin_ref_uuid(user_id)` para follows; `liftr_coin_ref_date(yyyy-mm-dd)` para hitos semanales/rachas.

| `action_type` | Recompensa | Disparador |
|---------------|------------|------------|
| `like_given` | 2 | INSERT `workout_likes` |
| `comment_added` | 5 | INSERT `workout_comments` (no borrado) |
| `user_followed` | 5 | INSERT `follows` (follower) |
| `earned_follower` | 10 | INSERT `follows` (followee) |
| `achievement_unlocked` | 25 / 50 / 100 (bronze / silver / gold) | INSERT `user_achievements` |
| `workout_logged` | dinámico (base entrenamiento) | workout `state → published` |
| `workout_pet_training_bonus` | `% bono mascota` sobre base | workout `state → published` (misma `reference_id`) |
| `workout_coin_doubling_v1` | delta legacy | backfill one-shot 2× |
| `workout_economy_rebalance_v1` | delta | backfill one-shot rebalance entrenos |
| `pet_passive_economy_rebalance_v1` | `−75%` de `pet_coins_generated` histórico | backfill one-shot pasivo |
| `workout_economy_reduction_30pct_v1` | clawback delta | backfill reducción 30% entrenos |
| `pet_passive_economy_reduction_30pct_v1` | `−30%` de `pet_coins_generated` histórico | backfill reducción 30% pasivo |
| `pet_coins_generated` | dinámico | cron horario `generate_pet_coins_v1` |
| `weekly_goal_perfect_week` | 40 | todas las metas de la semana completadas |
| `workout_consistency_streak` | 50 | racha de 7 días consecutivos con workout publicado |
| `nutrition_ingredient_logged` | 3 | INSERT `nutrition_diary_logs` con `ingredient_id` |
| `nutrition_recipe_logged` | 5 | INSERT `nutrition_diary_logs` con `recipe_id` |
| `nutrition_ingredient_created` | 10 | INSERT `nutrition_ingredients` con `user_id` (no catálogo sistema) |
| `nutrition_recipe_created` | 15 | INSERT `nutrition_recipes` con `user_id` (no catálogo sistema) |
| `competition_bet_escrow` | `−bet_amount` | creación / aceptación de duelo con stake |
| `competition_bet_win` | `+bet_amount × 2` | duelo `finished` con ganador |
| `competition_bet_refund_draw` | `+bet_amount` | duelo `finished` sin ganador (empate) |
| `competition_bet_refund_cancelled` | `+bet_amount` | `declined`, `cancelled`, `expired` (reembolso al creador) |
| `pet_market_purchase` | `−price × quantity` | RPC `buy_pet_market_item_v1` |
| `pet_egg_reroll` | `−FLOOR(50 × 1.1^reroll_count)` | RPC `reroll_pet_egg_v1` |
| `pet_rarity_upgrade` | `−(1000 × 2^(current_sort_order − 1))` | RPC `upgrade_pet_rarity_v1` |

**Apuestas en competiciones:** mutaciones solo vía RPC (`authenticated` sin `INSERT`/`UPDATE` directo en `competitions` / `competition_goals`). Liquidación idempotente en trigger `trg_competition_settle_bet` al pasar a estado terminal. Cron `expire_pending_competition_bets_hourly` expira `pending` con stake > 7 días.

**`workout_logged` dinámico (escala ×5.95 sobre la base pre-doble desde `20260621120000_economy_reduction_30pct_v1`):**
- Strength: `round((10 +` número de series completadas `) × 5.95)`.
- Cardio: `round((base 10` + umbrales por `cardio_sessions.duration_sec` (30 min +5, 60 min +5) y `distance_km` (≥5 km +5, ≥10 km +10); fallback `workouts.duration_min` `) × 5.95)`.
- Otros kinds publicados: `60` (base sin bono de mascota).
- **Bono de mascota activa** (solo hatched, `baby`–`elder`): porcentaje según `pet_training_bonus_config`; fila aparte `workout_pet_training_bonus` + `pet_logs.event_type = workout_pet_bonus` con `details.message` (frase aleatoria en inglés desde `pet_workout_bonus_messages`).
- Backfills históricos: `workout_coin_doubling_v1`, `workout_economy_rebalance_v1`, `workout_economy_reduction_30pct_v1` (clawback si el total pagado supera el nuevo cálculo), `pet_passive_economy_rebalance_v1`, `pet_passive_economy_reduction_30pct_v1` (clawback 30% de `pet_coins_generated`).

**Anti-exploit:** unlike / unfollow / re-like no otorgan monedas de nuevo (sin filas de revocación). Borrar un log de nutrición no revoca monedas. Reintentos devuelven `unique_violation` silenciado en `apply_liftr_coin_reward`.

**Nutrición:** cada fila de diario otorga monedas (carrito, plan marcado como comido vía `complete_meal_plan_as_eaten`). Creación solo para ítems con `user_id` no nulo. Backfill histórico: `backfill_nutrition_coin_rewards_v1`.

**Cliente — lectura:** `profiles.select(coins_balance)` en una petición **aparte** (falla en silencio → `0` si la migración aún no está desplegada). La cabecera de perfil no debe incluir `coins_balance` en el SELECT principal. Componentes: `CoinsBalanceBadge` (iOS/Android). Historial: `list_my_coin_transactions_v1`; desglose por fuente: `get_my_coin_sources_v1` (cliente envía `p_start`/`p_end` según periodo Week/Month/Year o omite ambos para all-time); limpiar: `clear_my_coin_history_v1`. Ranking: métrica **Liftr Coins** vía `get_coins_leaderboard_v1`. Banner efímero al ganar monedas (cliente compara balance antes/después).

**`get_my_coin_sources_v1` — `source_key`:** `workouts`, `pet_workout_bonus`, `pet_coins`, `social`, `nutrition`, `achievements`, `goals_streaks`, `competition`, `pet_combat`, `other`. Excluye `workout_coin_doubling_v1`, `workout_economy_rebalance_v1`, `workout_economy_reduction_30pct_v1`, `pet_passive_economy_rebalance_v1`, `pet_passive_economy_reduction_30pct_v1`.

## Pets & Mascots

Gamificación portada de SettleIt. Mutaciones solo vía RPC (`authenticated`); sin `INSERT`/`UPDATE` directo en `pet_instances`, `pet_instance_stats` ni `user_inventory`.

**Tablas:** `pet_types`, `pet_type_stat_weights`, `pet_levels`, `pet_stage_rewards`, `pet_training_bonus_config`, `pet_food_experience`, `pet_rarity_config`, `pet_market_items`, `pet_instances`, `pet_instance_stats`, `user_inventory`, `pet_logs`.

**Pasivo por hora (`pet_stage_rewards`, tras `economy_reduction_30pct_v1`):** baby 2–5, kid 4–8, teen 6–10, adult 8–13, elder 11–20 (× `pet_rarity_config.coin_multiplier`). Huevo: 0.

**Bono entrenamiento (`pet_training_bonus_config`):** matriz stage × rarity; helper `get_pet_training_bonus_pct(user_id)`; histórico backfill vía `resolve_pet_bonus_at_time(user_id, at)`. Grant en publish: `grant_workout_coin_rewards_v1`.

**`pet_logs.event_type = workout_pet_bonus`:** insertado al publicar entreno si hay bono > 0; `details`: `coins`, `bonus_pct`, `base_coins`, `workout_id`, `message` (rotación vía `pick_pet_workout_bonus_message`).

**Sprites:** bucket Storage `pets` (público). Archivos: `{pet_type}_{stage}.png` en la raíz del bucket (`stage` = `egg|baby|kid|teen|adult|elder`). Market: `pets/market/{filename}.png`. Población inicial: `Liftr/scripts/mirror-settleit-pet-assets.sh` (copia desde SettleIt).

**`pet_types` — URLs por etapa (fuente de verdad):** `image_egg`, `image_baby`, `image_kid`, `image_teen`, `image_adult`, `image_elder` (text, URL pública completa). Helper SQL: `liftr_pet_image_url_for_stage(pet_type, stage)`.

**`user_inventory.item_type`:** `pet_egg`, `incubator`, `food_baby`, `food_kid`, `food_teen`, `food_adult`, `food_elder`.

**RPCs (authenticated):**

| RPC | Uso |
|-----|-----|
| `get_my_pet_v1()` | Pet activo + stats + inventario + `xp_required` + `can_evolve`; **`pet.image_url`** desde `pet_types` según `evolution_stage`; inventario siempre (también sin pet activo); hace hatch del huevo del caller si `hatch_at <= now()` |
| `list_pet_market_items_v1()` | Catálogo Market |
| `buy_pet_market_item_v1(p_item_type, p_quantity)` | Compra con coins (ver reglas abajo) |
| `start_pet_incubation_v1()` | Consume `pet_egg`; requiere `incubator` en inventario |
| `feed_pet_v1(p_item_type)` | Alimentar pet activo (no egg) |
| `confirm_pet_evolution_v1()` | Evolución manual en niveles 25/50/75/100 |
| `update_pet_custom_name_v1(p_name)` | Renombrar pet equipado |
| `reroll_pet_egg_v1()` | Reroll tipo/rareza del huevo incubando; coste `floor(50 × 1.1^reroll_count)` coins |
| `upgrade_pet_rarity_v1()` | Sube la rareza del pet activo un tier; coste `1000 × 2^(sort_order − 1)` coins; no recalcula stats históricos |
| `get_my_pet_dex_v1()` | Pet Dex del caller: catálogo completo + stats por especie oponente (`is_discovered`, W/L/D, rarities/stages seen) + totales de colección |
| `get_pet_species_detail_v1(p_pet_type)` | Detalle de especie: URLs de las 6 etapas, `discovered_stages` (combate o evolución propia), `dex` opcional si hubo combates |

**Pet Dex (`20260629120000_pet_combat_dex_v1.sql`):** tablas `pet_combat_dex_species`, `pet_combat_dex_rarities`, `pet_combat_dex_stages`, `pet_user_discovered_stages`. Triggers: `trg_pet_combat_dex_from_history` (INSERT en `pet_combat_history`, parsea `battle_log.attacker_pet` / `defender_pet`) y `trg_pet_own_stage_discovery` (INSERT/UPDATE `evolution_stage` en `pet_instances`). Backfill desde historial existente. Logros de colección en arena: `pet_combat_all_rarities` (6 rarezas), `pet_combat_all_species` (todas las especies), `pet_combat_all_stages` (5 etapas combatibles: baby–elder). Verify: [`Liftr/supabase/verify/pet_combat_dex_v1.sql`](../Liftr/supabase/verify/pet_combat_dex_v1.sql).
**Energía de arena (`profiles.current_energy` / `max_energy`):** regeneración por punto — **1 energía cada 4 horas** hasta `max_energy` (migración `20260615140000_liftr_pet_energy_regen_v1.sql`; sustituye al refill diario UTC). Acumulación lazy vía `liftr_refresh_profile_energy(p_user_id)` (interna, llamada desde `get_my_pet_v1`, `get_pet_combat_preview_v1`, `execute_pet_combat_v1`, `upgrade_pet_energy_capacity_v1`): `points = floor(elapsed / 4h)`; `current = least(max, current + points)`; `last_energy_refresh` avanza `points × 4h`, o se fija a `now()` cuando `current >= max` (el contador arranca al gastar un punto estando lleno). `liftr_profile_energy_json` devuelve `{current, max, last_refresh, next_refresh_at, regen_minutes: 240}` — `next_refresh_at = last_refresh + 4h` si `current < max`, `null` si está lleno. `get_pet_combat_preview_v1` usa este mismo json (clave `energy`).\n\n**Cron:** `liftr_hatch_pet_eggs_job` cada 10 min → `check_and_hatch_pet_eggs_v1` (egg → baby, stats iniciales, consume incubator).

**XP:** `required_exp(level) = 50 × level²` (`pet_levels`). Comida: EXP aleatorio por matriz `pet_food_experience`.

**Arena combat — stat roles (`liftr_combat_strike_v4` + turn order en `execute_pet_combat_v1`, migración `20260625120000_liftr_combat_balance_v4.sql`):** `health` → HP máximo en arena vía `liftr_combat_battle_hp_v1(health)` = `(health × 8 + 9) / 10` (80% del pool anterior); `strength` → daño base por golpe; `agility` → esquiva 3–28% (2% por punto de agi menos mitigación por int enemiga) **y** aporta daño (`×0.22`); `intelligence` → reduce esquiva enemiga, multiplicador de crítico **y** aporta daño (`×0.10`); `defense` + `resistance` → mitigación de daño recibido (promedio); `speed` → ataca primero cada ronda; `agility` también desempata turno si `speed` empata; `critical_rate` → probabilidad de crítico (hasta 50%); `stamina` → reduce penalización por fatiga tras ronda 12; `exploration` → bonus pequeño en el primer golpe; `happiness` → suelo mínimo de varianza de daño. Daño base: `1.22 × effective_strength × mitigation × …` (v3 usaba `1.4 × strength`). `liftr_combat_strike_v3` se conserva para rollback.

**Arena combat — balance de arquetipos (`20260625120000` + `20260626120000`):** v4: suelo `health_weight` 3 para tipos con peso ≤2; cap tank+DPS: si `health_weight ≥ 5` y `strength_weight ≥ 5`, `strength −1` y `happiness +1`; `monkey` 4/4 HP/str; `griffin` base 4/4 HP/str. v5 (paridad mismo nivel+rareza ~40–60% entre arquetipos de producción): `neon_panther` `strength_weight` 5→4, `exploration_weight` 3→4; `griffin` movilidad `speed` 5, `agility` 4, `intelligence` 2, `exploration` 3 (mantiene `resistance_weight` 5); `dragon` override explícito 4/4/6 HP/str/def, `intelligence` 4, `resistance` 4, `happiness` 4, `exploration` 4, `critical_rate` 1 (suma 40) (el cap v4 dejaba dragon en 6/6). Recompute: `recompute_pet_stats_combat_balance_v1()` — v4 en `20260625120100`, v5 en `20260626120100`; hatch con `liftr_compute_hatch_stats_v1` + re-roll de cada `level_up` en `pet_logs`. Verificación: `supabase/verify/combat_balance_v5.sql` + `combat_balance_v5_monte_carlo.py`.

Cliente: botón ⓘ en Stats del pet y en comparativa pre-combate → `PetStatCombatHelpSheet` / `PetStatCombatHelpSheetContent` (incluye **Stat Balancing**, **Handicap Battles**, **Hardcore Challenge**). Pre-combate underdog: picker Balanced/Hardcore; preferencias `skipPetCombatUnbalancedWarning`, `petCombatChallengeMode`.

**Arena combat — stat handicap (`20260618120000` + hardcore `20260619120000`):** pool de combate = suma de 10 stats (excluye `happiness`). Desbalanceado si `max(pool) * 100 > min(pool) * 105`. Modo **balanced** (default): nerf in-memory del lado fuerte hasta `floor(weaker_pool × 1.05)`. Modo **hardcore** (`execute_pet_combat_v1(p_target, p_disable_nerf_choice=true)` solo si el atacante es underdog): sin nerf; defensor a stats reales. `pet_combat_history.is_handicapped = true` en cualquier combate desbalanceado (balanced o hardcore). `get_pet_combat_head_to_head_v1` excluye filas `is_handicapped = true` del W/L/D competitivo (stats globales `pet_combat_user_stats` siguen contando todo). Preview `stat_balancing` añade `hardcore_buff_multiplier`, `hardcore_bonus_percent`. Recompensas hardcore: underdog gana → `liftr_combat_hardcore_rewards` = premium × `(stronger_pool / weaker_pool)`; fuerte gana → mínimo (`xp:10, coins:5`). Cliente: picker Balanced/Hardcore en modal underdog; preferencias `skipPetCombatUnbalancedWarning`, `petCombatChallengeMode`. Verify: `pet_combat_stat_handicap_v1.sql`, `pet_combat_hardcore_v1.sql`.

**Subida de nivel — stats (`pet_level_stat_shared_budget_v1`):** un presupuesto compartido por subida vía `compute_pet_level_stat_delta_v1(pet_type, stage, user_id)` (llamada desde `distribute_pet_stats`). (1) `total_budget = floor(random() × (max − min + 1)) + min` según `pet_stage_rewards` del stage — **una sola tirada por nivel**; (2) por stat, jitter independiente `0.5 + random()` (50%–150%); (3) `raw = total_budget × get_pet_stat_multiplier × weight/total_weight × jitter`; `health = floor(raw × 20)`; resto `round(raw)`. Varianza por stat sin 11 presupuestos independientes (evita pantallas con mayoría de +0). `pet_logs.stats_delta` conserva la misma forma jsonb. Backfill histórico: `backfill_pet_level_stat_variance_v1()` — baseline hatch = stats actuales − suma de deltas `level_up`; re-tira cada log ordenado por `new_level` con stage resuelto por `resolve_pet_stage_at_time` (último log `evolution` antes del timestamp, si no `baby`). `critical_rate` (peso 1) puede seguir en 0 en baby. Fuera de alcance: stats iniciales al hatch (`generate_initial_pet_stats`) y bono evolución (`apply_evolution_stat_bonus`).

**Market — precios (`pet_market_items`):** `pet_egg` y `incubator` cuestan **2000** coins cada uno.

**`buy_pet_market_item_v1` — guardas de propiedad:**

| `p_item_type` | Rechaza con |
|---------------|-------------|
| `pet_egg` | `already_owns_egg` si `user_inventory.pet_egg` qty > 0 o hay `pet_instances` activo; `already_has_pet` si hay pet activo |
| `incubator` | `already_owns_incubator` si `user_inventory.incubator` qty > 0 o hay pet activo; `already_has_pet` si hay pet activo |

**Visibilidad Market (cliente):** ocultar `pet_egg`/`incubator` si el usuario ya los tiene en inventario o tiene pet activo; mostrar comida si hay pet activo (cualquier `evolution_stage`, incluido `egg`); mostrar `pet_rarity_upgrade` solo si hay pet activo y rareza ≠ `mythic` (precio dinámico en cliente, validado en servidor). Incubación desde **My Items**, no desde Market.

**Rarity upgrade — precios exponenciales (desde tier actual):** Common→Uncommon 1 000; Uncommon→Rare 2 000; Rare→Epic 4 000; Epic→Legendary 8 000; Legendary→Mythic 16 000. Compra vía `upgrade_pet_rarity_v1` (no `buy_pet_market_item_v1`). Imagen Market dinámica en Storage: `pets/market/rarity_upgrade_{from}_to_{to}.png` (p. ej. `rarity_upgrade_rare_to_epic.png`); el cliente resuelve la ruta según la rareza activa del pet.

**`pet_logs` (cliente):** lectura y borrado de filas propias vía RLS (`pet_logs_select_own`, `pet_logs_delete_own`). Paginación en cliente (5 por página). Perfil: FAB 90pt fijo abajo-derecha → sheet **Your Egg** con rarity, hatch time, tipo, Change Pet, logs.

**Market info sheet (cliente):** lectura directa de catálogo público vía PostgREST (`pet_types`: `name`, `display_name`, `description`, `image_egg`; `pet_rarity_config`: todos los campos, orden `sort_order`). RLS `pet_types_read` / `pet_rarity_config_read` (`using (true)`). iOS/Android: botón ⓘ en Pet Market → sheet con rarezas (drop %, multiplicadores, coste upgrade) y grid de especies.

## Política de cambios de contrato

Cuando iOS añada/elimine/renombre una tabla o RPC:

1. Actualizar `BackendContracts.kt`.
2. Actualizar este documento.
3. Adaptar Android en el mismo PR para mantener paridad de contrato.

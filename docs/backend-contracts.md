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
- `segments` (PostGIS `geography(LineString,4326)`; MVP solo creación por usuario; ver `docs/migrations/segments_mvp_v1.sql` o `segments_mvp_v1_part01_*.sql`–`part06_*.sql` si el cliente parte por `;`). Tras [`Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql`](../Liftr/supabase/migrations/20260509120000_segment_route_coverage_v1.sql): columnas opcionales `source_workout_id`, `source_start_fraction`, `source_end_fraction`, y `geog`/`geojson` coherente con el RPC de creación.
- `segment_efforts` (match por buffer sobre `route_geojson` + tiempo estimado; ver misma migración). Tras la migración `20260509120000_segment_route_coverage_v1.sql`: columna **`route_coverage`** (0–1); trigger antes de insert/actualizar que exige ≥0.95 salvo el entreno origen.
- `achievements` (catálogo; filas y reglas de desbloqueo principales vía `check_and_unlock_achievements_for` en la BD)
- `user_achievements` (desbloqueos por `user_id`)
- `challenge_templates` (catálogo de retos; `metric_kind`, `cadence`, umbrales, ámbitos opcionales `scope_activity_code` / `scope_sport` / `scope_muscle_primary`; ver [`docs/migrations/challenges_mvp_v1.sql`](migrations/challenges_mvp_v1.sql))
- `challenge_instances` (ventana temporal por plantilla, p. ej. semana ISO)
- `challenge_claims` (adjudicaciones: usuario, rango, `workout_id`, `adjudication_ts`)

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
- `get_workout_likes_received_leaderboard_v1`, `get_workout_comments_received_leaderboard_v1`, `get_group_workout_sessions_leaderboard_v1` (social / feed quality; published workouts in period)
- `get_achievements_unlocked_period_leaderboard_v1` (app metric **Achievements**; uses same workout-style period as other leaderboards). Optional in same migration file: `get_achievements_total_unlocked_leaderboard_v1` (no `p_period`) for ad-hoc / analytics, not wired in clients.
- `get_hyrox_best_official_time_leaderboard_v1`, `get_football_goals_leaderboard_v1`, `get_ski_distance_leaderboard_v1`
- `get_user_achievements`
- `get_user_prs` (`p_user_id`, optional `p_kind`, optional `p_search`) — profile/compare PR lists; bypasses own-only RLS via `SECURITY DEFINER` + authenticated read policies on PR tables
- `get_user_premium_status_v1` () → `boolean`; `auth.uid()` required; `true` iff a `user_subscriptions` row exists for the caller with `status in ('active','trialing')` and `expires_at > now()` (see migration above)
- `get_user_level`
- `get_weekly_goal_recommendation`
- `list_comparable_workouts_v1`
- `list_compare_average_pool_v1` (`p_baseline_workout`, `p_scope` `mine`|`global`, `p_limit`) → `workout_id`, `started_at` for compare-average pools (cardio activity / sport / strength exact primary-muscle set); see `Liftr/supabase/migrations/20260521120000_compare_average_pool_v1.sql`
- `get_home_feed_page_v1` (`p_page`, `p_page_size`, optional `p_kind`) → JSON `{ workouts, scores, likes, participants }` for authenticated home feed (one round-trip); see `Liftr/supabase/migrations/20260522140000_disk_io_optimizations_v1.sql`
- `plan_strength_squad_programs`
- `precheck_signup`
- `recompute_weekly_goal_results`
- `record_search`
- `review_competition_workout`
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

## Retos (Challenges MVP)

- **Diferencia vs logros:** los logros son hitos personales permanentes (`achievements` / `user_achievements`). Los retos son **eventos de ventana** con **plazas limitadas** (`max_winners`) e instancias por `period_start` / `period_end`. La plantilla define **`cadence`**: `week`, `month` o `once` (ventana larga para retos tipo evergreen).
- **Diferencia vs metas semanales:** `weekly_goals` es objetivo **solo para ti**. Los retos comparan orden de cumplimiento **en comunidad** (clasificación por `challenge_claims`).
- **Diferencia vs duelos:** `competitions` es 1:1; los retos del MVP son **globales** en la instancia.
- **`challenge_templates` (ámbitos opcionales):** `scope_activity_code` filtra cardio por `coalesce(cardio_sessions.activity_code, modality)`; `scope_sport` filtra por `sport_sessions.sport`; `scope_muscle_primary` restringe líneas de fuerza a `exercises.muscle_primary` (comparación `lower(btrim(...)))`).
- **Reglas híbridas por `metric_kind`** (ver [`challenges_mvp_v1.sql`](migrations/challenges_mvp_v1.sql)):
  - `cumulative_cardio_km` — suma km cardio en ventana (con filtro de actividad si hay `scope_activity_code`).
  - `single_set_max_kg` — primera publicación con serie ≥ umbral kg (filtro músculo opcional).
  - `cardio_session_pace_gate` — sesión que cumple distancia y tope de `duration_sec` (filtro actividad opcional).
  - `cumulative_sport_sessions` — cuenta sesiones sport publicadas (filtro `scope_sport` opcional vía join `sport_sessions`).
  - `cumulative_strength_workouts` — cuenta entrenos fuerza publicados.
  - `cumulative_strength_reps` / `cumulative_strength_sets` / `cumulative_strength_volume_kg` — acumulado de reps, de series con carga, o de volumen kg (reps × kg) en orden cronológico; filtro músculo opcional.
  - `single_set_max_reps` — primera publicación con alguna serie con reps ≥ umbral.
  - `strength_workouts_touching_muscle` — primero en alcanzar N entrenos de fuerza distintos que incluyan al menos un ejercicio con `muscle_primary` = `scope_muscle_primary` (requiere scope).
- **Notificación:** tipo **`challenge_won`** (legacy **`challenge_won_weekly`**) con `data.challenge_instance_id`, `template_code`, `workout_id` vía `create_notification`; misma cola **`send-notifications`** + FCM. Los clientes aceptan ambos tipos.

## Achievements (contrato cliente y operación en BD)

### Uso en app

- Los clientes **no** hacen `select` crudo al catálogo en el flujo de UI: llaman al RPC `get_user_achievements` con `p_user_id` (uuid) y reciben filas con al menos: `achievement_id`, `code`, `title`, `description`, `category`, `icon_url`, `user_id`, `unlocked_at`, `is_unlocked`. Tras aplicar [get_user_achievements_extend_progress_v1.sql](migrations/get_user_achievements_extend_progress_v1.sql), el RPC puede incluir también `requirement_type`, `requirement_value`, `progress_current`, y agregados opcionales `community_pct_unlocked` / `community_sample_size` (% de usuarios con al menos un workout publicado que tienen el logro; `NULL` si el denominador es menor que el umbral definido en SQL).
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

## Inicio de entreno en vivo (`start_workout_v1`)

- iOS y Android marcan `started_at` en el cliente al pulsar **Start** y abren la pantalla activa sin esperar la red.
- El RPC se encola y reintenta (≈0.5s / 2s / 5s) hasta éxito o error no recuperable; `p_started_at` puede llegar unos segundos antes que el ack del servidor.
- El programa de fuerza (ejercicios + series) se cachea al cargar el detalle y rehidrata la pantalla activa si la segunda lectura falla.
- Dual/grupo: si `create_linked_strength_workout_copy` falla, el cliente ofrece **Start solo** / **Start offline** además de reintentar.

## Fin de entreno en vivo (`finish_strength_workout_v1` / persistencia Android)

- iOS: al pulsar **Finish workout**, si la red falla de forma recuperable, el cliente encola el payload de `finish_strength_workout_v1`, muestra un toast y cierra la pantalla activa (sin pantalla de error bloqueante).
- Android: misma semántica con cola local (`WorkoutFinishSync`) que reejecuta la persistencia de series + cierre del workout cuando vuelve la conexión.
- Los errores de **carga** del programa siguen bloqueando solo cuando no hay caché local; los errores de **finish** no reemplazan la UI del entreno en curso.

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

## Política de cambios de contrato

Cuando iOS añada/elimine/renombre una tabla o RPC:

1. Actualizar `BackendContracts.kt`.
2. Actualizar este documento.
3. Adaptar Android en el mismo PR para mantener paridad de contrato.

# Liftr – Database Schema Documentation

_Last updated: 2025-10-17_

## Overview
PostgreSQL/Supabase schema for **Liftr**, including tables, relations, views, functions, triggers, RLS, checks, enums, indexes, extensions and grants.

---

## Schemas, Tables & Views

**Schemas scanned:** `auth`, `public`

**auth (managed by Supabase Auth)**
- `users` (BASE TABLE)
- (and other auth infra tables: `sessions`, `identities`, `mfa_*`, `oauth_*`, etc.)

**public**
- Tables: `profiles`, `workouts`, `workout_exercises`, `exercise_sets`, `cardio_sessions`, `sport_sessions`, `personal_records`, `score_rules`, `body_metrics`, `exercises`, `workout_scores`, `user_best_scores`, `endurance_records`, `sport_records`
- Views: `vw_latest_weight`, `vw_workout_volume`, `vw_user_total_scores`

---

## Tables (public)

### `public.profiles`
User profile linked to `auth.users`.

| Column | Type | Nullable | Default |
|---|---|---|---|
| user_id | uuid | NO | — |
| username | text | NO | — |
| sex | enum `sex` | YES | — |
| date_of_birth | date | YES | — |
| height_cm | numeric | YES | — |
| weight_kg | numeric | YES | — |
| created_at | timestamptz | YES | `now()` |
| updated_at | timestamptz | YES | `now()` |

**PK:** `profiles_pkey(user_id)`  
**FK:** `profiles_user_id_fkey` → `auth.users(id) ON DELETE CASCADE`  
**Indexes:** `profiles_pkey`, `profiles_username_key`, `profiles_username_ci_key`  
**Checks:** `profiles_height_positive`, `profiles_weight_positive`  
**RLS:** enabled (see “RLS & Security”)  
**Triggers:** `set_profiles_updated_at` (BEFORE UPDATE → `set_updated_at()`), `trg_profiles_set_updated_at` (BEFORE UPDATE → `set_updated_at()`)

---

### `public.workouts`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| user_id | uuid | NO | — |
| kind | enum `workout_kind` | NO | — |
| title | text | YES | — |
| started_at | timestamptz | YES | — |
| ended_at | timestamptz | YES | — |
| duration_min | integer | YES | GENERATED ALWAYS AS (EXTRACT(EPOCH FROM (ended_at - started_at)) / 60)::int STORED |
| perceived_intensity | enum `intensity` | YES | — |
| notes | text | YES | — |
| created_at | timestamptz | YES | `now()` |
| updated_at | timestamptz | YES | `now()` |

**PK:** `workouts_pkey(id)`  
**FK:** `workouts_user_id_fkey` → `profiles(user_id) ON DELETE CASCADE`  
**Indexes:** `workouts_user_id_started_at_idx(user_id, started_at DESC)`  
**RLS:** enabled  
**Triggers:** `trg_workouts_set_updated_at` (BEFORE UPDATE → `set_updated_at()`)
> **Note:**  
> `duration_min` is a **generated column**. Do not include it in `INSERT` or `UPDATE`.  
> It is computed from `started_at` and `ended_at`.  
> Attempting to write it will fail (GENERATED ALWAYS).

---

### `public.workout_exercises`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| workout_id | bigint | NO | — |
| exercise_id | bigint | NO | — |
| order_index | integer | NO | `1` |
| notes | text | YES | — |

**PK:** `workout_exercises_pkey(id)`  
**FK:** `workout_exercises_workout_id_fkey` → `workouts(id) ON DELETE CASCADE`  
**FK:** `workout_exercises_exercise_id_fkey` → `exercises(id)`  
**Indexes:** `idx_workout_exercises_order(workout_id, order_index)`, `workout_exercises_workout_id_idx`  
**RLS:** enabled

---

### `public.exercise_sets`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| workout_exercise_id | bigint | NO | — |
| set_number | integer | NO | — |
| reps | integer | YES | — |
| weight_kg | numeric | YES | — |
| rpe | numeric | YES | — |
| rest_sec | integer | YES | — |
| notes | text | YES | — |

**PK:** `exercise_sets_pkey(id)`  
**FK:** `exercise_sets_workout_exercise_id_fkey` → `workout_exercises(id) ON DELETE CASCADE`  
**Indexes:** `exercise_sets_workout_exercise_id_idx`, `idx_sets_by_exercise(workout_exercise_id, set_number)`  
**Checks:** `chk_sets_reps_nonneg`, `chk_sets_weight_nonneg`, `chk_sets_rest_nonneg`  
**RLS:** enabled

---

### `public.cardio_sessions`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| workout_id | bigint | NO | — |
| modality | text | NO | — |
| distance_km | numeric | YES | — |
| duration_sec | integer | YES | — |
| avg_hr | integer | YES | — |
| max_hr | integer | YES | — |
| avg_pace_sec_per_km | integer | YES | — |
| elevation_gain_m | integer | YES | — |
| notes | text | YES | — |

**PK:** `cardio_sessions_pkey(id)`  
**FK:** `cardio_sessions_workout_id_fkey` → `workouts(id) ON DELETE CASCADE`  
**Indexes:** `cardio_sessions_workout_id_idx`, `idx_cardio_by_modality(modality)`  
**Checks:** `chk_cardio_distance_nonneg`, `chk_cardio_duration_nonneg`, `chk_cardio_elev_nonneg`  
**RLS:** enabled

---

### `public.sport_sessions`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| workout_id | bigint | NO | — |
| sport | text | NO | — |
| duration_sec | integer | YES | — |
| match_result | text | YES | — |
| notes | text | YES | — |

**PK:** `sport_sessions_pkey(id)`  
**FK:** `sport_sessions_workout_id_fkey` → `workouts(id) ON DELETE CASCADE`  
**Indexes:** `sport_sessions_workout_id_idx`, `idx_sport_by_type(sport)`  
**Checks:** `chk_sport_duration_nonneg`  
**RLS:** enabled

---

### `public.personal_records`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| user_id | uuid | NO | — |
| exercise_id | bigint | NO | — |
| metric | text | NO | — |
| value | numeric | NO | — |
| achieved_at | timestamptz | NO | `now()` |

**PK:** `personal_records_pkey(id)`  
**FK:** `personal_records_user_id_fkey` → `profiles(user_id) ON DELETE CASCADE`  
**FK:** `personal_records_exercise_id_fkey` → `exercises(id)`  
**Indexes:** `personal_records_user_id_idx(user_id)`, `personal_records_user_id_exercise_id_metric_key` (unique)  
**RLS:** enabled

---

### `public.score_rules`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| algorithm | text | NO | — |
| sex_filter | enum `sex` | YES | — |
| weight_from | numeric | YES | — |
| weight_to | numeric | YES | — |
| kind_filter | enum `workout_kind` | YES | — |
| json_rule | jsonb | NO | — |

**PK:** `score_rules_pkey(id)`  
**RLS:** enabled

---

### `public.exercises`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| name | text | NO | — |
| category | text | NO | — |
| modality | text | NO | — |
| muscle_primary | text | YES | — |
| equipment | text | YES | — |
| is_public | boolean | YES | `true` |

**PK:** `exercises_pkey(id)`  
**Indexes:** `exercises_lower_idx (unique lower(name))`  
**RLS:** enabled

---

### `public.workout_scores`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| workout_id | bigint | NO | — |
| score | numeric | NO | — |
| algorithm | text | NO | — |
| calculated_at | timestamptz | YES | `now()` |

**PK:** `workout_scores_pkey(id)`  
**FK:** `workout_scores_workout_id_fkey` → `workouts(id) ON DELETE CASCADE`  
**Indexes:** `workout_scores_workout_id_algorithm_idx` (unique)  
**RLS:** enabled

---

### `public.user_best_scores`
Stores the highest score achieved by each user per algorithm.

| Column | Type | Nullable | Default |
|---|---|---|---|
| user_id | uuid | NO | — |
| algorithm | text | NO | — |
| best_score | numeric | NO | — |
| workout_id | bigint | NO | — |
| achieved_at | timestamptz | NO | `now()` |

**PK:** `(user_id, algorithm)`  
**FK:** `user_best_scores_user_id_fkey` → `profiles(user_id) ON DELETE CASCADE`  
**FK:** `user_best_scores_workout_id_fkey` → `workouts(id) ON DELETE CASCADE`  
**RLS:** enabled

---

### `public.endurance_records`
Tracks personal bests for cardio activities (e.g., Run, Bike).

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| user_id | uuid | NO | — |
| modality | text | NO | — |
| metric | text | NO | — |
| value | numeric | NO | — |
| achieved_at | timestamptz | NO | `now()` |

**Unique:** `(user_id, modality, metric)`  
**FK:** `endurance_records_user_id_fkey` → `profiles(user_id) ON DELETE CASCADE`  
**RLS:** enabled

---

### `public.sport_records`
Tracks personal bests for sports sessions (e.g., Football, Tennis).

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| user_id | uuid | NO | — |
| sport | text | NO | — |
| metric | text | NO | — |
| value | numeric | NO | — |
| achieved_at | timestamptz | NO | `now()` |

**Unique:** `(user_id, sport, metric)`  
**FK:** `sport_records_user_id_fkey` → `profiles(user_id) ON DELETE CASCADE`  
**RLS:** enabled

---

### `public.body_metrics`

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint | NO | nextval |
| user_id | uuid | NO | — |
| measured_at | date | NO | `CURRENT_DATE` |
| weight_kg | numeric | YES | — |
| height_cm | numeric | YES | — |
| body_fat_pct | numeric | YES | — |
| chest_cm | numeric | YES | — |
| waist_cm | numeric | YES | — |
| hip_cm | numeric | YES | — |
| notes | text | YES | — |
| created_at | timestamptz | YES | `now()` |

**PK:** `body_metrics_pkey(id)`  
**FK:** `body_metrics_user_id_fkey` → `profiles(user_id) ON DELETE CASCADE`  
**Indexes:** `body_metrics_user_id_measured_at_idx(user_id, measured_at DESC)`  
**Checks:** `chk_body_weight_nonneg`, `chk_body_height_nonneg`  
**RLS:** enabled

---

## Views (public)

### `vw_latest_weight`
```sql
SELECT DISTINCT ON (user_id)
  user_id, weight_kg, measured_at
FROM body_metrics bm
WHERE weight_kg IS NOT NULL
ORDER BY user_id, measured_at DESC;

vw_workout_volume

SELECT
  w.id AS workout_id,
  w.user_id,
  (COALESCE(SUM((es.reps::numeric * es.weight_kg)), 0::numeric))::numeric(12,3) AS total_volume_kg
FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
LEFT JOIN exercise_sets es ON es.workout_exercise_id = we.id
WHERE w.kind IN ('strength'::workout_kind, 'mixed'::workout_kind)
GROUP BY w.id, w.user_id;

vw_user_total_scores
Aggregates each user’s best scores across all algorithms.
SELECT user_id,
       COALESCE(SUM(best_score), 0)::numeric AS total_score
FROM public.user_best_scores
GROUP BY user_id;

⸻

Functions (public)
    •    set_updated_at() — trigger, PL/pgSQL
    •    handle_new_user() — trigger, PL/pgSQL (inserts into public.profiles after insert in auth.users)
    •    score_strength_v1(p_workout_id bigint) → numeric, PL/pgSQL
    •    score_cardio_run_v1(p_workout_id bigint) → numeric, PL/pgSQL
    •    compute_workout_score_v1(p_workout_id bigint) → TABLE(algorithm text, score numeric), PL/pgSQL  
         Calculates score(s) depending on workout kind and applicable algorithms.  
         Used internally by upsert_workout_score_v1().
    •    upsert_workout_score_v1(p_workout_id bigint) → void, PL/pgSQL  
         Inserts or updates `workout_scores` and `user_best_scores` entries automatically.
    •    create_profile_on_signup — trigger (listed; verify if used or legacy)
    
> **Security:** Las funciones RPC están declaradas como `SECURITY DEFINER`, con `REVOKE ALL FROM PUBLIC` y `GRANT EXECUTE TO authenticated`.
    
    #### Workout creation functions (RPC)
- `create_strength_workout(p_user_id uuid, p_items jsonb, p_title text, p_started_at timestamptz, p_ended_at timestamptz, p_notes text, p_perceived_intensity intensity) → bigint`  
  Creates the strength workout and inserts into `workouts`, `workout_exercises`, and `exercise_sets`.  
  **Does not** touch `duration_min` (generated column). Automatically updates `workout_scores` and `user_best_scores`.

- `create_cardio_workout(p_user_id uuid, p_modality text, p_title text, p_started_at timestamptz, p_ended_at timestamptz, p_notes text, p_distance_km numeric, p_duration_sec int, p_avg_hr int, p_max_hr int, p_avg_pace_sec_per_km int, p_elevation_gain_m int, p_perceived_intensity intensity) → bigint`  
  Inserts into `workouts` and `cardio_sessions`. Automatically updates `workout_scores` and `user_best_scores`.  

- `create_sport_workout_v1(p jsonb) → bigint`  
  Inserts into `workouts` and `sport_sessions`. Converts `p_duration_min` to seconds internally.  
  Automatically updates `workout_scores` and `user_best_scores`.  

⸻

Triggers

public
    •    profiles:
    •    set_profiles_updated_at → BEFORE UPDATE EXECUTE FUNCTION set_updated_at()
    •    trg_profiles_set_updated_at → BEFORE UPDATE EXECUTE FUNCTION set_updated_at()
    •    workouts:
    •    trg_workouts_set_updated_at → BEFORE UPDATE EXECUTE FUNCTION set_updated_at()
    
public (new)
    •    trg_strength_pr_from_set → AFTER INSERT OR UPDATE ON exercise_sets EXECUTE FUNCTION public.trg_strength_pr_from_set()
    •    trg_cardio_pr_from_session → AFTER INSERT OR UPDATE ON cardio_sessions EXECUTE FUNCTION public.trg_cardio_pr_from_session()
    •    trg_sport_pr_from_session → AFTER INSERT OR UPDATE ON sport_sessions EXECUTE FUNCTION public.trg_sport_pr_from_session()
    •    trg_rescore_from_set → AFTER INSERT OR UPDATE OR DELETE ON exercise_sets EXECUTE FUNCTION public.trg_rescore_from_set()
    •    trg_rescore_from_cardio → AFTER INSERT OR UPDATE OR DELETE ON cardio_sessions EXECUTE FUNCTION public.trg_rescore_from_cardio()
    •    trg_rescore_from_sport → AFTER INSERT OR UPDATE OR DELETE ON sport_sessions EXECUTE FUNCTION public.trg_rescore_from_sport()

auth
    •    users:
    •    (signup trigger not listed currently; verify existence if you expect auto-profile creation)

⸻

RLS & Security
    •    RLS enabled: true in all public tables listed above.
    •    Policies present: none returned by query → with RLS on and no policies, client access is blocked (except service_role).
    •    Nota: el alta de workouts se realiza mediante las funciones RPC `create_*_workout` (write-path controlado).  
         Asegurar políticas que verifiquen que `p_user_id = auth.uid()` dentro de las funciones, o añadir USING/WITH CHECK por tabla si se habilita escritura directa.
Re-create per-user policies when ready and document here (USING/WITH CHECK).

⸻

Foreign Keys (public)
    •    profiles.user_id → auth.users(id) ON DELETE CASCADE
    •    workouts.user_id → profiles(user_id) ON DELETE CASCADE
    •    workout_exercises.workout_id → workouts(id) ON DELETE CASCADE
    •    workout_exercises.exercise_id → exercises(id)
    •    exercise_sets.workout_exercise_id → workout_exercises(id) ON DELETE CASCADE
    •    cardio_sessions.workout_id → workouts(id) ON DELETE CASCADE
    •    sport_sessions.workout_id → workouts(id) ON DELETE CASCADE
    •    personal_records.user_id → profiles(user_id) ON DELETE CASCADE
    •    personal_records.exercise_id → exercises(id)
    •    workout_scores.workout_id → workouts(id) ON DELETE CASCADE
    •    body_metrics.user_id → profiles(user_id) ON DELETE CASCADE
    •    user_best_scores.user_id → profiles(user_id) ON DELETE CASCADE  
    •    user_best_scores.workout_id → workouts(id) ON DELETE CASCADE  
    •    endurance_records.user_id → profiles(user_id) ON DELETE CASCADE  
    •    sport_records.user_id → profiles(user_id) ON DELETE CASCADE

⸻

Indexes (highlights)
    •    workouts_user_id_started_at_idx
    •    idx_workout_exercises_order
    •    exercise_sets_workout_exercise_id_idx / idx_sets_by_exercise
    •    cardio_sessions_workout_id_idx / idx_cardio_by_modality
    •    sport_sessions_workout_id_idx / idx_sport_by_type
    •    personal_records_user_id_exercise_id_metric_key (unique composite)
    •    exercises_lower_idx (unique lower(name))
    •    workout_scores_workout_id_algorithm_idx (unique composite)
    •    body_metrics_user_id_measured_at_idx
    •    user_best_scores_pkey (user_id, algorithm)  
    •    endurance_records_user_id_modality_metric_key (unique composite)  
    •    sport_records_user_id_sport_metric_key (unique composite)

⸻

Checks
    •    Non-negative checks across: profiles, body_metrics, exercise_sets, cardio_sessions, sport_sessions
    •    `workouts.duration_min` — columna generada; consistencia garantizada por la expresión calculada a partir de `started_at` y `ended_at`.

⸻

Sequences
    •    Auto-increment sequences: *_id_seq for bigserial PKs.

⸻

Extensions
    •    pg_graphql, pg_stat_statements, pgcrypto, plpgsql, supabase_vault, uuid-ossp

⸻

### Deprecated / Removed
- Versiones antiguas de `create_cardio_workout` que:
  - incluían `p_duration_min` como parámetro, o
  - insertaban campos de cardio directamente en `workouts`.
Estas versiones se han eliminado en favor de la firma actual que retorna `bigint` y usa `cardio_sessions`.

### Scoring migration
- Added automatic recalculation of workout scores and user best scores.
- Added new views and tables (`user_best_scores`, `endurance_records`, `sport_records`, `vw_user_total_scores`).
- All RPCs (`create_*_workout`) now invoke `upsert_workout_score_v1()` automatically.

## Grants (public)

Grants show anon, authenticated, service_role, postgres on all tables/views; RLS still governs access.

⸻

Change process
    1.    Make schema changes in SQL.
    2.    Update this document in the same PR.
    3.    Bump CHANGELOG.md under [Unreleased] → release tag when applicable.

⸻

Open TODOs
    •    Verify signup trigger on auth.users (not listed).
    •    Re-create RLS policies (per-user access), then document them here.
    
---

## Workout Scoring Flow Summary
1. The app inserts a workout using one of the RPCs (`create_strength_workout`, `create_cardio_workout`, `create_sport_workout_v1`).
2. The RPC writes to the corresponding tables and calls `upsert_workout_score_v1(id)`.
3. The function computes scores per algorithm and updates:
   - `workout_scores` (per workout)
   - `user_best_scores` (per user)
4. When a workout is edited (sets, cardio, or sport), triggers automatically re-evaluate and update scores.
5. The view `vw_user_total_scores` aggregates total points for rankings.

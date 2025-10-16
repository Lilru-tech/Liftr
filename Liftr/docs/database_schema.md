# Liftr – Database Schema Documentation

_Last updated: 2025-10-15_

## Overview
PostgreSQL/Supabase schema for **Liftr**, including tables, relations, views, functions, triggers, RLS, checks, enums, indexes, extensions and grants.

---

## Schemas, Tables & Views

**Schemas scanned:** `auth`, `public`

**auth (managed by Supabase Auth)**
- `users` (BASE TABLE)
- (and other auth infra tables: `sessions`, `identities`, `mfa_*`, `oauth_*`, etc.)

**public**
- Tables: `profiles`, `workouts`, `workout_exercises`, `exercise_sets`, `cardio_sessions`, `sport_sessions`, `personal_records`, `score_rules`, `body_metrics`, `exercises`, `workout_scores`
- Views: `vw_latest_weight`, `vw_workout_volume`

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
| duration_min | integer | YES | — |
| perceived_intensity | enum `intensity` | YES | — |
| notes | text | YES | — |
| created_at | timestamptz | YES | `now()` |
| updated_at | timestamptz | YES | `now()` |

**PK:** `workouts_pkey(id)`  
**FK:** `workouts_user_id_fkey` → `profiles(user_id) ON DELETE CASCADE`  
**Indexes:** `workouts_user_id_started_at_idx(user_id, started_at DESC)`  
**RLS:** enabled  
**Triggers:** `trg_workouts_set_updated_at` (BEFORE UPDATE → `set_updated_at()`)

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

Enums (public)
    •    sex: male, female, other, prefer_not_to_say
    •    workout_kind: strength, cardio, sport, mixed
    •    intensity: easy, moderate, hard, max

⸻

Functions (public)
    •    set_updated_at() — trigger, PL/pgSQL
    •    handle_new_user() — trigger, PL/pgSQL (inserts into public.profiles after insert in auth.users)
    •    score_strength_v1(p_workout_id bigint) → numeric, PL/pgSQL
    •    score_cardio_run_v1(p_workout_id bigint) → numeric, PL/pgSQL
    •    create_profile_on_signup — trigger (listed; verify if used or legacy)

⸻

Triggers

public
    •    profiles:
    •    set_profiles_updated_at → BEFORE UPDATE EXECUTE FUNCTION set_updated_at()
    •    trg_profiles_set_updated_at → BEFORE UPDATE EXECUTE FUNCTION set_updated_at()
    •    workouts:
    •    trg_workouts_set_updated_at → BEFORE UPDATE EXECUTE FUNCTION set_updated_at()

auth
    •    users:
    •    (signup trigger not listed currently; verify existence if you expect auto-profile creation)

⸻

RLS & Security
    •    RLS enabled: true in all public tables listed above.
    •    Policies present: none returned by query → with RLS on and no policies, client access is blocked (except service_role).
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

⸻

Checks
    •    Non-negative checks across: profiles, body_metrics, exercise_sets, cardio_sessions, sport_sessions

⸻

Sequences
    •    Auto-increment sequences: *_id_seq for bigserial PKs.

⸻

Extensions
    •    pg_graphql, pg_stat_statements, pgcrypto, plpgsql, supabase_vault, uuid-ossp

⸻

Grants (public)

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

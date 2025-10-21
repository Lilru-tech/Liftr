# Liftr – Database Schema Documentation

_Last updated: 2025-10-18_

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
- Views: `vw_latest_weight`, `vw_workout_volume`, `vw_user_total_scores`, `vw_user_prs`

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
> `duration_min` is a **generated column**. Do not include it in `INSERT` or `UPDATE`. It is computed from `started_at` and `ended_at`. Attempting to write it will fail (GENERATED ALWAYS).

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
```

---

### `vw_workout_volume`
```sql
SELECT
  w.id AS workout_id,
  w.user_id,
  (COALESCE(SUM((es.reps::numeric * es.weight_kg)), 0::numeric))::numeric(12,3) AS total_volume_kg
FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
LEFT JOIN exercise_sets es ON es.workout_exercise_id = we.id
WHERE w.kind IN ('strength'::workout_kind, 'mixed'::workout_kind)
GROUP BY w.id, w.user_id;
```

---

### `vw_user_total_scores`
Aggregates each user’s best scores across all algorithms.
```sql
SELECT user_id,
       COALESCE(SUM(best_score), 0)::numeric AS total_score
FROM public.user_best_scores
GROUP BY user_id;
```

---

### `vw_user_prs`
Unifies personal records (strength), endurance records (cardio), and sport records into a single shape for profile PRs.

```sql
create or replace view public.vw_user_prs as
select
  'strength'::text as kind,
  pr.user_id,
  e.name        as label,
  pr.metric     as metric,
  pr.value      as value,
  pr.achieved_at
from public.personal_records pr
join public.exercises e on e.id = pr.exercise_id

union all
select
  'cardio'::text as kind,
  er.user_id,
  er.modality    as label,
  er.metric      as metric,
  er.value       as value,
  er.achieved_at
from public.endurance_records er

union all
select
  'sport'::text as kind,
  sr.user_id,
  sr.sport      as label,
  sr.metric     as metric,
  sr.value      as value,
  sr.achieved_at
from public.sport_records sr;
```

> **Note:** The view respects RLS of source tables; only the owner’s rows are visible to the client.

---

## Functions (public)

- `set_updated_at()` — trigger, PL/pgSQL  
- `handle_new_user()` — trigger, PL/pgSQL (inserts into public.profiles after insert in auth.users)  
- `score_strength_v1(p_workout_id bigint)` → numeric, PL/pgSQL  
- `score_cardio_run_v1(p_workout_id bigint)` → numeric, PL/pgSQL  
- `compute_workout_score_v1(p_workout_id bigint)` → TABLE(algorithm text, score numeric), PL/pgSQL  
- `upsert_workout_score_v1(p_workout_id bigint)` → void, PL/pgSQL  
- `create_profile_on_signup` — trigger (verify if legacy)  

---

### RPC: `get_user_prs`

```sql
create or replace function public.get_user_prs(
  p_user_id uuid,
  p_kind    text default null,
  p_search  text default null
) returns table(
  kind text, user_id uuid, label text, metric text, value numeric, achieved_at timestamptz
)
language sql stable as $$
  select *
  from public.vw_user_prs
  where user_id = p_user_id
    and (p_kind  is null or kind = p_kind)
    and (p_search is null or label ilike '%' || p_search || '%')
  order by achieved_at desc
$$;

revoke all on function public.get_user_prs(uuid, text, text) from public;
grant execute on function public.get_user_prs(uuid, text, text) to authenticated;
```

---

## RLS & Security

🆕 Changes in this version (2025-10-21)

Scope: RLS policies (visibility and access propagation for workouts and related entities)

✅ Changes

Affected Table
Change Type
Description
public.workout_exercises
Added / Updated Policy
Added policy we_select_visible allowing users to see exercises belonging to workouts of users they follow.
public.exercise_sets
Added / Updated Policy
Added policy es_select_visible allowing access to sets of followed users’ workouts (through workout_exercises).
public.follows
Added Policy
Added policy follows_select_own so authenticated users can read their own follow relationships.
public.cardio_sessions
Verified RLS
Confirmed cardio_sessions_all_own (visibility of own sessions) active. No structural change.
public.sport_sessions
Verified RLS
Confirmed sport_sessions_all_own active. No structural change.

-- workout_exercises visible to owner or followers
CREATE POLICY we_select_visible ON public.workout_exercises
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.workouts w
    WHERE w.id = workout_exercises.workout_id
      AND (
        w.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.followee_id = w.user_id
        )
      )
  )
);

-- exercise_sets visible via workout_exercises
CREATE POLICY es_select_visible ON public.exercise_sets
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.workout_exercises we
    JOIN public.workouts w ON w.id = we.workout_id
    WHERE we.id = exercise_sets.workout_exercise_id
      AND (
        w.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.followee_id = w.user_id
        )
      )
  )
);

-- Allow users to read their own follow relations
CREATE POLICY follows_select_own
ON public.follows
FOR SELECT
TO authenticated
USING (follower_id = auth.uid());

⚙️ Summary
    •    ✅ No schema or trigger changes.
    •    🔒 Updated RLS to propagate visibility of workouts to followers.
    •    🧩 Ensures users can view cardio/sport/strength details of workouts from followed accounts.
    •    ⚙️ All new policies are permissive, non-destructive, and backward compatible.
    
    
    -- Personal records (strength)
create policy if not exists pr_select_own
on public.personal_records for select
using (user_id = auth.uid());

-- Endurance records (cardio)
create policy if not exists er_select_own
on public.endurance_records for select
using (user_id = auth.uid());

-- Sport records
create policy if not exists sr_select_own
on public.sport_records for select
using (user_id = auth.uid());

-- Workout exercises: visible if own or following the owner
create policy if not exists we_select_visible
on public.workout_exercises for select
to authenticated
using (
  exists (
    select 1 from public.workouts w
    where w.id = workout_exercises.workout_id
      and (
        w.user_id = auth.uid()
        or exists (
          select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.followee_id = w.user_id
        )
      )
  )
);

-- Exercise sets: visible if own or following the owner
create policy if not exists es_select_visible
on public.exercise_sets for select
to authenticated
using (
  exists (
    select 1
    from public.workout_exercises we
    join public.workouts w on w.id = we.workout_id
    where we.id = exercise_sets.workout_exercise_id
      and (
        w.user_id = auth.uid()
        or exists (
          select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.followee_id = w.user_id
        )
      )
  )
);

-- Follows: allow users to read their own rows
create policy if not exists follows_select_own
on public.follows for select
to authenticated
using (follower_id = auth.uid());
    

```sql
-- Personal records (strength)
create policy if not exists pr_select_own
on public.personal_records for select
using (user_id = auth.uid());

-- Endurance records (cardio)
create policy if not exists er_select_own
on public.endurance_records for select
using (user_id = auth.uid());

-- Sport records
create policy if not exists sr_select_own
on public.sport_records for select
using (user_id = auth.uid());
```

---

## Grants (public)
- Functions: `EXECUTE` on `public.get_user_prs` granted to `authenticated` (revoked from `public`).  
- RLS enabled on all PR-related tables.  
- Grants remain as in previous version (anon, authenticated, service_role, postgres).

---

### Summary (2025-10-18)
- Added unified view `vw_user_prs`
- Added RLS policies for all PR tables  
- Added RPC `get_user_prs(uuid, text, text)`  
- Granted `EXECUTE` to `authenticated`  

---

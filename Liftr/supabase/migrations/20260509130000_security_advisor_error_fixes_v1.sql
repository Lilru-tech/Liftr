-- ============================================================================
-- Security advisor ERROR-level fixes (48 findings)
-- Source: get_advisors(security) on project rjzhaafvkxmvlnpsikbi @ 2026-05-09.
-- Idempotent: every statement is guarded so the migration can be re-run.
--
-- Categories addressed:
--   1) security_definer_view              (23) → switch to security_invoker
--   2) rls_disabled_in_public             (18) → enable RLS + policies / revoke
--   3) sensitive_columns_exposed          ( 7) → covered by (2) on stat tables
--
-- Out of scope here (see follow-up migrations):
--   - WARN-level lints (function_search_path_mutable, pg_graphql exposure, …)
--   - Performance lints (auth_rls_initplan, multiple_permissive_policies, …)
-- ============================================================================

set local check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1) SECURITY DEFINER VIEWS → SECURITY INVOKER
--
-- All 23 views are owned by `postgres` and were created without an explicit
-- `security_invoker` reloption, so they currently bypass RLS on the
-- underlying tables. Switching to `security_invoker = true` makes them run
-- as the calling role and respect each base table's policies — which is the
-- behaviour the advisor expects and what the rest of the schema assumes.
-- ---------------------------------------------------------------------------

do $$
declare
  v text;
  views constant text[] := array[
    'cardio_sessions_v',
    'user_rankings',
    'v_competition_history',
    'v_competition_progress',
    'vw_competition_progress',
    'vw_conversation_previews',
    'vw_feature_request_comments',
    'vw_feature_requests',
    'vw_hyrox_session_exercises',
    'vw_latest_weight',
    'vw_profile_counts',
    'vw_sport_session_full',
    'vw_sport_sessions_enriched',
    'vw_sport_sessions_with_stats',
    'vw_user_achievements',
    'vw_user_achievements_debug', -- TODO: consider dropping (hardcoded uuid)
    'vw_user_prs',
    'vw_user_total_scores',
    'vw_weekly_progress',
    'vw_workout_comments_visible',
    'vw_workout_participants',
    'vw_workout_volume',
    'vw_workouts_by_day'
  ];
begin
  foreach v in array views loop
    if exists (
      select 1 from pg_views
      where schemaname = 'public' and viewname = v
    ) then
      execute format(
        'alter view public.%I set (security_invoker = true)',
        v
      );
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 2) RLS DISABLED IN PUBLIC
--
-- 2a) PostGIS metadata: spatial_ref_sys
--     Owned by the postgis extension, so we cannot safely change its RLS.
--     Strip API access instead — clients should never read it directly.
-- ---------------------------------------------------------------------------

revoke all on table public.spatial_ref_sys from anon, authenticated;
-- service_role keeps full access (needed for spatial helpers and admin tasks).

-- ---------------------------------------------------------------------------
-- 2b) Backup / scratch tables: lock down (RLS on, no policies, no API access).
--     Drop candidates flagged with TODO; keep them readable from service_role.
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
  tables constant text[] := array[
    'endurance_records_backup_lilru_20260129',
    'personal_records_backup_lilru_20260129',
    'sport_records_backup_lilru_20260129',
    'sport_records_cleanup_backup_20260410',
    'cnt',                  -- TODO: looks like a leftover scratch table; drop after verifying.
    'score_recalc_audit'    -- internal audit; service_role only.
  ];
begin
  foreach t in array tables loop
    if exists (
      select 1 from pg_tables
      where schemaname = 'public' and tablename = t
    ) then
      execute format(
        'alter table public.%I enable row level security',
        t
      );
      execute format(
        'revoke all on table public.%I from anon, authenticated',
        t
      );
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 2c) Public reference / lookup tables (read-only public data).
--     Enable RLS, allow read for anon+authenticated, revoke direct writes.
--     Schema mutations stay possible via service_role / migrations.
-- ---------------------------------------------------------------------------

-- public.cardio_activity_types
alter table public.cardio_activity_types enable row level security;
revoke insert, update, delete, truncate on public.cardio_activity_types
  from anon, authenticated;
drop policy if exists "cardio_activity_types_read_public"
  on public.cardio_activity_types;
create policy "cardio_activity_types_read_public"
  on public.cardio_activity_types
  for select
  to anon, authenticated
  using (true);

-- public.level_thresholds
alter table public.level_thresholds enable row level security;
revoke insert, update, delete, truncate on public.level_thresholds
  from anon, authenticated;
drop policy if exists "level_thresholds_read_public"
  on public.level_thresholds;
create policy "level_thresholds_read_public"
  on public.level_thresholds
  for select
  to anon, authenticated
  using (true);

-- public.user_rankings_daily — public ranking snapshot.
alter table public.user_rankings_daily enable row level security;
revoke insert, update, delete, truncate on public.user_rankings_daily
  from anon, authenticated;
drop policy if exists "user_rankings_daily_read_public"
  on public.user_rankings_daily;
create policy "user_rankings_daily_read_public"
  on public.user_rankings_daily
  for select
  to anon, authenticated
  using (true);

-- idle_game.vocations
do $$
begin
  if exists (
    select 1 from pg_tables
    where schemaname = 'idle_game' and tablename = 'vocations'
  ) then
    execute 'alter table idle_game.vocations enable row level security';
    execute 'revoke insert, update, delete, truncate on idle_game.vocations from anon, authenticated';
    execute 'drop policy if exists "vocations_read_public" on idle_game.vocations';
    execute $p$
      create policy "vocations_read_public"
        on idle_game.vocations
        for select
        to anon, authenticated
        using (true)
    $p$;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2d) Per-session stat tables.
--     Visibility chains through sport_sessions / cardio_sessions, both of
--     which already have RLS. We piggy-back on their existing policies via
--     EXISTS sub-queries: the stat row is visible iff the parent session is
--     visible to the caller. Writes are gated on the workout owner.
--     This also fixes the 7 sensitive_columns_exposed lints (same tables).
-- ---------------------------------------------------------------------------

-- Helper: every stat table follows the same shape, so encapsulate the policy
-- pair to keep things DRY and idempotent.
do $$
declare
  cfg record;
  parent_table text;
begin
  for cfg in
    select * from (values
      ('cardio_session_stats',    'cardio_sessions'),
      ('handball_session_stats',  'sport_sessions'),
      ('hockey_session_stats',    'sport_sessions'),
      ('hyrox_session_exercises', 'sport_sessions'),
      ('hyrox_session_stats',     'sport_sessions'),
      ('rugby_session_stats',     'sport_sessions'),
      ('volleyball_session_stats','sport_sessions')
    ) as t(child, parent)
  loop
    if not exists (
      select 1 from pg_tables
      where schemaname = 'public' and tablename = cfg.child
    ) then
      continue;
    end if;

    parent_table := cfg.parent;

    execute format(
      'alter table public.%I enable row level security',
      cfg.child
    );

    execute format(
      'drop policy if exists "%s_select_via_session" on public.%I',
      cfg.child, cfg.child
    );
    execute format($p$
      create policy "%1$s_select_via_session"
        on public.%1$I
        for select
        to anon, authenticated
        using (
          exists (
            select 1 from public.%2$I p
            where p.id = %1$I.session_id
          )
        )
    $p$, cfg.child, parent_table);

    execute format(
      'drop policy if exists "%s_modify_owner" on public.%I',
      cfg.child, cfg.child
    );
    execute format($p$
      create policy "%1$s_modify_owner"
        on public.%1$I
        as permissive
        for all
        to authenticated
        using (
          exists (
            select 1
            from public.%2$I p
            join public.workouts w on w.id = p.workout_id
            where p.id = %1$I.session_id
              and w.user_id = (select auth.uid())
          )
        )
        with check (
          exists (
            select 1
            from public.%2$I p
            join public.workouts w on w.id = p.workout_id
            where p.id = %1$I.session_id
              and w.user_id = (select auth.uid())
          )
        )
    $p$, cfg.child, parent_table);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 3) Sanity check (logs only — does not fail the migration).
-- ---------------------------------------------------------------------------

do $$
declare
  v_views_left int;
  v_rls_left int;
begin
  select count(*) into v_views_left
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'v'
    and not coalesce(
      'security_invoker=true' = any (c.reloptions),
      false
    );

  select count(*) into v_rls_left
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
    and not c.relrowsecurity
    and c.relname <> 'spatial_ref_sys';

  raise notice 'Security fixes applied. public views without security_invoker: %, public tables without RLS (excl. spatial_ref_sys): %',
    v_views_left, v_rls_left;
end
$$;

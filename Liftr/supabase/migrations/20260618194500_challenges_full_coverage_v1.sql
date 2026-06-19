-- Challenges full coverage: bilingual muscle matching, 6 new metric kinds, ~85 new templates.

ALTER TABLE public.challenge_templates ADD COLUMN IF NOT EXISTS scope_stat_key text;

CREATE OR REPLACE FUNCTION public._challenge_muscle_matches(p_catalog_muscle text, p_scope_muscle text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $mm$
  SELECT
    p_catalog_muscle IS NOT NULL
    AND p_scope_muscle IS NOT NULL
    AND (
      lower(btrim(p_catalog_muscle)) = lower(btrim(p_scope_muscle))
      OR EXISTS (
        SELECT 1
        FROM (VALUES
          ('abductores', 'abductors'),
          ('aductores', 'adductors'),
          ('antebrazos', 'forearms'),
          ('bíceps', 'biceps'),
          ('cardio', 'cardio'),
          ('core', 'core'),
          ('cuádriceps', 'quadriceps'),
          ('espalda', 'back'),
          ('gemelos', 'calves'),
          ('glúteos', 'glutes'),
          ('hombros', 'shoulders'),
          ('isquiotibiales', 'hamstrings'),
          ('lumbares', 'lower back'),
          ('pecho', 'chest'),
          ('piernas', 'legs'),
          ('trapecios', 'traps'),
          ('tríceps', 'triceps')
        ) AS m(es, en)
        WHERE lower(btrim(p_catalog_muscle)) IN (lower(m.es), lower(m.en))
          AND lower(btrim(p_scope_muscle)) IN (lower(m.es), lower(m.en))
      )
    );
$mm$;

CREATE OR REPLACE FUNCTION public._challenge_sport_stat_value(
  p_session_id bigint,
  p_sport text,
  p_scope_sport text,
  p_stat_key text
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $ssv$
DECLARE
  v_sport text := lower(btrim(coalesce(p_sport, '')));
  v_scope text := lower(btrim(coalesce(p_scope_sport, '')));
  v_key text := lower(btrim(coalesce(p_stat_key, '')));
  v_val numeric;
BEGIN
  IF p_session_id IS NULL OR v_sport = '' OR v_scope = '' OR v_sport <> v_scope THEN
    RETURN 0;
  END IF;

  IF v_sport = 'football' AND v_key = 'goals' THEN
    SELECT COALESCE(goals, 0)::numeric INTO v_val FROM public.football_session_stats WHERE session_id = p_session_id;
  ELSIF v_sport = 'handball' AND v_key = 'goals' THEN
    SELECT COALESCE(goals, 0)::numeric INTO v_val FROM public.handball_session_stats WHERE session_id = p_session_id;
  ELSIF v_sport = 'hockey' AND v_key = 'goals' THEN
    SELECT COALESCE(goals, 0)::numeric INTO v_val FROM public.hockey_session_stats WHERE session_id = p_session_id;
  ELSIF v_sport = 'basketball' AND v_key = 'points' THEN
    SELECT COALESCE(points, 0)::numeric INTO v_val FROM public.basketball_session_stats WHERE session_id = p_session_id;
  ELSIF v_sport = 'rugby' AND v_key = 'tries' THEN
    SELECT COALESCE(tries, 0)::numeric INTO v_val FROM public.rugby_session_stats WHERE session_id = p_session_id;
  ELSE
    RETURN 0;
  END IF;

  RETURN COALESCE(v_val, 0);
END;
$ssv$;

ALTER TABLE public.challenge_templates DROP CONSTRAINT IF EXISTS challenge_templates_metric_kind_check;
ALTER TABLE public.challenge_templates ADD CONSTRAINT challenge_templates_metric_kind_check
  CHECK (metric_kind IN (
    'cumulative_cardio_km',
    'single_set_max_kg',
    'cardio_session_pace_gate',
    'cumulative_sport_sessions',
    'cumulative_strength_workouts',
    'cumulative_strength_reps',
    'cumulative_strength_sets',
    'cumulative_strength_volume_kg',
    'single_set_max_reps',
    'strength_workouts_touching_muscle',
    'cumulative_elevation_gain_m',
    'hyrox_official_time_gate',
    'cumulative_climbing_routes_sent',
    'cumulative_ski_distance_km',
    'cumulative_sport_scoring_stat',
    'cardio_session_rowerg_split_gate'
  ));
CREATE OR REPLACE FUNCTION public.evaluate_challenges_for_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $eval$
DECLARE
  r record;
  ccount int;
  mwin int;
  nrank int;
  w_id bigint;
  adj_ts timestamptz;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM public._challenge_ensure_weekly_instances();

  FOR r IN
    SELECT ci.id AS iid, ci.template_id, ci.period_start, ci.period_end,
           t.metric_kind, t.threshold_numeric, t.threshold_secondary,
           t.max_winners, t.code AS tcode, t.title,
           t.scope_activity_code, t.scope_sport, t.scope_muscle_primary, t.scope_stat_key
    FROM public.challenge_instances ci
    INNER JOIN public.challenge_templates t ON t.id = ci.template_id
    WHERE ci.status = 'active'
      AND now() >= ci.period_start
      AND now() < ci.period_end
    FOR UPDATE OF ci
  LOOP
    SELECT COUNT(*) INTO ccount
    FROM public.challenge_claims cc
    WHERE cc.instance_id = r.iid;

    IF ccount >= r.max_winners THEN
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.challenge_claims cc
      WHERE cc.instance_id = r.iid AND cc.user_id = p_user_id
    ) THEN
      CONTINUE;
    END IF;

    w_id := NULL;
    adj_ts := NULL;

    IF r.metric_kind = 'cumulative_cardio_km' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          COALESCE(cs.distance_km, 0::numeric) AS km,
          SUM(COALESCE(cs.distance_km, 0::numeric)) OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
          ) AS run_sum
        FROM public.workouts w
        INNER JOIN public.cardio_sessions cs ON cs.workout_id = w.id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'cardio'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND (
            r.scope_activity_code IS NULL
            OR lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
          )
      ),
      cross_row AS (
        SELECT wid, ts
        FROM ordered
        WHERE run_sum >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC
        LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'single_set_max_kg' THEN
      SELECT bw.wid, bw.ts INTO w_id, adj_ts
      FROM (
        SELECT w.id AS wid, COALESCE(w.updated_at, w.created_at) AS ts
        FROM public.workouts w
        INNER JOIN public.workout_exercises we ON we.workout_id = w.id
        INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
        INNER JOIN public.exercises ex ON ex.id = we.exercise_id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'strength'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND COALESCE(es.weight_kg, 0::numeric) >= r.threshold_numeric
          AND (
            r.scope_muscle_primary IS NULL
            OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
          )
        ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
        LIMIT 1
      ) bw;

    ELSIF r.metric_kind = 'cardio_session_pace_gate' THEN
      SELECT w.id, COALESCE(w.updated_at, w.created_at)
      INTO w_id, adj_ts
      FROM public.workouts w
      INNER JOIN public.cardio_sessions cs ON cs.workout_id = w.id
      WHERE w.user_id = p_user_id
        AND w.kind::text = 'cardio'
        AND w.state = 'published'::public.workout_state
        AND w.started_at >= r.period_start
        AND w.started_at < r.period_end
        AND COALESCE(cs.distance_km, 0::numeric) >= r.threshold_numeric
        AND COALESCE(cs.duration_sec, 0) > 0
        AND COALESCE(cs.duration_sec, 99999999) <= COALESCE(r.threshold_secondary, 3600)
        AND (
          r.scope_activity_code IS NULL
          OR lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
        )
      ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
      LIMIT 1;

    ELSIF r.metric_kind = 'cumulative_sport_sessions' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          ROW_NUMBER() OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
          ) AS n
        FROM public.workouts w
        INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'sport'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND (
            r.scope_sport IS NULL
            OR lower(btrim(ss.sport::text)) = lower(btrim(r.scope_sport))
          )
      ),
      cross_row AS (
        SELECT wid, ts
        FROM ordered
        WHERE n >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC
        LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cumulative_strength_workouts' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          ROW_NUMBER() OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
          ) AS n
        FROM public.workouts w
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'strength'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
      ),
      cross_row AS (
        SELECT wid, ts
        FROM ordered
        WHERE n >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC
        LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cumulative_strength_reps' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          COALESCE(es.reps, 0)::numeric AS rpt,
          SUM(COALESCE(es.reps, 0)::numeric) OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC, we.order_index ASC, es.id ASC
          ) AS run_sum
        FROM public.workouts w
        INNER JOIN public.workout_exercises we ON we.workout_id = w.id
        INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
        INNER JOIN public.exercises ex ON ex.id = we.exercise_id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'strength'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND (
            r.scope_muscle_primary IS NULL
            OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
          )
      ),
      cross_row AS (
        SELECT wid, ts
        FROM ordered
        WHERE run_sum >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC
        LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cumulative_strength_sets' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          ROW_NUMBER() OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC, we.order_index ASC, es.id ASC
          ) AS n
        FROM public.workouts w
        INNER JOIN public.workout_exercises we ON we.workout_id = w.id
        INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
        INNER JOIN public.exercises ex ON ex.id = we.exercise_id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'strength'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND (COALESCE(es.reps, 0) > 0 OR COALESCE(es.weight_kg, 0::numeric) > 0::numeric)
          AND (
            r.scope_muscle_primary IS NULL
            OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
          )
      ),
      cross_row AS (
        SELECT wid, ts
        FROM ordered
        WHERE n >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC
        LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cumulative_strength_volume_kg' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          (COALESCE(es.weight_kg, 0::numeric) * COALESCE(es.reps, 0)::numeric) AS vol,
          SUM(COALESCE(es.weight_kg, 0::numeric) * COALESCE(es.reps, 0)::numeric) OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC, we.order_index ASC, es.id ASC
          ) AS run_sum
        FROM public.workouts w
        INNER JOIN public.workout_exercises we ON we.workout_id = w.id
        INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
        INNER JOIN public.exercises ex ON ex.id = we.exercise_id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'strength'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND (
            r.scope_muscle_primary IS NULL
            OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
          )
      ),
      cross_row AS (
        SELECT wid, ts
        FROM ordered
        WHERE run_sum >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC
        LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'single_set_max_reps' THEN
      SELECT bw.wid, bw.ts INTO w_id, adj_ts
      FROM (
        SELECT w.id AS wid, COALESCE(w.updated_at, w.created_at) AS ts
        FROM public.workouts w
        INNER JOIN public.workout_exercises we ON we.workout_id = w.id
        INNER JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
        INNER JOIN public.exercises ex ON ex.id = we.exercise_id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'strength'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND COALESCE(es.reps, 0)::numeric >= r.threshold_numeric
          AND (
            r.scope_muscle_primary IS NULL
            OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
          )
        ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
        LIMIT 1
      ) bw;

    ELSIF r.metric_kind = 'strength_workouts_touching_muscle' THEN
      WITH musc_w AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts
        FROM public.workouts w
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'strength'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND r.scope_muscle_primary IS NOT NULL
          AND EXISTS (
            SELECT 1
            FROM public.workout_exercises we2
            INNER JOIN public.exercises ex2 ON ex2.id = we2.exercise_id
            WHERE we2.workout_id = w.id
              AND public._challenge_muscle_matches(ex2.muscle_primary, r.scope_muscle_primary)
          )
      ),
      ordered AS (
        SELECT wid, ts,
          ROW_NUMBER() OVER (ORDER BY ts ASC, wid ASC) AS n
        FROM musc_w
      ),
      cross_row AS (
        SELECT wid, ts
        FROM ordered
        WHERE n >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC
        LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cumulative_elevation_gain_m' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          COALESCE(cs.elevation_gain_m, cs.elev_gain_m, 0)::numeric AS elev,
          SUM(COALESCE(cs.elevation_gain_m, cs.elev_gain_m, 0)::numeric) OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
          ) AS run_sum
        FROM public.workouts w
        INNER JOIN public.cardio_sessions cs ON cs.workout_id = w.id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'cardio'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND (
            r.scope_activity_code IS NULL
            OR lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
          )
      ),
      cross_row AS (
        SELECT wid, ts FROM ordered WHERE run_sum >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'hyrox_official_time_gate' THEN
      SELECT w.id, COALESCE(w.updated_at, w.created_at)
      INTO w_id, adj_ts
      FROM public.workouts w
      INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
      INNER JOIN public.hyrox_session_stats hs ON hs.session_id = ss.id
      WHERE w.user_id = p_user_id
        AND w.kind::text = 'sport'
        AND w.state = 'published'::public.workout_state
        AND w.started_at >= r.period_start
        AND w.started_at < r.period_end
        AND lower(btrim(ss.sport::text)) = 'hyrox'
        AND COALESCE(hs.official_time_sec, 0) > 0
        AND COALESCE(hs.official_time_sec, 99999999) <= COALESCE(r.threshold_secondary, 3600)
      ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
      LIMIT 1;

    ELSIF r.metric_kind = 'cumulative_climbing_routes_sent' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          COALESCE(cls.routes_sent, 0)::numeric AS routes,
          SUM(COALESCE(cls.routes_sent, 0)::numeric) OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
          ) AS run_sum
        FROM public.workouts w
        INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
        INNER JOIN public.climbing_session_stats cls ON cls.session_id = ss.id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'sport'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND lower(btrim(ss.sport::text)) = 'climbing'
      ),
      cross_row AS (
        SELECT wid, ts FROM ordered WHERE run_sum >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cumulative_ski_distance_km' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          COALESCE(sks.total_distance_km, 0::numeric) AS km,
          SUM(COALESCE(sks.total_distance_km, 0::numeric)) OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
          ) AS run_sum
        FROM public.workouts w
        INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
        INNER JOIN public.ski_session_stats sks ON sks.session_id = ss.id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'sport'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND lower(btrim(ss.sport::text)) = 'ski'
      ),
      cross_row AS (
        SELECT wid, ts FROM ordered WHERE run_sum >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cumulative_sport_scoring_stat' THEN
      WITH ordered AS (
        SELECT
          w.id AS wid,
          COALESCE(w.updated_at, w.created_at) AS ts,
          public._challenge_sport_stat_value(ss.id, ss.sport::text, r.scope_sport, r.scope_stat_key) AS stat_val,
          SUM(public._challenge_sport_stat_value(ss.id, ss.sport::text, r.scope_sport, r.scope_stat_key)) OVER (
            ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
          ) AS run_sum
        FROM public.workouts w
        INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
        WHERE w.user_id = p_user_id
          AND w.kind::text = 'sport'
          AND w.state = 'published'::public.workout_state
          AND w.started_at >= r.period_start
          AND w.started_at < r.period_end
          AND r.scope_sport IS NOT NULL
          AND lower(btrim(ss.sport::text)) = lower(btrim(r.scope_sport))
      ),
      cross_row AS (
        SELECT wid, ts FROM ordered WHERE run_sum >= r.threshold_numeric
        ORDER BY ts ASC, wid ASC LIMIT 1
      )
      SELECT cr.wid, cr.ts INTO w_id, adj_ts FROM cross_row cr;

    ELSIF r.metric_kind = 'cardio_session_rowerg_split_gate' THEN
      SELECT w.id, COALESCE(w.updated_at, w.created_at)
      INTO w_id, adj_ts
      FROM public.workouts w
      INNER JOIN public.cardio_sessions cs ON cs.workout_id = w.id
      LEFT JOIN public.cardio_session_stats cst ON cst.session_id = cs.id
      WHERE w.user_id = p_user_id
        AND w.kind::text = 'cardio'
        AND w.state = 'published'::public.workout_state
        AND w.started_at >= r.period_start
        AND w.started_at < r.period_end
        AND COALESCE(cs.distance_km, 0::numeric) >= r.threshold_numeric
        AND NULLIF(btrim(cst.stats->>'split_sec_per_500m'), '') IS NOT NULL
        AND (cst.stats->>'split_sec_per_500m')::numeric <= COALESCE(r.threshold_secondary, 120)
        AND lower(btrim(coalesce(cs.activity_code, cs.modality))) = 'rowerg'
      ORDER BY COALESCE(w.updated_at, w.created_at) ASC, w.id ASC
      LIMIT 1;

    END IF;

    IF w_id IS NULL OR adj_ts IS NULL THEN
      CONTINUE;
    END IF;

    nrank := ccount + 1;

    BEGIN
      INSERT INTO public.challenge_claims (instance_id, user_id, rank, workout_id, adjudication_ts)
      VALUES (r.iid, p_user_id, nrank, w_id, adj_ts);

      IF to_regprocedure('public.create_notification(uuid,text,text,text,jsonb)') IS NOT NULL THEN
        PERFORM public.create_notification(
          p_user_id,
          'challenge_won',
          'Challenge won',
          r.title,
          jsonb_build_object(
            'challenge_instance_id', r.iid::text,
            'template_code', r.tcode,
            'workout_id', w_id
          )
        );
      END IF;
    EXCEPTION WHEN unique_violation THEN
      NULL;
    END;
  END LOOP;
END;
$eval$;

CREATE OR REPLACE FUNCTION public.get_challenge_my_progress_v1(p_instance_id uuid)
RETURNS TABLE (
  progress_value numeric,
  target_value numeric,
  secondary_cap numeric,
  metric_kind text,
  is_eligible boolean
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $prog$
DECLARE
  uid uuid := auth.uid();
  r record;
  pv numeric;
  elig boolean := false;
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  SELECT t.metric_kind, t.threshold_numeric, t.threshold_secondary,
         ci.period_start, ci.period_end,
         t.scope_activity_code, t.scope_sport, t.scope_muscle_primary, t.scope_stat_key
  INTO r
  FROM public.challenge_instances ci
  JOIN public.challenge_templates t ON t.id = ci.template_id
  WHERE ci.id = p_instance_id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF r.metric_kind = 'cumulative_cardio_km' THEN
    SELECT COALESCE(SUM(cs.distance_km), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.cardio_sessions cs ON cs.workout_id = w.id
    WHERE w.user_id = uid
      AND w.kind::text = 'cardio'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (
        r.scope_activity_code IS NULL
        OR lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'single_set_max_kg' THEN
    SELECT COALESCE(MAX(es.weight_kg), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.workout_exercises we ON we.workout_id = w.id
    JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    JOIN public.exercises ex ON ex.id = we.exercise_id
    WHERE w.user_id = uid
      AND w.kind::text = 'strength'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (
        r.scope_muscle_primary IS NULL
        OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cardio_session_pace_gate' THEN
    SELECT COALESCE(MAX(cs.distance_km), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.cardio_sessions cs ON cs.workout_id = w.id
    WHERE w.user_id = uid
      AND w.kind::text = 'cardio'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND COALESCE(cs.duration_sec, 99999999) <= COALESCE(r.threshold_secondary, 3600)
      AND (
        r.scope_activity_code IS NULL
        OR lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_sport_sessions' THEN
    SELECT COUNT(*)::numeric INTO pv
    FROM public.workouts w
    INNER JOIN public.sport_sessions ss ON ss.workout_id = w.id
    WHERE w.user_id = uid
      AND w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (
        r.scope_sport IS NULL
        OR lower(btrim(ss.sport::text)) = lower(btrim(r.scope_sport))
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_strength_workouts' THEN
    SELECT COUNT(*)::numeric INTO pv
    FROM public.workouts w
    WHERE w.user_id = uid
      AND w.kind::text = 'strength'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end;
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_strength_reps' THEN
    SELECT COALESCE(SUM(es.reps), 0)::numeric INTO pv
    FROM public.workouts w
    JOIN public.workout_exercises we ON we.workout_id = w.id
    JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    JOIN public.exercises ex ON ex.id = we.exercise_id
    WHERE w.user_id = uid
      AND w.kind::text = 'strength'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (
        r.scope_muscle_primary IS NULL
        OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_strength_sets' THEN
    SELECT COUNT(*)::numeric INTO pv
    FROM public.workouts w
    JOIN public.workout_exercises we ON we.workout_id = w.id
    JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    JOIN public.exercises ex ON ex.id = we.exercise_id
    WHERE w.user_id = uid
      AND w.kind::text = 'strength'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (COALESCE(es.reps, 0) > 0 OR COALESCE(es.weight_kg, 0::numeric) > 0::numeric)
      AND (
        r.scope_muscle_primary IS NULL
        OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_strength_volume_kg' THEN
    SELECT COALESCE(SUM(COALESCE(es.weight_kg, 0::numeric) * COALESCE(es.reps, 0)::numeric), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.workout_exercises we ON we.workout_id = w.id
    JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    JOIN public.exercises ex ON ex.id = we.exercise_id
    WHERE w.user_id = uid
      AND w.kind::text = 'strength'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (
        r.scope_muscle_primary IS NULL
        OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'single_set_max_reps' THEN
    SELECT COALESCE(MAX(es.reps), 0)::numeric INTO pv
    FROM public.workouts w
    JOIN public.workout_exercises we ON we.workout_id = w.id
    JOIN public.exercise_sets es ON es.workout_exercise_id = we.id
    JOIN public.exercises ex ON ex.id = we.exercise_id
    WHERE w.user_id = uid
      AND w.kind::text = 'strength'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (
        r.scope_muscle_primary IS NULL
        OR public._challenge_muscle_matches(ex.muscle_primary, r.scope_muscle_primary)
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'strength_workouts_touching_muscle' THEN
    SELECT COUNT(*)::numeric INTO pv
    FROM public.workouts w
    WHERE w.user_id = uid
      AND w.kind::text = 'strength'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND r.scope_muscle_primary IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.workout_exercises we2
        INNER JOIN public.exercises ex2 ON ex2.id = we2.exercise_id
        WHERE we2.workout_id = w.id
          AND public._challenge_muscle_matches(ex2.muscle_primary, r.scope_muscle_primary)
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_elevation_gain_m' THEN
    SELECT COALESCE(SUM(COALESCE(cs.elevation_gain_m, cs.elev_gain_m, 0)), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.cardio_sessions cs ON cs.workout_id = w.id
    WHERE w.user_id = uid
      AND w.kind::text = 'cardio'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND (
        r.scope_activity_code IS NULL
        OR lower(btrim(coalesce(cs.activity_code, cs.modality))) = lower(btrim(r.scope_activity_code))
      );
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'hyrox_official_time_gate' THEN
    SELECT COALESCE(MIN(hs.official_time_sec), 0)::numeric INTO pv
    FROM public.workouts w
    JOIN public.sport_sessions ss ON ss.workout_id = w.id
    JOIN public.hyrox_session_stats hs ON hs.session_id = ss.id
    WHERE w.user_id = uid
      AND w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND lower(btrim(ss.sport::text)) = 'hyrox'
      AND COALESCE(hs.official_time_sec, 0) > 0;
    elig := pv > 0 AND pv <= COALESCE(r.threshold_secondary, 3600);

  ELSIF r.metric_kind = 'cumulative_climbing_routes_sent' THEN
    SELECT COALESCE(SUM(cls.routes_sent), 0)::numeric INTO pv
    FROM public.workouts w
    JOIN public.sport_sessions ss ON ss.workout_id = w.id
    JOIN public.climbing_session_stats cls ON cls.session_id = ss.id
    WHERE w.user_id = uid
      AND w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND lower(btrim(ss.sport::text)) = 'climbing';
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_ski_distance_km' THEN
    SELECT COALESCE(SUM(sks.total_distance_km), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.sport_sessions ss ON ss.workout_id = w.id
    JOIN public.ski_session_stats sks ON sks.session_id = ss.id
    WHERE w.user_id = uid
      AND w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND lower(btrim(ss.sport::text)) = 'ski';
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cumulative_sport_scoring_stat' THEN
    SELECT COALESCE(SUM(public._challenge_sport_stat_value(ss.id, ss.sport::text, r.scope_sport, r.scope_stat_key)), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.sport_sessions ss ON ss.workout_id = w.id
    WHERE w.user_id = uid
      AND w.kind::text = 'sport'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND r.scope_sport IS NOT NULL
      AND lower(btrim(ss.sport::text)) = lower(btrim(r.scope_sport));
    elig := pv >= r.threshold_numeric;

  ELSIF r.metric_kind = 'cardio_session_rowerg_split_gate' THEN
    SELECT COALESCE(MAX(cs.distance_km), 0::numeric) INTO pv
    FROM public.workouts w
    JOIN public.cardio_sessions cs ON cs.workout_id = w.id
    LEFT JOIN public.cardio_session_stats cst ON cst.session_id = cs.id
    WHERE w.user_id = uid
      AND w.kind::text = 'cardio'
      AND w.state = 'published'::public.workout_state
      AND w.started_at >= r.period_start
      AND w.started_at < r.period_end
      AND lower(btrim(coalesce(cs.activity_code, cs.modality))) = 'rowerg'
      AND NULLIF(btrim(cst.stats->>'split_sec_per_500m'), '') IS NOT NULL
      AND (cst.stats->>'split_sec_per_500m')::numeric <= COALESCE(r.threshold_secondary, 120);
    elig := pv >= r.threshold_numeric;

  END IF;

  progress_value := pv;
  target_value := r.threshold_numeric;
  secondary_cap := r.threshold_secondary;
  metric_kind := r.metric_kind;
  is_eligible := elig;
  RETURN NEXT;
END;
$prog$;

CREATE OR REPLACE FUNCTION public.list_active_challenges_v1()
RETURNS TABLE (
  instance_id uuid,
  template_code text,
  title text,
  description text,
  cadence text,
  period_start timestamptz,
  period_end timestamptz,
  max_winners int,
  claims_count bigint,
  metric_kind text,
  threshold_numeric numeric,
  threshold_secondary numeric,
  challenge_category text,
  scope_activity_code text,
  scope_sport text,
  scope_muscle_primary text,
  viewer_rank int,
  viewer_claimed boolean
)
LANGUAGE plpgsql
-- VOLATILE: debe escribir vía _challenge_ensure_weekly_instances (UPDATE/INSERT). STABLE provoca
-- «cannot execute UPDATE in a read-only transaction» en PostgREST cuando la TX es read-only.
VOLATILE
-- SECURITY DEFINER: _challenge_ensure_weekly_instances tiene EXECUTE revocado para authenticated
-- (db audit lockdown); con INVOKER la llamada falla con permission denied.
SECURITY DEFINER
SET search_path TO 'public'
AS $list$
DECLARE
  v_uid uuid;
BEGIN
  PERFORM public._challenge_ensure_weekly_instances();
  v_uid := auth.uid();

  RETURN QUERY
  SELECT
    ci.id,
    t.code,
    t.title,
    t.description,
    t.cadence,
    ci.period_start,
    ci.period_end,
    t.max_winners,
    (SELECT COUNT(*)::bigint FROM public.challenge_claims cc WHERE cc.instance_id = ci.id),
    t.metric_kind,
    t.threshold_numeric,
    t.threshold_secondary,
    CASE
      WHEN t.metric_kind IN (
        'cumulative_cardio_km', 'cardio_session_pace_gate',
        'cumulative_elevation_gain_m', 'cardio_session_rowerg_split_gate'
      ) THEN 'cardio'
      WHEN t.metric_kind IN (
        'cumulative_sport_sessions', 'hyrox_official_time_gate',
        'cumulative_climbing_routes_sent', 'cumulative_ski_distance_km',
        'cumulative_sport_scoring_stat'
      ) THEN 'sport'
      ELSE 'strength'
    END::text,
    t.scope_activity_code,
    t.scope_sport,
    t.scope_muscle_primary,
    (SELECT cc.rank FROM public.challenge_claims cc
     WHERE cc.instance_id = ci.id AND v_uid IS NOT NULL AND cc.user_id = v_uid
     LIMIT 1),
    EXISTS (
      SELECT 1 FROM public.challenge_claims cc2
      WHERE cc2.instance_id = ci.id AND v_uid IS NOT NULL AND cc2.user_id = v_uid
    )
  FROM public.challenge_instances ci
  INNER JOIN public.challenge_templates t ON t.id = ci.template_id
  WHERE ci.status = 'active'
    AND now() >= ci.period_start
    AND now() < ci.period_end
  ORDER BY t.cadence ASC, t.code ASC;
END;
$list$;

INSERT INTO public.challenge_templates (
  code, title, description, metric_kind, threshold_numeric, threshold_secondary, cadence, max_winners, is_active,
  scope_activity_code, scope_sport, scope_muscle_primary, scope_stat_key
)
VALUES
('monthly_walk_first_80km','First to 80 km walk (monthly)','Monthly cumulative distance for activity walk.','cumulative_cardio_km',80,NULL,'month',5,true,'walk',NULL,NULL,NULL),
('monthly_hike_first_50km','First to 50 km hike (monthly)','Monthly cumulative distance for activity hike.','cumulative_cardio_km',50,NULL,'month',5,true,'hike',NULL,NULL,NULL),
('monthly_treadmill_first_35km','First to 35 km treadmill (monthly)','Monthly cumulative distance for activity treadmill.','cumulative_cardio_km',35,NULL,'month',5,true,'treadmill',NULL,NULL,NULL),
('monthly_bike_first_120km','First to 120 km bike (monthly)','Monthly cumulative distance for activity bike.','cumulative_cardio_km',120,NULL,'month',5,true,'bike',NULL,NULL,NULL),
('monthly_e_bike_first_150km','First to 150 km e bike (monthly)','Monthly cumulative distance for activity e_bike.','cumulative_cardio_km',150,NULL,'month',5,true,'e_bike',NULL,NULL,NULL),
('monthly_mtb_first_90km','First to 90 km mtb (monthly)','Monthly cumulative distance for activity mtb.','cumulative_cardio_km',90,NULL,'month',5,true,'mtb',NULL,NULL,NULL),
('monthly_indoor_cycling_first_200km','First to 200 km indoor cycling (monthly)','Monthly cumulative distance for activity indoor_cycling.','cumulative_cardio_km',200,NULL,'month',5,true,'indoor_cycling',NULL,NULL,NULL),
('monthly_rowerg_first_40km','First to 40 km rowerg (monthly)','Monthly cumulative distance for activity rowerg.','cumulative_cardio_km',40,NULL,'month',5,true,'rowerg',NULL,NULL,NULL),
('monthly_swim_pool_first_10km','First to 10 km swim pool (monthly)','Monthly cumulative distance for activity swim_pool.','cumulative_cardio_km',10,NULL,'month',5,true,'swim_pool',NULL,NULL,NULL),
('monthly_swim_open_water_first_6km','First to 6 km swim open water (monthly)','Monthly cumulative distance for activity swim_open_water.','cumulative_cardio_km',6,NULL,'month',5,true,'swim_open_water',NULL,NULL,NULL),
('weekly_ski_first_2_sessions','First to 2 ski sessions (weekly)','Published sport workouts tagged ski.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'ski',NULL,NULL),
('weekly_climbing_first_2_sessions','First to 2 climbing sessions (weekly)','Published sport workouts tagged climbing.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'climbing',NULL,NULL),
('monthly_tennis_first_8_sessions','First to 8 tennis sessions (monthly)','Monthly cumulative tennis sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'tennis',NULL,NULL),
('monthly_football_first_8_sessions','First to 8 football sessions (monthly)','Monthly cumulative football sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'football',NULL,NULL),
('monthly_basketball_first_8_sessions','First to 8 basketball sessions (monthly)','Monthly cumulative basketball sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'basketball',NULL,NULL),
('monthly_badminton_first_8_sessions','First to 8 badminton sessions (monthly)','Monthly cumulative badminton sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'badminton',NULL,NULL),
('monthly_squash_first_8_sessions','First to 8 squash sessions (monthly)','Monthly cumulative squash sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'squash',NULL,NULL),
('monthly_table_tennis_first_8_sessions','First to 8 table_tennis sessions (monthly)','Monthly cumulative table_tennis sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'table_tennis',NULL,NULL),
('monthly_volleyball_first_8_sessions','First to 8 volleyball sessions (monthly)','Monthly cumulative volleyball sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'volleyball',NULL,NULL),
('monthly_handball_first_8_sessions','First to 8 handball sessions (monthly)','Monthly cumulative handball sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'handball',NULL,NULL),
('monthly_hockey_first_8_sessions','First to 8 hockey sessions (monthly)','Monthly cumulative hockey sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'hockey',NULL,NULL),
('monthly_rugby_first_8_sessions','First to 8 rugby sessions (monthly)','Monthly cumulative rugby sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'rugby',NULL,NULL),
('monthly_hyrox_first_8_sessions','First to 8 hyrox sessions (monthly)','Monthly cumulative hyrox sessions.','cumulative_sport_sessions',8,NULL,'month',8,true,NULL,'hyrox',NULL,NULL),
('monthly_ski_first_6_sessions','First to 6 ski sessions (monthly)','Monthly cumulative ski sessions.','cumulative_sport_sessions',6,NULL,'month',8,true,NULL,'ski',NULL,NULL),
('monthly_climbing_first_6_sessions','First to 6 climbing sessions (monthly)','Monthly cumulative climbing sessions.','cumulative_sport_sessions',6,NULL,'month',8,true,NULL,'climbing',NULL,NULL),
('weekly_3_abductors_sessions','First to 3 abductors-focused workouts (weekly)','Strength workouts including at least one abductors exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'abductors',NULL),
('weekly_3_adductors_sessions','First to 3 adductors-focused workouts (weekly)','Strength workouts including at least one adductors exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'adductors',NULL),
('weekly_3_forearms_sessions','First to 3 forearms-focused workouts (weekly)','Strength workouts including at least one forearms exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'forearms',NULL),
('weekly_3_biceps_sessions','First to 3 biceps-focused workouts (weekly)','Strength workouts including at least one biceps exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'biceps',NULL),
('weekly_3_core_sessions','First to 3 core-focused workouts (weekly)','Strength workouts including at least one core exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'core',NULL),
('weekly_3_quadriceps_sessions','First to 3 quadriceps-focused workouts (weekly)','Strength workouts including at least one quadriceps exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'quadriceps',NULL),
('weekly_3_calves_sessions','First to 3 calves-focused workouts (weekly)','Strength workouts including at least one calves exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'calves',NULL),
('weekly_3_glutes_sessions','First to 3 glutes-focused workouts (weekly)','Strength workouts including at least one glutes exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'glutes',NULL),
('weekly_3_hamstrings_sessions','First to 3 hamstrings-focused workouts (weekly)','Strength workouts including at least one hamstrings exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'hamstrings',NULL),
('weekly_3_lower_back_sessions','First to 3 lower back-focused workouts (weekly)','Strength workouts including at least one lower back exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'lower back',NULL),
('weekly_3_traps_sessions','First to 3 traps-focused workouts (weekly)','Strength workouts including at least one traps exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'traps',NULL),
('weekly_3_triceps_sessions','First to 3 triceps-focused workouts (weekly)','Strength workouts including at least one triceps exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'triceps',NULL),
('monthly_8_abductors_sessions','First to 8 abductors-focused workouts (monthly)','Monthly: strength workouts including at least one abductors exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'abductors',NULL),
('monthly_8_adductors_sessions','First to 8 adductors-focused workouts (monthly)','Monthly: strength workouts including at least one adductors exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'adductors',NULL),
('monthly_8_forearms_sessions','First to 8 forearms-focused workouts (monthly)','Monthly: strength workouts including at least one forearms exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'forearms',NULL),
('monthly_8_biceps_sessions','First to 8 biceps-focused workouts (monthly)','Monthly: strength workouts including at least one biceps exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'biceps',NULL),
('monthly_8_core_sessions','First to 8 core-focused workouts (monthly)','Monthly: strength workouts including at least one core exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'core',NULL),
('monthly_8_quadriceps_sessions','First to 8 quadriceps-focused workouts (monthly)','Monthly: strength workouts including at least one quadriceps exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'quadriceps',NULL),
('monthly_8_back_sessions','First to 8 back-focused workouts (monthly)','Monthly: strength workouts including at least one back exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'back',NULL),
('monthly_8_calves_sessions','First to 8 calves-focused workouts (monthly)','Monthly: strength workouts including at least one calves exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'calves',NULL),
('monthly_8_glutes_sessions','First to 8 glutes-focused workouts (monthly)','Monthly: strength workouts including at least one glutes exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'glutes',NULL),
('monthly_8_shoulders_sessions','First to 8 shoulders-focused workouts (monthly)','Monthly: strength workouts including at least one shoulders exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'shoulders',NULL),
('monthly_8_hamstrings_sessions','First to 8 hamstrings-focused workouts (monthly)','Monthly: strength workouts including at least one hamstrings exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'hamstrings',NULL),
('monthly_8_lower_back_sessions','First to 8 lower back-focused workouts (monthly)','Monthly: strength workouts including at least one lower back exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'lower back',NULL),
('monthly_8_chest_sessions','First to 8 chest-focused workouts (monthly)','Monthly: strength workouts including at least one chest exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'chest',NULL),
('monthly_8_legs_sessions','First to 8 legs-focused workouts (monthly)','Monthly: strength workouts including at least one legs exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'legs',NULL),
('monthly_8_traps_sessions','First to 8 traps-focused workouts (monthly)','Monthly: strength workouts including at least one traps exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'traps',NULL),
('monthly_8_triceps_sessions','First to 8 triceps-focused workouts (monthly)','Monthly: strength workouts including at least one triceps exercise.','strength_workouts_touching_muscle',8,NULL,'month',8,true,NULL,NULL,'triceps',NULL),
('evergreen_first_5k_under_22min','First 5 km under 22 min (open)','Evergreen pace gate: ≥ 5 km and ≤ 1320 s.','cardio_session_pace_gate',5,1320,'once',10,true,NULL,NULL,NULL,NULL),
('evergreen_hm_under_105min','First half marathon under 1h45 (open)','Evergreen: ≥ 21.1 km and ≤ 6300 s.','cardio_session_pace_gate',21.1,6300,'once',8,true,NULL,NULL,NULL,NULL),
('evergreen_first_strength_set_120kg','First to a 120 kg+ set (open)','Evergreen strength: first athletes with a set ≥ 120 kg.','single_set_max_kg',120,NULL,'once',10,true,NULL,NULL,NULL,NULL),
('evergreen_first_15000_kg_volume','First to 15,000 kg volume (open)','Evergreen cumulative volume in any window until slots fill.','cumulative_strength_volume_kg',15000,NULL,'once',15,true,NULL,NULL,NULL,NULL),
('evergreen_padel_first_20_sessions','First to 20 padel sessions (open)','Evergreen cumulative padel sessions.','cumulative_sport_sessions',20,NULL,'once',15,true,NULL,'padel',NULL,NULL),
('evergreen_hyrox_first_10_sessions','First to 10 Hyrox sessions (open)','Evergreen cumulative Hyrox sessions.','cumulative_sport_sessions',10,NULL,'once',12,true,NULL,'hyrox',NULL,NULL),
('evergreen_first_marathon_under_3h30','First marathon under 3h30 (open)','Evergreen: ≥ 42.195 km and ≤ 12600 s.','cardio_session_pace_gate',42.195,12600,'once',5,true,NULL,NULL,NULL,NULL),
('evergreen_first_strength_set_60kg','First to a 60 kg+ set (open)','Entry evergreen strength milestone.','single_set_max_kg',60,NULL,'once',20,true,NULL,NULL,NULL,NULL),
('evergreen_first_20_reps_set','First 20+ rep set (open)','Evergreen: first athletes with a 20+ rep set.','single_set_max_reps',20,NULL,'once',15,true,NULL,NULL,NULL,NULL),
('evergreen_tennis_first_15_sessions','First to 15 tennis sessions (open)','Evergreen cumulative tennis sessions.','cumulative_sport_sessions',15,NULL,'once',12,true,NULL,'tennis',NULL,NULL),
('evergreen_first_half_marathon_under_100min','First half marathon under 100 min (open)','Evergreen: ≥ 21.1 km and ≤ 6000 s.','cardio_session_pace_gate',21.1,6000,'once',8,true,NULL,NULL,NULL,NULL),
('evergreen_first_10_strength_workouts','First to 10 strength workouts (open)','Evergreen cumulative strength workouts.','cumulative_strength_workouts',10,NULL,'once',15,true,NULL,NULL,NULL,NULL),
('evergreen_first_50km_cardio','First to 50 km cardio (open)','Evergreen cumulative cardio distance.','cumulative_cardio_km',50,NULL,'once',20,true,NULL,NULL,NULL,NULL),
('evergreen_first_5_strength_workouts','First to 5 strength workouts (open)','Evergreen entry strength volume.','cumulative_strength_workouts',5,NULL,'once',25,true,NULL,NULL,NULL,NULL),
('evergreen_first_1000_reps','First to 1,000 strength reps (open)','Evergreen cumulative reps.','cumulative_strength_reps',1000,NULL,'once',15,true,NULL,NULL,NULL,NULL),
('evergreen_first_3000_kg_volume','First to 3,000 kg volume (open)','Evergreen entry volume milestone.','cumulative_strength_volume_kg',3000,NULL,'once',20,true,NULL,NULL,NULL,NULL),
('evergreen_hyrox_official_under_70min','Hyrox official time under 70 min (open)','Evergreen: Hyrox with official time ≤ 4200 s. Log official time in session stats.','hyrox_official_time_gate',1,4200,'once',10,true,NULL,'hyrox',NULL,NULL),
('weekly_hyrox_official_under_75min','Hyrox official time under 75 min (weekly)','Weekly: Hyrox session with official time ≤ 4500 s.','hyrox_official_time_gate',1,4500,'week',8,true,NULL,'hyrox',NULL,NULL),
('monthly_hyrox_official_under_72min','Hyrox official time under 72 min (monthly)','Monthly: Hyrox session with official time ≤ 4320 s.','hyrox_official_time_gate',1,4320,'month',8,true,NULL,'hyrox',NULL,NULL),
('weekly_climbing_10_routes_sent','First to 10 climbing routes sent (weekly)','Weekly cumulative routes sent (log in climbing stats).','cumulative_climbing_routes_sent',10,NULL,'week',8,true,NULL,'climbing',NULL,NULL),
('monthly_climbing_30_routes_sent','First to 30 climbing routes sent (monthly)','Monthly cumulative routes sent.','cumulative_climbing_routes_sent',30,NULL,'month',8,true,NULL,'climbing',NULL,NULL),
('weekly_ski_20km','First to 20 km skiing (weekly)','Weekly cumulative ski distance from session stats.','cumulative_ski_distance_km',20,NULL,'week',8,true,NULL,'ski',NULL,NULL),
('monthly_ski_50km','First to 50 km skiing (monthly)','Monthly cumulative ski distance.','cumulative_ski_distance_km',50,NULL,'month',8,true,NULL,'ski',NULL,NULL),
('weekly_elevation_2000m','First to 2,000 m elevation (weekly)','Weekly cumulative elevation gain from cardio sessions.','cumulative_elevation_gain_m',2000,NULL,'week',8,true,NULL,NULL,NULL,NULL),
('monthly_elevation_8000m','First to 8,000 m elevation (monthly)','Monthly cumulative elevation gain.','cumulative_elevation_gain_m',8000,NULL,'month',8,true,NULL,NULL,NULL,NULL),
('weekly_hike_elevation_5000m','First to 5,000 m hike elevation (weekly)','Weekly elevation gain from hike sessions only.','cumulative_elevation_gain_m',5000,NULL,'week',8,true,'hike',NULL,NULL,NULL),
('weekly_football_3_goals','First to 3 football goals (weekly)','Weekly cumulative goals (log in football stats).','cumulative_sport_scoring_stat',3,NULL,'week',8,true,NULL,'football',NULL,'goals'),
('monthly_football_10_goals','First to 10 football goals (monthly)','Monthly cumulative football goals.','cumulative_sport_scoring_stat',10,NULL,'month',8,true,NULL,'football',NULL,'goals'),
('weekly_handball_3_goals','First to 3 handball goals (weekly)','Weekly cumulative handball goals.','cumulative_sport_scoring_stat',3,NULL,'week',8,true,NULL,'handball',NULL,'goals'),
('monthly_handball_10_goals','First to 10 handball goals (monthly)','Monthly cumulative handball goals.','cumulative_sport_scoring_stat',10,NULL,'month',8,true,NULL,'handball',NULL,'goals'),
('weekly_hockey_3_goals','First to 3 hockey goals (weekly)','Weekly cumulative hockey goals.','cumulative_sport_scoring_stat',3,NULL,'week',8,true,NULL,'hockey',NULL,'goals'),
('monthly_hockey_10_goals','First to 10 hockey goals (monthly)','Monthly cumulative hockey goals.','cumulative_sport_scoring_stat',10,NULL,'month',8,true,NULL,'hockey',NULL,'goals'),
('weekly_basketball_15_points','First to 15 basketball points (weekly)','Weekly cumulative basketball points.','cumulative_sport_scoring_stat',15,NULL,'week',8,true,NULL,'basketball',NULL,'points'),
('monthly_basketball_40_points','First to 40 basketball points (monthly)','Monthly cumulative basketball points.','cumulative_sport_scoring_stat',40,NULL,'month',8,true,NULL,'basketball',NULL,'points'),
('weekly_rugby_3_tries','First to 3 rugby tries (weekly)','Weekly cumulative rugby tries.','cumulative_sport_scoring_stat',3,NULL,'week',8,true,NULL,'rugby',NULL,'tries'),
('monthly_rugby_10_tries','First to 10 rugby tries (monthly)','Monthly cumulative rugby tries.','cumulative_sport_scoring_stat',10,NULL,'month',8,true,NULL,'rugby',NULL,'tries'),
('monthly_rowerg_5km_under_2min_split','First 5 km row under 2:00/500m (monthly)','Monthly: rowerg session ≥ 5 km with split ≤ 120 s/500m.','cardio_session_rowerg_split_gate',5,120,'month',5,true,'rowerg',NULL,NULL,NULL)
ON CONFLICT (code) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  metric_kind = EXCLUDED.metric_kind,
  threshold_numeric = EXCLUDED.threshold_numeric,
  threshold_secondary = EXCLUDED.threshold_secondary,
  cadence = EXCLUDED.cadence,
  max_winners = EXCLUDED.max_winners,
  is_active = EXCLUDED.is_active,
  scope_activity_code = EXCLUDED.scope_activity_code,
  scope_sport = EXCLUDED.scope_sport,
  scope_muscle_primary = EXCLUDED.scope_muscle_primary,
  scope_stat_key = EXCLUDED.scope_stat_key;

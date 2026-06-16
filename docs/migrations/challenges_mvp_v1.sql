-- =============================================================================
-- Liftr — Challenges MVP v1: retos semanales globales (plantilla + instancia +
-- adjudicación "primeros N"). Alinear ventana temporal con leaderboards
-- (started_at del workout en [period_start, period_end), state = published).
--
-- Reglas híbridas por plantilla (metric_kind):
--   cumulative_cardio_km — Suma km cardio en la semana; el "cruce" del umbral
--     se ordena por adjudication_ts = COALESCE(w.updated_at, w.created_at) ASC
--     entre entrenos que cuentan (solo publicados).
--   single_set_max_kg — Primera publicación (mismo adjudication_ts) con al menos
--     una serie >= threshold_numeric en un entreno fuerza en ventana.
--   cardio_session_pace_gate — Una sesión cardio con distance_km >= threshold_numeric
--     y duration_sec <= threshold_secondary; gana quien antes publica tal sesión.
--
-- Empates en el mismo adjudication_ts: tie_break lexicográfico user_id ASC.
-- Sin retroactividad fuera de la instancia activa. max_winners en plantilla.
--
-- Notificación opcional vía public.create_notification (si existe).
-- Ejecutar en SQL Editor Supabase tras revisar grants/RLS del proyecto.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.challenge_templates (
  id serial PRIMARY KEY,
  code text NOT NULL UNIQUE,
  title text NOT NULL,
  description text NOT NULL,
  metric_kind text NOT NULL
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
      'strength_workouts_touching_muscle'
    )),
  threshold_numeric numeric NOT NULL,
  threshold_secondary numeric,
  cadence text NOT NULL DEFAULT 'week'
    CHECK (cadence IN ('week', 'month', 'once')),
  max_winners int NOT NULL DEFAULT 1 CHECK (max_winners >= 1),
  is_active boolean NOT NULL DEFAULT true,
  scope_activity_code text,
  scope_sport text,
  scope_muscle_primary text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.challenge_instances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id int NOT NULL REFERENCES public.challenge_templates (id) ON DELETE CASCADE,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (template_id, period_start)
);

CREATE TABLE IF NOT EXISTS public.challenge_claims (
  id bigserial PRIMARY KEY,
  instance_id uuid NOT NULL REFERENCES public.challenge_instances (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (user_id) ON DELETE CASCADE,
  rank int NOT NULL CHECK (rank >= 1),
  workout_id bigint REFERENCES public.workouts (id) ON DELETE SET NULL,
  adjudication_ts timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (instance_id, user_id),
  UNIQUE (instance_id, rank)
);

CREATE INDEX IF NOT EXISTS idx_challenge_instances_active
  ON public.challenge_instances (status, period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_challenge_claims_instance
  ON public.challenge_claims (instance_id, rank);

ALTER TABLE public.challenge_templates ADD COLUMN IF NOT EXISTS scope_activity_code text;
ALTER TABLE public.challenge_templates ADD COLUMN IF NOT EXISTS scope_sport text;
ALTER TABLE public.challenge_templates ADD COLUMN IF NOT EXISTS scope_muscle_primary text;

-- ---------------------------------------------------------------------------
-- Ventana semanal ISO (lunes 00:00 UTC) coherente con date_trunc('week', now())
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._challenge_week_bounds_utc(p_at timestamptz DEFAULT now())
RETURNS TABLE (w_start timestamptz, w_end timestamptz)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $b$
  SELECT date_trunc('week', p_at), date_trunc('week', p_at) + interval '7 days';
$b$;

-- Crea instancias faltantes: semana ISO actual, mes calendario actual, o ventana larga para cadence once.
CREATE OR REPLACE FUNCTION public._challenge_ensure_weekly_instances()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $ensure$
DECLARE
  ws timestamptz;
  we timestamptz;
  ms timestamptz;
  me timestamptz;
BEGIN
  SELECT b.w_start, b.w_end INTO ws, we FROM public._challenge_week_bounds_utc(now()) AS b;
  ms := date_trunc('month', now());
  me := ms + interval '1 month';

  UPDATE public.challenge_instances ci
  SET status = 'closed'
  WHERE ci.status = 'active'
    AND ci.period_end <= now();

  INSERT INTO public.challenge_instances (template_id, period_start, period_end, status)
  SELECT t.id, ws, we, 'active'
  FROM public.challenge_templates t
  WHERE t.is_active
    AND t.cadence = 'week'
    AND NOT EXISTS (
      SELECT 1
      FROM public.challenge_instances x
      WHERE x.template_id = t.id
        AND x.period_start = ws
    );

  INSERT INTO public.challenge_instances (template_id, period_start, period_end, status)
  SELECT t.id, ms, me, 'active'
  FROM public.challenge_templates t
  WHERE t.is_active
    AND t.cadence = 'month'
    AND NOT EXISTS (
      SELECT 1
      FROM public.challenge_instances x
      WHERE x.template_id = t.id
        AND x.period_start = ms
    );

  INSERT INTO public.challenge_instances (template_id, period_start, period_end, status)
  SELECT t.id, timestamptz '2000-01-01 UTC', timestamptz '2099-12-31 UTC', 'active'
  FROM public.challenge_templates t
  WHERE t.is_active
    AND t.cadence = 'once'
    AND NOT EXISTS (
      SELECT 1
      FROM public.challenge_instances x
      WHERE x.template_id = t.id
        AND x.status = 'active'
    );
END;
$ensure$;

REVOKE ALL ON FUNCTION public._challenge_week_bounds_utc(timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._challenge_ensure_weekly_instances() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._challenge_week_bounds_utc(timestamptz) TO postgres;
GRANT EXECUTE ON FUNCTION public._challenge_ensure_weekly_instances() TO postgres;
-- list/detail RPCs (invoker) llaman a ensure; la función es segura (solo crea filas de semana faltantes)
GRANT EXECUTE ON FUNCTION public._challenge_ensure_weekly_instances() TO authenticated;

-- ---------------------------------------------------------------------------
-- Evaluación (llamar al publicar entreno o vía trigger)
-- ---------------------------------------------------------------------------
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
           t.scope_activity_code, t.scope_sport, t.scope_muscle_primary
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
            OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
            OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
            OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
            OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
            OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
              AND lower(btrim(ex2.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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

CREATE OR REPLACE FUNCTION public._workouts_evaluate_challenges_after_publish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $tr$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state = 'published'::public.workout_state THEN
      PERFORM public.evaluate_challenges_for_user(NEW.user_id);
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.state = 'published'::public.workout_state
       AND (OLD.state IS DISTINCT FROM 'published'::public.workout_state) THEN
      PERFORM public.evaluate_challenges_for_user(NEW.user_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$tr$;

DROP TRIGGER IF EXISTS tr_workouts_evaluate_challenges_after_publish ON public.workouts;
CREATE TRIGGER tr_workouts_evaluate_challenges_after_publish
  AFTER INSERT OR UPDATE OF state ON public.workouts
  FOR EACH ROW
  EXECUTE PROCEDURE public._workouts_evaluate_challenges_after_publish();

REVOKE ALL ON FUNCTION public.evaluate_challenges_for_user(uuid) FROM PUBLIC;
-- Solo trigger interno + service_role (replays); no exponer a clientes para evitar abuso por user_id
GRANT EXECUTE ON FUNCTION public.evaluate_challenges_for_user(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.evaluate_challenges_for_user(uuid) TO service_role;

REVOKE ALL ON FUNCTION public._workouts_evaluate_challenges_after_publish() FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- RPCs cliente
-- ---------------------------------------------------------------------------
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
      WHEN t.metric_kind IN ('cumulative_cardio_km', 'cardio_session_pace_gate') THEN 'cardio'
      WHEN t.metric_kind = 'cumulative_sport_sessions' THEN 'sport'
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

-- Leaderboard: challenge podium slots claimed in period (by adjudication_ts), global/friends + demographics like training RPCs.
CREATE OR REPLACE FUNCTION public.get_challenge_podiums_period_leaderboard_v1(
  p_scope text,
  p_period text,
  p_limit int DEFAULT 100,
  p_sex text DEFAULT NULL,
  p_age_band text DEFAULT NULL
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  podium_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $podium_lb$
WITH bounds AS (
  SELECT
    CASE lower(coalesce(p_period, 'week'))
      WHEN 'day'   THEN date_trunc('day', now())
      WHEN 'week'  THEN date_trunc('week', now())
      WHEN 'month' THEN date_trunc('month', now())
      WHEN 'all'   THEN '1970-01-01'::timestamptz
      ELSE date_trunc('week', now())
    END AS t_start,
    now() AS t_end
),
agg AS (
  SELECT cc.user_id AS uid, COUNT(*)::bigint AS podium_count
  FROM public.challenge_claims cc
  CROSS JOIN bounds b
  WHERE cc.adjudication_ts >= b.t_start
    AND cc.adjudication_ts < b.t_end
  GROUP BY cc.user_id
),
scoped AS (
  SELECT a.uid, a.podium_count
  FROM agg a
  INNER JOIN public.profiles pr ON pr.user_id = a.uid
  WHERE
    (p_sex IS NULL OR p_sex = '' OR pr.sex = p_sex::public.sex)
    AND (
      p_age_band IS NULL OR p_age_band = ''
      OR (
        CASE p_age_band
          WHEN '18-24' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 18 AND 24
          WHEN '25-34' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 25 AND 34
          WHEN '35-44' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 35 AND 44
          WHEN '45-54' THEN extract(year from age(current_date, pr.date_of_birth)) BETWEEN 45 AND 54
          WHEN '55+'   THEN extract(year from age(current_date, pr.date_of_birth)) >= 55
          ELSE TRUE
        END
      )
    )
    AND (
      COALESCE(p_scope, 'global') = 'global'
      OR pr.user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = auth.uid() AND f.followee_id = pr.user_id
      )
    )
),
ordered AS (
  SELECT s.uid, s.podium_count,
    ROW_NUMBER() OVER (ORDER BY s.podium_count DESC, s.uid) AS rnk
  FROM scoped s
)
SELECT o.rnk::int, o.uid, pr.username, pr.avatar_url, o.podium_count
FROM ordered o
INNER JOIN public.profiles pr ON pr.user_id = o.uid
WHERE o.rnk <= GREATEST(1, COALESCE(p_limit, 100))
ORDER BY o.rnk
$podium_lb$;

CREATE OR REPLACE FUNCTION public.get_challenge_instance_detail_v1(p_instance_id uuid)
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
  viewer_rank int,
  viewer_claimed boolean,
  viewer_workout_id bigint
)
LANGUAGE plpgsql
VOLATILE
-- SECURITY DEFINER: ver nota en list_active_challenges_v1.
SECURITY DEFINER
SET search_path TO 'public'
AS $det$
DECLARE
  uid uuid := auth.uid();
BEGIN
  PERFORM public._challenge_ensure_weekly_instances();

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
    (SELECT cc.rank FROM public.challenge_claims cc
     WHERE cc.instance_id = ci.id AND cc.user_id = uid LIMIT 1),
    EXISTS (SELECT 1 FROM public.challenge_claims cc2
            WHERE cc2.instance_id = ci.id AND cc2.user_id = uid),
    (SELECT cc3.workout_id FROM public.challenge_claims cc3
     WHERE cc3.instance_id = ci.id AND cc3.user_id = uid LIMIT 1)
  FROM public.challenge_instances ci
  INNER JOIN public.challenge_templates t ON t.id = ci.template_id
  WHERE ci.id = p_instance_id
  LIMIT 1;
END;
$det$;

CREATE OR REPLACE FUNCTION public.get_challenge_instance_leaderboard_v1(
  p_instance_id uuid,
  p_limit int DEFAULT 20
)
RETURNS TABLE (
  rank int,
  user_id uuid,
  username text,
  avatar_url text,
  adjudication_ts timestamptz,
  workout_id bigint
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $lb$
BEGIN
  RETURN QUERY
  SELECT
    cc.rank,
    cc.user_id,
    pr.username,
    pr.avatar_url,
    cc.adjudication_ts,
    cc.workout_id
  FROM public.challenge_claims cc
  LEFT JOIN public.profiles pr ON pr.user_id = cc.user_id
  WHERE cc.instance_id = p_instance_id
  ORDER BY cc.rank ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
END;
$lb$;

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
         t.scope_activity_code, t.scope_sport, t.scope_muscle_primary
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
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
        OR lower(btrim(ex.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
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
          AND lower(btrim(ex2.muscle_primary)) = lower(btrim(r.scope_muscle_primary))
      );
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

REVOKE ALL ON FUNCTION public.list_active_challenges_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_challenge_instance_detail_v1(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_challenge_instance_leaderboard_v1(uuid, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_challenge_my_progress_v1(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_challenge_podiums_period_leaderboard_v1(text, text, int, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_active_challenges_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_challenge_instance_detail_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_challenge_instance_leaderboard_v1(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_challenge_my_progress_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_challenge_podiums_period_leaderboard_v1(text, text, int, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS (lectura pública autenticada; escritura solo vía SECURITY DEFINER)
-- ---------------------------------------------------------------------------
ALTER TABLE public.challenge_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS challenge_templates_read ON public.challenge_templates;
CREATE POLICY challenge_templates_read ON public.challenge_templates
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS challenge_instances_read ON public.challenge_instances;
CREATE POLICY challenge_instances_read ON public.challenge_instances
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS challenge_claims_read ON public.challenge_claims;
CREATE POLICY challenge_claims_read ON public.challenge_claims
  FOR SELECT TO authenticated USING (true);

-- Ampliar metric_kind en despliegues que ya tenían solo los 3 tipos iniciales
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
    'strength_workouts_touching_muscle'
  ));

-- ---------------------------------------------------------------------------
-- Seed: weekly + monthly + one evergreen (once). Upsert text/thresholds for existing codes.
-- ---------------------------------------------------------------------------
INSERT INTO public.challenge_templates (
  code, title, description, metric_kind, threshold_numeric, threshold_secondary, cadence, max_winners, is_active,
  scope_activity_code, scope_sport, scope_muscle_primary
)
VALUES
(
  'weekly_first_cardio_30km',
  'First to 30 km cardio (weekly)',
  'Global weekly race: published cardio in the window counts toward distance. First athletes to reach 30 km total win a slot. Not a permanent achievement or a personal goal—limited podium seats.',
  'cumulative_cardio_km',
  30,
  NULL,
  'week',
  3,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_strength_set_100kg',
  'First to a 100 kg+ set (weekly)',
  'Global weekly race: first to publish a strength workout with at least one set at 100 kg or more. Order is by publish time within the week.',
  'single_set_max_kg',
  100,
  NULL,
  'week',
  3,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_10k_under_60',
  'First 10 km under 60 min (weekly)',
  'Global weekly race: one published cardio session with ≥ 10 km and duration ≤ 60 minutes. First to qualify wins. Different from leaderboards, which rank totals—this is a threshold race with limited winners.',
  'cardio_session_pace_gate',
  10,
  3600,
  'week',
  3,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_first_cardio_100km',
  'First to 100 km cardio (monthly)',
  'Same rules as the weekly cardio challenge, but the window is the calendar month and the target is 100 km cumulative.',
  'cumulative_cardio_km',
  100,
  NULL,
  'month',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_first_strength_set_140kg',
  'First to a 140 kg+ set (monthly)',
  'Monthly window: first to publish a strength workout with at least one set at 140 kg or more.',
  'single_set_max_kg',
  140,
  NULL,
  'month',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_half_marathon_under_2h',
  'First half marathon under 2 h (monthly)',
  'Monthly window: one published cardio session with ≥ 21.1 km and duration ≤ 7200 seconds (2 hours).',
  'cardio_session_pace_gate',
  21.1,
  7200,
  'month',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'evergreen_first_5k_under_25min',
  'First 5 km under 25 min (open)',
  'Long-running challenge: first athletes globally to post a published cardio session with ≥ 5 km and duration ≤ 1500 s (25 min). Resets only if you replace the template; instance window is fixed in DB.',
  'cardio_session_pace_gate',
  5,
  1500,
  'once',
  10,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_cardio_15km',
  'First to 15 km cardio (weekly)',
  'Weekly cumulative cardio distance from published runs/rides/etc. First to 15 km in the window wins a slot.',
  'cumulative_cardio_km',
  15,
  NULL,
  'week',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_cardio_50km',
  'First to 50 km cardio (weekly)',
  'Weekly cumulative cardio; higher volume race than the 30 km challenge. Same counting rules.',
  'cumulative_cardio_km',
  50,
  NULL,
  'week',
  3,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_5k_under_30',
  'First 5 km under 30 min (weekly)',
  'One published cardio session with ≥ 5 km and duration ≤ 1800 s (30 min). First to qualify wins.',
  'cardio_session_pace_gate',
  5,
  1800,
  'week',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_half_marathon_under_2h',
  'First half marathon under 2 h (weekly)',
  'One session ≥ 21.1 km with duration ≤ 7200 s in the ISO week.',
  'cardio_session_pace_gate',
  21.1,
  7200,
  'week',
  3,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_strength_set_80kg',
  'First to an 80 kg+ set (weekly)',
  'First published strength workout in the week with at least one set ≥ 80 kg.',
  'single_set_max_kg',
  80,
  NULL,
  'week',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_3_sport_sessions',
  'First to 3 sport sessions (weekly)',
  'Counts published workouts with kind sport (padel, football, hyrox, etc.). First to complete 3 in the week wins a slot.',
  'cumulative_sport_sessions',
  3,
  NULL,
  'week',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'weekly_first_4_strength_workouts',
  'First to 4 strength workouts (weekly)',
  'Counts distinct published strength workouts in the window. First to 4 wins.',
  'cumulative_strength_workouts',
  4,
  NULL,
  'week',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_first_cardio_200km',
  'First to 200 km cardio (monthly)',
  'Calendar month cumulative cardio distance; same rules as weekly cardio challenges.',
  'cumulative_cardio_km',
  200,
  NULL,
  'month',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_first_10k_under_50',
  'First 10 km under 50 min (monthly)',
  'One session ≥ 10 km with duration ≤ 3000 s (50 min) within the month.',
  'cardio_session_pace_gate',
  10,
  3000,
  'month',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_marathon_under_4h',
  'First marathon under 4 h (monthly)',
  'One session ≥ 42.195 km with duration ≤ 14400 s (4 hours).',
  'cardio_session_pace_gate',
  42.195,
  14400,
  'month',
  3,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_first_12_sport_sessions',
  'First to 12 sport sessions (monthly)',
  'Monthly race: cumulative published sport workouts; first to 12 in the calendar month.',
  'cumulative_sport_sessions',
  12,
  NULL,
  'month',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'monthly_first_20_strength_workouts',
  'First to 20 strength workouts (monthly)',
  'Monthly: first athletes to publish 20 strength workouts in the window.',
  'cumulative_strength_workouts',
  20,
  NULL,
  'month',
  5,
  true,
  NULL,
  NULL,
  NULL
),
(
  'evergreen_first_10k_under_50',
  'First 10 km under 50 min (open)',
  'Evergreen pace gate: ≥ 10 km and ≤ 3000 s. Limited global slots; see max_winners on the template.',
  'cardio_session_pace_gate',
  10,
  3000,
  'once',
  15,
  true,
  NULL,
  NULL,
  NULL
),
(
  'evergreen_first_8_sport_sessions',
  'First to 8 sport sessions (open)',
  'Evergreen: cumulative published sport workouts until slots are filled (long instance window).',
  'cumulative_sport_sessions',
  8,
  NULL,
  'once',
  20,
  true,
  NULL,
  NULL,
  NULL
),
-- Scoped cardio (activity_code matches app / CardioActivityType.rawValue)
('weekly_run_first_12km','First to 12 km running (weekly)','Weekly cumulative distance for activity run only (published cardio).','cumulative_cardio_km',12,NULL,'week',5,true,'run',NULL,NULL),
('weekly_walk_first_25km','First to 25 km walking (weekly)','Weekly cumulative distance for activity walk.','cumulative_cardio_km',25,NULL,'week',5,true,'walk',NULL,NULL),
('weekly_hike_first_15km','First to 15 km hiking (weekly)','Weekly cumulative distance for activity hike.','cumulative_cardio_km',15,NULL,'week',5,true,'hike',NULL,NULL),
('weekly_treadmill_first_10km','First to 10 km treadmill (weekly)','Weekly cumulative distance for treadmill sessions.','cumulative_cardio_km',10,NULL,'week',5,true,'treadmill',NULL,NULL),
('weekly_bike_first_40km','First to 40 km outdoor bike (weekly)','Weekly cumulative distance for activity bike.','cumulative_cardio_km',40,NULL,'week',5,true,'bike',NULL,NULL),
('weekly_ebike_first_50km','First to 50 km e-bike (weekly)','Weekly cumulative distance for activity e_bike.','cumulative_cardio_km',50,NULL,'week',5,true,'e_bike',NULL,NULL),
('weekly_mtb_first_30km','First to 30 km MTB (weekly)','Weekly cumulative distance for activity mtb.','cumulative_cardio_km',30,NULL,'week',5,true,'mtb',NULL,NULL),
('weekly_indoor_cycling_first_80km','First to 80 km indoor cycling (weekly)','Weekly cumulative distance for indoor_cycling.','cumulative_cardio_km',80,NULL,'week',5,true,'indoor_cycling',NULL,NULL),
('weekly_rowerg_first_15km','First to 15 km rowing (weekly)','Weekly cumulative distance for rowerg.','cumulative_cardio_km',15,NULL,'week',5,true,'rowerg',NULL,NULL),
('weekly_swim_pool_first_3km','First to 3 km pool swim (weekly)','Weekly cumulative distance for swim_pool.','cumulative_cardio_km',3,NULL,'week',5,true,'swim_pool',NULL,NULL),
('weekly_swim_open_first_2km','First to 2 km open-water swim (weekly)','Weekly cumulative distance for swim_open_water.','cumulative_cardio_km',2,NULL,'week',5,true,'swim_open_water',NULL,NULL),
('monthly_run_first_80km','First to 80 km running (monthly)','Monthly cumulative run distance.','cumulative_cardio_km',80,NULL,'month',5,true,'run',NULL,NULL),
-- Scoped sport (sport_sessions.sport)
('weekly_padel_first_2_sessions','First to 2 padel sessions (weekly)','Published sport workouts tagged padel.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'padel',NULL),
('weekly_tennis_first_2_sessions','First to 2 tennis sessions (weekly)','Published sport workouts tagged tennis.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'tennis',NULL),
('weekly_football_first_2_sessions','First to 2 football sessions (weekly)','Published sport workouts tagged football.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'football',NULL),
('weekly_basketball_first_2_sessions','First to 2 basketball sessions (weekly)','Published sport workouts tagged basketball.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'basketball',NULL),
('weekly_badminton_first_2_sessions','First to 2 badminton sessions (weekly)','Published sport workouts tagged badminton.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'badminton',NULL),
('weekly_squash_first_2_sessions','First to 2 squash sessions (weekly)','Published sport workouts tagged squash.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'squash',NULL),
('weekly_table_tennis_first_2_sessions','First to 2 table tennis sessions (weekly)','Published sport workouts tagged table_tennis.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'table_tennis',NULL),
('weekly_volleyball_first_2_sessions','First to 2 volleyball sessions (weekly)','Published sport workouts tagged volleyball.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'volleyball',NULL),
('weekly_handball_first_2_sessions','First to 2 handball sessions (weekly)','Published sport workouts tagged handball.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'handball',NULL),
('weekly_hockey_first_2_sessions','First to 2 hockey sessions (weekly)','Published sport workouts tagged hockey.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'hockey',NULL),
('weekly_rugby_first_2_sessions','First to 2 rugby sessions (weekly)','Published sport workouts tagged rugby.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'rugby',NULL),
('weekly_hyrox_first_2_sessions','First to 2 Hyrox sessions (weekly)','Published sport workouts tagged hyrox.','cumulative_sport_sessions',2,NULL,'week',8,true,NULL,'hyrox',NULL),
('monthly_padel_first_8_sessions','First to 8 padel sessions (monthly)','Monthly cumulative padel sessions.','cumulative_sport_sessions',8,NULL,'month',10,true,NULL,'padel',NULL),
-- Strength variety (muscle_primary: align with exercises catalog, lowercase English)
('weekly_first_400_reps_strength','First to 400 strength reps (weekly)','Sum of reps across all sets in published strength workouts in the window.','cumulative_strength_reps',400,NULL,'week',5,true,NULL,NULL,NULL),
('weekly_first_40_working_sets','First to 40 working sets (weekly)','Counts sets with reps or weight in published strength workouts.','cumulative_strength_sets',40,NULL,'week',5,true,NULL,NULL,NULL),
('weekly_first_8000_kg_volume','First to 8,000 kg volume (weekly)','Sum of weight × reps (kg) in the window.','cumulative_strength_volume_kg',8000,NULL,'week',5,true,NULL,NULL,NULL),
('weekly_first_set_15_reps_bodyweight','First 15+ rep set (weekly)','First published strength workout with a set of at least 15 reps.','single_set_max_reps',15,NULL,'week',8,true,NULL,NULL,NULL),
('weekly_3_chest_sessions','First to 3 chest-focused workouts (weekly)','Strength workouts that include at least one exercise with primary muscle chest.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'chest'),
('weekly_3_back_sessions','First to 3 back-focused workouts (weekly)','Strength workouts including at least one back exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'back'),
('weekly_3_legs_sessions','First to 3 leg-focused workouts (weekly)','Strength workouts including at least one legs exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'legs'),
('weekly_3_shoulders_sessions','First to 3 shoulder-focused workouts (weekly)','Strength workouts including at least one shoulders exercise.','strength_workouts_touching_muscle',3,NULL,'week',8,true,NULL,NULL,'shoulders'),
('monthly_first_2500_reps','First to 2,500 strength reps (monthly)','Monthly cumulative reps.','cumulative_strength_reps',2500,NULL,'month',5,true,NULL,NULL,NULL),
('monthly_first_200k_volume','First to 200,000 kg volume (monthly)','Monthly cumulative volume (kg).','cumulative_strength_volume_kg',200000,NULL,'month',5,true,NULL,NULL,NULL)
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
  scope_muscle_primary = EXCLUDED.scope_muscle_primary;

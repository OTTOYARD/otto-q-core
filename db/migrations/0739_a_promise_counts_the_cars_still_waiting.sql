-- migration-version: 20261017173306
-- migration-name:    a_promise_counts_the_cars_still_waiting
--
-- 0739  **A promise counts the cars still waiting, is drawn from the world, and reads its spread from enough draws
--       (G452).** Three changes to 0736's estimator of when a car will be ready, and one to its recorder. Nothing decides
--       on any of them: the estimator is read-only and the recorder runs only under 0736's dial, default off.
--
-- ══ §1 WHY (G452, rehearsed on 2026-10-17 against last night's arms before anything was built) ════════════════════════
--
--   (a) **A backed-up bay was invisible.** 0736 learns what a run's cars need after their charge (bay work, then the
--       readiness check) only from the cars that have finished. A car stuck behind a backed-up bay is not counted until it
--       gets out, so on a day the bays back up the promise kept saying what the lucky cars took. Rehearsed on the arms'
--       own visit records, after_bay at the median, against the cars whose charge closed in the next hour:
--         arm 81 (busy day, 20 fast chargers): hour 8, 0736 said 33 minutes, the next hour's cars took 395 (14 of 21 were
--           still not ready when the run ended); hour 10, 40 against 600, with 86 of the 131 cars it could have learned
--           from still waiting.
--         arm 82 (dcfc10): hour 6, 35 against 110; hour 10, 35 while 15 of the next 17 cars were never ready at all.
--         normal days (arms 83 and 86): 33-43 against 20-70, so nothing was wrong where the bays keep up.
--       The standard answer to durations some of which are still running is Kaplan-Meier, which counts a car still
--       waiting as lasting at least as long as it has waited so far. Rehearsed the same way it said 255 at arm 81's hour 8
--       (against 395) and "more than half are still waiting" at hour 10; 85 at arm 82's hour 6 (against 110) and 195 at
--       hour 10; and 35-45 on the normal days, where it agrees with 0736. Only 0-1 visits a run close without their check
--       (5 arms read), so the cars still waiting are exactly the open visits with no check done.
--   (b) **The promise was drawn from the run's minted id.** 0736 seeded its sampled futures with the run's uuid, which
--       is 0712's DC-7 class: two replicas of the same world gave the same car different promises. The seed is now the
--       world's, `world:<random_seed>:promise:<clock>`, falling back to the run's id where a run has no random_seed (a
--       production session), exactly as 0712 seeds the check.
--   (c) **A p90 read from 16 draws is a coin toss.** Each of 0736's 16 sampled futures carried one draw of what the car
--       needs after its charge. With the prior's after_bay spread (median 45, p90 130), a p90 read from 16 draws lands
--       between 71 and 198 minutes in 90% of cases; from 128, between 105 and 157 (100,000 simulated promises, numpy,
--       linear interpolation as percentile_cont). The charge futures are the expensive part and stay at 16; each now
--       carries 8 draws of the rest, so a promise is read from 128 sums.
--   (d) **The recorder could ask forever for a promise it could never get.** It listed every car with an unpromised open
--       visit, and the estimator answers for each car's newest visit only, so a car with an older open visit and a newer
--       promised one would be estimated on every tick and never written. It now lists each car's newest open visit, in
--       the estimator's own order.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) public.ottoq_km_quantiles(durations, ended, quantiles): new, pure. Kaplan-Meier: the first duration at which the
--       share of durations ended reaches each quantile, a duration not yet ended being at risk at its own length; a
--       quantile the curve does not reach is NULL.
--   (2) public.ottoq_ready_promise, four anchored patches:
--       - the seed is the world's (b);
--       - the run's own allowance per kind of visit is Kaplan-Meier over the cars whose check has passed by the clock
--         (ended) and the cars still waiting at it (an open visit with no check done, or, read at a past clock, one whose
--         check came later or that was still open when its run closed). Used from 8 cars of the kind, as before. A grid
--         point the curve does not reach is a lower bound: the longest wait so far or the prior's value there, whichever
--         is greater, and the promise's detail counts such points (after_lb) beside after_events and after_waiting (a);
--       - 8 draws of the allowance per charge future (c), keyed by future and draw;
--       - the detail carries draws (futures x 8) and the allowance's counts.
--   (3) twin.ottoq_sim_record_ready_promises, one anchored patch: each car's newest open visit only (d).
--   The ledger, the grade, the tick and the dial are 0736's, untouched.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the estimator and the recorder are 0736's bodies (md5 68064349, 7ba930bc), the charge line
--   simulator and the hash draws are present, nothing of this file is. P2: not already applied. V1: each patched body
--   less its patches is 0736's. V2: Kaplan-Meier's arithmetic on four samples with known answers. V3: the estimator and
--   the recorder act on nothing for a run that does not exist. V4: the grants.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no certification arm, canon cell or dial experiment sets
--   ready_promise_record, and nothing on the tick path calls the estimator or the recorder without it.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0739_pre' (both functions); DROP FUNCTION
--   public.ottoq_km_quantiles(double precision[], boolean[], double precision[]); DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0739_a_promise_counts_the_cars_still_waiting'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0739 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: 0736's bodies, the simulator and the draws present, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'))
     IS DISTINCT FROM '6806434948562e087193c3bbed65e1f6' THEN
    RAISE EXCEPTION '0739 P1: public.ottoq_ready_promise is not 0736''s body (md5 68064349)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'))
     IS DISTINCT FROM '7ba930bccc14b6b2f003ce1decd17c26' THEN
    RAISE EXCEPTION '0739 P1: twin.ottoq_sim_record_ready_promises is not 0736''s body (md5 7ba930bc)';
  END IF;
  IF to_regprocedure('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)') IS NULL
     OR to_regprocedure('public.ottoq_hash_normal(text)') IS NULL OR to_regprocedure('public.ottoq_hash_uniform(text)') IS NULL THEN
    RAISE EXCEPTION '0739 P1: the charge line simulator or the hash draws is missing';
  END IF;
  IF to_regprocedure('public.ottoq_km_quantiles(double precision[],boolean[],double precision[])') IS NOT NULL THEN
    RAISE EXCEPTION '0739 P1: public.ottoq_km_quantiles already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0739_a_promise_counts_the_cars_still_waiting') THEN
    RAISE EXCEPTION '0739 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0739_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
                 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure);

-- ── (1) Kaplan-Meier ──
CREATE OR REPLACE FUNCTION public.ottoq_km_quantiles(p_x double precision[], p_ended boolean[], p_q double precision[])
RETURNS double precision[]
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path = public, extensions
AS $fn$
-- 0739 (G452): the Kaplan-Meier p_q quantiles of the durations p_x, where p_ended[i] false marks a duration still running
-- (it lasts at least p_x[i]). A quantile is the first duration at which the share of durations ended reaches it; a
-- duration still running is at risk at its own length; a quantile the curve does not reach (too many still running) is
-- NULL. A NULL duration is ignored and a NULL flag is read as still running. Pure: the same arrays give the same answer.
DECLARE
  g record; v_s float8 := 1; v_t float8[] := '{}'; v_f float8[] := '{}'; v_out float8[] := '{}'; v_q float8;
BEGIN
  FOR g IN
    WITH o AS (SELECT u.x, COALESCE(u.e, false) AS e FROM unnest(p_x, p_ended) AS u(x, e) WHERE u.x IS NOT NULL),
         t AS (SELECT o.x, count(*) FILTER (WHERE o.e) AS d, count(*) AS c FROM o GROUP BY o.x)
    SELECT t.x, t.d, sum(t.c) OVER (ORDER BY t.x DESC) AS n FROM t ORDER BY t.x
  LOOP
    IF g.d > 0 THEN
      v_s := v_s * (1 - g.d::float8 / g.n);
      v_t := v_t || g.x;
      v_f := v_f || (1 - v_s);
    END IF;
  END LOOP;
  FOREACH v_q IN ARRAY COALESCE(p_q, '{}'::float8[]) LOOP
    v_out := v_out || (SELECT v_t[i] FROM generate_subscripts(v_t, 1) AS i WHERE v_f[i] >= v_q - 1e-9 ORDER BY i LIMIT 1);
  END LOOP;
  RETURN v_out;
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_km_quantiles(double precision[], boolean[], double precision[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_km_quantiles(double precision[], boolean[], double precision[]) TO service_role;

-- ══ (2) and (3): anchored patches, each anchor once ══════════════════════════════════════════════════════════════════
CREATE TEMP TABLE _0739_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0739_patch VALUES
-- (2a) the seed is the world's; the draws and the grid's normal scores
(1, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$  v_seed  text   := p_sim_run_id::text || ':promise:' || floor(extract(epoch FROM p_clock))::bigint::text;
$old$,
$new$  -- 0739 (G452): drawn from the world, as 0712 draws the check's futures: the run's random_seed, else (a production
  -- session) its id. Two replicas of one world give a car one promise.
  v_seed  text   := 'world:' || COALESCE((SELECT r.random_seed::text FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id),
                                         p_sim_run_id::text)
                    || ':promise:' || floor(extract(epoch FROM p_clock))::bigint::text;
  c_draws constant int := 8;       -- 0739: draws of what follows the charge, per charge future; a promise reads n x 8 sums
  -- 0739: the standard normal at the 21 grid points (the ends at 1% and 99%), for the prior's value at a grid point
  c_z     constant float8[] := ARRAY[-2.326, -1.645, -1.282, -1.036, -0.842, -0.674, -0.524, -0.385, -0.253, -0.126, 0,
                                     0.126, 0.253, 0.385, 0.524, 0.674, 0.842, 1.036, 1.282, 1.645, 2.326];
  v_dr    int; v_gi int; v_lb int; v_pq float8; v_gq float8[];
$new$),
-- (2b) the run's own allowance counts the cars still waiting (Kaplan-Meier)
(2, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$  -- what the run's own cars needed, up to this clock, by kind of visit
  FOR g IN
    WITH d AS (
      SELECT vn.arrived_at,
             (SELECT (x ->> 'done_at')::timestamptz FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x
               WHERE x ->> 'svc' = 'readiness_check' AND x ->> 'status' = 'done' ORDER BY x ->> 'done_at' LIMIT 1) AS ready_at,
             (SELECT max(COALESCE((x ->> 'closed_at')::timestamptz, (x ->> 'done_at')::timestamptz))
                FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x
               WHERE x ->> 'svc' = 'charge' AND x ->> 'status' = 'done') AS chg_at,
             EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x WHERE x ->> 'svc' = 'charge') AS chg,
             EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x WHERE x ->> 'concurrency' = 'bay') AS bay
        FROM ottoq_visit_needs vn
       WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = p_depot_id)
    SELECT k.key, count(*) AS n, percentile_cont(v_grid) WITHIN GROUP (ORDER BY k.x) AS q
      FROM d
      CROSS JOIN LATERAL (VALUES
             (CASE WHEN d.chg AND d.chg_at IS NOT NULL THEN CASE WHEN d.bay THEN 'after_bay' ELSE 'after_no_bay' END END,
              CASE WHEN d.chg_at IS NOT NULL THEN GREATEST(extract(epoch FROM (d.ready_at - d.chg_at)) / 60.0, 0)::float8 END),
             (CASE WHEN d.chg THEN 'door_chg_' ELSE 'door_nochg_' END || CASE WHEN d.bay THEN 'bay' ELSE 'no_bay' END,
              CASE WHEN d.arrived_at IS NOT NULL THEN GREATEST(extract(epoch FROM (d.ready_at - d.arrived_at)) / 60.0, 0)::float8 END))
             AS k(key, x)
     WHERE d.ready_at IS NOT NULL AND d.ready_at <= p_clock AND k.key IS NOT NULL AND k.x IS NOT NULL
     GROUP BY k.key
  LOOP
    IF g.n >= c_min_n THEN
      v_allow := v_allow || jsonb_build_object(g.key, jsonb_build_object('src', 'run', 'n', g.n, 'q', to_jsonb(g.q)));
    END IF;
  END LOOP;
$old$,
$new$  -- what the run's own cars needed, up to this clock, by kind of visit. 0739 (G452): a car whose readiness check has
  -- passed by the clock has ended, and a car still waiting at it is counted as lasting at least as long as it has waited
  -- so far: an open visit with no check done, or, read at a past clock, one whose check came later or that was still open
  -- when its run closed. The quantiles are Kaplan-Meier's, so a car stuck behind a backed-up bay counts before it gets out.
  FOR g IN
    WITH d AS (
      SELECT vn.arrived_at, vn.status,
             CASE WHEN vn.meta ->> 'closed_at' ~ '^\d{4}-\d{2}-\d{2}' THEN (vn.meta ->> 'closed_at')::timestamptz END AS closed_at,
             (SELECT (x ->> 'done_at')::timestamptz FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x
               WHERE x ->> 'svc' = 'readiness_check' AND x ->> 'status' = 'done' ORDER BY x ->> 'done_at' LIMIT 1) AS ready_at,
             (SELECT max(COALESCE((x ->> 'closed_at')::timestamptz, (x ->> 'done_at')::timestamptz))
                FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x
               WHERE x ->> 'svc' = 'charge' AND x ->> 'status' = 'done') AS chg_at,
             EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x WHERE x ->> 'svc' = 'charge') AS chg,
             EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x WHERE x ->> 'concurrency' = 'bay') AS bay
        FROM ottoq_visit_needs vn
       WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = p_depot_id),
    o AS (
      SELECT k.key, k.x, COALESCE(d.ready_at <= p_clock, false) AS ended
        FROM d
        CROSS JOIN LATERAL (VALUES
               (CASE WHEN d.chg AND d.chg_at <= p_clock THEN CASE WHEN d.bay THEN 'after_bay' ELSE 'after_no_bay' END END,
                GREATEST(extract(epoch FROM (LEAST(COALESCE(d.ready_at, p_clock), p_clock) - d.chg_at)) / 60.0, 0)::float8),
               (CASE WHEN d.arrived_at <= p_clock
                     THEN CASE WHEN d.chg THEN 'door_chg_' ELSE 'door_nochg_' END || CASE WHEN d.bay THEN 'bay' ELSE 'no_bay' END END,
                GREATEST(extract(epoch FROM (LEAST(COALESCE(d.ready_at, p_clock), p_clock) - d.arrived_at)) / 60.0, 0)::float8))
               AS k(key, x)
       WHERE k.key IS NOT NULL AND k.x IS NOT NULL
         AND (d.ready_at IS NOT NULL OR d.status IN ('open', 'in_progress') OR COALESCE(d.closed_at > p_clock, false)))
    SELECT o.key, count(*) AS n, count(*) FILTER (WHERE o.ended) AS ne, max(o.x) AS xmax,
           public.ottoq_km_quantiles(array_agg(o.x ORDER BY o.x, o.ended), array_agg(o.ended ORDER BY o.x, o.ended), v_grid) AS q
      FROM o
     GROUP BY o.key
  LOOP
    IF g.n >= c_min_n THEN
      -- a grid point the run's curve does not reach yet, with too many cars still waiting, is at least the longest wait so
      -- far and at least the prior's value there: a lower bound, and counted (lb)
      v_lb := 0; v_gq := ARRAY[]::float8[];
      FOR v_gi IN 1 .. 21 LOOP
        IF g.q[v_gi] IS NULL THEN
          v_lb := v_lb + 1;
          v_pq := CASE WHEN c_prior ? g.key
                       THEN (c_prior -> g.key ->> 0)::float8
                            * exp(ln((c_prior -> g.key ->> 1)::float8 / (c_prior -> g.key ->> 0)::float8) / 1.2816 * c_z[v_gi]) END;
          v_gq := v_gq || GREATEST(g.xmax, COALESCE(v_pq, g.xmax));
        ELSE
          v_gq := v_gq || g.q[v_gi];
        END IF;
      END LOOP;
      v_allow := v_allow || jsonb_build_object(g.key, jsonb_build_object('src', 'run', 'n', g.n, 'events', g.ne,
                                                                          'waiting', g.n - g.ne, 'lb', v_lb, 'q', to_jsonb(v_gq)));
    END IF;
  END LOOP;
$new$),
-- (2c) eight draws of what follows the charge per charge future
(3, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$    v_rd := ARRAY[]::float8[];
    FOR s IN 1 .. v_n LOOP
      IF v_q IS NOT NULL THEN
        v_u := public.ottoq_hash_uniform(v_seed || ':' || s || ':' || c.vehicle_id::text || ':after');
        v_i := LEAST(floor(v_u * 20)::int, 19);
        v_f := v_u * 20 - v_i;
        v_a := v_q[v_i + 1] + (v_q[v_i + 2] - v_q[v_i + 1]) * v_f;
      ELSE
        v_a := (c_prior -> v_akey ->> 0)::float8
               * exp(ln((c_prior -> v_akey ->> 1)::float8 / (c_prior -> v_akey ->> 0)::float8) / 1.2816
                     * public.ottoq_hash_normal(v_seed || ':' || s || ':' || c.vehicle_id::text || ':after'));
      END IF;
      v_rd := v_rd || (COALESCE(v_r[s], 0) + GREATEST(v_a - v_el, 0));
    END LOOP;
$old$,
$new$    v_rd := ARRAY[]::float8[];
    FOR s IN 1 .. v_n LOOP
      FOR v_dr IN 1 .. c_draws LOOP                      -- 0739 (G452): each charge future carries 8 draws of the rest
        IF v_q IS NOT NULL THEN
          v_u := public.ottoq_hash_uniform(v_seed || ':' || s || ':' || v_dr || ':' || c.vehicle_id::text || ':after');
          v_i := LEAST(floor(v_u * 20)::int, 19);
          v_f := v_u * 20 - v_i;
          v_a := v_q[v_i + 1] + (v_q[v_i + 2] - v_q[v_i + 1]) * v_f;
        ELSE
          v_a := (c_prior -> v_akey ->> 0)::float8
                 * exp(ln((c_prior -> v_akey ->> 1)::float8 / (c_prior -> v_akey ->> 0)::float8) / 1.2816
                       * public.ottoq_hash_normal(v_seed || ':' || s || ':' || v_dr || ':' || c.vehicle_id::text || ':after'));
        END IF;
        v_rd := v_rd || (COALESCE(v_r[s], 0) + GREATEST(v_a - v_el, 0));
      END LOOP;
    END LOOP;
$new$),
-- (2d) the detail says how many sums a promise is read from and what the allowance learned from
(4, 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure,
$old$                         'after_src', COALESCE(v_al ->> 'src', 'prior'), 'after_n', COALESCE((v_al ->> 'n')::int, 0),
$old$,
$new$                         'after_src', COALESCE(v_al ->> 'src', 'prior'), 'after_n', COALESCE((v_al ->> 'n')::int, 0),
                         'draws', v_n * c_draws, 'after_events', (v_al ->> 'events')::int,
                         'after_waiting', (v_al ->> 'waiting')::int, 'after_lb', (v_al ->> 'lb')::int,
$new$),
-- (3) the recorder lists each car's newest open visit, in the estimator's own order
(5, 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
$old$  SELECT array_agg(DISTINCT vn.vehicle_id ORDER BY vn.vehicle_id) INTO v_ids
    FROM public.ottoq_visit_needs vn
   WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = v_depot AND vn.status IN ('open', 'in_progress')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_ready_promises p
                      WHERE p.sim_run_id = p_sim_run_id AND p.visit_id = vn.visit_id);
$old$,
$new$  -- 0739 (G452): each car's newest open visit, in the estimator's own order, so a car with an older open visit beside a
  -- promised newer one is not estimated on every tick for a promise that could never be written
  SELECT array_agg(z.vehicle_id ORDER BY z.vehicle_id) INTO v_ids
    FROM (SELECT DISTINCT ON (vn.vehicle_id) vn.vehicle_id, vn.visit_id
            FROM public.ottoq_visit_needs vn
           WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = v_depot AND vn.status IN ('open', 'in_progress')
           ORDER BY vn.vehicle_id, vn.arrived_at DESC NULLS LAST, vn.created_at DESC, vn.visit_id DESC) z
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_ready_promises p
                      WHERE p.sim_run_id = p_sim_run_id AND p.visit_id = z.visit_id);
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0739_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0739: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0739: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body less its patches is 0736's ──
DO $v1$
DECLARE f record; v_body text; p record;
BEGIN
  FOR f IN SELECT DISTINCT fn, CASE WHEN fn = 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)'::regprocedure
                                    THEN '6806434948562e087193c3bbed65e1f6' ELSE '7ba930bccc14b6b2f003ce1decd17c26' END AS md5_0736
             FROM _0739_patch LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = f.fn;
    FOR p IN SELECT * FROM _0739_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM f.md5_0736 THEN
      RAISE EXCEPTION '0739 V1: % less its patches is not 0736''s body (md5 %)', f.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: Kaplan-Meier on samples with known answers ──
DO $v2$
DECLARE q float8[] := ARRAY[0, 0.25, 0.5, 0.75, 1.0]; a float8[];
BEGIN
  -- all ended: the empirical step quantiles
  a := public.ottoq_km_quantiles(ARRAY[10, 20, 30, 40]::float8[], ARRAY[true, true, true, true], q);
  IF a IS DISTINCT FROM ARRAY[10, 10, 20, 30, 40]::float8[] THEN
    RAISE EXCEPTION '0739 V2: four ended durations gave %', a;
  END IF;
  -- 20 and 40 still running: at 10 one of four ends (S 0.75), at 30 one of the two at risk ends (S 0.375); the median is
  -- 30, where the cars that had finished alone would say 20, and the curve never reaches 0.75
  a := public.ottoq_km_quantiles(ARRAY[10, 20, 30, 40]::float8[], ARRAY[true, false, true, false], q);
  IF a IS DISTINCT FROM ARRAY[10, 10, 30, NULL, NULL]::float8[] THEN
    RAISE EXCEPTION '0739 V2: two ended and two still running gave %', a;
  END IF;
  -- nothing ended: nothing is reached; nothing at all: nothing either; a NULL duration is ignored
  a := public.ottoq_km_quantiles(ARRAY[10, 20]::float8[], ARRAY[false, false], q);
  IF a IS DISTINCT FROM ARRAY[NULL, NULL, NULL, NULL, NULL]::float8[] THEN
    RAISE EXCEPTION '0739 V2: two still running gave %', a;
  END IF;
  a := public.ottoq_km_quantiles(ARRAY[]::float8[], ARRAY[]::boolean[], q);
  IF a IS DISTINCT FROM ARRAY[NULL, NULL, NULL, NULL, NULL]::float8[] THEN
    RAISE EXCEPTION '0739 V2: no durations gave %', a;
  END IF;
  a := public.ottoq_km_quantiles(ARRAY[10, NULL, 30]::float8[], ARRAY[true, true, true], ARRAY[0.5]::float8[]);
  IF a IS DISTINCT FROM ARRAY[10]::float8[] THEN
    RAISE EXCEPTION '0739 V2: a NULL duration was not ignored: %', a;
  END IF;
END $v2$;

-- ── V3: nothing for a run that does not exist ──
DO $v3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_ready_promise(gen_random_uuid(), '11111111-1111-1111-1111-111111111111', now());
  IF v_n <> 0 OR twin.ottoq_sim_record_ready_promises(gen_random_uuid(), now()) <> 0 THEN
    RAISE EXCEPTION '0739 V3: the estimator (% rows) or the recorder acted on a run that does not exist', v_n;
  END IF;
END $v3$;

-- ── V4: the grants ──
DO $v4$
BEGIN
  IF has_function_privilege('anon', 'public.ottoq_km_quantiles(double precision[],boolean[],double precision[])', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_km_quantiles(double precision[],boolean[],double precision[])', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0739 V4: a browser role can call Kaplan-Meier, the estimator or the recorder, or the server cannot';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0739_a_promise_counts_the_cars_still_waiting', false, false,
  'public.ottoq_km_quantiles (Kaplan-Meier, pure). public.ottoq_ready_promise: the seed is the world''s (0712''s DC-7 '
  'class); the run''s own allowance counts the cars still waiting (Kaplan-Meier, a lower bound where its curve does not '
  'reach); 8 draws of the allowance per charge future. twin.ottoq_sim_record_ready_promises: each car''s newest open visit. '
  'V1: each body less its patches is 0736''s. Read-only, and recorded only under 0736''s dial ready_promise_record '
  '(default 0), which no certification arm, canon cell or dial experiment sets.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 17:33:06 UTC (12:33 PM CT), ledger version 20261017173306 ═════════════════════════════════════
--
--   Through apply_migration with the sweep window closed and nothing in flight (P0 read 0, no run running, at 17:32:02
--   UTC). Executable part 20,635 characters, md5 17d99464ff74b1db443d3782a721f0f2, equal to the ledger's statements[1]
--   read back. public.ottoq_ready_promise is now md5 bc718022c00bd26ae3072f463dcd6ead (prosrc),
--   twin.ottoq_sim_record_ready_promises 9a733c10d0a553a1f34d54eafcc887e3, public.ottoq_km_quantiles
--   836b85ae64802e3b5651d9f6f3e8b9ed; the grade (36a72509) and the tick (b8f1ea6d) are 0736's, untouched.
--
--   Dry-run first, on live, rolled back by a closing exception: P0-P2, the patches (each anchor once), V1-V4, and an end
--   to end check before and after the patches on arm 81's run (busy day, 20 fast chargers, bays backed up) at its hour 10
--   (2026-09-01 21:00 UTC), three cars put in the line with a charge, a wash and preventive maintenance. 0736's estimator
--   learned from the 45 cars that had finished and promised them ready at a median 140, 156 and 188 minutes (p90 242-318).
--   0739's counted 130: the 45 that had finished and 85 still waiting, with 10 of the 21 grid points lower bounds, and
--   promised a median 470, 491 and 560 minutes (p90 625-677), from 128 draws each, seeded
--   world:686364201590009433:promise:1788296400. On that arm the cars whose charge closed in the next hour took a median
--   600 minutes, and 3 of those 8 were never ready before the run ended. The estimator took 1.6 s before and 1.4 s after;
--   the recorder wrote 3 promises either way.
--
--   Executed beside it on the scratch PostgreSQL by tests/test_ready_promise_sql.py (13 tests, about 30 seconds), on the
--   miniature depot taken through 0642 with the live charge line md5-asserted.

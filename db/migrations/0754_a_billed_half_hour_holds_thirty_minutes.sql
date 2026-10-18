-- migration-version: PENDING
-- migration-name:    a_billed_half_hour_holds_thirty_minutes
--
-- 0754  **A billed half hour holds thirty minutes.** (G469)
--       The sweep scorer takes a run's demand peak as the highest mean of grid import over [t, t + 30 minutes) for every
--       snapshot t. At the end of a run that window holds what is left of the day, one to three samples, and its mean is
--       billed as a half hour: a single late tick can set the month's demand charge. The battery's own plan already
--       counts only completed half hours (0600, G310); the scorers do not. A correction to the research wing's
--       instrument, not an experiment: it changes no world and no decision.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-18 between 1:38 and 2:08 AM CT; db/checks/0451 §17, query (33)) ══════════════
--
--   public.ottoq_arm_peak_profile (0577, prosrc md5 917cfc1b) and public.ottoq_dial_arm_metrics (0439, 8a852c7d) both
--   average whatever the window frame RANGE BETWEEN CURRENT ROW AND '29 minutes 59 seconds' FOLLOWING holds, and take
--   the highest. 0439 names the basis as NES's NCP_30min, the highest 30-consecutive-minute mean. Of the 69 sweep arms
--   that carry peak_after_open, 8 have their half hour billed from 180 minutes start in the run's last half hour: arms
--   35, 42, 58 and 62 (value_2026_09_30's 24-hour days, at minute 1,430-1,435 of 1,440) and 84, 89, 94 and 95 (at minute
--   715-720 of 720), on one to three samples. Over full half hours they read 0.7-2.2% lower on the 24-hour days and
--   3.7-7.3% lower on the 12-hour ones (arm 84: 941.8 kW against 1,006.8, $20,155 a month against $21,547). The
--   whole-day half hour is never partial: the opening sets it on all 69. ottoq_bess_day_plan's billed peak so far counts
--   a window only when t + 30 minutes <= its clock (0600), so the battery never planned on a partial one.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   One anchored replacement in each scorer, of the window it maximises over: a window counts only when it starts at
--   least thirty minutes before the day ends, and the day ends as the scorer integrates it, one mean interval (capped
--   at an hour, as its energy sum caps it) after the last sample. At 5 sim-minutes a tick that is the window of six
--   samples starting 25 minutes before the last one; at 2.5, twelve. ottoq_arm_peak_profile filters its window CTE, so
--   every offset (0, 30, 60, 90, 120, 180 and 240 minutes) and every starts_min read full half hours only;
--   ottoq_dial_arm_metrics leaves a partial window's mean NULL, so peak_30min_kw and demand_charge_usd_month do. At 0
--   the profile still equals the scorer (0577's V1), because both end the day the same way. Every arm scored after this
--   lands is billed on full half hours; arms already scored keep their stored numbers, and db/checks/0451 query (33)
--   recomputes any arm whose run is still on record. A run shorter than half an hour has no half hour and reads NULL;
--   none on record is (the shortest sweep arm runs 120 sim-minutes, the shortest dial pair 540).
--   Not changed: the energy, cost and battery sums (the samples and their holds are untouched), the battery's plan, and
--   public.ottoq_twin_kpi_board, whose live readout averages the half hour still filling, which is what a running
--   readout shows.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 both scorers are the bodies read (917cfc1b, 8a852c7d), and the battery plan still counts
--   completed windows only. P2 not already applied. Pre-images to ottoq_schema_snapshots as '0754_pre'. Each anchor
--   matches once. V1 each body less its replacement is its pre-image. V2 on live, read-only (both scorers are STABLE and
--   write nothing): on the latest sweep arm whose run is still on record, the profile's half hour at every offset starts
--   at least thirty minutes before its day ends and equals that offset's full-window maximum recomputed from the arm's
--   snapshots, and at 0 the profile equals the scorer's peak_30min_kw.
--   tests/test_arm_half_hour_sql.py executes both patched scorers on the scratch PostgreSQL against their live bodies
--   (md5 asserted), on days with a late spike, a full late half hour, a 2.5-minute tick and a single sample.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. Neither scorer is an atom of the fourteen-atom verdict or read by
--   the decide path, the battery or the twin; they score an arm after it has run. A dial pair scores both its arms with
--   the scorer of the moment, so each pair's delta stays like for like. Of the 8 active experiments one reads a metric
--   that carries the demand charge (82c5568b, site_cost_usd_per_day, 5 pairs, the last on 2026-09-27); its recorded
--   pairs keep their scores. No dial: the length of a half hour is not a setting.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0754_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0754_a_billed_half_hour_holds_thirty_minutes'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0754 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read; the battery plan counts completed windows only ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_arm_peak_profile(uuid,uuid)'))
     IS DISTINCT FROM '917cfc1b667ce33289602438d298e218' THEN
    RAISE EXCEPTION '0754 P1: public.ottoq_arm_peak_profile is not the body read (md5 917cfc1b)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'))
     IS DISTINCT FROM '8a852c7d1394ffbc3fc56296da3d8dbb' THEN
    RAISE EXCEPTION '0754 P1: public.ottoq_dial_arm_metrics is not the body read (md5 8a852c7d)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc
                  WHERE oid = to_regprocedure('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)')
                    AND position($q$WHERE w.t + interval '30 minutes' <= p_sim_clock$q$ IN prosrc) > 0) THEN
    RAISE EXCEPTION '0754 P1: public.ottoq_bess_day_plan no longer counts completed half hours only (0600)';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0754_a_billed_half_hour_holds_thirty_minutes') THEN
    RAISE EXCEPTION '0754 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0754_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_arm_peak_profile(uuid,uuid)'::regprocedure,
                 'public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);

-- ── the scorers: a half hour holds thirty minutes of samples ──
CREATE TEMP TABLE _0754_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0754_patch VALUES
  -- 1: the profile's window, filtered to full half hours, so every offset and every starts_min reads them
  (1, 'public.ottoq_arm_peak_profile(uuid,uuid)'::regprocedure,
   $o1$), w AS (
  SELECT s.t, avg(s.g) OVER (ORDER BY s.t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30
    FROM (SELECT e.timestamp AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g
            FROM public.site_energy_snapshots e
           WHERE e.sim_run_id = p_run AND e.depot_id = p_depot) s
), tar AS ($o1$,
   $n1$), w AS (
  -- 0754 (G469): a half hour counts only when its window holds thirty minutes of samples. The day ends as the scorer
  -- integrates it, one mean interval (capped at an hour) after its last sample; a window starting later than half an
  -- hour before that holds what is left of the day, one to three samples, and is not a 30-consecutive-minute mean.
  SELECT x.t, x.g30
    FROM (SELECT s.t, avg(s.g) OVER (ORDER BY s.t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30,
                 max(s.t) OVER () + make_interval(secs => round(3600 * LEAST(COALESCE(avg(s.dt) OVER (), 0), 1.0))) AS t_end
            FROM (SELECT e.timestamp AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g,
                         EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt
                    FROM public.site_energy_snapshots e
                   WHERE e.sim_run_id = p_run AND e.depot_id = p_depot) s) x
   WHERE x.t + interval '30 minutes' <= x.t_end
), tar AS ($n1$),
  -- 2: the scorer's window, a partial one's mean left NULL, so the peak and the demand charge read full half hours
  (2, 'public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure,
   $o2$  ), w AS (
    SELECT avg(g) OVER (ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30 FROM s2
  )
$o2$,
   $n2$  ), w AS (
    -- 0754 (G469): only a window that holds thirty minutes of samples is a half hour. s2 holds the last sample for the
    -- arm's mean interval, capped at an hour, so the day ends, as this integration counts it, that long after it.
    SELECT CASE WHEN t + interval '30 minutes' <= max(t + make_interval(secs => round(3600 * dt))) OVER ()
                THEN avg(g) OVER (ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) END AS g30
      FROM s2
  )
$n2$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0754_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0754: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0754: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body less its replacement is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  FOR p IN SELECT * FROM _0754_patch ORDER BY seq LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = p.fn;
    v_body := replace(v_body, p.c_new, p.c_old);
    IF md5(v_body) IS DISTINCT FROM (CASE p.seq WHEN 1 THEN '917cfc1b667ce33289602438d298e218'
                                                ELSE '8a852c7d1394ffbc3fc56296da3d8dbb' END) THEN
      RAISE EXCEPTION '0754 V1: % less its replacement is not its pre-image (md5 %)', p.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: on live, read-only, on the latest sweep arm whose run is still on record ──
DO $v2$
DECLARE
  v_run uuid; v_depot uuid; v_arm bigint; v_prof jsonb; v_met jsonb; v_end timestamptz; v_t0 timestamptz;
  k int; v_full numeric; v_start numeric;
BEGIN
  SELECT a.arm_id, a.sim_run_id, r.depot_id, r.sim_clock_start
    INTO v_arm, v_run, v_depot, v_t0
    FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_sim_runs r ON r.sim_run_id = a.sim_run_id
   WHERE a.complete AND a.arm_metrics ? 'peak_after_open'
     AND EXISTS (SELECT 1 FROM public.site_energy_snapshots e WHERE e.sim_run_id = a.sim_run_id AND e.depot_id = r.depot_id)
   ORDER BY a.arm_id DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0754 V2: no sweep arm with its snapshots still on record to prove on';
  END IF;
  v_prof := public.ottoq_arm_peak_profile(v_run, v_depot);
  v_met  := public.ottoq_dial_arm_metrics(v_run, v_depot, NULL);
  SELECT max(s.t) + make_interval(secs => round(3600 * LEAST(COALESCE(avg(s.dt), 0), 1.0)))
    INTO v_end
    FROM (SELECT e.timestamp AS t,
                 EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt
            FROM public.site_energy_snapshots e WHERE e.sim_run_id = v_run AND e.depot_id = v_depot) s;
  FOREACH k IN ARRAY ARRAY[0, 30, 60, 90, 120, 180, 240] LOOP
    v_start := (v_prof #>> ARRAY['starts_min', k::text])::numeric;
    SELECT round(max(w.g30), 1) INTO v_full
      FROM (SELECT e.timestamp AS t,
                   avg(GREATEST(COALESCE(e.grid_import_kw, 0), 0)) OVER (ORDER BY e.timestamp
                       RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30
              FROM public.site_energy_snapshots e WHERE e.sim_run_id = v_run AND e.depot_id = v_depot) w
     WHERE w.t >= v_t0 + make_interval(mins => k) AND w.t + interval '30 minutes' <= v_end;
    IF v_full IS DISTINCT FROM (v_prof #>> ARRAY['peak_30min_kw', k::text])::numeric THEN
      RAISE EXCEPTION '0754 V2: arm % at offset %: the profile reads % kW, its full half hours %',
        v_arm, k, v_prof #>> ARRAY['peak_30min_kw', k::text], v_full;
    END IF;
    -- starts_min is rounded to the minute, so allow the minute
    IF v_start IS NOT NULL AND v_t0 + make_interval(mins => v_start::int) + interval '30 minutes' > v_end + interval '1 minute' THEN
      RAISE EXCEPTION '0754 V2: arm % at offset %: the half hour starts at minute %, inside the day''s last half hour',
        v_arm, k, v_start;
    END IF;
  END LOOP;
  IF (v_met ->> 'peak_30min_kw')::numeric IS DISTINCT FROM (v_prof #>> '{peak_30min_kw,0}')::numeric THEN
    RAISE EXCEPTION '0754 V2: arm %: at 0 the profile (%) is not the scorer (%)',
      v_arm, v_prof #>> '{peak_30min_kw,0}', v_met ->> 'peak_30min_kw';
  END IF;
  RAISE NOTICE '0754 V2: arm % (run %): the half hour from 180 minutes % kW at minute %, the whole day % kW',
    v_arm, v_run, v_prof #>> '{peak_30min_kw,180}', v_prof #>> '{starts_min,180}', v_met ->> 'peak_30min_kw';
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0754_a_billed_half_hour_holds_thirty_minutes', false, false,
        'G469. public.ottoq_arm_peak_profile and public.ottoq_dial_arm_metrics, one anchored replacement each: the '
        'demand peak''s half hour counts only a window that starts at least thirty minutes before the day ends, as the '
        'scorer integrates it (the last sample plus the mean interval, capped at an hour), so a run''s last one to three '
        'samples are no longer billed as a half hour. Neither scorer is an atom or read by any decision; arms already '
        'scored keep their stored numbers. The battery plan already counted completed half hours only (0600).',
        now());

COMMIT;

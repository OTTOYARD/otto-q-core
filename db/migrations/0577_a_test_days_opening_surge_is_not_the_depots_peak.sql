-- migration-version: PENDING
-- migration-name:    a_test_days_opening_surge_is_not_the_depots_peak
--
-- 0577  **A test day opens with every parked car plugging in at once, which a depot that runs around the clock never
--       does, so each arm also records its peak demand from after that opening.** Lane A value. Harness and reading
--       only: nothing the engine reads changes.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   NES bills a demand charge on the month's highest 30-minute average: $21.40 a kW in summer for the first 1,000 kW. At
--   the smoke day's peak that was $42,327 a month (G299). The sweep scores it over the whole test day from the first tick
--   (`ottoq_dial_arm_metrics`, 0439). But a test day starts from the fleet reset, so every car the seed parks at the depot
--   needing a charge asks for a charger in the first minutes.
--   Measured on the smoke arm (88e46ad3, 20 fast chargers, from 6 AM CT), fleet charging averaged 1,635 kW in the first
--   half hour, then 980, 687, 617 and 593 kW. The day's peak, 1,960.8 kW, is that first half hour.
--   A depot that runs around the clock has no first half hour. Night 2's comparison (0575) is exposed to it. The energy
--   planner starts each value day with the battery 65-94% full (the three seeds' draws), so it can shave the opening. The
--   plain depot has its planner off and cannot. A peak cut earned against the opening would be earned against a moment
--   that exists only because the test starts from a standstill.
--   The opening does not always set the peak. The one surviving 24-hour busy day (c8fe7bda, 10 fast chargers, from 9 PM)
--   peaked at 902 kW at 8 PM, because its battery shaved the opening with 597 kW. So this measures where each day's peak
--   falls rather than assuming it.
--
-- ══ §2 WHAT THIS ADDS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_arm_peak_profile(run, depot)`, read-only, computes the 30-minute peak and its monthly demand charge the
--   way `ottoq_dial_arm_metrics` does: the same samples, the same forward 30-minute window and the same tariff row. It
--   does so over the windows that start at least 0, 30, 60, 90, 120, 180 and 240 minutes into the day, and gives the minute each
--   peak window starts. At 0 it is the scorer's own figure, which V1 proves on a live run.
--   `ottoq_throughput_sweep_arm` merges it into each arm's `arm_metrics` as `peak_after_open`. It is read before the
--   teardown, like everything else the runner scores. The scorer the dial lab uses is untouched, and every existing key
--   keeps its value.
--   0576 reads it. When every arm carries it, the Value tab bills peak demand from three hours in and says so. The full-day
--   figure stays on every arm and beside every peak the tab shows.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: 0572 is applied; its own P1 pins the runner as 0568 left it, so this goes after it.
--   P2: the scorer's energy block is the one measured on 2026-09-30 (md5 f95eaf7bc07cbf9e440bfa636a313ff1), which this
--   mirrors. The runner's scoring line occurs exactly once, before its teardown. P3: not already applied.
--   The runner goes to `ottoq_schema_snapshots` as '0577_pre'.
--   V1: on the latest twin run with at least 12 energy samples, the profile's 0-minute peak and demand charge equal the
--   scorer's. V2: the peak never rises as the start moves later. V3: the runner merges the profile once, after the scorer
--   and before the teardown.
--   Measured before applying (2026-09-29, 10:10 PM CT), with the function's body run read-only on the live database: at 0
--   it equals the scorer on three runs, to the cent. The smoke arm (88e46ad3) reads 1,960.8 kW ($42,326.59 a month) over
--   the whole day, and 1,524.9, 1,414.9, 1,367.5 and 1,254.3 kW from 30, 60, 90 and 120 minutes in: $30,435.80 a month
--   from an hour in. The 24-hour day (c8fe7bda) reads 901.7 kW ($19,296.38) at every offset, its peak at 8 PM. The demo
--   run 1ebae97a reads 624.2 kW ($13,357.30) through 60 minutes, its peak 63 minutes in.
--   Confirmed on night 1 (db/checks/0413 §4), and it lasts longer than an hour. On all 20 arms the profile equals the
--   scorer at 0, and the opening set the whole day's peak. The load it left kept falling for about three hours: the
--   highest half hour after the cut still sat right at the cut on 13 of 19 primary arms at 60 minutes, 9 at 90, 7 at 120,
--   4 at 180 and 3 at 240. The mean peak was 1,017 kW from 60 minutes and 849 kW from 180. So 0576 bills from 180
--   minutes, and this reads to 240.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: nothing the engine reads changes, and no existing score moves.
--
-- ROLLBACK: DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0577_pre'
--                                  AND object_name = 'ottoq_throughput_sweep_arm' ORDER BY snapshot_id DESC LIMIT 1); END $$;
--   DROP FUNCTION public.ottoq_arm_peak_profile(uuid, uuid);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0577_a_test_days_opening_surge_is_not_the_depots_peak'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0577 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0572 first ──
DO $order$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0572_a_fleet_build_out_borrows_cars_for_one_test_day') THEN
    RAISE EXCEPTION '0577 P1: 0572 is not applied, and it pins the runner as 0568 left it';
  END IF;
END $order$;

-- ── P2: the scorer's energy block, and the runner's scoring line ──
DO $premises$
DECLARE
  v_src text;
  v_a int;
  v_z int;
  v_line text := E'  v_m     := public.ottoq_dial_arm_metrics(v_run, s.depot_id, v_soc0);\n';
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure;
  v_a := position('  WITH s AS (' IN v_src);
  v_z := position('  v_amort := GREATEST(1,' IN v_src);
  IF v_a = 0 OR v_z <= v_a OR md5(substring(v_src FROM v_a FOR v_z - v_a)) IS DISTINCT FROM 'f95eaf7bc07cbf9e440bfa636a313ff1' THEN
    RAISE EXCEPTION '0577 P2: ottoq_dial_arm_metrics'' energy block is not the one measured on 2026-09-30';
  END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure;
  IF (length(v_src) - length(replace(v_src, v_line, ''))) / length(v_line) <> 1
     OR position(v_line IN v_src) > position('public.ottoq_sim_stop_and_reset(' IN v_src) THEN
    RAISE EXCEPTION '0577 P2: the runner''s scoring line is not there once, before its teardown';
  END IF;
END $premises$;

-- ── P3: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0577_a_test_days_opening_surge_is_not_the_depots_peak')
     OR to_regprocedure('public.ottoq_arm_peak_profile(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0577 P3: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0577_pre', 'function', 'public', 'ottoq_throughput_sweep_arm',
       pg_get_functiondef('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure));

-- ── (a) the peak after the opening ──
CREATE FUNCTION public.ottoq_arm_peak_profile(p_run uuid, p_depot uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0577: the sweep scorer's 30-minute peak and monthly demand charge (ottoq_dial_arm_metrics, 0439: the same samples,
   forward window and tariff row), over the windows that start at least 0, 30, 60, 90, 120, 180 and 240 minutes after the run's
   sim_clock_start, and the minute each peak window starts. Read-only. At 0 it equals the scorer (0577 V1). */
WITH r AS (
  SELECT x.sim_clock_start AS t0,
         EXTRACT(MONTH FROM (x.sim_clock_start AT TIME ZONE 'America/Chicago'))::int AS mon
    FROM public.ottoq_sim_runs x WHERE x.sim_run_id = p_run
), w AS (
  SELECT s.t, avg(s.g) OVER (ORDER BY s.t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30
    FROM (SELECT e.timestamp AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g
            FROM public.site_energy_snapshots e
           WHERE e.sim_run_id = p_run AND e.depot_id = p_depot) s
), tar AS (
  SELECT t.block_kw, t.demand_first_block_usd_kw AS r1, t.demand_excess_usd_kw AS r2
    FROM public.ottoq_depot_tariffs t, r
   WHERE t.depot_id = p_depot AND t.active AND r.mon = ANY (t.season_months)
   ORDER BY t.effective_from DESC LIMIT 1
), o AS (
  SELECT m.k, (SELECT max(w.g30) FROM w, r WHERE w.t >= r.t0 + make_interval(mins => m.k)) AS peak
    FROM unnest(ARRAY[0, 30, 60, 90, 120, 180, 240]) AS m(k)
), o2 AS (
  SELECT o.k, o.peak,
         (SELECT round(EXTRACT(EPOCH FROM min(w.t - r.t0)) / 60.0)::int FROM w, r
           WHERE w.t >= r.t0 + make_interval(mins => o.k) AND w.g30 = o.peak)                         AS starts_min,
         CASE WHEN tar.r1 IS NULL OR o.peak IS NULL THEN NULL
              ELSE tar.r1 * LEAST(o.peak, COALESCE(tar.block_kw, o.peak))
                   + COALESCE(tar.r2, tar.r1) * GREATEST(0, o.peak - COALESCE(tar.block_kw, o.peak)) END AS demand
    FROM o LEFT JOIN tar ON true
)
SELECT jsonb_build_object(
  'offsets_min',             jsonb_agg(o2.k ORDER BY o2.k),
  'peak_30min_kw',           jsonb_object_agg(o2.k::text, round(o2.peak, 1)),
  'demand_charge_usd_month', jsonb_object_agg(o2.k::text, round(o2.demand, 2)),
  'starts_min',              jsonb_object_agg(o2.k::text, o2.starts_min))
  FROM o2
$fn$;

COMMENT ON FUNCTION public.ottoq_arm_peak_profile(uuid, uuid) IS
'0577. A test day opens with every parked car plugging in at once, which a depot running around the clock never does. The sweep scorer''s 30-minute peak and monthly demand charge, computed its way, over the windows starting at least 0, 30, 60, 90, 120, 180 and 240 minutes into the day, with the minute each peak window starts. At 0 it is the scorer''s own figure.';
REVOKE ALL ON FUNCTION public.ottoq_arm_peak_profile(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_arm_peak_profile(uuid, uuid) TO authenticated, service_role;

-- ── (b) the runner keeps it with each arm, read before the teardown ──
DO $splice$
DECLARE
  v_def text;
  v_old text := E'  v_m     := public.ottoq_dial_arm_metrics(v_run, s.depot_id, v_soc0);\n';
  v_new text := E'  v_m     := public.ottoq_dial_arm_metrics(v_run, s.depot_id, v_soc0);\n'
             || E'  -- 0577: the peak after the day''s opening, beside the full-day peak the scorer keeps\n'
             || E'  v_m     := v_m || jsonb_build_object(''peak_after_open'', public.ottoq_arm_peak_profile(v_run, s.depot_id));\n';
  n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN
    RAISE EXCEPTION '0577: the runner''s scoring line matched % times, not once', n;
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $splice$;

-- ── V1: at 0 minutes the profile is the scorer's own figure, on a live run ──
DO $v1$
DECLARE
  v_run uuid;
  p jsonb;
  m jsonb;
BEGIN
  SELECT r.sim_run_id INTO v_run
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND (SELECT count(*) FROM public.site_energy_snapshots e
           WHERE e.sim_run_id = r.sim_run_id AND e.depot_id = r.depot_id) >= 12
   ORDER BY r.started_at DESC NULLS LAST, r.sim_run_id
   LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0577 V1: no twin run with 12 energy samples to prove the profile against';
  END IF;
  p := public.ottoq_arm_peak_profile(v_run, '11111111-1111-1111-1111-111111111111');
  m := public.ottoq_dial_arm_metrics(v_run, '11111111-1111-1111-1111-111111111111', NULL);
  IF p #>> '{peak_30min_kw,0}' IS NULL
     OR (p #>> '{peak_30min_kw,0}')::numeric IS DISTINCT FROM (m ->> 'peak_30min_kw')::numeric
     OR (p #>> '{demand_charge_usd_month,0}')::numeric IS DISTINCT FROM (m ->> 'demand_charge_usd_month')::numeric THEN
    RAISE EXCEPTION '0577 V1: on run % the profile says % kW and $% a month, the scorer % kW and $%', v_run,
      p #>> '{peak_30min_kw,0}', p #>> '{demand_charge_usd_month,0}', m ->> 'peak_30min_kw', m ->> 'demand_charge_usd_month';
  END IF;
  PERFORM set_config('ottoq.m0577_run', v_run::text, true);
END $v1$;

-- ── V2: the peak never rises as the start moves later ──
DO $v2$
DECLARE
  p jsonb := public.ottoq_arm_peak_profile(current_setting('ottoq.m0577_run')::uuid, '11111111-1111-1111-1111-111111111111');
  v_offsets int[] := ARRAY(SELECT jsonb_array_elements_text(p -> 'offsets_min')::int);
  i int;
BEGIN
  IF v_offsets IS DISTINCT FROM ARRAY[0, 30, 60, 90, 120, 180, 240] THEN
    RAISE EXCEPTION '0577 V2: the offsets are %', v_offsets;
  END IF;
  FOR i IN 2 .. cardinality(v_offsets) LOOP
    IF (p #>> ARRAY['peak_30min_kw', v_offsets[i]::text])::numeric > (p #>> ARRAY['peak_30min_kw', v_offsets[i - 1]::text])::numeric THEN
      RAISE EXCEPTION '0577 V2: the peak from % minutes is above the peak from %: %', v_offsets[i], v_offsets[i - 1], p;
    END IF;
  END LOOP;
END $v2$;

-- ── V3: the runner merges it once, after the scorer and before the teardown ──
DO $v3$
DECLARE
  v_src text;
  v_call text := 'public.ottoq_arm_peak_profile(v_run, s.depot_id)';
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)'::regprocedure;
  IF (length(v_src) - length(replace(v_src, v_call, ''))) / length(v_call) <> 1
     OR position(v_call IN v_src) < position('public.ottoq_dial_arm_metrics(v_run' IN v_src)
     OR position(v_call IN v_src) > position('public.ottoq_sim_stop_and_reset(' IN v_src) THEN
    RAISE EXCEPTION '0577 V3: the runner does not merge the profile once, between the scorer and the teardown';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0577_a_test_days_opening_surge_is_not_the_depots_peak', false, false,
  'Lane A value. ottoq_arm_peak_profile: the sweep scorer''s 30-minute peak and demand charge over the windows starting '
  'at least 0/30/60/90/120/180/240 minutes into a test day, kept on each sweep arm as arm_metrics.peak_after_open. A test day '
  'opens with every parked car plugging in at once, and on night 1 that opening set the day''s peak on 20 of 20 arms with a tail '
  'of about three hours (db/checks/0413); the Value tab (0576) bills the peak from 180 minutes. Harness and reading only; no '
  'existing score moves.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

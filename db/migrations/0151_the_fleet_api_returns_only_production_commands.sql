-- =====================================================================
-- 0151  The fleet API returns only production commands
-- =====================================================================
-- Convicted in db/checks/0066 §3. public.ottoq_fleet_pending_commands
-- returns ottoq_vehicle_commands WHERE status='issued' filtered by depot
-- and fleet operator, with no run predicate. Measured: 170 issued
-- simulation commands vs 4 production, indistinguishable in the result.
-- A fleet operator calling this got 97.7% simulation.
--
-- This is an OUTBOUND production surface. Simulation commands must never
-- reach it, whatever run they belong to. The fix is therefore
-- sim_run_id IS NULL, not the zero-uuid run-match idiom: there is no
-- legitimate caller that wants a specific sim run's commands from here.
--
-- Classified forces_recert = FALSE: read-only API, zero engine callers
-- (verified), reads no hashed stream into any decision.
-- =====================================================================

DO $pin$
DECLARE v_pin text; v_n int;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)), count(*) OVER () INTO v_pin, v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_fleet_pending_commands';
  IF v_n <> 1 THEN RAISE EXCEPTION '0151 expected 1 arity, found %', v_n; END IF;
  IF v_pin IS DISTINCT FROM 'ce45cfa5d2d587944c0ba2d33eee8657' THEN
    RAISE EXCEPTION '0151 pin mismatch ottoq_fleet_pending_commands: %', v_pin;
  END IF;
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.proname<>'ottoq_fleet_pending_commands'
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g') ~ 'ottoq_fleet_pending_commands';
  IF v_n <> 0 THEN RAISE EXCEPTION '0151 unexpected engine caller count %', v_n; END IF;
END $pin$;

DO $anchor$
DECLARE v_raw text; v_src text; v_a text := $a$WHERE c.status = 'issued'$a$; v_nr int; v_ns int;
BEGIN
  SELECT pg_get_functiondef(p.oid), regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g')
    INTO v_raw, v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_fleet_pending_commands';
  v_nr := (length(v_raw)-length(replace(v_raw,v_a,'')))/length(v_a);
  v_ns := (length(v_src)-length(replace(v_src,v_a,'')))/length(v_a);
  IF v_nr <> 1 OR v_ns <> 1 THEN RAISE EXCEPTION '0151 anchor expected once, raw=% stripped=%', v_nr, v_ns; END IF;
  IF position('sim_run_id' in v_src) <> 0 THEN RAISE EXCEPTION '0151 already mentions sim_run_id - refusing to double-apply'; END IF;
END $anchor$;

-- Proof by calling the function before and after. Exact equalities that
-- hold regardless of how many sim rows exist right now:
--   before = production_issued + sim_issued
--   after  = production_issued
CREATE TEMP TABLE pg_temp_0151 AS
SELECT (SELECT count(*) FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000)) AS before_n,
       (SELECT count(*) FROM ottoq_vehicle_commands WHERE status='issued' AND sim_run_id IS NULL) AS prod_issued,
       (SELECT count(*) FROM ottoq_vehicle_commands WHERE status='issued' AND sim_run_id IS NOT NULL) AS sim_issued;

DO $pre$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM pg_temp_0151;
  IF r.before_n <> r.prod_issued + r.sim_issued THEN
    RAISE EXCEPTION '0151 proof: before-count % <> prod % + sim % - the function is not returning what this migration assumes', r.before_n, r.prod_issued, r.sim_issued;
  END IF;
END $pre$;

DO $edit$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_fleet_pending_commands';
  v_def := replace(v_def, $a$WHERE c.status = 'issued'$a$, $a$WHERE c.status = 'issued' AND c.sim_run_id IS NULL$a$);
  EXECUTE v_def;
END $edit$;

DO $post$
DECLARE r record; v_after bigint; v_src text; v_pin text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_fleet_pending_commands';
  IF v_n <> 1 THEN RAISE EXCEPTION '0151 arity changed to %', v_n; END IF;
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g'), md5(pg_get_functiondef(p.oid))
    INTO v_src, v_pin FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_fleet_pending_commands';
  IF v_pin = 'ce45cfa5d2d587944c0ba2d33eee8657' THEN RAISE EXCEPTION '0151 body did not change'; END IF;
  IF position($a$WHERE c.status = 'issued' AND c.sim_run_id IS NULL$a$ in v_src) = 0 THEN RAISE EXCEPTION '0151 predicate missing'; END IF;

  SELECT * INTO r FROM pg_temp_0151;
  SELECT count(*) INTO v_after FROM public.ottoq_fleet_pending_commands(NULL, NULL, 1000000);
  IF v_after <> r.prod_issued THEN
    RAISE EXCEPTION '0151 proof failed: after-count % <> production issued %', v_after, r.prod_issued;
  END IF;
  IF r.sim_issued > 0 AND v_after >= r.before_n THEN
    RAISE EXCEPTION '0151 proof failed: % sim commands existed but the count did not drop (% -> %)', r.sim_issued, r.before_n, v_after;
  END IF;
  RAISE NOTICE '0151 applied; new pin %; returned % before, % after (% sim rows excluded)', v_pin, r.before_n, v_after, r.sim_issued;
END $post$;

DROP TABLE pg_temp_0151;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0151_the_fleet_api_returns_only_production_commands', false,
        'ottoq_fleet_pending_commands returns only sim_run_id IS NULL. Read-only outbound API, zero engine callers; cannot move canon.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

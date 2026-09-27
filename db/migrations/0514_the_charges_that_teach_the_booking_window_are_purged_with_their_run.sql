-- migration-version: 20260927052757
-- migration-name:    the_charges_that_teach_the_booking_window_are_purged_with_their_run
--
-- 0514  **G240, step 1: every charge that stops on an operator or production run is recorded in an append-only
--       evidence ledger with what the booking knew and what the charge did, so the booking window can be calibrated
--       from data that outlives its run.** `db/checks/0385`.
--
-- ══ §1 WHY THIS COMES FIRST ════════════════════════════════════════════════════════════════════════════════════
--
--   G240: a charge's booking window is sized by the booking writer's nominal model (`ottoq_charge_minutes_between`
--   at 22 C and SoH 95, from the car's SoC to its visit's target), and on the nine operator runs of 2026-09-25..27 that
--   window covered 32.6% of the charges it booked. A leave-one-run-out Mondrian split-conformal window over the same
--   470 completed charges (charger type x air band, alpha 0.10) covered 91.3%, each group 89.9-93.0% (0384's sibling
--   work, scratchpad read on 2026-09-27; the method is Angelopoulos & Bates, arXiv:2107.07511 §4.1, Proposition 1,
--   https://arxiv.org/abs/2107.07511, read 2026-09-27). Every one of those charges lives in `ocpp_sessions`, which is
--   `class='engine'`: `ottoq_purge_prior_runs` deletes it by run, so the calibration's evidence is one purge from gone.
--   The booking window cannot be learned from data that does not survive, and it cannot be re-derived later either.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `public.ottoq_charge_duration_ledger`: one row per stopped charge session, keyed by the session id. It holds
--       the features the booking writer reads (charger type, the stall's connector kW as it reads it, the car's inlet
--       kW and pack kWh, SoC start and end), the air the charge ran in (the session's recorded ambient, and the depot's
--       air at its start for a twin run), what happened (start, end, minutes, energy, why it stopped), the nominal
--       minutes the booking writer's model gives for exactly that span, and the run's kind and tick. Evidence: no FK
--       to `ottoq_sim_runs`, append-only unconditionally, registered `class='evidence'` so the purge leaves it alone.
--   (2) A capture trigger on `ocpp_sessions`: when a session's `stopped_reason` is first set on an operator run, a
--       production run, or a session with no run, the row is written. Certification and A/B arms are skipped: their
--       30-minute ticks quantise a charge's length, and a sweep would add thousands of rows a day. The capture
--       swallows its own errors (0340's rule: a capture must never break its writer).
--   (3) A backfill of every stopped session that survives on those runs now.
--   Nothing reads the ledger yet. Step 2 fits a versioned calibration from it, and step 3 puts the booking writer
--   behind a dial that names one.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   A certification arm fires the trigger and returns at its first lookup (run_by = 'cert_harness'), writing nothing.
--   No certified atom reads the ledger. The run-scope registry gains one evidence row, and the purge's own checks were
--   read for what an evidence row needs: no FK, and the append-only-guard check only applies to class 'engine' (0441 §3).

BEGIN;

-- ── P0: no pair in flight (0513's one probe: pairs, A/B pairs, the recert runner, dial pairs and their runner) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0514 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_charge_duration_ledger') IS NOT NULL THEN
    RAISE EXCEPTION '0514 P2: the ledger already exists';
  END IF;
  -- the booking writer's model, the signature the nominal is computed with
  IF to_regprocedure('public.ottoq_charge_minutes_between(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)') IS NULL
     OR to_regprocedure('twin.ottoq_sim_site_ambient_c(uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0514 P2: the charge model or the site-ambient helper is not the one this file reads';
  END IF;
  -- the booking writer still sizes a charge from the stall's connector kW (default 50) and the car's inlet and pack
  -- with the defaults this ledger records. Looked up by name, not signature: what matters is the sizing, not the
  -- argument list, and exactly one writer of that name exists.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking') <> 1
     OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_record_enacted_booking'
            AND p.prosrc LIKE '%COALESCE(s.connector_max_kw, 50)%'
            AND p.prosrc LIKE '%COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150)%'
            AND p.prosrc LIKE '%COALESCE(v.battery_capacity_kwh, 75)%'
            AND p.prosrc LIKE '%ottoq_charge_minutes_between(%') <> 1 THEN
    RAISE EXCEPTION '0514 P2: the booking writer no longer sizes a charge from the inputs this ledger records';
  END IF;
  -- an evidence row needs no FK and no retention-aware guard (0441 §3), and the registry takes one row per column
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_run_scope_registry'::regclass
                  AND c.contype IN ('p','u') AND pg_get_constraintdef(c.oid) LIKE '%table_schema, table_name, column_name%') THEN
    RAISE EXCEPTION '0514 P2: ottoq_run_scope_registry has no (schema, table, column) key to register against';
  END IF;
END $premises$;

-- (1) the ledger
CREATE TABLE public.ottoq_charge_duration_ledger (
  session_id            uuid        PRIMARY KEY,            -- ocpp_sessions.id; the session row itself is purgeable
  recorded_at           timestamptz NOT NULL DEFAULT now(),
  source_kind           text        NOT NULL CHECK (source_kind IN ('capture','backfill')),
  -- DELIBERATELY NO FK to ottoq_sim_runs (0441 §3): evidence must outlive its run
  sim_run_id            uuid,
  run_by                text,
  tick_interval_seconds integer,
  depot_id              uuid,
  stall_id              uuid,
  charger_type          text,
  charger_kw            numeric,       -- what the booking writer reads: COALESCE(stalls.connector_max_kw, 50)
  vehicle_id            uuid,
  vehicle_kw            numeric,       -- COALESCE(inlet_max_kw, max_charge_rate_kw, 150)
  battery_kwh           numeric,       -- COALESCE(battery_capacity_kwh, 75)
  soc_start             integer,
  soc_end               integer,
  ambient_temp_c        numeric,       -- the session's recorded ambient
  depot_air_c           numeric,       -- the depot's air at the session's start (twin runs; 0510)
  started_at            timestamptz,   -- the session's clock: sim time on a twin run
  ended_at              timestamptz,
  duration_min          numeric,
  energy_delivered_kwh  numeric,
  stopped_reason        text,
  nominal_min           numeric,       -- the booking writer's model for exactly this span (22 C, SoH 95, unclamped)
  detail                jsonb       NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX ottoq_charge_duration_ledger_run_idx ON public.ottoq_charge_duration_ledger (sim_run_id);
CREATE INDEX ottoq_charge_duration_ledger_fit_idx ON public.ottoq_charge_duration_ledger (charger_type, stopped_reason);

REVOKE ALL ON public.ottoq_charge_duration_ledger FROM anon, authenticated;

COMMENT ON TABLE public.ottoq_charge_duration_ledger IS
  '0514 (G240 step 1). Append-only evidence: one row per stopped charge session on an operator run, a production run '
  'or a session with no run, with the booking writer''s inputs, the air it ran in, what it did, and the nominal '
  'minutes the booking writer''s model gives for exactly that span. class=evidence, no FK to ottoq_sim_runs, so it '
  'outlives the purge that clears ocpp_sessions. Certification and A/B arms are not recorded (their 30-minute ticks '
  'quantise a charge''s length).';

-- append-only, unconditionally (evidence, not engine)
CREATE FUNCTION public.ottoq_charge_duration_ledger_append_only()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION 'ottoq_charge_duration_ledger is append-only evidence (0514): % refused', TG_OP;
END $fn$;

CREATE TRIGGER ottoq_charge_duration_ledger_append_only_trg
  BEFORE DELETE OR UPDATE ON public.ottoq_charge_duration_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_duration_ledger_append_only();

-- (2) the capture: one row when a session first stops, on the runs whose ticks are fine enough to time a charge
CREATE FUNCTION public.ottoq_capture_charge_duration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, twin, ottoq, extensions
AS $fn$
DECLARE
  v_run   record;
  v_st    record;
  v_veh   record;
  v_nom   numeric;
  v_air   numeric;
BEGIN
  IF NEW.sim_run_id IS NOT NULL THEN
    SELECT r.run_by, r.tick_interval_seconds INTO v_run FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id;
    IF COALESCE(v_run.run_by, '') NOT IN ('operator_demo', 'production_live') THEN
      RETURN NULL;   -- a certification or A/B arm, or a run this ledger does not time
    END IF;
  END IF;

  SELECT s.stall_type::text AS stall_type, COALESCE(s.connector_max_kw, 50) AS kw, s.depot_id
    INTO v_st FROM public.stalls s WHERE s.id = NEW.stall_id;
  SELECT COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150) AS kw, COALESCE(v.battery_capacity_kwh, 75) AS kwh
    INTO v_veh FROM public.vehicles v WHERE v.id = NEW.vehicle_id;

  BEGIN
    IF NEW.soc_start IS NOT NULL AND NEW.soc_end IS NOT NULL AND NEW.soc_end > NEW.soc_start THEN
      v_nom := public.ottoq_charge_minutes_between(NEW.soc_start, NEW.soc_end, v_st.kw, v_veh.kw, v_veh.kwh);
    END IF;
  EXCEPTION WHEN OTHERS THEN v_nom := NULL;
  END;
  BEGIN
    IF NEW.sim_run_id IS NOT NULL AND NEW.started_at IS NOT NULL THEN
      v_air := twin.ottoq_sim_site_ambient_c(NEW.sim_run_id, NEW.started_at);
    END IF;
  EXCEPTION WHEN OTHERS THEN v_air := NULL;
  END;

  INSERT INTO public.ottoq_charge_duration_ledger (
    session_id, source_kind, sim_run_id, run_by, tick_interval_seconds, depot_id, stall_id, charger_type, charger_kw,
    vehicle_id, vehicle_kw, battery_kwh, soc_start, soc_end, ambient_temp_c, depot_air_c, started_at, ended_at,
    duration_min, energy_delivered_kwh, stopped_reason, nominal_min)
  VALUES (
    NEW.id, 'capture', NEW.sim_run_id, v_run.run_by, v_run.tick_interval_seconds, COALESCE(NEW.depot_id, v_st.depot_id),
    NEW.stall_id, v_st.stall_type, v_st.kw, NEW.vehicle_id, v_veh.kw, v_veh.kwh, NEW.soc_start, NEW.soc_end,
    NEW.ambient_temp_c, v_air, NEW.started_at, NEW.ended_at,
    round((EXTRACT(epoch FROM NEW.ended_at - NEW.started_at) / 60.0)::numeric, 3),
    NEW.energy_delivered_kwh, NEW.stopped_reason, round(v_nom, 3))
  ON CONFLICT (session_id) DO NOTHING;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '0514 charge-duration capture: %', SQLERRM;   -- never break the session's own write
  RETURN NULL;
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_capture_charge_duration() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER ottoq_capture_charge_duration_trg
  AFTER UPDATE OF stopped_reason ON public.ocpp_sessions
  FOR EACH ROW
  WHEN (NEW.stopped_reason IS NOT NULL AND OLD.stopped_reason IS NULL)
  EXECUTE FUNCTION public.ottoq_capture_charge_duration();

-- (3) the backfill: every stopped session that survives on those runs now
INSERT INTO public.ottoq_charge_duration_ledger (
  session_id, source_kind, sim_run_id, run_by, tick_interval_seconds, depot_id, stall_id, charger_type, charger_kw,
  vehicle_id, vehicle_kw, battery_kwh, soc_start, soc_end, ambient_temp_c, depot_air_c, started_at, ended_at,
  duration_min, energy_delivered_kwh, stopped_reason, nominal_min)
SELECT os.id, 'backfill', os.sim_run_id, r.run_by, r.tick_interval_seconds, COALESCE(os.depot_id, st.depot_id),
       os.stall_id, st.stall_type::text, COALESCE(st.connector_max_kw, 50), os.vehicle_id,
       COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150), COALESCE(v.battery_capacity_kwh, 75),
       os.soc_start, os.soc_end, os.ambient_temp_c,
       CASE WHEN os.sim_run_id IS NOT NULL AND os.started_at IS NOT NULL
            THEN twin.ottoq_sim_site_ambient_c(os.sim_run_id, os.started_at) END,
       os.started_at, os.ended_at, round((EXTRACT(epoch FROM os.ended_at - os.started_at) / 60.0)::numeric, 3),
       os.energy_delivered_kwh, os.stopped_reason,
       CASE WHEN os.soc_start IS NOT NULL AND os.soc_end IS NOT NULL AND os.soc_end > os.soc_start
            THEN round(public.ottoq_charge_minutes_between(os.soc_start, os.soc_end, COALESCE(st.connector_max_kw, 50),
                         COALESCE(v.inlet_max_kw, v.max_charge_rate_kw, 150), COALESCE(v.battery_capacity_kwh, 75)), 3) END
  FROM public.ocpp_sessions os
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = os.sim_run_id
  LEFT JOIN public.stalls st ON st.id = os.stall_id
  LEFT JOIN public.vehicles v ON v.id = os.vehicle_id
 WHERE os.stopped_reason IS NOT NULL
   AND (os.sim_run_id IS NULL OR r.run_by IN ('operator_demo', 'production_live'))
ON CONFLICT (session_id) DO NOTHING;

-- registry: evidence, so ottoq_purge_prior_runs leaves it alone
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_charge_duration_ledger', 'sim_run_id', 'evidence',
        '0514 (G240 step 1): the durable record of stopped charge sessions on operator and production runs, from '
        'which the charge booking window is calibrated. Evidence, not engine: ocpp_sessions is emptied by the purge, '
        'and a calibration that cannot be re-derived from its evidence is a claim on trust. No FK to ottoq_sim_runs by design.')
ON CONFLICT (table_schema, table_name, column_name) DO UPDATE SET class = EXCLUDED.class, note = EXCLUDED.note;

DO $verify$
DECLARE v_block int; v_self int; n_ops int; n_ledger int;
BEGIN
  -- V1: the registry has no blocking defect and flags nothing about the new table
  SELECT count(*) FILTER (WHERE severity = 'block'), count(*) FILTER (WHERE table_name = 'ottoq_charge_duration_ledger')
    INTO v_block, v_self FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 OR v_self > 0 THEN
    RAISE EXCEPTION '0514 V1: the run-scope registry reports % blocking defect(s), % about the ledger', v_block, v_self;
  END IF;
  -- V2: the backfill holds every stopped session on those runs, and the browser keys cannot read it
  SELECT count(*) INTO n_ops FROM public.ocpp_sessions os LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = os.sim_run_id
   WHERE os.stopped_reason IS NOT NULL AND (os.sim_run_id IS NULL OR r.run_by IN ('operator_demo', 'production_live'));
  SELECT count(*) INTO n_ledger FROM public.ottoq_charge_duration_ledger;
  IF n_ledger <> n_ops OR n_ledger = 0
     OR has_table_privilege('anon', 'public.ottoq_charge_duration_ledger', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_charge_duration_ledger', 'SELECT')
     OR has_function_privilege('anon', 'public.ottoq_capture_charge_duration()', 'EXECUTE') THEN
    RAISE EXCEPTION '0514 V2: the ledger holds % of % stopped sessions, or a browser key can read it', n_ledger, n_ops;
  END IF;
END $verify$;

-- V3: rolled back. A session stopped on the newest stopped operator run is captured once, with the booking writer's
--     nominal; the same stop on a certification arm writes nothing; the ledger refuses an UPDATE and a DELETE.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_cert uuid; v_sess uuid; v_sess2 uuid; n int; r record; v_refused int := 0;
BEGIN
  BEGIN
    SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed' ORDER BY sr.started_at DESC LIMIT 1;
    SELECT sr.sim_run_id INTO v_cert FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'cert_harness' ORDER BY sr.started_at DESC LIMIT 1;
    IF v_run IS NULL OR v_cert IS NULL THEN RAISE EXCEPTION '0514 V3 FAILED: no operator run or no cert arm to plant on'; END IF;

    -- (a) an operator-run session: planted open, then stopped
    SELECT os.* INTO r FROM public.ocpp_sessions os
     WHERE os.sim_run_id = v_run AND os.stopped_reason = 'completed' AND os.soc_end > os.soc_start
     ORDER BY os.started_at LIMIT 1;
    IF r.id IS NULL THEN RAISE EXCEPTION '0514 V3 FAILED: the operator run has no completed session to copy'; END IF;
    v_sess := gen_random_uuid();
    INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, soc_start, ambient_temp_c, sim_run_id)
    VALUES (v_sess, r.depot_id, r.stall_id, r.vehicle_id, r.charge_point_id, '0514-v3-' || v_sess::text, r.evse_id,
            r.connector_id, r.status, r.started_at, r.soc_start, r.ambient_temp_c, v_run);
    UPDATE public.ocpp_sessions SET ended_at = r.ended_at, soc_end = r.soc_end, stopped_reason = 'completed',
           energy_delivered_kwh = r.energy_delivered_kwh
     WHERE id = v_sess;
    SELECT count(*) INTO n FROM public.ottoq_charge_duration_ledger l
     WHERE l.session_id = v_sess AND l.source_kind = 'capture' AND l.run_by = 'operator_demo'
       AND l.duration_min = round((EXTRACT(epoch FROM r.ended_at - r.started_at) / 60.0)::numeric, 3)
       AND l.nominal_min IS NOT NULL AND l.charger_kw IS NOT NULL AND l.depot_air_c IS NOT NULL;
    IF n <> 1 THEN RAISE EXCEPTION '0514 V3 FAILED (a): the operator-run stop was captured % times, with its fields', n; END IF;
    -- a second stop reason on the same session does not write again
    UPDATE public.ocpp_sessions SET stopped_reason = 'completed' WHERE id = v_sess;
    SELECT count(*) INTO n FROM public.ottoq_charge_duration_ledger WHERE session_id = v_sess;
    IF n <> 1 THEN RAISE EXCEPTION '0514 V3 FAILED (a): a repeated stop wrote % rows', n; END IF;

    -- (b) the same stop on a certification arm writes nothing
    v_sess2 := gen_random_uuid();
    INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, soc_start, ambient_temp_c, sim_run_id)
    VALUES (v_sess2, r.depot_id, r.stall_id, r.vehicle_id, r.charge_point_id, '0514-v3-' || v_sess2::text, r.evse_id,
            r.connector_id, r.status, r.started_at, r.soc_start, r.ambient_temp_c, v_cert);
    UPDATE public.ocpp_sessions SET ended_at = r.ended_at, soc_end = r.soc_end, stopped_reason = 'completed' WHERE id = v_sess2;
    SELECT count(*) INTO n FROM public.ottoq_charge_duration_ledger WHERE session_id = v_sess2;
    IF n <> 0 THEN RAISE EXCEPTION '0514 V3 FAILED (b): a certification arm''s stop was captured'; END IF;

    -- (c) append-only
    BEGIN UPDATE public.ottoq_charge_duration_ledger SET detail = '{}'::jsonb WHERE session_id = v_sess;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%append-only evidence (0514)%' THEN v_refused := v_refused + 1; END IF; END;
    BEGIN DELETE FROM public.ottoq_charge_duration_ledger WHERE session_id = v_sess;
    EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE '%append-only evidence (0514)%' THEN v_refused := v_refused + 1; END IF; END;
    IF v_refused <> 2 THEN RAISE EXCEPTION '0514 V3 FAILED (c): % of 2 edits refused', v_refused; END IF;

    RAISE EXCEPTION '0514 V3 PASSED: an operator-run stop is captured once with the booking writer''s nominal and the depot''s air; a certification arm''s stop writes nothing; the ledger refuses UPDATE and DELETE';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0514 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0514 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: DROP TRIGGER ottoq_capture_charge_duration_trg ON public.ocpp_sessions; DROP the two functions; DELETE the
-- registry row; DROP TABLE public.ottoq_charge_duration_ledger (it is evidence, so only by deliberate decision).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0514_the_charges_that_teach_the_booking_window_are_purged_with_their_run', false,
  'G240 step 1: an append-only evidence ledger of stopped charge sessions on operator and production runs, captured by '
  'a trigger on ocpp_sessions that returns at its first lookup on a certification arm, plus a backfill. No certified '
  'atom reads it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;

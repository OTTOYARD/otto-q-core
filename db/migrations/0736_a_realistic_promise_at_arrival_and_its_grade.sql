-- migration-version: 20261017163802
-- migration-name:    a_realistic_promise_at_arrival_and_its_grade
--
-- 0736  **A realistic promise at arrival, and its grade (G383).** When a car arrives, OTTO-Q estimates when it will be
--       ready, from its own plan of the charge line, as a median and a 90th percentile; the twin records that promise
--       once per visit, at arrival, and a grade reads every promise against when the car was actually ready. Nothing
--       decides on it. Under a dial, default off, for research days; the estimator and the grade are read-only.
--
-- ══ §1 WHY (G383, db/checks/0451 §12) ════════════════════════════════════════════════════════════════════════════════
--
--   Nothing in OTTO-Q says when a car will be ready. The only time a visit carries is the owner's dispatch_due_at, and
--   every immediate dispatch is due exactly 45 minutes after it arrives. On arm 83 (the depot as built, normal day, seed
--   1) the immediate dispatches that charged on a fast charger with no bay work were dispatched a median 85 minutes after
--   arriving (p90 130); the 18 the line put on an L2 took a median 193 (p90 315), and with bay work 298 (p90 394). With
--   forty fast chargers and power to spare, 31 of 66 immediate dispatches spent longer than 45 minutes on the charger
--   alone (G383). Rule 9 settles which gives: every car charges to 100% and leaves with nothing open. So the 45 minutes
--   is the owner's ask, and the depot owes the owner the truth about when the car will really be ready, at arrival,
--   with its spread.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) dial `ready_promise_record`, 0..1, default 0, not agent-writable.
--   (b) public.ottoq_ready_promises: one row per visit, its promise as first made. Evidence, append-only, no foreign key
--       to ottoq_sim_runs (the registry's evidence rule, 0340/0364), row security on and no policy, so only the server
--       reads it.
--   (c) public.ottoq_ready_promise(run, depot, clock, cars, futures): read-only. For each car's open visit:
--       - its charge-ready minutes in the expected future and in `futures` sampled ones (default 16), by the charge
--         line's own simulator: a car in the line from ottoq_charge_line_schedule's seats on ottoq_charge_line_state
--         (the kernel's order, the cars coming home, the charger faults and the calendar's holds, each sampled future
--         drawing every charge on the depot's charge clock, rule 9: never shortened); a car already charging from what
--         the state says its charger has left, drawn as the simulator draws a running charger (same key); a car
--         holding a reserved charger from its whole charge on that charger's kind on the same clock (same key as the
--         simulator's charge draw); 0 for a visit with no charge left; and a visit OTTO-Q has not yet planned is
--         'unplanned';
--       - plus what the run's own earlier cars needed between their charge closing and their readiness check passing
--         (or, with no charge or unplanned, between arriving and the check), by whether bay work remains: drawn from the
--         run's completed visits up to this clock once there are 8 of the kind, else from a prior (measured on arms
--         83-88 at 5 minutes a tick, before 0735; the run's own takes over within its first hours);
--       - the 50th and 90th percentiles of their sums over the sampled futures. Seeded by run and clock, so the same
--         run and clock give the same promise.
--   (d) twin.ottoq_sim_record_ready_promises(run, clock): promises each open visit at the depot that has none yet, at
--       this clock, so a visit is promised in the tick it is first seen; returns the rows written. A failure is a
--       WARNING and the tick goes on.
--   (e) public.ottoq_sim_advance_tick, one anchored insertion after 0735's: with the dial on, and the run not
--       completing this tick, it calls (d) at the world's clock. Off, it reads the dial and does nothing (V1).
--   (f) public.ottoq_ready_promise_grade(run): read-only. Each promise against the visit's readiness check (done_at):
--       the share ready by the p50 and by the p90, the p50's mean absolute error and bias, by situation and by bay
--       work; a car not ready when the run ended is a miss if its promise had passed by then and is otherwise left out;
--       and, for visits with an owner's due, the share ready by the due against the share ready by the promise.
--   (g) sweep `promise_normal_2026_10_17`, priority 15, after 0735's: answer_normal's dcfc10 cell plus this dial. The
--       recorder decides nothing, so this arm and that one must agree on every outcome: the observer's own test.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the tick is 0735's body (md5 34173eb6), the schedule and the state are the bodies read on
--   2026-10-17, 0735 applied, nothing of this file present. P2: not already applied. V1: the tick's body less its
--   insertion is 0735's. V2: the estimator and the grade return nothing for a run that does not exist. V3: the
--   estimator's line path on a synthetic line, through the simulator's own seats. V4: the ledger's registry row, its
--   append-only trigger, its row security and grants, the dial, the sweep and its cell.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no certification arm, canon cell or dial experiment sets
--   ready_promise_record, and with it 0 the tick's added IF reads the dial and does nothing. With it 1 the recorder
--   only reads and writes its own ledger.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0736_pre'; DROP FUNCTION
--   twin.ottoq_sim_record_ready_promises(uuid, timestamptz), public.ottoq_ready_promise(uuid, uuid, timestamptz, uuid[],
--   integer), public.ottoq_ready_promise_grade(uuid); before the sweep has run, DELETE its cell and sweep rows, and the
--   ledger can be dropped with its registry row (DELETE FROM ottoq_run_scope_registry WHERE table_name =
--   'ottoq_ready_promises'); once it has run, its rows are evidence and stay; DELETE the dial's catalog row once no
--   params row names it; DELETE FROM public.ottoq_cert_lineage WHERE name = '0736_a_realistic_promise_at_arrival_and_its_grade'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0736 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, 0735 applied, nothing of this file present ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_sim_advance_tick(uuid)'))
     IS DISTINCT FROM '34173eb6eea02369ad32360c47c38fa2' THEN
    RAISE EXCEPTION '0736 P1: public.ottoq_sim_advance_tick is not 0735''s body (md5 34173eb6)';
  END IF;
  IF to_regprocedure('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)') IS NULL
     OR to_regprocedure('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)') IS NULL
     OR to_regprocedure('public.ottoq_hash_normal(text)') IS NULL OR to_regprocedure('public.ottoq_hash_uniform(text)') IS NULL THEN
    RAISE EXCEPTION '0736 P1: the charge line simulator, its state, the charge clock or the hash draws is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0735_a_car_answers_a_command_in_the_tick_it_is_given') THEN
    RAISE EXCEPTION '0736 P1: 0735 is not applied';
  END IF;
  IF to_regclass('public.ottoq_ready_promises') IS NOT NULL
     OR to_regprocedure('public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)') IS NOT NULL
     OR to_regprocedure('public.ottoq_ready_promise_grade(uuid)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'ready_promise_record') THEN
    RAISE EXCEPTION '0736 P1: the promise ledger, its functions or its dial already exist';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'promise_normal_2026_10_17') THEN
    RAISE EXCEPTION '0736 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0736_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_sim_advance_tick(uuid)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('ready_promise_record',
        '0736 (G383): 1 = the twin records, once per visit at the tick it is first seen, when OTTO-Q expects the car to be '
        'ready (public.ottoq_ready_promise: its charge line simulated in 16 sampled futures plus what the run''s earlier '
        'cars needed after their charge, as a median and a 90th percentile) in public.ottoq_ready_promises, which '
        'public.ottoq_ready_promise_grade reads against when each car was actually ready. 0 = nothing is recorded. '
        'Decides nothing. Research days only.',
        0, 0, 1, 'public.ottoq_sim_advance_tick, twin.ottoq_sim_record_ready_promises', false);

-- ── (b) the ledger ──
CREATE TABLE public.ottoq_ready_promises (
  promise_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sim_run_id      uuid        NOT NULL,
  depot_id        uuid        NOT NULL,
  visit_id        uuid        NOT NULL,
  vehicle_id      uuid        NOT NULL,
  promised_at     timestamptz NOT NULL,          -- the run's clock when the promise was made
  arrived_at      timestamptz,
  due_at          timestamptz,                   -- the owner's ask (ottoq_visit_needs.dispatch_due_at), when there is one
  situation       text        NOT NULL CHECK (situation IN ('in_line', 'charging', 'holds_charger', 'unplanned', 'no_charge')),
  bundle          text        NOT NULL CHECK (bundle IN ('bay', 'no_bay')),
  plan_charge_min numeric,                       -- charge ready in the expected future, minutes from promised_at
  charge_p50_min  numeric,
  charge_p90_min  numeric,
  ready_p50_min   numeric     NOT NULL,
  ready_p90_min   numeric     NOT NULL,
  ready_p50_at    timestamptz NOT NULL,
  ready_p90_at    timestamptz NOT NULL,
  futures         integer     NOT NULL,
  detail          jsonb       NOT NULL DEFAULT '{}'::jsonb,
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_ready_promises_one_per_visit UNIQUE (sim_run_id, visit_id),
  CONSTRAINT ottoq_ready_promises_ordered CHECK (ready_p90_min >= ready_p50_min AND ready_p50_min >= 0)
);
COMMENT ON TABLE public.ottoq_ready_promises IS
  '0736 (G383): when OTTO-Q expected each visit''s car to be ready, as first promised (median and 90th percentile), '
  'written by twin.ottoq_sim_record_ready_promises under the dial ready_promise_record and graded by '
  'public.ottoq_ready_promise_grade. Evidence: append-only, and deliberately no foreign key to ottoq_sim_runs.';
CREATE INDEX ottoq_ready_promises_run_idx ON public.ottoq_ready_promises (sim_run_id, promised_at);

CREATE OR REPLACE FUNCTION public.ottoq_ready_promises_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.ready_promises_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_ready_promises is append-only: % refused. Set ottoq.ready_promises_unlock=on in the session to override, and say why in a migration.',
    TG_OP
    USING ERRCODE = '42501';
END
$fn$;

CREATE TRIGGER ottoq_ready_promises_append_only_trg BEFORE DELETE OR UPDATE ON public.ottoq_ready_promises
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_ready_promises_append_only();

ALTER TABLE public.ottoq_ready_promises ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_ready_promises FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.ottoq_ready_promises TO service_role;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_ready_promises', 'sim_run_id', 'evidence',
        '0736 (G383): the promise each visit was given at arrival, graded against when it was ready. Evidence, not engine: '
        'a promise is worth grading only if it survives the next demo run''s purge. Carries NO foreign key to '
        'ottoq_sim_runs, deliberately, as 0340 and 0364 explain for their ledgers.');

-- ── (c) the estimator ──
CREATE OR REPLACE FUNCTION public.ottoq_ready_promise(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz,
                                                      p_vehicle_ids uuid[] DEFAULT NULL, p_futures integer DEFAULT 16)
RETURNS TABLE (vehicle_id uuid, visit_id uuid, situation text, bundle text, plan_charge_min numeric,
               charge_p50_min numeric, charge_p90_min numeric, ready_p50_min numeric, ready_p90_min numeric,
               due_min numeric, detail jsonb)
LANGUAGE plpgsql STABLE
SET search_path = public, ottoq, twin, extensions
AS $fn$
-- 0736 (G383): when each car's open visit will be ready, as a median and a 90th percentile in minutes from p_clock:
-- its charge on the charge line's own simulator (ottoq_charge_line_schedule over ottoq_charge_line_state, the expected
-- future and p_futures sampled ones; rule 9: no charge is shortened), plus what the run's earlier cars needed after their
-- charge closed until their readiness check passed (or from arrival, with no charge left), by whether bay work remains.
-- Read-only; seeded by run and clock. The prior below is a measurement, not a guess: arms 83-88 (2026-10-17, normal day,
-- 5 minutes a tick, before 0735) as [p50, p90] minutes, used for a kind of visit until the run has 8 of its own.
DECLARE
  c_min_n   constant int := 8;
  c_horizon constant float8 := 480;
  c_prior   constant jsonb := '{"after_no_bay": [10, 20], "after_bay": [45, 130],
                                "door_chg_no_bay": [105, 330], "door_chg_bay": [150, 400],
                                "door_nochg_no_bay": [40, 55], "door_nochg_bay": [75, 95]}';
  v_n     int    := GREATEST(4, LEAST(COALESCE(p_futures, 16), 64));
  v_seed  text   := p_sim_run_id::text || ':promise:' || floor(extract(epoch FROM p_clock))::bigint::text;
  v_grid  float8[] := ARRAY(SELECT g / 20.0 FROM generate_series(0, 20) g ORDER BY g);
  v_any   boolean;
  v_state jsonb; v_ct jsonb; v_ev jsonb;
  v_seats jsonb := '{}'::jsonb;    -- car id -> [r in the expected future, r in sampled futures 1..n]
  v_plan  jsonb := '{}'::jsonb;    -- car id -> its seat in the expected future
  v_chg   jsonb := '{}'::jsonb;    -- busy charger (stall id) -> its state entry
  v_allow jsonb := '{}'::jsonb;    -- kind of visit -> {src, n, q: 21 quantiles}
  c record; g record; e jsonb; v_sch jsonb; s int;
  v_r float8[]; v_rd float8[]; v_q float8[]; v_r0 float8; v_m float8; v_sd float8; v_a float8; v_u float8; v_f float8;
  v_el float8; v_p50 float8; v_p90 float8; v_i int; v_key text; v_sit text; v_akey text; v_al jsonb; v_ck jsonb;
  v_st_id uuid; v_st_kind text; v_st_kw numeric; v_beyond int;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM ottoq_visit_needs vn
     WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = p_depot_id AND vn.status IN ('open', 'in_progress')
       AND (p_vehicle_ids IS NULL OR vn.vehicle_id = ANY (p_vehicle_ids))
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                    WHERE a ->> 'svc' = 'charge' AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')))
    INTO v_any;

  IF v_any THEN
    v_state := public.ottoq_charge_line_state(p_sim_run_id, p_depot_id, p_clock);
    FOR s IN 0 .. v_n LOOP
      v_sch := public.ottoq_charge_line_schedule(v_state, NULL, s, v_seed, true);
      FOR e IN SELECT x FROM jsonb_array_elements(COALESCE(v_sch -> 'seats', '[]'::jsonb)) x LOOP
        CONTINUE WHEN COALESCE((e ->> 'inb')::boolean, false);     -- a car still coming home is promised when it arrives
        v_seats := jsonb_set(v_seats, ARRAY[e ->> 'id'],
                             COALESCE(v_seats -> (e ->> 'id'), '[]'::jsonb) || jsonb_build_array(e -> 'r'));
        IF s = 0 THEN
          v_plan := v_plan || jsonb_build_object(e ->> 'id', e);
        END IF;
      END LOOP;
    END LOOP;
    FOR e IN SELECT x FROM jsonb_array_elements(COALESCE(v_state -> 'chargers', '[]'::jsonb)) x
              WHERE COALESCE((x ->> 'free')::numeric, 0) > 0 LOOP
      v_chg := v_chg || jsonb_build_object(e ->> 'id', e);
    END LOOP;
  END IF;

  -- what the run's own cars needed, up to this clock, by kind of visit
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

  FOR c IN
    SELECT DISTINCT ON (vn.vehicle_id) vn.visit_id, vn.vehicle_id, vn.arrived_at, vn.dispatch_due_at,
           EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                    WHERE a ->> 'svc' = 'charge' AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')) AS chg,
           EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                    WHERE a ->> 'concurrency' = 'bay' AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')) AS bay,
           v.current_state::text AS vstate, v.current_stall_id, v.current_soc, v.battery_capacity_kwh, v.inlet_max_kw,
           v.vehicle_class_code, v.make, v.model
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = p_depot_id AND vn.status IN ('open', 'in_progress')
       AND (p_vehicle_ids IS NULL OR vn.vehicle_id = ANY (p_vehicle_ids))
     ORDER BY vn.vehicle_id, vn.arrived_at DESC NULLS LAST, vn.created_at DESC, vn.visit_id DESC
  LOOP
    v_r := NULL; v_r0 := NULL; v_sit := NULL; v_key := NULL; v_beyond := 0; v_st_id := NULL;
    IF NOT c.chg THEN
      v_sit := 'no_charge';
    ELSIF v_seats ? c.vehicle_id::text THEN
      v_sit := 'in_line';
      SELECT array_agg(CASE WHEN jsonb_typeof(x.v) = 'number' THEN (x.v #>> '{}')::float8 ELSE c_horizon END ORDER BY x.o),
             count(*) FILTER (WHERE jsonb_typeof(x.v) <> 'number' AND x.o > 1)
        INTO v_r, v_beyond
        FROM jsonb_array_elements(v_seats -> c.vehicle_id::text) WITH ORDINALITY AS x(v, o);
      v_r0 := v_r[1];
      v_r := v_r[2:];
    ELSIF c.vstate IN ('charging_dcfc', 'charging_l2') AND c.current_stall_id IS NOT NULL
          AND v_chg ? c.current_stall_id::text THEN
      v_sit := 'charging';
      e := v_chg -> c.current_stall_id::text;
      v_m := (e ->> 'free')::float8; v_sd := COALESCE((e ->> 'sd')::float8, 0);
      v_key := c.current_stall_id::text || ':running';                 -- the simulator's draw for a running charger
    ELSE
      SELECT st.id, st.stall_type::text, st.connector_max_kw INTO v_st_id, v_st_kind, v_st_kw
        FROM stalls st
       WHERE st.depot_id = p_depot_id AND st.reserved_by = c.vehicle_id AND st.stall_type::text IN ('dcfc', 'l2')
         AND COALESCE(st.reservation_expires_at, 'infinity'::timestamptz) > p_clock
       ORDER BY st.id LIMIT 1;
      IF v_st_id IS NOT NULL THEN
        IF v_ct IS NULL THEN
          v_ct := public.ottoq_charge_clock_model(p_depot_id);
          v_ev := public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock);
        END IF;
        v_ck := public.ottoq_charge_clock(v_ct, v_st_kind,
                  public.ottoq_charge_clock_who(c.vehicle_id, c.vehicle_class_code, c.make, c.model),
                  c.battery_capacity_kwh, c.current_soc, public.ottoq_effective_target_soc_at(c.vehicle_id, p_clock),
                  v_st_kw, c.inlet_max_kw, v_ev -> v_st_kind);
        v_m := (v_ck ->> 'm')::float8; v_sd := COALESCE((v_ck ->> 'sd')::float8, 0);
        IF v_m IS NOT NULL THEN
          v_sit := 'holds_charger';
          v_key := c.vehicle_id::text || ':charge';                    -- the simulator's draw for a car's charge
        END IF;
      END IF;
      IF v_sit IS NULL THEN
        v_sit := 'unplanned';
      END IF;
    END IF;
    IF v_key IS NOT NULL THEN
      v_r0 := v_m;
      v_r := ARRAY(SELECT v_m * exp(v_sd * public.ottoq_hash_normal(v_seed || ':' || k || ':' || v_key))
                     FROM generate_series(1, v_n) k ORDER BY k);
    END IF;

    v_akey := CASE WHEN v_sit IN ('in_line', 'charging', 'holds_charger') THEN 'after_'
                   WHEN c.chg THEN 'door_chg_' ELSE 'door_nochg_' END
              || CASE WHEN c.bay THEN 'bay' ELSE 'no_bay' END;
    v_el := CASE WHEN v_akey LIKE 'door_%' AND c.arrived_at IS NOT NULL
                 THEN GREATEST(extract(epoch FROM (p_clock - c.arrived_at)) / 60.0, 0) ELSE 0 END;
    v_al := v_allow -> v_akey;
    v_q := CASE WHEN v_al IS NOT NULL
                THEN ARRAY(SELECT (x.v #>> '{}')::float8 FROM jsonb_array_elements(v_al -> 'q') WITH ORDINALITY AS x(v, o) ORDER BY x.o) END;
    v_rd := ARRAY[]::float8[];
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

    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x), percentile_cont(0.9) WITHIN GROUP (ORDER BY x)
      INTO v_p50, v_p90 FROM unnest(v_rd) x;
    vehicle_id      := c.vehicle_id;
    visit_id        := c.visit_id;
    situation       := v_sit;
    bundle          := CASE WHEN c.bay THEN 'bay' ELSE 'no_bay' END;
    plan_charge_min := round(v_r0::numeric, 2);
    SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY x)::numeric, 2),
           round(percentile_cont(0.9) WITHIN GROUP (ORDER BY x)::numeric, 2)
      INTO charge_p50_min, charge_p90_min FROM unnest(v_r) x;
    ready_p50_min   := round(v_p50::numeric, 2);
    ready_p90_min   := round(GREATEST(v_p90, v_p50)::numeric, 2);
    due_min         := round((extract(epoch FROM (c.dispatch_due_at - p_clock)) / 60.0)::numeric, 2);
    detail          := jsonb_strip_nulls(jsonb_build_object(
                         'futures', v_n, 'seed', v_seed, 'after', v_akey,
                         'after_src', COALESCE(v_al ->> 'src', 'prior'), 'after_n', COALESCE((v_al ->> 'n')::int, 0),
                         'elapsed_min', round(v_el::numeric, 2), 'beyond_horizon', NULLIF(v_beyond, 0),
                         'plan_seat', v_plan -> c.vehicle_id::text, 'stall', COALESCE(v_st_id, CASE WHEN v_sit = 'charging' THEN c.current_stall_id END),
                         'models', v_state -> 'models'));
    RETURN NEXT;
  END LOOP;
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_ready_promise(uuid, uuid, timestamptz, uuid[], integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_ready_promise(uuid, uuid, timestamptz, uuid[], integer) TO service_role;

-- ── (d) the recorder ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_record_ready_promises(p_sim_run_id uuid, p_sim_clock_now timestamptz)
RETURNS integer
LANGUAGE plpgsql
SET search_path = twin, ottoq, public, extensions
AS $fn$
-- 0736 (G383): promises each open visit at the run's depot that has no promise yet, at this clock, so a visit is promised
-- in the tick it is first seen. Called by public.ottoq_sim_advance_tick only under the dial ready_promise_record. Decides
-- nothing; a failure is a WARNING and the tick goes on.
DECLARE v_depot uuid; v_ids uuid[]; v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_sim_clock_now IS NULL THEN
    RETURN 0;
  END IF;
  SELECT r.depot_id INTO v_depot FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN
    RETURN 0;
  END IF;
  SELECT array_agg(DISTINCT vn.vehicle_id ORDER BY vn.vehicle_id) INTO v_ids
    FROM public.ottoq_visit_needs vn
   WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = v_depot AND vn.status IN ('open', 'in_progress')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_ready_promises p
                      WHERE p.sim_run_id = p_sim_run_id AND p.visit_id = vn.visit_id);
  IF v_ids IS NULL THEN
    RETURN 0;
  END IF;
  BEGIN
    INSERT INTO public.ottoq_ready_promises
           (sim_run_id, depot_id, visit_id, vehicle_id, promised_at, arrived_at, due_at, situation, bundle,
            plan_charge_min, charge_p50_min, charge_p90_min, ready_p50_min, ready_p90_min, ready_p50_at, ready_p90_at,
            futures, detail)
    SELECT p_sim_run_id, v_depot, rp.visit_id, rp.vehicle_id, p_sim_clock_now, vn.arrived_at, vn.dispatch_due_at,
           rp.situation, rp.bundle, rp.plan_charge_min, rp.charge_p50_min, rp.charge_p90_min, rp.ready_p50_min,
           rp.ready_p90_min, p_sim_clock_now + make_interval(secs => rp.ready_p50_min * 60),
           p_sim_clock_now + make_interval(secs => rp.ready_p90_min * 60), (rp.detail ->> 'futures')::int, rp.detail
      FROM public.ottoq_ready_promise(p_sim_run_id, v_depot, p_sim_clock_now, v_ids, 16) rp
      JOIN public.ottoq_visit_needs vn ON vn.visit_id = rp.visit_id
     WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_ready_promises p
                        WHERE p.sim_run_id = p_sim_run_id AND p.visit_id = rp.visit_id)
    ON CONFLICT (sim_run_id, visit_id) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0736 ready promises: % %', SQLSTATE, SQLERRM;
    RETURN 0;
  END;
  RETURN v_n;
END
$fn$;

REVOKE ALL ON FUNCTION twin.ottoq_sim_record_ready_promises(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_record_ready_promises(uuid, timestamptz) TO service_role;

-- ── (f) the grade ──
CREATE OR REPLACE FUNCTION public.ottoq_ready_promise_grade(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path = public, ottoq, extensions
AS $fn$
-- 0736 (G383): each promise against the visit's readiness check. A car not ready when the run ended is a miss if its
-- promise had passed by then and is otherwise left out (censored). Read-only.
WITH g0 AS (
  SELECT p.situation, p.bundle, p.ready_p50_min, p.ready_p90_min, p.ready_p50_at, p.ready_p90_at, p.due_at,
         p.promised_at, p.detail ->> 'after_src' AS after_src,
         (SELECT (x ->> 'done_at')::timestamptz FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) x
           WHERE x ->> 'svc' = 'readiness_check' AND x ->> 'status' = 'done' ORDER BY x ->> 'done_at' LIMIT 1) AS ready_at,
         r.sim_clock_current AS run_end
    FROM public.ottoq_ready_promises p
    LEFT JOIN public.ottoq_visit_needs vn ON vn.visit_id = p.visit_id
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.sim_run_id
   WHERE p.sim_run_id = p_sim_run_id
), g AS (
  SELECT g0.*,
         extract(epoch FROM (g0.ready_at - g0.promised_at)) / 60.0 AS actual_min,
         CASE WHEN g0.ready_at IS NOT NULL THEN g0.ready_at <= g0.ready_p50_at
              WHEN g0.ready_p50_at < g0.run_end THEN false END AS by_p50,
         CASE WHEN g0.ready_at IS NOT NULL THEN g0.ready_at <= g0.ready_p90_at
              WHEN g0.ready_p90_at < g0.run_end THEN false END AS by_p90,
         CASE WHEN g0.due_at IS NULL THEN NULL
              WHEN g0.ready_at IS NOT NULL THEN g0.ready_at <= g0.due_at
              WHEN g0.due_at < g0.run_end THEN false END AS by_due
    FROM g0
), parts AS (
  SELECT 'all'::text AS part, 'all'::text AS v, g.* FROM g
  UNION ALL SELECT 'situation', g.situation, g.* FROM g
  UNION ALL SELECT 'bundle', g.bundle, g.* FROM g
  UNION ALL SELECT 'after_src', COALESCE(g.after_src, 'unknown'), g.* FROM g
), s AS (
  SELECT part, v,
         jsonb_build_object(
           'promises', count(*), 'ready', count(ready_at), 'censored', count(*) - count(ready_at),
           'graded_p50', count(by_p50), 'by_p50', round(avg(by_p50::int)::numeric, 3),
           'graded_p90', count(by_p90), 'by_p90', round(avg(by_p90::int)::numeric, 3),
           'mae_p50_min', round(avg(abs(actual_min - ready_p50_min))::numeric, 1),
           'bias_min', round(avg(actual_min - ready_p50_min)::numeric, 1),
           'p50_min_median', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ready_p50_min)::numeric, 1),
           'p90_min_median', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ready_p90_min)::numeric, 1),
           'actual_min_median', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_min)::numeric, 1),
           'with_due', count(due_at), 'by_due', round(avg(by_due::int)::numeric, 3),
           'by_p90_of_those_with_due', round(avg(by_p90::int) FILTER (WHERE due_at IS NOT NULL)::numeric, 3)) AS j
    FROM parts GROUP BY part, v
)
SELECT jsonb_build_object('run', p_sim_run_id)
       || COALESCE((SELECT j FROM s WHERE part = 'all'), jsonb_build_object('promises', 0))
       || jsonb_build_object(
            'by_situation', COALESCE((SELECT jsonb_object_agg(v, j) FROM s WHERE part = 'situation'), '{}'::jsonb),
            'by_bundle',    COALESCE((SELECT jsonb_object_agg(v, j) FROM s WHERE part = 'bundle'), '{}'::jsonb),
            'by_after_src', COALESCE((SELECT jsonb_object_agg(v, j) FROM s WHERE part = 'after_src'), '{}'::jsonb));
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_ready_promise_grade(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_ready_promise_grade(uuid) TO service_role;

-- ══ (e): one anchored insertion in the tick, after 0735's, the anchor once ═══════════════════════════════════════════
CREATE TEMP TABLE _0736_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0736_patch VALUES
(1, 'public.ottoq_sim_advance_tick(uuid)'::regprocedure,
$old$    PERFORM twin.ottoq_sim_answer_in_tick(p_sim_run_id, w.out_sim_clock_after);
  END IF;
$old$,
$new$    PERFORM twin.ottoq_sim_answer_in_tick(p_sim_run_id, w.out_sim_clock_after);
  END IF;
  -- 0736 (G383): with ready_promise_record on, each visit first seen this tick is promised a ready time, and the
  -- promise recorded; it decides nothing. Off, nothing is recorded.
  IF NOT COALESCE(w.out_completed, false) AND w.out_sim_clock_after IS NOT NULL
     AND COALESCE(ottoq_policy_get(p_sim_run_id, 'ready_promise_record', 0), 0) >= 1 THEN
    PERFORM twin.ottoq_sim_record_ready_promises(p_sim_run_id, w.out_sim_clock_after);
  END IF;
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0736_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0736: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0736: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── (g) the sweep that measures it, paired with answer_normal's dcfc10 cell ──
INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes, created_at)
SELECT 'promise_normal_2026_10_17',
       'A realistic promise at arrival: the depot as built over the normal day, every visit promised and graded',
       v.depot_id, 'normal_day', v.sim_start, 144, 5, v.seeds[1:1], 0, 15, 5400, now(),
       '0736 (G383): answer_normal_2026_10_17''s dcfc10 cell (arm 83''s cell plus twin_answer_in_tick) plus '
       'ready_promise_record, on value_2026_09_30''s first seed. The recorder decides nothing, so this arm must agree '
       'with that one on every outcome; public.ottoq_ready_promise_grade reads its promises.',
       clock_timestamp()
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc10.otto_q.answer_in_tick.promise', 1, 'otto_q', 'dcfc10',
       '{"deploy_peak_fraction": 0.90, "twin_answer_in_tick": 1, "ready_promise_record": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'promise_normal_2026_10_17';

-- ── V1: the tick's body less its 0736 insertion is 0735's ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  FOR p IN SELECT * FROM _0736_patch ORDER BY seq LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = p.fn;
    v_body := replace(v_body, p.c_new, p.c_old);
    IF md5(v_body) IS DISTINCT FROM '34173eb6eea02369ad32360c47c38fa2' THEN
      RAISE EXCEPTION '0736 V1: % less its insertion is not 0735''s body (md5 %)', p.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: nothing for a run that does not exist ──
DO $v2$
DECLARE v_n int; v_g jsonb;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_ready_promise(gen_random_uuid(), '11111111-1111-1111-1111-111111111111', now());
  v_g := public.ottoq_ready_promise_grade(gen_random_uuid());
  IF v_n <> 0 OR (v_g ->> 'promises')::int IS DISTINCT FROM 0
     OR twin.ottoq_sim_record_ready_promises(gen_random_uuid(), now()) <> 0 THEN
    RAISE EXCEPTION '0736 V2: the estimator (% rows), the grade (%) or the recorder acted on a run that does not exist', v_n, v_g;
  END IF;
END $v2$;

-- ── V3: the line path on a synthetic line, through the simulator's own seats ──
DO $v3$
DECLARE v_state jsonb; v_seat jsonb; v_r0 numeric; v_r1 numeric;
BEGIN
  v_state := jsonb_build_object('v', 1, 'clock', '2026-09-01T12:00:00Z', 'tick_min', 5, 'ttl_min', 75, 'pin_min', 90,
    'horizon_min', 480, 'arrival_window_min', 180, 'order_minutes', true, 'floor_min', 90, 'inbound', '[]'::jsonb,
    'cars', jsonb_build_array(
       jsonb_build_object('id', 'car-a', 'w', 0, 'g', 40, 'imm', true, 'soc', 60, 'due', 45, 'dok', true, 'lok', true,
                          'md', 30, 'ml', 200, 'sd', 0, 'sl', 0, 'cls', 'robotaxi', 'om', 30),
       jsonb_build_object('id', 'car-b', 'w', 0, 'g', 50, 'imm', false, 'soc', 50, 'dok', true, 'lok', true,
                          'md', 40, 'ml', 250, 'sd', 0, 'sl', 0, 'cls', 'robotaxi', 'om', 40)),
    'chargers', jsonb_build_array(jsonb_build_object('id', 'st-1', 'k', 'dcfc', 'free', 0, 'sd', 0)));
  -- the second car waits for the first: ready at 30 + 40 in every future when no charge has a spread
  SELECT x INTO v_seat FROM jsonb_array_elements(public.ottoq_charge_line_schedule(v_state, NULL, 0, 'v3', true) -> 'seats') x
   WHERE x ->> 'id' = 'car-b';
  v_r0 := (v_seat ->> 'r')::numeric;
  SELECT (x ->> 'r')::numeric INTO v_r1 FROM jsonb_array_elements(public.ottoq_charge_line_schedule(v_state, NULL, 5, 'v3', true) -> 'seats') x
   WHERE x ->> 'id' = 'car-b';
  IF v_r0 IS DISTINCT FROM 70 OR v_r1 IS DISTINCT FROM 70 OR v_seat ->> 'k0' IS DISTINCT FROM 'dcfc' THEN
    RAISE EXCEPTION '0736 V3: the simulator''s seats are not what the estimator reads (car-b: %, sampled r %)', v_seat, v_r1;
  END IF;
END $v3$;

-- ── V4: the ledger, the dial, the sweep and its cell ──
DO $v4$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_run_scope_registry WHERE table_schema = 'public' AND table_name = 'ottoq_ready_promises')
       <> 1
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_ready_promises'
                     AND column_name = 'sim_run_id' AND class = 'evidence') THEN
    RAISE EXCEPTION '0736 V4: the ledger is not registered once, as evidence on sim_run_id';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ottoq_ready_promises'::regclass AND contype = 'f') THEN
    RAISE EXCEPTION '0736 V4: the ledger carries a foreign key, which an evidence table must not';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ottoq_ready_promises'::regclass)
     OR has_table_privilege('anon', 'public.ottoq_ready_promises', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_ready_promises', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.ottoq_ready_promises', 'INSERT') THEN
    RAISE EXCEPTION '0736 V4: the ledger''s row security or grants are not server-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.ottoq_ready_promises'::regclass
                  AND tgname = 'ottoq_ready_promises_append_only_trg' AND NOT tgisinternal) THEN
    RAISE EXCEPTION '0736 V4: the ledger has no append-only trigger';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_ready_promise_grade(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_sim_advance_tick(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_sim_advance_tick(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0736 V4: a browser role can call the estimator, the recorder, the grade or the tick';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'ready_promise_record'
                  AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'ready_promise_record') THEN
    RAISE EXCEPTION '0736 V4: ready_promise_record is not catalogued 0..1 default 0 with no row setting it';
  END IF;
  IF (SELECT row(s.scenario, s.priority, cardinality(s.seeds), s.ticks, s.sim_min_per_tick, s.seeds[1], s.sim_start, s.depot_id)
        FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'promise_normal_2026_10_17')
     IS DISTINCT FROM (SELECT row(s.scenario, s.priority, cardinality(s.seeds), s.ticks, s.sim_min_per_tick, s.seeds[1], s.sim_start, s.depot_id)
                         FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'answer_normal_2026_10_17') THEN
    RAISE EXCEPTION '0736 V4: the sweep is not answer_normal''s scenario, priority, seed, ticks, start and depot';
  END IF;
  IF (SELECT row(c.fixed_params - 'ready_promise_record', c.buildout_code, c.seat)
        FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'promise_normal_2026_10_17')
     IS DISTINCT FROM (SELECT row(c.fixed_params, c.buildout_code, c.seat)
                         FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                        WHERE s.sweep_code = 'answer_normal_2026_10_17' AND c.cell_code = 'dcfc10.otto_q.answer_in_tick') THEN
    RAISE EXCEPTION '0736 V4: the cell is not answer_normal''s dcfc10 cell plus ready_promise_record';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'promise_normal_2026_10_17') <> 1
     OR (SELECT created_at FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'promise_normal_2026_10_17')
        <= (SELECT created_at FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'answer_normal_2026_10_17') THEN
    RAISE EXCEPTION '0736 V4: the sweep does not hold one cell, or would run before 0735''s';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0736_a_realistic_promise_at_arrival_and_its_grade', false, false,
  'Dial ready_promise_record (default 0); evidence ledger public.ottoq_ready_promises; read-only estimator '
  'public.ottoq_ready_promise and grade public.ottoq_ready_promise_grade; recorder twin.ottoq_sim_record_ready_promises; '
  'one anchored insertion in public.ottoq_sim_advance_tick after 0735''s that, with the dial off, reads the dial and does '
  'nothing (V1: body less insertion is 0735''s). Sweep promise_normal_2026_10_17 (one cell), priority 15. No '
  'certification arm, canon cell or dial experiment sets the dial.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 16:38:02 UTC (11:38 AM CT), ledger version 20261017163802 ═════════════════════════════════════
--
--   Through apply_migration with the sweep window closed, P0 passing. Executable part 36,689 characters, md5
--   beac2089436b62c73e42a684242ecf89, equal to the ledger's statements[1] read back. public.ottoq_sim_advance_tick is now
--   md5 b8f1ea6ddfdd75b64f3a106473e09971 (prosrc); public.ottoq_ready_promise 6806434948562e087193c3bbed65e1f6;
--   twin.ottoq_sim_record_ready_promises 7ba930bccc14b6b2f003ce1decd17c26; public.ottoq_ready_promise_grade
--   36a7250943264056b352c4b94b7d28f1. The sweep was written at 16:38:02.574425 UTC, after 0735's, so the runner takes it
--   as the 8th arm of the next window.
--
--   Dry-run first, on live, rolled back by a closing exception: P0-P2, the patch (anchor once), V1-V4, then an end to
--   end check on arm 83's run at its last clock (2026-09-01 23:00 UTC), with the run's clock published as the tick
--   publishes it: three cars put in the line, an immediate dispatch among them (02ff42a9, 62%, due in 45 minutes) and a
--   wash-only visit (1225f10e). The estimator took 705 ms. The immediate dispatch was in_line, seated in the expected
--   future on a fast charger at once, its charge ready at a plan 49.5, p50 50.4 and p90 56.3 minutes, and ready to leave
--   at a p50 60.6 and p90 68.8 (after_no_bay from the run's own completed visits): a realistic answer where its due said
--   45. The wash-only visit was no_charge, p50 77.3 and p90 93.8 on the prior (the run had 2 such visits, not 8). The
--   recorder wrote both, 16 futures each, and the grade read 2 promises, 0 ready, 2 censored (both promised past the
--   run's end).

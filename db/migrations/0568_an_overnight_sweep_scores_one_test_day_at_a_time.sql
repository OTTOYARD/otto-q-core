-- migration-version: PENDING
-- migration-name:    an_overnight_sweep_scores_one_test_day_at_a_time
--
-- 0568  **An overnight sweep that runs the twin's test days one at a time, scores each, and keeps the scores.**
--       Lane A, phase 2. Chase, 2026-09-29: "SO as many vehicles being serviced as possible will be ideal, ultimately
--       ... that will be OTTO-Q's main orchestration objective", and of the plan: "GO".
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0565 counts the cars a test day serves, and 0567 lets a test day run on 15 or 20 robotic fast chargers. What is
--   missing is the instrument that runs MANY such days -- every combination of build-out and policy, over several
--   independent seeds, at a step fine enough that a 13-minute charge is not billed as 30 -- and keeps what they scored
--   in a place the next demo's purge cannot reach. The pieces all exist and are reused as they are:
--     the arm protocol          ottoq_dial_pair's (0439): the world lock, no live run, the fleet reset filed to no run
--                               (0421), the operator's door (0531), the 30-second tick at 2 x sim-minutes of time_scale
--                               (0520), the quiesce (0152/0112), each tick in its own subtransaction (0535);
--     the policy seat           ottoq_ab_pair's (0261): proposer_seat 0 otto_q, 1 fifo, 2 greedy;
--     the scoring               0565's scorecard (read, and written as evidence) and 0439's arm metrics (deployed and
--                               unmet car-hours, site cost, peak kW), both read before the teardown;
--     the staleness rule        the dial floor (0523): an arm counts only if it ran at or after ottoq_dial_pair_floor(),
--                               so an engine change that could move an arm re-runs it rather than mixing it in.
--   What a dial pair cannot do is compare more than two arms, vary the seat or the depot, or run one arm alone. This
--   runs one arm per call and lets a sweep define as many cells as it needs.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_throughput_sweeps           a sweep: depot, scenario, operator-day start, ticks, sim-minutes per tick,
--                                            its seeds (a pure hash of the sweep code, like 0439's), and how many
--                                            replicate arms re-run a finished arm to check it reproduces.
--   public.ottoq_throughput_sweep_cells      a cell: a build-out (0567), a seat, and the run-scoped dials held fixed
--                                            (validated against the catalog exactly as ottoq_dial_pair validates).
--   public.ottoq_throughput_sweep_arms       EVIDENCE, append-only, class 'evidence', no FK to ottoq_sim_runs (0340):
--                                            one row per arm run -- the scorecard, the arm metrics, the fourteen-atom
--                                            hashes (ottoq_ab_arm_atoms), the boot image's digest, the build-out
--                                            receipt and its restore, whether the shield was paid, and any engine error.
--   public.ottoq_throughput_sweep_arm(cell, seed, replicate)
--                                            one arm, in the caller's transaction, build-out applied and restored inside it.
--   public.ottoq_throughput_sweep_runner()   the cron entry: at most one arm per call, and only while
--                                            throughput_sweep_runner_enabled is 1, no run is live, every canon column is
--                                            current and the world lock is free. An arm that fails is recorded as failed
--                                            and not retried; an arm a manual Start interrupts (0564 cancels the world
--                                            lock's holder) rolls back whole and runs again the next night.
--   public.ottoq_throughput_frontier         per cell: arms, valid arms, and each headline as a range over seeds.
--   public.ottoq_throughput_sweep_pairs      per seed and build-out: OTTO-Q against FIFO and greedy on the same day,
--                                            with whether the arms booted from one world.
--   public.ottoq_throughput_sweep_replicates each replicate against its primary: identical on every atom, or which moved.
--   cron: ottoq-throughput-sweep-runner every 2 minutes; the window opens 04:00 UTC (11 PM CDT) and closes 11:00 UTC
--         (6 AM CDT). Under CST (from 2026-11-01) the same UTC window is 10 PM-5 AM CT.
--
-- ══ §3 THE FIRST SWEEP (night 1) ══════════════════════════════════════════════════════════════════════════════════
--
--   frontier_2026_09_29: busy_day on the twin depot from 6 AM CT, 144 ticks of 5 sim-minutes (12 hours, to 6 PM CT), with
--   deploy_peak_fraction 0.90 held on every arm. That is the catalog default and normal_day's level, against busy_day's
--   own 0.45, so it pairs a normal day's deployment target with a busy day's service load: the fleet is out working and
--   the depot must turn it around. Six cells: {dcfc10, dcfc20} x {otto_q, fifo, greedy}, run seed by seed so a partial
--   night still yields complete comparisons. Five seeds; one replicate (cell 1, seed 1, run again after seed 1's cells).
--   At about 9 s a tick an arm takes about 23 minutes, so one 7-hour night runs about 18 arms (three seeds) and the
--   next night finishes it. The sweep waits for tonight's window (run_after 2026-09-30 04:00 UTC, 11 PM CDT).
--
--   Before it, and first whenever the window opens, smoke_2026_09_29 runs one 2-hour dcfc20 OTTO-Q day (24 ticks, one
--   seed) so the whole protocol is seen working on the live engine before a night depends on it. It is not a result.
--
--   What the seats are, stated plainly because the result will be quoted: FIFO and greedy replace OTTO-Q's charger
--   assignment (ottoq_l2_propose_stall_seat); the rest of the engine is the same, and every seat's decisions pass the
--   same shield (paid_shield records it). So a difference measures OTTO-Q's assignment and sequencing, and understates
--   what the whole of OTTO-Q does against a depot run by hand.
--
-- ══ §4 WHEN TO APPLY ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Any time. The runner is inert until the window opens, and nothing in the engine or the determinism pair calls any of
--   this: forces_recert and forces_dial_restart FALSE.
--
-- ROLLBACK: SELECT cron.unschedule(j) for 'ottoq-throughput-sweep-runner', 'ottoq_sweep_window_open',
--   'ottoq_sweep_window_close'; DROP VIEW public.ottoq_throughput_sweep_replicates, public.ottoq_throughput_sweep_pairs,
--   public.ottoq_throughput_frontier; DROP FUNCTION public.ottoq_throughput_sweep_runner(),
--   public.ottoq_throughput_sweep_arm(uuid, bigint, boolean); DELETE FROM public.ottoq_run_scope_registry WHERE table_name
--   = 'ottoq_throughput_sweep_arms'; DROP TABLE public.ottoq_throughput_sweep_arms, public.ottoq_throughput_sweep_cells,
--   public.ottoq_throughput_sweeps; DROP FUNCTION public.ottoq_throughput_sweep_arms_append_only(); DELETE FROM
--   public.ottoq_policy_params / ottoq_policy_param_catalog WHERE param_key = 'throughput_sweep_runner_enabled'; DELETE
--   FROM public.ottoq_cert_lineage WHERE name = '0568_an_overnight_sweep_scores_one_test_day_at_a_time'.

BEGIN;

-- ── P1: the arm protocol's parts exist with the shapes this calls ──
DO $premises$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(f, ', ') INTO v_missing
    FROM unnest(ARRAY[
      'public.ottoq_try_world_lock(integer,numeric)', 'public.ottoq_dial_pair_floor()', 'public.ottoq_engine_hash()',
      'public.ottoq_tick_invariance_reset_fleet(uuid,bigint,timestamptz)',
      'public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)', 'ottoq.ottoq_world_fingerprint(uuid)',
      'public.ottoq_boot_state_fingerprint(uuid,uuid)', 'public.ottoq_sim_advance_tick(uuid)',
      'public.ottoq_ab_arm_atoms(uuid,uuid)', 'public.ottoq_dial_arm_metrics(uuid,uuid,numeric)',
      'public.ottoq_sim_stop_and_reset(uuid,text)', 'public.ottoq_throughput_score_write(uuid,text)',
      'public.ottoq_site_buildout_apply(uuid,text)', 'public.ottoq_site_buildout_restore(uuid)',
      'public.ottoq_policy_set(text,uuid,text,numeric,text)']) AS f
   WHERE to_regprocedure(f) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0568 P1: the arm protocol calls functions that do not exist: %', v_missing;
  END IF;
  IF to_regclass('public.ottoq_determinism_canon') IS NULL OR to_regclass('public.ottoq_policy_param_catalog') IS NULL
     OR to_regclass('public.ottoq_policy_params') IS NULL OR to_regclass('public.ottoq_bess_units') IS NULL THEN
    RAISE EXCEPTION '0568 P1: the canon, the dial catalog, the dial table or the battery table is missing';
  END IF;
  -- The seat numbering this maps onto (0261): 0 otto_q, 1 fifo, 2 greedy, catalogued 0..2.
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'proposer_seat'
                    AND min_value = 0 AND max_value = 2) THEN
    RAISE EXCEPTION '0568 P1: proposer_seat is no longer catalogued 0..2';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'deploy_peak_fraction'
                    AND 0.90 BETWEEN min_value AND max_value) THEN
    RAISE EXCEPTION '0568 P1: deploy_peak_fraction does not admit 0.90, the first sweep''s load';
  END IF;
  -- 0520's cadence rule, which this copies: time_scale = 2 x sim-minutes per tick on a 30-second tick.
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_dial_pair(uuid,bigint,integer)')
                    AND prosrc ~ 'time_scale = 2 \* x\.sim_min_per_tick, tick_interval_seconds = 30') THEN
    RAISE EXCEPTION '0568 P1: ottoq_dial_pair no longer sets time_scale = 2 x sim_min_per_tick on a 30-second tick';
  END IF;
  -- 0564's Start door cancels the world lock's holder: the reason an arm under that lock is interruptible.
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_operator_start_run' AND prosrc ~ 'ottoq_recert_runner') THEN
    RAISE EXCEPTION '0568 P1: the operator start door no longer interrupts the world lock''s holder';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_scenarios WHERE scenario_code = 'busy_day' AND status = 'available'
                    AND default_depot_id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0568 P1: busy_day is not an available scenario on the twin depot';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code IN ('dcfc10', 'dcfc20') HAVING count(*) = 2) THEN
    RAISE EXCEPTION '0568 P1: the dcfc10 and dcfc20 build-outs (0567) are missing';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF to_regclass('public.ottoq_throughput_sweeps') IS NOT NULL
     OR to_regprocedure('public.ottoq_throughput_sweep_runner()') IS NOT NULL THEN
    RAISE EXCEPTION '0568 P2: the sweep already exists; this file has already been applied';
  END IF;
END $fresh$;

-- ── 1. sweeps and cells ──
CREATE TABLE public.ottoq_throughput_sweeps (
  sweep_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sweep_code       text NOT NULL UNIQUE CHECK (sweep_code ~ '^[a-z0-9_]+$'),
  title            text NOT NULL,
  depot_id         uuid NOT NULL REFERENCES public.depots(id),
  scenario         text NOT NULL,
  sim_start        timestamptz NOT NULL,
  ticks            integer NOT NULL CHECK (ticks > 0),
  sim_min_per_tick numeric NOT NULL CHECK (sim_min_per_tick > 0 AND sim_min_per_tick <= 30),
  seeds            bigint[] NOT NULL CHECK (cardinality(seeds) > 0),
  replicates       integer NOT NULL DEFAULT 1 CHECK (replicates >= 0),
  priority         integer NOT NULL DEFAULT 100,
  arm_budget_s     integer,
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'concluded')),
  run_after        timestamptz,
  notes            text,
  created_by       text NOT NULL DEFAULT 'research_wing',
  created_at       timestamptz NOT NULL DEFAULT now(),
  concluded_at     timestamptz
);
CREATE TABLE public.ottoq_throughput_sweep_cells (
  cell_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sweep_id      uuid NOT NULL REFERENCES public.ottoq_throughput_sweeps(sweep_id),
  cell_code     text NOT NULL,
  ord           integer NOT NULL,
  seat          text NOT NULL CHECK (seat IN ('otto_q', 'fifo', 'greedy')),
  buildout_code text NOT NULL REFERENCES public.ottoq_site_buildouts(buildout_code),
  fixed_params  jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(fixed_params) = 'object'),
  UNIQUE (sweep_id, cell_code),
  UNIQUE (sweep_id, ord)
);

-- ── 2. the arms: evidence ──
CREATE TABLE public.ottoq_throughput_sweep_arms (
  arm_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sweep_id     uuid NOT NULL REFERENCES public.ottoq_throughput_sweeps(sweep_id),
  cell_id      uuid NOT NULL REFERENCES public.ottoq_throughput_sweep_cells(cell_id),
  seed         bigint NOT NULL,
  replicate    boolean NOT NULL DEFAULT false,
  sim_run_id   uuid,
  engine_hash  text NOT NULL,
  dial_floor   timestamptz NOT NULL,
  ran_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  complete     boolean NOT NULL,
  ticks        integer,
  wall_s       numeric,
  paid_shield  boolean,
  boot_md5     text,
  h_cal        text,
  atoms        jsonb,
  buildout     jsonb,
  restore      jsonb,
  score_id     bigint,
  scorecard    jsonb,
  arm_metrics  jsonb,
  arm_error    jsonb
);
CREATE INDEX ottoq_throughput_sweep_arms_key_idx ON public.ottoq_throughput_sweep_arms (cell_id, seed, replicate, ran_at);
CREATE INDEX ottoq_throughput_sweep_arms_run_idx ON public.ottoq_throughput_sweep_arms (sim_run_id);

CREATE FUNCTION public.ottoq_throughput_sweep_arms_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'ottoq_throughput_sweep_arms is evidence and append-only: % is refused', TG_OP;
END $fn$;
CREATE TRIGGER trg_ottoq_throughput_sweep_arms_append_only
  BEFORE UPDATE OR DELETE ON public.ottoq_throughput_sweep_arms
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_throughput_sweep_arms_append_only();

ALTER TABLE public.ottoq_throughput_sweeps      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_throughput_sweep_cells ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_throughput_sweep_arms  ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_throughput_sweeps_read      ON public.ottoq_throughput_sweeps      FOR SELECT TO authenticated, service_role USING (true);
CREATE POLICY ottoq_throughput_sweep_cells_read ON public.ottoq_throughput_sweep_cells FOR SELECT TO authenticated, service_role USING (true);
CREATE POLICY ottoq_throughput_sweep_arms_read  ON public.ottoq_throughput_sweep_arms  FOR SELECT TO authenticated, service_role USING (true);
REVOKE ALL ON public.ottoq_throughput_sweeps, public.ottoq_throughput_sweep_cells, public.ottoq_throughput_sweep_arms
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_throughput_sweeps, public.ottoq_throughput_sweep_cells, public.ottoq_throughput_sweep_arms
  TO authenticated, service_role;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_throughput_sweep_arms', 'sim_run_id', 'evidence',
        '0568: one row per throughput-sweep arm. Evidence, not engine: the frontier and the Margin Ledger quote from it, so it must survive ottoq_purge_prior_runs. Deliberately carries NO foreign key to ottoq_sim_runs, as 0340''s ledger does not: check (b) asks for one from engine/stamp only.');

COMMENT ON TABLE public.ottoq_throughput_sweeps IS
'0568. A throughput sweep: one scenario on one depot from one operator-day start, at a fixed step, over a list of seeds (a pure hash of the sweep code). Its cells are in ottoq_throughput_sweep_cells and its arms in ottoq_throughput_sweep_arms.';
COMMENT ON TABLE public.ottoq_throughput_sweep_arms IS
'0568. Evidence: one row per arm a throughput sweep ran, append-only, class evidence with no FK to ottoq_sim_runs. An arm counts only when ran_at >= ottoq_dial_pair_floor(); valid when complete and paid_shield.';

-- ── 3. the window's switch ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, description, affects, agent_writable)
VALUES ('throughput_sweep_runner_enabled', 0, 1, 0,
  '0568: master switch for public.ottoq_throughput_sweep_runner (pg_cron every 2 min). When 1, each firing runs at most ONE throughput-sweep arm, and only when no run is live, every canon column is current and the world lock is free. An arm holds the world for its whole length (G141), so the switch is opened only in the overnight window (04:00-11:00 UTC by cron).',
  'public.ottoq_throughput_sweep_runner', false);
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
VALUES ('global', '00000000-0000-0000-0000-000000000000', 'throughput_sweep_runner_enabled', 0, '0568');

-- ── 4. one arm ──
CREATE FUNCTION public.ottoq_throughput_sweep_arm(p_cell uuid, p_seed bigint, p_replicate boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  c public.ottoq_throughput_sweep_cells%ROWTYPE;
  s public.ottoq_throughput_sweeps%ROWTYPE;
  v_seat int; v_k text; v_num numeric;
  v_floor timestamptz; v_engine text; v_budget int;
  v_bo jsonb; v_restore jsonb; v_run uuid; v_boot jsonb; v_soc0 numeric;
  v_t0 timestamptz; v_clock timestamptz; v_status text; v_ticks int;
  v_err jsonb; v_err_msg text; v_err_detail text; v_err_ctx text;
  v_atoms jsonb; v_score bigint; v_sc jsonb; v_m jsonb;
  v_complete boolean; v_paid boolean; v_wall numeric; v_arm bigint;
BEGIN
  SELECT * INTO c FROM public.ottoq_throughput_sweep_cells WHERE cell_id = p_cell;
  IF NOT FOUND THEN RAISE EXCEPTION 'sweep_arm: no cell %', p_cell USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO s FROM public.ottoq_throughput_sweeps WHERE sweep_id = c.sweep_id;
  IF s.status <> 'active' THEN
    RAISE EXCEPTION 'sweep_arm: sweep % is %, not active', s.sweep_code, s.status USING ERRCODE = 'P0001';
  END IF;
  IF NOT (p_seed = ANY (s.seeds)) THEN
    RAISE EXCEPTION 'sweep_arm: seed % is not one of sweep %''s seeds', p_seed, s.sweep_code USING ERRCODE = 'P0001';
  END IF;

  -- ONE MOVER: the recertification runner's lock (0439/0440), which 0564's Start door cancels the holder of.
  IF NOT public.ottoq_try_world_lock() THEN
    RAISE EXCEPTION 'sweep_arm: the recertification runner (or another pair or arm) holds the world' USING ERRCODE = '55P03';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'sweep_arm: a run is live; arms run between runs' USING ERRCODE = '55006';
  END IF;

  v_floor  := public.ottoq_dial_pair_floor();
  v_engine := public.ottoq_engine_hash();
  -- Under determinism a re-run is repetition, not replication (G153): once per cell and seed since the floor, and a
  -- replicate once more, on purpose, to check the repetition is exact.
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms a
              WHERE a.cell_id = p_cell AND a.seed = p_seed AND a.replicate = p_replicate AND a.ran_at >= v_floor) THEN
    RAISE EXCEPTION 'sweep_arm: cell % seed % (replicate %) already ran since the dial floor %', c.cell_code, p_seed,
      p_replicate, v_floor USING ERRCODE = '23505';
  END IF;
  IF p_replicate AND NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms a
                                  WHERE a.cell_id = p_cell AND a.seed = p_seed AND NOT a.replicate
                                    AND a.complete AND a.ran_at >= v_floor) THEN
    RAISE EXCEPTION 'sweep_arm: a replicate needs a complete primary arm of cell % seed % since the floor', c.cell_code, p_seed
      USING ERRCODE = 'P0001';
  END IF;

  v_seat := CASE c.seat WHEN 'otto_q' THEN 0 WHEN 'fifo' THEN 1 WHEN 'greedy' THEN 2 END;
  -- every fixed dial is catalogued and in range, and none is one of the harness's own (ottoq_dial_pair's rule)
  FOR v_k IN SELECT jsonb_object_keys(c.fixed_params) LOOP
    IF v_k IN ('cuopt_propose_enabled', 'cuopt_first_refusal_max_defers', 'orchestrator_agent_enabled', 'proposer_seat') THEN
      RAISE EXCEPTION 'sweep_arm: fixed param % is one of the harness''s own keys', v_k USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_typeof(c.fixed_params->v_k) <> 'number' THEN
      RAISE EXCEPTION 'sweep_arm: fixed param % is not a number', v_k USING ERRCODE = '22023';
    END IF;
    v_num := (c.fixed_params->>v_k)::numeric;
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = v_k
                      AND (k.min_value IS NULL OR v_num >= k.min_value) AND (k.max_value IS NULL OR v_num <= k.max_value)) THEN
      RAISE EXCEPTION 'sweep_arm: fixed param % = % is uncatalogued or outside its range', v_k, v_num USING ERRCODE = '22003';
    END IF;
  END LOOP;
  v_budget := COALESCE(s.arm_budget_s, GREATEST(240, s.ticks * 30));

  -- The reset and the build-out belong to no run (0421): harness setup, not the day's evidence.
  PERFORM set_config('ottoq.sim_run_id', 'none', true);
  PERFORM public.ottoq_tick_invariance_reset_fleet(s.depot_id, p_seed, s.sim_start);
  v_bo := public.ottoq_site_buildout_apply(s.depot_id, c.buildout_code);

  -- The operator's door (0531), on the depot as built out.
  PERFORM set_config('ottoq.sim_run_id', '', true);
  v_run := public.ottoq_sim_run_scenario(s.scenario, p_seed, 'ab_harness', s.sim_start);
  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
  -- 0520's cadence, and the record the scorecard (0567) reads its census from.
  UPDATE public.ottoq_sim_runs
     SET time_scale = 2 * s.sim_min_per_tick, tick_interval_seconds = 30,
         payload = COALESCE(payload, '{}'::jsonb)
                || jsonb_build_object('world_fingerprint', ottoq.ottoq_world_fingerprint(s.depot_id),
                                      'arm_start', '0531:operator_door', 'proposer_seat', c.seat,
                                      'site_buildout', v_bo,
                                      'throughput_sweep', jsonb_build_object('sweep_id', s.sweep_id, 'sweep_code', s.sweep_code,
                                                                             'cell_id', c.cell_id, 'cell_code', c.cell_code,
                                                                             'seed', p_seed, 'replicate', p_replicate))
   WHERE sim_run_id = v_run;

  -- The deterministic core alone plus the seat, exactly as ottoq_ab_pair quiesces an arm (0152, 0112, 0261).
  INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
  VALUES ('run', v_run, 'cuopt_propose_enabled', 0, '0568_sweep_quiesce'),
         ('run', v_run, 'cuopt_first_refusal_max_defers', 0, '0568_sweep_quiesce'),
         ('run', v_run, 'orchestrator_agent_enabled', 0, '0568_sweep_quiesce'),
         ('run', v_run, 'proposer_seat', v_seat, '0568_sweep_seat')
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
    SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by;
  INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
  SELECT 'run', v_run, f.key, f.value::numeric, '0568_sweep_fixed' FROM jsonb_each_text(c.fixed_params) AS f(key, value)
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
    SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by;

  v_boot := public.ottoq_boot_state_fingerprint(s.depot_id, v_run);
  SELECT sum(b.current_soc_kwh) INTO v_soc0 FROM public.ottoq_bess_units b WHERE b.depot_id = s.depot_id;

  v_t0 := clock_timestamp();
  LOOP
    SELECT sim_clock_current, status, tick_count INTO v_clock, v_status, v_ticks
      FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    EXIT WHEN v_status <> 'running' OR v_ticks >= s.ticks;
    EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= v_budget;
    -- 0535: each tick in its own subtransaction; an engine error ends this arm and is recorded with it.
    BEGIN
      PERFORM public.ottoq_sim_advance_tick(v_run);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err_msg = MESSAGE_TEXT, v_err_detail = PG_EXCEPTION_DETAIL, v_err_ctx = PG_EXCEPTION_CONTEXT;
      v_err := jsonb_build_object('error', v_err_msg, 'detail', v_err_detail, 'where', left(v_err_ctx, 800),
                                  'tick', v_ticks + 1, 'sim_clock', v_clock);
      EXIT;
    END;
  END LOOP;
  v_wall := round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0))::numeric, 1);

  -- Everything read BEFORE the teardown, as 0439 reads its arms.
  v_atoms := public.ottoq_ab_arm_atoms(s.depot_id, v_run);
  v_m     := public.ottoq_dial_arm_metrics(v_run, s.depot_id, v_soc0);
  v_score := public.ottoq_throughput_score_write(v_run, CASE WHEN p_replicate THEN 'sweep_0568_replicate' ELSE 'sweep_0568' END);
  SELECT scorecard INTO v_sc FROM public.ottoq_throughput_scores WHERE score_id = v_score;
  SELECT tick_count >= s.ticks INTO v_complete FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
  v_complete := COALESCE(v_complete, false) AND v_err IS NULL;
  -- db/checks/0146, structurally: an arm that skipped the shield is not comparable
  v_paid := COALESCE((v_m->>'rule_evaluations')::bigint, 0) > 0;

  PERFORM public.ottoq_sim_stop_and_reset(v_run, 'sweep_arm_complete');
  -- stop_and_reset pins the tagging GUC to the run it tore down; the restore belongs to no run
  PERFORM set_config('ottoq.sim_run_id', 'none', true);
  v_restore := public.ottoq_site_buildout_restore(s.depot_id);

  -- validation_status on a harness arm means THE INSTRUMENT WAS VALID, never that a policy won
  UPDATE public.ottoq_sim_runs
     SET validation_status = CASE WHEN NOT v_complete THEN 'inconclusive' WHEN v_paid THEN 'passed' ELSE 'failed' END,
         validation_notes = jsonb_build_object('kind', 'throughput_sweep_arm', 'sweep', s.sweep_code, 'cell', c.cell_code,
                                               'seed', p_seed, 'replicate', p_replicate, 'complete', v_complete,
                                               'paid_shield', v_paid)::text
   WHERE sim_run_id = v_run;

  INSERT INTO public.ottoq_throughput_sweep_arms
    (sweep_id, cell_id, seed, replicate, sim_run_id, engine_hash, dial_floor, complete, ticks, wall_s, paid_shield,
     boot_md5, h_cal, atoms, buildout, restore, score_id, scorecard, arm_metrics, arm_error)
  VALUES (s.sweep_id, c.cell_id, p_seed, p_replicate, v_run, v_engine, v_floor, v_complete,
          (SELECT tick_count FROM public.ottoq_sim_runs WHERE sim_run_id = v_run), v_wall, v_paid,
          md5(v_boot::text), v_boot->'calibration'->>'h', v_atoms, v_bo, v_restore, v_score, v_sc, v_m, v_err)
  RETURNING arm_id INTO v_arm;

  RETURN jsonb_build_object('arm_id', v_arm, 'sweep', s.sweep_code, 'cell', c.cell_code, 'seed', p_seed,
                            'replicate', p_replicate, 'sim_run_id', v_run, 'complete', v_complete, 'paid_shield', v_paid,
                            'wall_s', v_wall, 'visits_served', v_sc #> '{throughput,visits_served}',
                            'arm_error', v_err);
END $fn$;
COMMENT ON FUNCTION public.ottoq_throughput_sweep_arm(uuid, bigint, boolean) IS
'0568. One throughput-sweep arm in the caller''s transaction: world lock, no live run, fleet reset and build-out filed to no run, the operator''s door, the cell''s seat and dials, the sweep''s step and ticks, scored before teardown into ottoq_throughput_scores and ottoq_throughput_sweep_arms, build-out restored. Once per cell and seed since the dial floor (and once more as a replicate).';

-- ── 5. the runner ──
CREATE FUNCTION public.ottoq_throughput_sweep_runner()
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_floor timestamptz; v_below int; t record; v_res jsonb; v_msg text; v_state text; v_detail text; v_ctx text;
  s record;
BEGIN
  IF COALESCE(public.ottoq_policy_get(NULL, 'throughput_sweep_runner_enabled', 0), 0) < 1 THEN
    RETURN jsonb_build_object('ran', false, 'why', 'throughput_sweep_runner_enabled is 0');
  END IF;
  IF NOT public.ottoq_try_world_lock() THEN
    RETURN jsonb_build_object('ran', false, 'why', 'the world lock is held (a certification, a dial pair or an arm)');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RETURN jsonb_build_object('ran', false, 'why', 'a run is live');
  END IF;
  SELECT count(*) INTO v_below FROM public.ottoq_determinism_canon WHERE enabled AND NOT satisfies_floor;
  IF v_below > 0 THEN
    RETURN jsonb_build_object('ran', false, 'why', format('certification has priority: %s canon column(s) below the recert floor', v_below));
  END IF;

  v_floor := public.ottoq_dial_pair_floor();
  -- The next task: the due sweep of lowest priority number first, then seed by seed, cell by cell; a replicate of one of the first `replicates` primaries runs once that
  -- primary's seed is done (ord 1000 + the cell's ord puts it after the seed's cells). Anything already recorded since the
  -- floor -- complete, incomplete or failed -- is done: a failure is recorded, not retried.
  WITH active AS (
    SELECT sw.* FROM public.ottoq_throughput_sweeps sw
     WHERE sw.status = 'active' AND (sw.run_after IS NULL OR sw.run_after <= now())
  ), prim AS (
    SELECT a.sweep_id, a.priority, a.created_at, c.cell_id, sd.seed, sd.k, c.ord, false AS replicate,
           row_number() OVER (PARTITION BY a.sweep_id ORDER BY sd.k, c.ord) AS n
      FROM active a
      JOIN public.ottoq_throughput_sweep_cells c ON c.sweep_id = a.sweep_id
      CROSS JOIN LATERAL unnest(a.seeds) WITH ORDINALITY AS sd(seed, k)
  ), tasks AS (
    SELECT sweep_id, priority, created_at, cell_id, seed, k, ord, replicate FROM prim
    UNION ALL
    SELECT p.sweep_id, p.priority, p.created_at, p.cell_id, p.seed, p.k, 1000 + p.ord, true
      FROM prim p JOIN active a ON a.sweep_id = p.sweep_id
     WHERE p.n <= a.replicates
  )
  SELECT t2.* INTO t FROM tasks t2
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms x
                      WHERE x.cell_id = t2.cell_id AND x.seed = t2.seed AND x.replicate = t2.replicate AND x.ran_at >= v_floor)
     AND (NOT t2.replicate OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms x
                                       WHERE x.cell_id = t2.cell_id AND x.seed = t2.seed AND NOT x.replicate
                                         AND x.complete AND x.ran_at >= v_floor))
   ORDER BY t2.priority, t2.created_at, t2.sweep_id, t2.k, t2.ord
   LIMIT 1;

  IF NOT FOUND THEN
    -- nothing left: every active sweep whose tasks are all recorded is concluded
    FOR s IN SELECT sw.sweep_id, sw.sweep_code FROM public.ottoq_throughput_sweeps sw WHERE sw.status = 'active'
                AND (sw.run_after IS NULL OR sw.run_after <= now()) LOOP
      UPDATE public.ottoq_throughput_sweeps SET status = 'concluded', concluded_at = now() WHERE sweep_id = s.sweep_id;
    END LOOP;
    RETURN jsonb_build_object('ran', false, 'why', 'no active sweep has an arm left to run');
  END IF;

  BEGIN
    v_res := public.ottoq_throughput_sweep_arm(t.cell_id, t.seed, t.replicate);
  EXCEPTION WHEN OTHERS THEN
    -- The arm's subtransaction rolled back everything it did, the build-out included. Record the failure so the night
    -- moves on instead of retrying the same arm until the window closes (0535's lesson). A manual Start's cancel is
    -- query_canceled, which OTHERS does not catch: that arm rolls back whole and runs again the next night.
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE, v_detail = PG_EXCEPTION_DETAIL,
                            v_ctx = PG_EXCEPTION_CONTEXT;
    -- A contention failure is not the arm's: a deadlock, a serialization failure, a lock that was not free or a run
    -- that went live in between. Nothing is recorded, and the next firing tries the same arm again.
    IF v_state IN ('40P01', '40001', '55P03', '55006') THEN
      RETURN jsonb_build_object('ran', false, 'why', 'contention: ' || v_msg, 'sqlstate', v_state,
                                'cell_id', t.cell_id, 'seed', t.seed, 'replicate', t.replicate);
    END IF;
    INSERT INTO public.ottoq_throughput_sweep_arms
      (sweep_id, cell_id, seed, replicate, engine_hash, dial_floor, complete, arm_error)
    VALUES (t.sweep_id, t.cell_id, t.seed,
            t.replicate, public.ottoq_engine_hash(), v_floor, false,
            jsonb_build_object('error', v_msg, 'sqlstate', v_state, 'detail', v_detail, 'where', left(v_ctx, 800),
                               'stage', 'arm'));
    RETURN jsonb_build_object('ran', true, 'failed', true, 'cell_id', t.cell_id, 'seed', t.seed,
                              'replicate', t.replicate, 'error', v_msg);
  END;
  RETURN jsonb_build_object('ran', true, 'arm', v_res);
END $fn$;
COMMENT ON FUNCTION public.ottoq_throughput_sweep_runner() IS
'0568. The cron entry for throughput sweeps: at most one arm per call, only while throughput_sweep_runner_enabled is 1, no run is live, every canon column is current and the world lock is free. Seed by seed, cell by cell; a failed arm is recorded and not retried.';

-- ── 6. the readouts ──
CREATE VIEW public.ottoq_throughput_frontier
WITH (security_invoker = true) AS
WITH cur AS (
  SELECT a.*, c.cell_code, c.ord, c.seat, c.buildout_code, c.fixed_params, s.sweep_code, s.ticks AS sweep_ticks,
         s.sim_min_per_tick, s.seeds
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE NOT a.replicate AND a.ran_at >= public.ottoq_dial_pair_floor()
), v AS (
  SELECT cur.*,
         (scorecard #>> '{throughput,visits_served}')::numeric              AS served,
         (scorecard #>> '{throughput,vehicles_served}')::numeric            AS vehicles,
         (scorecard #>> '{throughput,peak_hour_served}')::numeric           AS peak_hour,
         (scorecard #>> '{timeliness,on_time_pct}')::numeric                AS on_time_pct,
         (scorecard #>> '{timeliness,door_p50_min}')::numeric               AS door_p50,
         (scorecard #>> '{rule9,left_below_target}')::numeric
           + (scorecard #>> '{rule9,left_with_needed_work_open}')::numeric  AS rule9_breaches,
         (scorecard #>> '{fast_chargers,turns_per_charger_per_day}')::numeric AS turns,
         (scorecard #>> '{fast_chargers,busy_pct}')::numeric                AS busy_pct,
         (scorecard #>> '{fast_chargers,mean_kw}')::numeric                 AS mean_kw,
         (scorecard ->> 'l2_sessions')::numeric                             AS l2_sessions,
         (arm_metrics ->> 'deployed_car_hours')::numeric                    AS deployed_h,
         (arm_metrics ->> 'unmet_demand_pct')::numeric                      AS unmet_pct,
         (arm_metrics ->> 'site_cost_usd_per_day')::numeric                 AS site_cost,
         (arm_metrics ->> 'peak_site_kw')::numeric                          AS peak_kw
    FROM cur
)
SELECT sweep_code, cell_code, ord, buildout_code, seat, fixed_params, sim_min_per_tick, sweep_ticks,
       cardinality(min(seeds)) AS seeds_planned,
       count(*)                                                         AS arms,
       count(*) FILTER (WHERE complete AND paid_shield)                 AS valid_arms,
       count(*) FILTER (WHERE arm_error IS NOT NULL)                    AS failed_arms,
       jsonb_build_object('mean', round(avg(served) FILTER (WHERE complete AND paid_shield), 1),
                          'min', min(served) FILTER (WHERE complete AND paid_shield),
                          'max', max(served) FILTER (WHERE complete AND paid_shield))      AS visits_served,
       jsonb_build_object('mean', round(avg(vehicles) FILTER (WHERE complete AND paid_shield), 1),
                          'min', min(vehicles) FILTER (WHERE complete AND paid_shield),
                          'max', max(vehicles) FILTER (WHERE complete AND paid_shield))    AS vehicles_served,
       jsonb_build_object('mean', round(avg(peak_hour) FILTER (WHERE complete AND paid_shield), 1),
                          'max', max(peak_hour) FILTER (WHERE complete AND paid_shield))   AS peak_hour_served,
       jsonb_build_object('mean', round(avg(on_time_pct) FILTER (WHERE complete AND paid_shield), 1),
                          'min', min(on_time_pct) FILTER (WHERE complete AND paid_shield),
                          'max', max(on_time_pct) FILTER (WHERE complete AND paid_shield)) AS on_time_pct,
       jsonb_build_object('mean', round(avg(door_p50) FILTER (WHERE complete AND paid_shield), 0),
                          'min', min(door_p50) FILTER (WHERE complete AND paid_shield),
                          'max', max(door_p50) FILTER (WHERE complete AND paid_shield))    AS door_p50_min,
       sum(rule9_breaches) FILTER (WHERE complete AND paid_shield)                         AS rule9_breaches,
       round(avg(turns) FILTER (WHERE complete AND paid_shield), 2)                        AS dcfc_turns_per_charger_per_day,
       round(avg(busy_pct) FILTER (WHERE complete AND paid_shield), 1)                     AS dcfc_busy_pct,
       round(avg(mean_kw) FILTER (WHERE complete AND paid_shield), 1)                      AS dcfc_mean_kw,
       round(avg(l2_sessions) FILTER (WHERE complete AND paid_shield), 1)                  AS l2_sessions,
       round(avg(deployed_h) FILTER (WHERE complete AND paid_shield), 1)                   AS deployed_car_hours,
       round(avg(unmet_pct) FILTER (WHERE complete AND paid_shield), 1)                    AS unmet_demand_pct,
       round(avg(site_cost) FILTER (WHERE complete AND paid_shield), 2)                    AS site_cost_usd_per_day,
       round(avg(peak_kw) FILTER (WHERE complete AND paid_shield), 1)                      AS peak_site_kw,
       round(avg(wall_s), 0)                                                               AS mean_wall_s
  FROM v
 GROUP BY sweep_code, cell_code, ord, buildout_code, seat, fixed_params, sim_min_per_tick, sweep_ticks;
COMMENT ON VIEW public.ottoq_throughput_frontier IS
'0568. Per sweep cell, over its current (ran_at >= ottoq_dial_pair_floor()) primary arms: how many ran, how many are valid (complete and shield paid), and each headline as a mean and range over the valid arms'' seeds. A range, never one lucky run.';

CREATE VIEW public.ottoq_throughput_sweep_pairs
WITH (security_invoker = true) AS
WITH cur AS (
  SELECT a.*, c.seat, c.buildout_code, c.fixed_params, s.sweep_code
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE NOT a.replicate AND a.ran_at >= public.ottoq_dial_pair_floor() AND a.complete AND a.paid_shield
)
SELECT q.sweep_code, q.buildout_code, q.fixed_params, q.seed, b.seat AS baseline,
       q.boot_md5 = b.boot_md5 AND q.h_cal IS NOT DISTINCT FROM b.h_cal                     AS world_identical,
       (q.scorecard #>> '{throughput,visits_served}')::numeric
         - (b.scorecard #>> '{throughput,visits_served}')::numeric                        AS served_delta,
       (q.scorecard #>> '{timeliness,on_time_pct}')::numeric
         - (b.scorecard #>> '{timeliness,on_time_pct}')::numeric                          AS on_time_pct_delta,
       (q.scorecard #>> '{timeliness,door_p50_min}')::numeric
         - (b.scorecard #>> '{timeliness,door_p50_min}')::numeric                         AS door_p50_delta_min,
       (q.arm_metrics ->> 'deployed_car_hours')::numeric
         - (b.arm_metrics ->> 'deployed_car_hours')::numeric                              AS deployed_car_hours_delta,
       (q.arm_metrics ->> 'site_cost_usd_per_day')::numeric
         - (b.arm_metrics ->> 'site_cost_usd_per_day')::numeric                           AS site_cost_usd_delta,
       q.sim_run_id AS otto_q_run, b.sim_run_id AS baseline_run
  FROM cur q
  JOIN cur b ON b.sweep_id = q.sweep_id AND b.seed = q.seed AND b.buildout_code = q.buildout_code
            AND b.fixed_params = q.fixed_params AND b.seat <> 'otto_q'
 WHERE q.seat = 'otto_q';
COMMENT ON VIEW public.ottoq_throughput_sweep_pairs IS
'0568. OTTO-Q against each baseline seat on the same seed, build-out and dials (common random numbers): the deltas are OTTO-Q minus the baseline, and world_identical says whether the two arms booted from one world. Current valid arms only.';

CREATE VIEW public.ottoq_throughput_sweep_replicates
WITH (security_invoker = true) AS
SELECT s.sweep_code, c.cell_code, r.seed, p.arm_id AS primary_arm, r.arm_id AS replicate_arm,
       p.ran_at AS primary_ran_at, r.ran_at AS replicate_ran_at,
       r.boot_md5 = p.boot_md5 AND r.atoms = p.atoms                                         AS identical,
       (SELECT COALESCE(jsonb_agg(k ORDER BY k), '[]'::jsonb)
          FROM jsonb_object_keys(COALESCE(p.atoms, '{}'::jsonb) || COALESCE(r.atoms, '{}'::jsonb)) AS k
         WHERE (p.atoms -> k) IS DISTINCT FROM (r.atoms -> k))                               AS moved
  FROM public.ottoq_throughput_sweep_arms r
  JOIN public.ottoq_throughput_sweep_arms p ON p.cell_id = r.cell_id AND p.seed = r.seed AND NOT p.replicate
                                           AND p.complete AND p.ran_at >= public.ottoq_dial_pair_floor()
  JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = r.cell_id
  JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = r.sweep_id
 WHERE r.replicate AND r.complete AND r.ran_at >= public.ottoq_dial_pair_floor();
COMMENT ON VIEW public.ottoq_throughput_sweep_replicates IS
'0568. Each replicate arm against its primary: identical when the boot image and every atom (ottoq_ab_arm_atoms) agree. Two arms in different transactions, hours apart: the cross-transaction determinism G140 asked for, at the sweep''s step and on its build-out.';

REVOKE ALL ON public.ottoq_throughput_frontier, public.ottoq_throughput_sweep_pairs, public.ottoq_throughput_sweep_replicates
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_throughput_frontier, public.ottoq_throughput_sweep_pairs, public.ottoq_throughput_sweep_replicates
  TO authenticated, service_role;

-- ── grants: the arm and the runner move the world, so postgres (cron) and service_role only ──
REVOKE ALL ON FUNCTION public.ottoq_throughput_sweep_arm(uuid, bigint, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_throughput_sweep_runner()                  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_throughput_sweep_arms_append_only()        FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_throughput_sweep_arm(uuid, bigint, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_throughput_sweep_runner()                  TO service_role;

-- ── 7. the first sweep ──
WITH sw AS (
  INSERT INTO public.ottoq_throughput_sweeps
    (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, run_after, notes)
  SELECT 'frontier_2026_09_29',
         'Throughput frontier, night 1: 10 vs 20 robotic fast chargers, OTTO-Q vs FIFO vs greedy, a busy day at a normal day''s deployment target',
         '11111111-1111-1111-1111-111111111111', 'busy_day', '2026-09-01 11:00:00+00', 144, 5,
         ARRAY(SELECT ('x' || substr(md5('frontier_2026_09_29:' || k), 1, 15))::bit(60)::bigint
                 FROM generate_series(1, 5) AS k ORDER BY k),
         1, '2026-09-30 04:00:00+00',
         'busy_day from 6 AM CT for 12 hours at 5 sim-minutes a tick; deploy_peak_fraction 0.90 on every arm (catalog default, normal_day''s level; busy_day''s own is 0.45). FIFO and greedy replace OTTO-Q''s charger assignment only; every seat pays the same shield.'
  RETURNING sweep_id
)
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT sw.sweep_id, v.code, v.ord, v.seat, v.bo, '{"deploy_peak_fraction": 0.90}'::jsonb
  FROM sw, (VALUES (1, 'dcfc10.otto_q', 'otto_q', 'dcfc10'), (2, 'dcfc10.fifo', 'fifo', 'dcfc10'),
                   (3, 'dcfc10.greedy', 'greedy', 'dcfc10'), (4, 'dcfc20.otto_q', 'otto_q', 'dcfc20'),
                   (5, 'dcfc20.fifo', 'fifo', 'dcfc20'), (6, 'dcfc20.greedy', 'greedy', 'dcfc20')) AS v(ord, code, seat, bo);

-- The smoke arm: one 2-hour dcfc20 OTTO-Q day on the real engine, first whenever the window opens (priority 10), so the
-- whole protocol -- build-out, door, seat, ticks at 5 minutes, scoring, teardown, restore, ledger -- is seen working on
-- the engine itself before a night depends on it.
WITH sw AS (
  INSERT INTO public.ottoq_throughput_sweeps
    (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority, notes)
  SELECT 'smoke_2026_09_29', 'Smoke: one 2-hour day on 20 robotic fast chargers, OTTO-Q, on the real engine before night 1',
         '11111111-1111-1111-1111-111111111111', 'busy_day', '2026-09-01 11:00:00+00', 24, 5,
         ARRAY[('x' || substr(md5('smoke_2026_09_29:1'), 1, 15))::bit(60)::bigint], 0, 10,
         'Validates the arm protocol end to end on the live engine. Not a result: 2 hours, one seed, one cell.'
  RETURNING sweep_id
)
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT sw.sweep_id, 'dcfc20.otto_q', 1, 'otto_q', 'dcfc20', '{"deploy_peak_fraction": 0.90}'::jsonb FROM sw;

-- ── 8. cron: the runner every 2 minutes, the window 04:00-11:00 UTC (11 PM-6 AM CDT) ──
SELECT cron.schedule('ottoq-throughput-sweep-runner', '*/2 * * * *',
                     'SET statement_timeout = 0; SELECT public.ottoq_throughput_sweep_runner();');
SELECT cron.schedule('ottoq_sweep_window_open', '0 4 * * *',
                     $cmd$SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_runner_enabled', 1, 'sweep_window_cron:open')$cmd$);
SELECT cron.schedule('ottoq_sweep_window_close', '0 11 * * *',
                     $cmd$SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_runner_enabled', 0, 'sweep_window_cron:close')$cmd$);

-- ── V1: the objects, the switch, the first sweep, the schedule ──
DO $verify_catalog$
DECLARE
  v_bad text;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'frontier_2026_09_29') <> 6
     OR (SELECT cardinality(seeds) FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29') <> 5
     OR (SELECT count(DISTINCT x) FROM public.ottoq_throughput_sweeps, unnest(seeds) x WHERE sweep_code = 'frontier_2026_09_29') <> 5
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps, unnest(seeds) x WHERE x <= 0) THEN
    RAISE EXCEPTION '0568 V1: the first sweep is not 6 cells over 5 distinct positive seeds';
  END IF;
  IF (SELECT run_after FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29') <> '2026-09-30 04:00:00+00'
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code = 'smoke_2026_09_29') <> 1
     OR (SELECT priority FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'smoke_2026_09_29') <> 10 THEN
    RAISE EXCEPTION '0568 V1: night 1 does not wait for its window, or the smoke arm is not first';
  END IF;
  -- every cell's fixed dials pass the arm's own validation now, so no arm fails on them at 11 PM
  SELECT string_agg(c.cell_code || '.' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c, jsonb_each_text(c.fixed_params) f
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0568 V1: these fixed dials would fail the arm''s validation: %', v_bad;
  END IF;
  IF COALESCE(public.ottoq_policy_get(NULL, 'throughput_sweep_runner_enabled', 0), 0) <> 0 THEN
    RAISE EXCEPTION '0568 V1: the runner''s switch is not closed';
  END IF;
  IF (SELECT count(*) FROM cron.job WHERE jobname IN ('ottoq-throughput-sweep-runner', 'ottoq_sweep_window_open',
                                                       'ottoq_sweep_window_close') AND active) <> 3 THEN
    RAISE EXCEPTION '0568 V1: the runner and its window are not all scheduled';
  END IF;
  IF has_function_privilege('authenticated', 'public.ottoq_throughput_sweep_runner()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)', 'EXECUTE')
     OR NOT has_table_privilege('authenticated', 'public.ottoq_throughput_frontier', 'SELECT') THEN
    RAISE EXCEPTION '0568 V1: grants are not as declared';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_throughput_sweep_arms'
                    AND column_name = 'sim_run_id' AND class = 'evidence') THEN
    RAISE EXCEPTION '0568 V1: the arms table is not registered as evidence';
  END IF;
  -- the runner, called now with its switch closed, does nothing and says so
  IF public.ottoq_throughput_sweep_runner()->>'why' <> 'throughput_sweep_runner_enabled is 0' THEN
    RAISE EXCEPTION '0568 V1: the runner did not stand down with its switch closed';
  END IF;
END $verify_catalog$;

-- ── V2: append-only holds ──
DO $verify_append_only$
BEGIN
  INSERT INTO public.ottoq_throughput_sweep_arms (sweep_id, cell_id, seed, engine_hash, dial_floor, complete, arm_error)
  SELECT s.sweep_id, c.cell_id, s.seeds[1], 'v2', now(), false, '{"v2": true}'
    FROM public.ottoq_throughput_sweeps s JOIN public.ottoq_throughput_sweep_cells c USING (sweep_id)
   WHERE s.sweep_code = 'frontier_2026_09_29' AND c.ord = 1;
  BEGIN
    UPDATE public.ottoq_throughput_sweep_arms SET complete = true WHERE arm_error = '{"v2": true}';
    RAISE EXCEPTION '0568 V2: an UPDATE of ottoq_throughput_sweep_arms was allowed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'ottoq_throughput_sweep_arms is evidence and append-only%' THEN RAISE; END IF;
  END;
  RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '0568_V2_ROLLBACK';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> '0568_V2_ROLLBACK' THEN RAISE; END IF;
END $verify_append_only$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0568_an_overnight_sweep_scores_one_test_day_at_a_time', false, false,
  'Sweep tables, an evidence ledger, the arm and runner functions, three read views, a catalogued switch (0) and three cron jobs. Nothing in the engine, the recertification runner, the dial runner or the determinism pair calls any of it; an arm runs the unchanged engine, so no certified digest can move and no dial experiment spans a changed engine.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;

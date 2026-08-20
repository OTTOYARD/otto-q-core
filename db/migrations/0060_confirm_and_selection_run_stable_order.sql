-- migration-version: 20260820180000
-- migration-name:    confirm_and_selection_run_stable_order
-- 0060 — C7 FOLLOW-UP #14, found by re-certification #14 (post-0059 arms
-- 1a505390 vs eea3a256: 13/20 identical, first divergence sim-min 420). 0059
-- HOLDS and is visible in the evidence: at the divergent tick both arms walk
-- the refusal reactor in the new ascending-vehicle order. What differs is the
-- CONTENT of the reactor's queue — arm B carries one refused command arm A
-- does not.
--
-- A new instrument found the true origin four ticks earlier than the frame
-- digest sees it. Aligning both arms' COMMAND STREAMS in run-relative time
-- (rel_min = issued_at - sim_clock_start, ordered by content) puts the first
-- difference at sim-min 300, invisible to the frame digest because a refused
-- command changes no vehicle state until the reactor acts on it: arm A seated
-- vehicle ba70312c in stall 45014fff, arm B seated 5dfd9db9 in that same
-- stall.
--
-- ROOT CAUSE — twin.ottoq_sim_confirm_commands, the confirm walk, carrying
-- BOTH known nondeterminism classes at once:
--   (a) the 0059 class (insufficient key): the main FOR loop orders by
--       c.issued_at ALONE, the per-tick batch stamp, so within a tick it is
--       heap order — and the loop OCCUPIES the stall it validates, making it
--       the sharpest capacity gate in the engine;
--   (b) the 0058 class (per-run-random UUID): the preflight-supersede window
--       breaks issued_at ties on c.command_id, which is gen_random_uuid(), so
--       a random value chose which command counted as current intent and which
--       were retired as 'superseded'.
--
-- A SYSTEMATIC SWEEP replaced the one-site-at-a-time habit that has now cost
-- three rounds: every ORDER BY in schemas public/twin/ottoq was extracted and
-- filtered for a sole key that is a per-tick timestamp (issued_at, created_at,
-- sim_clock, occurred_at, ...) or a random-UUID tiebreak, then each hit was
-- classified by whether it sits on the tick path (caller graph) AND decides a
-- scarce resource or a selection. Twelve candidates, five fixed here, the rest
-- reviewed and deliberately not changed:
--   * ottoq.ottoq_active_sim_run_id — ORDER BY started_at DESC LIMIT 1 over
--     RUNNING runs; a tie needs two runs started in the same instant, and the
--     session GUC short-circuits it in every tick path. Reviewed, unchanged.
--   * ottoq_blackbox_latest_run, ottoq_clock_fidelity_ticks, ottoq_depot_cards,
--     ottoq_fleet_pending_commands, ottoq_twin_snapshot, ottoq_causation_chain,
--     ottoq_generate_incident_report — reporting / UI / test-assertion reads
--     with no call path from the tick. Reviewed, unchanged.
--   * ottoq_enact_cuopt_batch — ORDER BY p.created_at on the cuOpt enactment
--     path; no in-database caller (invoked by edge function) and quiesced in
--     every cert run by 0056, so it cannot affect a verdict. Left for the
--     cuOpt work rather than widening this migration. RECORDED, not fixed.
--
-- The five fixed sites are all tick-path and all selection-deciding. Nothing
-- about scheduling semantics moves: the same commands are confirmed, the same
-- reroutes made, the same needs rebooked — the ORDER is simply a function of
-- the run instead of physical row order.
--
-- Same self-verifying in-place mechanism as 0054-0059. Pre-image pins:
--   twin.ottoq_sim_confirm_commands          89c6f1fc756a6995a88e12720d4c3886
--   twin.ottoq_demand_rebook_after_eviction  0b7f41cbb66ffe7484b95d449fa50195
--   ottoq.ottoq_rider_flag_indepot_sweep     434f1b1017269445921cda8cc7f5e81f
--   public.ottoq_active_charge_cap_kw        69eae7856c48bd6317a85d6459ed0242
--   public.ottoq_l2_propose_bess             d6ed881fc535c970dd9c47cd60d3c62d

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int; v_done jsonb := '{}'::jsonb;
BEGIN
  FOR p IN
    SELECT * FROM (VALUES
    ('twin','ottoq_sim_confirm_commands','89c6f1fc756a6995a88e12720d4c3886',1,$anchor$     WHERE c.sim_run_id = p_sim_run_id
       AND c.status = 'issued'
     ORDER BY c.issued_at
  LOOP$anchor$,$anchor$     WHERE c.sim_run_id = p_sim_run_id
       AND c.status = 'issued'
     /* ═════════ 0060: THE CONFIRM WALK IS THE SHARPEST CAPACITY GATE ═════════
        issued_at is the per-tick sim-clock batch stamp shared by every command
        in the tick, so ORDER BY it alone is heap order — and this loop does not
        merely observe: it checks stall availability and then OCCUPIES the stall
        (UPDATE stalls SET current_vehicle_id ...), so whoever is confirmed first
        takes it and every later command for that stall is refused
        'stall_unavailable'. Measured (re-cert #14, arms 1a505390/eea3a256, first
        command-stream divergence sim-min 300): arm A seated ba70312c in stall
        45014fff while arm B seated 5dfd9db9 in the same stall; the refusal sets,
        the reactor's pending queue, and every downstream reservation diverged
        from there. Same class and same shape of fix as 0059, one layer earlier
        in the pipeline. Semantics unchanged — only the order is now a function
        of the run instead of physical row order. */
     ORDER BY c.issued_at, c.vehicle_id, c.command_type, COALESCE(c.payload->>'stall_id','')
  LOOP$anchor$),
    ('twin','ottoq_sim_confirm_commands','89c6f1fc756a6995a88e12720d4c3886',1,$anchor$ORDER BY c.issued_at DESC, c.command_id DESC$anchor$,$anchor$ORDER BY c.issued_at DESC, c.command_type DESC, (c.payload->>'stall_id') DESC
                 /* 0060: command_id is gen_random_uuid(), so on an issued_at tie a
                    per-run-random value decided which command counted as CURRENT
                    intent and which were retired as superseded. Content keys. */$anchor$),
    ('twin','ottoq_sim_confirm_commands','89c6f1fc756a6995a88e12720d4c3886',1,$anchor$ORDER BY c.issued_at ASC, c.command_id ASC$anchor$,$anchor$ORDER BY c.issued_at ASC, c.payload::text ASC, c.command_id ASC
                              /* 0060: content before the random command_id, so
                                 duplicates differing in payload retire stably */$anchor$),
    ('twin','ottoq_demand_rebook_after_eviction','0b7f41cbb66ffe7484b95d449fa50195',1,$anchor$   ORDER BY n.created_at DESC
   LIMIT 1;$anchor$,$anchor$   /* 0060: created_at defaults to now() — ONE wall-clock value for every row
      written in the same tick — so alone it is heap order, and this pick decides
      which reopened visit gets rebooked after an eviction. visit_key is the run's
      own ledger key (vehicle + sim clock); it is uniformly shifted between two
      same-seed arms, so its relative order is identical in both. */
   ORDER BY n.created_at DESC, n.visit_key DESC
   LIMIT 1;$anchor$),
    ('ottoq','ottoq_rider_flag_indepot_sweep','434f1b1017269445921cda8cc7f5e81f',1,$anchor$     ORDER BY n.created_at DESC
     LIMIT 1;$anchor$,$anchor$     /* 0060: same as twin.ottoq_demand_rebook_after_eviction — created_at is a
        per-tick wall-clock constant; visit_key is the run-stable ledger key. This
        pick decides which open visit the rider flag's work is appended to. */
     ORDER BY n.created_at DESC, n.visit_key DESC
     LIMIT 1;$anchor$),
    ('public','ottoq_active_charge_cap_kw','69eae7856c48bd6317a85d6459ed0242',1,$anchor$   ORDER BY issued_at DESC
   LIMIT 1;$anchor$,$anchor$   /* 0060: two energy commands issued in the same tick share issued_at, so the
      "latest active cap" pick was heap order — and this value is the site power
      cap the decide path plans against. tick_seq is the run's own tick counter. */
   ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, setpoint_kw DESC
   LIMIT 1;$anchor$),
    ('public','ottoq_l2_propose_bess','d6ed881fc535c970dd9c47cd60d3c62d',1,$anchor$   ORDER BY issued_at DESC
   LIMIT 1;$anchor$,$anchor$   /* 0060: same as ottoq_active_charge_cap_kw — issued_at ties within a tick made
      the active BESS setpoint pick heap order. tick_seq is the run's tick counter. */
   ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, setpoint_kw DESC
   LIMIT 1;$anchor$)
    ) AS t(sch, fn, pre_md5, n_expected, old, new)
  LOOP
    SELECT pr.oid INTO STRICT v_oid
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = p.sch AND pr.proname = p.fn AND pr.prokind = 'f';
    v_src := pg_get_functiondef(v_oid);
    IF NOT (v_done ? (p.sch || '.' || p.fn)) AND md5(v_src) <> p.pre_md5 THEN
      RAISE EXCEPTION '0060: %.% pre-image md5 % != pinned %', p.sch, p.fn, md5(v_src), p.pre_md5;
    END IF;
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> p.n_expected THEN
      RAISE EXCEPTION '0060: %.% anchor occurs % times (need %): %', p.sch, p.fn, v_cnt, p.n_expected, left(p.old, 80);
    END IF;
    EXECUTE replace(v_src, p.old, p.new);
    v_done := v_done || jsonb_build_object(p.sch || '.' || p.fn, true);
    RAISE NOTICE '0060 patched %.% -> md5 %', p.sch, p.fn,
      (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
        JOIN pg_namespace n ON n.oid = pr.pronamespace
       WHERE n.nspname = p.sch AND pr.proname = p.fn AND pr.prokind = 'f');
  END LOOP;
END
$do$;

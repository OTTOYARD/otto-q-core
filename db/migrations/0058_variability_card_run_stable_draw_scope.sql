-- migration-version: 20260820080000
-- migration-name:    variability_card_run_stable_draw_scope
-- 0058 — C7 FOLLOW-UP #12, found by re-certification #12 (post-0057 arms
-- 54ff816e vs 7015af46: 14/20 identical, first divergence sim-min 450). The
-- best round yet, and the residue is the sharpest signature so far: at tick 15
-- exactly TWO vehicles diverge, and the decisions audit trail shows positions
-- 1-16 byte-paired with run B carrying three extra decisions for vehicle
-- 464c07e3. The ledger closes the case itself: 464c07e3's eta_delay
-- variability card reads will_delay=false in arm A and
-- will_delay=true/'accident'/60min/applied in arm B — same seed, same
-- vehicle, same trip, different card. The mechanism is the 0052 salt class
-- (per-run-random UUID): ottoq_twin_deal_eta_card salts its three CRN draws
-- with p_dispatch_id, and ottoq_vehicle_dispatches.dispatch_id defaults to
-- gen_random_uuid(). The applied 60-minute delay held B's arrival, re-ordered
-- the tick-15 decide stream one entry down, and flipped vehicle 6e5c4806's
-- deferrable-return booking (deployed in A, en_route in B) downstream of the
-- shifted stall capacity. ottoq_twin_deal_fault_card has the identical defect
-- (session UUID scope, uuid_generate_v4) and is fixed in the same pass; a
-- function-wide sweep found no third offender.
--
-- THE FIX (0055's role split): the UUID stays the LEDGER key — scope_instance,
-- bucket_key, and the dedupe lookup are untouched — while the draw scope moves
-- to run-stable identity (vehicle [+ stall] + whole sim-minutes of the
-- dispatch/session start since the run's own sim_clock_start; both operands
-- sim-clock domain, so the delta is an exact tick multiple in every arm).
-- No-run and no-row callers keep the old UUID scope verbatim: live behavior
-- unchanged where there is no run to key on. Nothing about production
-- scheduling semantics moves; both functions are twin variability dealers.
--
-- Same self-verifying in-place mechanism as 0054-0057. Pre-image pins:
--   public.ottoq_twin_deal_eta_card   ca12e4f3013749e1f044eb465d84d4ba
--   public.ottoq_twin_deal_fault_card 1e6c83c946adeb5f15dffe3160209063

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int; v_done jsonb := '{}'::jsonb;
BEGIN
  FOR p IN
    SELECT * FROM (VALUES
    ('public','ottoq_twin_deal_eta_card','ca12e4f3013749e1f044eb465d84d4ba',1,$anchor$  v_clim jsonb; v_weather numeric;$anchor$,$anchor$  v_clim jsonb; v_weather numeric;
  v_scope text;   /* 0058: run-stable draw scope; dispatch_id stays the ledger key */$anchor$),
    ('public','ottoq_twin_deal_eta_card','ca12e4f3013749e1f044eb465d84d4ba',1,$anchor$  v_mult := COALESCE(ottoq_profile_rate_mult(p_run_id,'eta_delay'),1);   -- own knob (congestion deck)$anchor$,$anchor$  v_mult := COALESCE(ottoq_profile_rate_mult(p_run_id,'eta_delay'),1);   -- own knob (congestion deck)

  /* ══════════ 0058: THE DRAW SCOPE LEAVES THE RANDOM-UUID DOMAIN ══════════
     Every CRN draw below was salted with p_dispatch_id — and dispatch_id is
     gen_random_uuid() at dispatch creation, so two same-seed runs dealt
     DIFFERENT eta cards for the same vehicle's same trip by construction.
     Measured (re-cert #12, arms 54ff816e/7015af46, first divergence tick 15):
     vehicle 464c07e3's card was will_delay=false in one arm and
     will_delay=true/'accident'/60min in the other; the applied delay held the
     arrival, re-ordered the tick's whole decide stream, and flipped a second
     vehicle's deferrable-return booking downstream. Same split as 0055/0052:
     the UUID REMAINS the ledger key (scope_instance, bucket_key, the dedupe
     lookup — untouched); only the draw scope moves to run-stable identity:
     vehicle + whole minutes of dispatched_at since the run's own
     sim_clock_start (both sim-clock domain, so the delta is an exact tick
     multiple in every arm). No-run / no-row callers keep the old UUID scope
     verbatim, so live behavior is unchanged where there is no run to key on. */
  v_scope := COALESCE(
    (SELECT d.vehicle_id::text || ':' ||
            GREATEST(0, floor(EXTRACT(EPOCH FROM (d.dispatched_at - r.sim_clock_start)) / 60.0))::text
       FROM ottoq_vehicle_dispatches d
       JOIN ottoq_sim_runs r ON r.sim_run_id = p_run_id
      WHERE d.dispatch_id = p_dispatch_id),
    p_dispatch_id::text);$anchor$),
    ('public','ottoq_twin_deal_eta_card','ca12e4f3013749e1f044eb465d84d4ba',3,$anchor$p_dispatch_id::text, p_sim_day, p_tick);$anchor$,$anchor$v_scope, p_sim_day, p_tick);$anchor$),
    ('public','ottoq_twin_deal_fault_card','1e6c83c946adeb5f15dffe3160209063',1,$anchor$  v_repair_min numeric; v_mode_mult numeric; v_staffed numeric;$anchor$,$anchor$  v_repair_min numeric; v_mode_mult numeric; v_staffed numeric;
  v_scope text;   /* 0058: run-stable draw scope; session_id stays the ledger key */$anchor$),
    ('public','ottoq_twin_deal_fault_card','1e6c83c946adeb5f15dffe3160209063',1,$anchor$  v_mult := COALESCE(ottoq_profile_rate_mult(p_run_id, 'charger_fault'), 1);$anchor$,$anchor$  v_mult := COALESCE(ottoq_profile_rate_mult(p_run_id, 'charger_fault'), 1);

  /* 0058: same defect as the eta card, same fix — ocpp_sessions.id is
     uuid_generate_v4(), so session-scoped fault/repair draws differed across
     same-seed runs. Draw scope becomes vehicle + stall + whole minutes of the
     session's sim-clock started_at since sim_clock_start; the session UUID
     stays the ledger key (scope_instance, bucket_key, dedupe) untouched. The
     per-charger MTBF card is already keyed by charger identity and needed no
     change. No-run / no-row callers fall back to the old UUID scope. */
  v_scope := COALESCE(
    (SELECT s.vehicle_id::text || ':' || s.stall_id::text || ':' ||
            GREATEST(0, floor(EXTRACT(EPOCH FROM (s.started_at - r.sim_clock_start)) / 60.0))::text
       FROM ocpp_sessions s
       JOIN ottoq_sim_runs r ON r.sim_run_id = p_run_id
      WHERE s.id = p_session_id),
    p_session_id::text);$anchor$),
    ('public','ottoq_twin_deal_fault_card','1e6c83c946adeb5f15dffe3160209063',3,$anchor$p_session_id::text, p_sim_day, p_tick);$anchor$,$anchor$v_scope, p_sim_day, p_tick);$anchor$),
    ('public','ottoq_twin_deal_fault_card','1e6c83c946adeb5f15dffe3160209063',1,$anchor$'repair:' || p_session_id::text$anchor$,$anchor$'repair:' || v_scope$anchor$)
    ) AS t(sch, fn, pre_md5, n_expected, old, new)
  LOOP
    SELECT pr.oid INTO STRICT v_oid
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = p.sch AND pr.proname = p.fn;
    v_src := pg_get_functiondef(v_oid);
    IF NOT (v_done ? (p.sch || '.' || p.fn)) AND md5(v_src) <> p.pre_md5 THEN
      RAISE EXCEPTION '0058: %.% pre-image md5 % != pinned %', p.sch, p.fn, md5(v_src), p.pre_md5;
    END IF;
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> p.n_expected THEN
      RAISE EXCEPTION '0058: %.% anchor occurs % times (need %): %', p.sch, p.fn, v_cnt, p.n_expected, left(p.old, 80);
    END IF;
    EXECUTE replace(v_src, p.old, p.new);
    v_done := v_done || jsonb_build_object(p.sch || '.' || p.fn, true);
    RAISE NOTICE '0058 patched %.% -> md5 %', p.sch, p.fn,
      (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
        JOIN pg_namespace n ON n.oid = pr.pronamespace
       WHERE n.nspname = p.sch AND pr.proname = p.fn);
  END LOOP;
END
$do$;

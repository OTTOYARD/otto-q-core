-- migration-version: 20260821040000
-- migration-name:    cert_arm_pinned_sim_start
-- 0065 -- THE MEASUREMENT FIX. Not an engine change: public.ottoq_cert_arm_start is
-- the determinism-certification harness and has no caller outside it.
--
-- THE DEFECT: the function hardcoded the run's SIM clock to v_now
-- (sim_clock_start = sim_clock_current = v_now, sim_clock_end = v_now + 24h), so a
-- cert pair did not sample "the scenario" -- it sampled whichever 10-sim-hour slice of
-- normal_day began at the wall-clock minute the arm was started. Measured across two
-- consecutive rounds on the SAME code path: re-cert #17 (armed 22:40Z) carried
-- 1,075 / 1,098 vehicle commands per arm; re-cert #18 (armed 00:32Z) carried
-- 1,562 / 1,598 -- roughly 45% more work from the arrival curve alone.
--
-- WHAT THAT COST: within-round A-vs-B comparisons stayed valid throughout (the two arms
-- of a pair are armed ~2 minutes apart inside one 30-minute band, so they share a slice
-- and a load), and every determinism verdict and every bug found in 0045-0064 still
-- stands. But NO round could be differenced against another. That is why 0064's
-- throughput effect is recorded in MIGRATION_LOG as unmeasured-because-confounded
-- rather than as failed, and why the reservation-livelock fixes that follow this
-- migration need it landed FIRST: without a pinned slice there is no before/after.
--
-- THE FIX: v_sim0 pins the sim clock to 22:00 UTC of the current date -- a real
-- return-wave slice, chosen to sit between the two loads above so the #17/#18 family
-- stays roughly comparable. The signature is deliberately UNCHANGED (adding a
-- defaulted parameter would create an overload and make every existing 4-argument
-- call ambiguous).
--
-- THE DOMAIN SPLIT, which is the whole care of this patch:
--   SIM domain, moved to v_sim0  -- sim_clock_start / sim_clock_current / sim_clock_end,
--     vehicles.last_state_change (both writes), and the dispatch window
--     (dispatched_at, scheduled_return_at).
--   REAL domain, left on v_now   -- started_at, last_tick_at, next_tick_due_at. These
--     schedule the metronome in wall-clock time; moving them would either strand the
--     run or fire it 22 hours of ticks at once.
-- last_state_change MUST move with the sim clock: cold-start and dwell logic read
-- (sim_clock - last_state_change), and splitting those two across domains would put a
-- ~22-hour constant into a comparison that expects an exact tick multiple.
--
-- Same self-verifying in-place mechanism as 0054-0064. Pre-image pin:
--   public.ottoq_cert_arm_start 7dbb6135c887c8b53ec205273bfc1fbf

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int; v_first boolean := true;
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_start';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '7dbb6135c887c8b53ec205273bfc1fbf' THEN
    RAISE EXCEPTION '0065: pre-image md5 % != pinned 7dbb6135c887c8b53ec205273bfc1fbf', md5(v_src);
  END IF;

  FOR p IN
    SELECT * FROM (VALUES
    (1,$anchor$v_wseed bigint; v_deploy_n int; v_total int;$anchor$,$anchor$v_wseed bigint; v_deploy_n int; v_total int; v_sim0 timestamptz;$anchor$),
    (1,$anchor$BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);$anchor$,$anchor$BEGIN
  /* ══════════ 0065: THE CERT SAMPLES A PINNED SLICE, NOT THE ARMING MINUTE ══════════
     This function hardcoded the run's SIM clock to v_now, so a cert pair sampled
     whichever 10-sim-hour slice of normal_day began at the wall-clock minute it was
     armed. Measured on one unchanged code path: re-cert #17 (armed 22:40Z) carried
     1,075 / 1,098 vehicle commands per arm; #18 (armed 00:32Z) carried 1,562 / 1,598
     -- ~45% more work from the arrival curve alone. Within-round A-vs-B stayed valid
     (both arms armed ~2 min apart in the same band), but no round could be differenced
     against another, so no fix in the 0045-0064 series could be MEASURED, only verified.

     v_sim0 pins the sim clock to 22:00 UTC of the current date: a real return-wave
     slice, and between the two loads above so the #17/#18 family stays roughly
     comparable. The REAL-time metronome stamps (started_at, last_tick_at,
     next_tick_due_at) deliberately keep v_now -- they schedule ticks in wall-clock and
     must not move. Everything in the SIM domain moves together: sim_clock_*,
     last_state_change, and the dispatch window. Moving last_state_change with the sim
     clock is required, not incidental: cold-start and dwell logic read
     (sim_clock - last_state_change), and leaving it on the real clock would put that
     delta in a different domain from the clock it is compared against.

     Harness only. ottoq_cert_arm_start has no caller outside the determinism cert;
     production scheduling semantics are untouched by this migration. */
  v_sim0 := date_trunc('day', v_now) + interval '22 hours';
  PERFORM ottoq_benchmark_reset(d, 30, 80);$anchor$),
    (1,$anchor$  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;$anchor$,$anchor$  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;
  /* 0065: the charger fleet must start in the SIM domain too, or pinning the clock
     silently empties every proposal. ottoq_benchmark_reset stamps
     last_heartbeat_at = now() (REAL), and the proposers gate on
     last_heartbeat_at >= <sim clock> - 90 seconds -- ottoq_honour_reservation_proposal
     (the proposer ottoq_decide_tick calls first) and ottoq_l2_propose_stall_assignment;
     ottoq_book_appointment, ottoq_plan_opportunistic_charges and
     ottoq_sim_prearrival_contracts use a 35-minute window against p_clock. While the
     sim clock equalled the arming minute those comparisons happened to line up. Pinned,
     they do not: a real-clock heartbeat reads as OFFLINE against the pinned sim clock,
     every charger drops out of every proposal on tick 1, and nothing raises. The twin
     re-stamps these to the sim clock on every tick (ottoq_sim_advance_tick_world), so
     this supplies tick 1's value only, in the same domain the twin will use.
     ottoq_eval_hw_002_charger_state is safe either way: its v_now is
     COALESCE(p_context->>'now_ts', NOW()) and the decide path wires the sim clock in. */
  UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_sim0 WHERE depot_id = d;$anchor$),
    (1,$anchor$current_stall_id=NULL, last_state_change=v_now$anchor$,$anchor$current_stall_id=NULL, last_state_change=v_sim0   /* 0065: sim domain */$anchor$),
    (1,$anchor$'normal_day', v_now, v_now, v_now + interval '24 hours',$anchor$,$anchor$'normal_day', v_sim0, v_sim0, v_sim0 + interval '24 hours',   /* 0065: pinned sim start */$anchor$),
    (1,$anchor$p.fleet_operator_id, v_now,
         v_now + ((360 + $anchor$,$anchor$p.fleet_operator_id, v_sim0,   /* 0065: sim domain */
         v_sim0 + ((360 + $anchor$),
    (1,$anchor$UPDATE vehicles SET current_state='deployed', last_state_change=v_now$anchor$,$anchor$UPDATE vehicles SET current_state='deployed', last_state_change=v_sim0   /* 0065: sim domain */$anchor$)
    ) AS t(n_expected, old, new)
  LOOP
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> p.n_expected THEN
      RAISE EXCEPTION '0065: anchor occurs % times (need %): %', v_cnt, p.n_expected, left(p.old, 70);
    END IF;
    v_src := replace(v_src, p.old, p.new);
  END LOOP;

  /* The metronome triple must survive verbatim: started_at, last_tick_at and
     next_tick_due_at stay on the REAL clock. If this assertion ever fails the patch
     has moved wall-clock scheduling into the sim domain, which would strand the run. */
  IF position('v_now, v_now, v_now)' in v_src) = 0 THEN
    RAISE EXCEPTION '0065: real-clock metronome triple (started_at, last_tick_at, next_tick_due_at) did not survive';
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0065 patched public.ottoq_cert_arm_start -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_start');
END
$do$;

-- ============================================================================================
-- 0046 — SAME-SEED DETERMINISM ARMS: run the identical world twice; the ledgers must match.
--
-- Chase's repeatability complaint ("very little if any repeatability"), made executable.
-- The claim under test decomposes into two properties:
--   (a) same seed => same INITIAL world (fleet state, wear, cadence, emission gates)
--   (b) same initial world => same EVOLUTION (the 0054/0060 ordering work's territory)
-- A pair that diverges says at least one is false; a triplet says which way it drifts.
--
-- ── VERDICT, first triplet (2026-08-29) — FAIL, with structure ─────────────────────────────
-- Three arms, byte-identical treatment each time:
--   reset:  ottoq_tick_invariance_reset_fleet(depot 11111111, seed 424242)
--   start:  twin.ottoq_sim_start_run('busy_day', '2026-09-01 02:00:00+00', 60, 424242,
--           'cert_harness');  prime_deployment(clock, 0.70);  12 synchronous ticks to 08:00.
--
--   arm | run_id                               | cmds | decisions | events | bookings
--   A   | e8852600-1e8d-4f2c-af92-88dcb46d4ad4 |  507 |      1426 |   3236 |      810
--   B   | c1ca08bb-e91b-4986-a97a-9c4e72e875dc |  526 |      1506 |   3007 |      788
--   C   | de027539-8f2b-4478-978a-cb8eef3a4c5c |  587 |      1698 |    785 |      798
--   All four stream hashes differ on every pair. No arm matches any other.
--
-- TWO DISTINCT BLEEDS, both cross-run state the seeded reset does not cover:
--   1. SCHEDULING DRIFT, monotonic across arms: wash_atoms 84→73→64, soil_index_mean
--      .0381→.0408→.0416, kwh_per_100km 24.06→20.26→13.95, refusal_escalated 134→139→209.
--      Monotonic = cumulative per-vehicle state (wear/soil/cadence/need history) carried
--      between runs. reset_fleet restores SoC/state/stalls/cycles_since_wash only; the
--      harness start path (twin.ottoq_sim_start_run) does NOT re-draw need profiles or
--      re-phase wear the way ottoq_sim_run_scenario's boot does.
--   2. EMISSION SUPPRESSION, cliff-shaped in arm C: vehicle.state_changed 1566→1422→30,
--      stall.state_changed 844→798→0 — while activity continued (58 charge sessions started,
--      116 dispatches completed).
--      ROOT-CAUSED (same day, superseding the flood-guard suspicion this file first recorded):
--      not suppression — MIS-TAGGING. ottoq_active_sim_run_id() cached 'none' in its
--      transaction-scoped GUC when the arm's fleet reset fired triggers before the run row
--      existed, and arm C ran reset+start+ticks in ONE transaction — so 12 ticks of witness
--      events were written sim_run_id NULL / data_source 'production' (arms A/B ticked in a
--      separate transaction and resolved correctly; that procedural difference was the cliff).
--      The same mechanism mis-tagged EVERY run teardown ever: stop flips status before the
--      depot reset, so teardown events found no 'running' run — 4,074 orphaned witness rows
--      measured in one 16-minute window. Fixed by 0092 (no cached misses; GUC pinned at run
--      start and at teardown); check 0045 R12 watches the teardown window permanently.
--
-- ── SECOND PAIR, after 0092–0096 (2026-08-29, arms 05553150 / e1fe726c) ────────────────────
-- Property (a) is now PROVEN: both arms stamped the SAME world fingerprint
-- (3c903a8f2e7dc924ca2a6661f62feb21) — the 0095 whitelist reset + 0093 residue strip close
-- the world completely (rolled-back 8-tick probe: fp_equal=t, zero column diffs).
--
-- Property (b) FAILS, and the first divergence names its mechanisms. Tick 1 is BYTE-IDENTICAL
-- (55 commands, same hash). Divergence begins at tick 2: five 'stage' (ready:true) commands
-- present in arm A, absent in arm B — the task_start staging decision drew differently from
-- an identical world. Two wall-clock/cross-run inputs reach that decision:
--   1. PROPOSAL TTLs LIVE IN THE WALL DOMAIN: greedy proposals get expires_at = now()+120
--      REAL seconds and ottoq_l2_external_proposal filters >= now() — ticks run at variable
--      wall speed, so a proposal straddles the next tick in one arm and is expired in the
--      other (20 proposals in arm A vs 32 in arm B). Same disease class as the 0067
--      reservation-expiry fix; the cure is the same: sim-domain freshness for sim runs.
--   2. ottoq_ops_approvals IS READ WITHOUT RUN SCOPE: the table HAS sim_run_id, but decide's
--      checks filter only vehicle/type/status/created_at — so arm B inherits arm A's
--      approvals (66 approvals written during the pair; 271 accumulated). One run's
--      greenlights leak into the next run's gates.
-- Fix both, then re-run this pair expecting equality tick by tick; the first-divergence
-- bisection above is the debugging loop to repeat if a third mechanism hides behind them.
--
-- ── PAIRS 4 AND 5, after 0097/0098 (2026-08-29) — the horizon moves, the diagnosis lands ──
-- Pair 4 (02ad9218/40cd6a63, after 0097 expired approvals at teardown): ticks 1 AND 2 now
-- byte-identical — mechanism 2 (approvals) confirmed dead. Divergence moved to tick 3:
-- one vehicle (bc55d859) admitted to the overnight drain in one arm only. Root: the
-- admission cursor ORDER BY (deferred count DESC, last_state_change) LIMIT n — same-tick
-- transitions share last_state_change (the sim clock), so the last slot went in heap order.
-- Fixed by 0098 (append id).
-- Pair 5 (908c16bc/de282fc7, after 0098): stall_assignment queue identical through
-- position 28 (the drain fix held); the first divergence is now a forward temp-hold at
-- tick 2 — the same window's hold on stall a06d087f went to fixture vehicle a1111111 in
-- arm A and b2222222 in arm B, and the pairing permutation cascades from there.
--
-- ── THE GENERAL DIAGNOSIS (ending one-at-a-time whack-a-mole) ─────────────────────────────
-- A live sweep of pg_proc for `ORDER BY ... LIMIT` cursors lacking a closing unique key
-- found DOZENS of sites across the tick path, dominated by two families:
--   * `ORDER BY vn.created_at DESC LIMIT 1` — "the latest need" picked by a WALL-clock
--     column whose values tie for rows created in the same transaction (arrival_disposition,
--     book_appointment, decide_wash_triage, plan_opportunistic_charges, readmit_*,
--     record_enacted_booking, reoptimize_reservation_book, reserve_inbound_bays, ...);
--   * score-only ORDER BY with no id tiebreak (the 0054/0067 disease, re-grown since the
--     decide-path rewrite).
-- The remaining work is a 0054-scale sweep: enumerate every site from the live catalog,
-- close each order with the row's unique key, one self-verifying migration, then re-run
-- this pair expecting tick-by-tick equality. The sweep query lives in the session notes;
-- rebuild it as: regexp over pg_proc.prosrc for 'ORDER BY ... LIMIT' minus snippets already
-- carrying id/stall_code/seq columns.
--
-- ── THE INSTRUMENT (re-runnable verbatim) ──────────────────────────────────────────────────
-- One arm (repeat per arm; cert_harness is exempt from the metronome and the governor):
--
--   DO $arm$
--   DECLARE v_run uuid; v_t0 timestamptz := clock_timestamp(); v_clock timestamptz; v_status text;
--   BEGIN
--     PERFORM public.ottoq_tick_invariance_reset_fleet('11111111-1111-1111-1111-111111111111'::uuid, 424242);
--     v_run := twin.ottoq_sim_start_run('busy_day', '2026-09-01 02:00:00+00'::timestamptz, 60, 424242, 'cert_harness');
--     BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, '2026-09-01 02:00:00+00'::timestamptz, 0.70);
--     EXCEPTION WHEN OTHERS THEN RAISE WARNING 'prime failed: %', SQLERRM; END;
--     LOOP
--       SELECT sim_clock_current, status INTO v_clock, v_status FROM public.ottoq_sim_runs WHERE sim_run_id=v_run;
--       EXIT WHEN v_status <> 'running' OR v_clock >= '2026-09-01 08:00:00+00'::timestamptz;
--       EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp()-v_t0)) >= 45;
--       PERFORM public.ottoq_sim_advance_tick(v_run);
--     END LOOP;
--   END $arm$;
--   -- then run the projection below, then: SELECT ottoq_sim_stop_and_reset(<run>, 'determinism_arm_complete');
--
-- Stream projection for one run (replace :run). Volatile identifiers (booking/leg/event UUIDs,
-- wall-clock created_at) are deliberately excluded; vehicle/stall ids are stable fleet rows.
-- ============================================================================================

WITH r AS (SELECT :run::uuid AS id)
SELECT
  (SELECT md5(COALESCE(string_agg(
      issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
      E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status), ''))
     FROM public.ottoq_vehicle_commands c, r WHERE c.sim_run_id=r.id) AS h_cmd,
  (SELECT md5(COALESCE(string_agg(
      sim_clock::text||'|'||tick_seq::text||'|'||action_context||'|'||entity_id::text||'|'||outcome_status
      ||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-'),
      E'\n' ORDER BY sim_clock, tick_seq, action_context, entity_id, outcome_status,
                    COALESCE(enacted_action->>'verb', proposed_action->>'verb','-'), COALESCE(proposed_action->>'stall_id','-')), ''))
     FROM public.ottoq_decisions d, r WHERE d.sim_run_id=r.id) AS h_dec,
  (SELECT md5(COALESCE(string_agg(event_type||'|'||COALESCE(entity_id::text,'-'),
      E'\n' ORDER BY event_type, COALESCE(entity_id::text,'-')), ''))
     FROM public.ottoq_events e, r WHERE e.sim_run_id=r.id) AS h_evt,
  (SELECT md5(COALESCE(string_agg(
      lower(during)::text||'|'||upper(during)::text||'|'||vehicle_id::text||'|'||stall_id::text||'|'||purpose||'|'||state,
      E'\n' ORDER BY lower(during), vehicle_id, stall_id, purpose, state), ''))
     FROM public.ottoq_stall_bookings k, r WHERE k.sim_run_id=r.id) AS h_bkg,
  public.ottoq_tick_invariance_metrics((SELECT id FROM r)) AS metrics;

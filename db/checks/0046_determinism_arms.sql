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
-- Until (a) holds, (b) cannot even be assessed. Remaining fix order: give run start a WORLD
-- FINGERPRINT (hash of vehicle/wear/gate state, stored in the run payload) so same-seed runs
-- prove they started equal; make the seeded reset (or a scenario-boot-equivalent) cover the
-- full vehicle world. Then re-run this triplet — one transaction per arm step — expecting
-- A=B=C on commands/decisions/bookings, and event parity now that tagging is honest.
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

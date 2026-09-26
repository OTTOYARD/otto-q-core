-- 0366  **0491-0492: an ops action outside the whitelist is refused and says so, and the orphan sweep ends a twin
--       session on its run's clock.** Two small open findings from the list (G222, G220), each proven on a
--       rolled-back probe before apply. Times are UTC in the data and CT (CDT, UTC-5) in the prose.

-- ══ §1 G222 (0491) ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_apply_ops_action`'s ELSE branch inserted an `ottoq_ops_approvals` row of type
--   `nemotron_ops_action`, which the table's own check constraint rejects, and returned `queued_for_approval`.
--   0491 = 20260926170743 (12:07 PM CT), stored statement md5 cd9b976c..., equal to the file's body.
--   forces_recert FALSE: only the agent calls it, and `ottoq_sim_decide_and_dispatch` fires the agent only when
--   `run_by` is neither `cert_harness` nor `benchmark` (0105), read from its source before apply.

\echo '=== 0366 §1 — the approval types the table allows, and that no queued ops action ever existed ==='
SELECT pg_get_constraintdef(c.oid) AS approval_type_check,
       (SELECT count(*) FROM public.ottoq_ops_approvals WHERE approval_type = 'nemotron_ops_action') AS nemotron_rows
  FROM pg_constraint c
 WHERE c.conname = 'ottoq_ops_approvals_approval_type_check';
-- READ (2026-09-26): the check allows opportunistic_charge, tech_greenlight and indepot_reassign; 0 nemotron rows.
--   0491's V2 calls the function with an action outside the whitelist: `status = 'refused'`, the whitelist named,
--   nothing written. The agent (ottoq-orchestrator-agent) files any status other than applied or queued_for_approval
--   under `rejected` with the reply attached, so its record now carries the reason, not a constraint violation.

-- ══ §2 G220 (0492) ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_reconcile_charger_states` cancelled an orphaned twin session with `ended_at = COALESCE(ended_at,
--   now())`, the wall clock, on a row whose other times are the sim clock. 0492 = 20260926170804 (12:08 PM CT),
--   stored statement md5 48bb36e3..., equal to the file's body. forces_recert TRUE: the sweep runs in the
--   certified world tick.

\echo '=== 0366 §2 — twin sessions the sweep ended, and how many ended off their run''s clock ==='
SELECT count(*) AS swept,
       count(*) FILTER (WHERE o.ended_at > r.sim_clock_current + interval '1 minute'
                           OR o.ended_at < o.started_at) AS ended_off_the_run_clock
  FROM public.ocpp_sessions o
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = o.sim_run_id
 WHERE o.stopped_reason = 'vehicle_departed_orphan_sweep'
   AND r.depot_id = '11111111-1111-1111-1111-111111111111';
-- READ: pending the next operator run. Every session swept after 12:08 PM CT should read `ended_off_the_run_clock`
--   0 (the rows swept before it keep the wall-clock end they were written with).
--
--   The probe as run (0492's body without P0, then a tail in the same transaction ending in RAISE), on the stopped
--   run 461c79fa: a synthetic active twin session (token `TWIN-probe0492`, 3 meter values, started 20 sim-minutes
--   before the run's last clock) on the first L2 stall with no active session, for a car that does not point at it.
--   One call to the reconciler:
--     run clock 2026-09-26 15:54:57.770336+00, session ended_at 2026-09-26 15:54:57.770336+00, status cancelled,
--     reason vehicle_departed_orphan_sweep; on the run clock = true (now() was 17:07:17)
--   The tail, verbatim:
--   DO $probe$
--   DECLARE
--     v_run uuid := '461c79fa-6f85-467f-b90a-92b33d40728d';
--     v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_clock timestamptz; v_stall uuid; v_car uuid; v_sess uuid; v_end timestamptz; v_status text; v_reason text;
--   BEGIN
--     SELECT sim_clock_current INTO v_clock FROM ottoq_sim_runs WHERE sim_run_id = v_run;
--     SELECT s.id INTO v_stall FROM stalls s
--      WHERE s.depot_id = v_depot AND s.stall_type = 'l2'
--        AND NOT EXISTS (SELECT 1 FROM ocpp_sessions o WHERE o.stall_id = s.id AND o.status = 'active')
--      ORDER BY s.id LIMIT 1;
--     SELECT v.id INTO v_car FROM vehicles v
--      WHERE v.home_depot_id = v_depot AND v.current_stall_id IS DISTINCT FROM v_stall ORDER BY v.id LIMIT 1;
--     INSERT INTO ocpp_sessions (depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id, connector_id,
--                                status, started_at, meter_values_count, id_token, sim_run_id)
--     VALUES (v_depot, v_stall, v_car, 'PROBE-CP', 'probe0492', 1, 1, 'active', v_clock - interval '20 minutes', 3,
--             'TWIN-probe0492', v_run)
--     RETURNING id INTO v_sess;
--     PERFORM public.ottoq_reconcile_charger_states(v_depot);
--     SELECT ended_at, status::text, stopped_reason INTO v_end, v_status, v_reason FROM ocpp_sessions WHERE id = v_sess;
--     RAISE EXCEPTION 'PROBE run clock=% | swept session: ended_at=% status=% reason=% | on the run clock=% | now()=%',
--       v_clock, v_end, v_status, v_reason, (v_end = v_clock), now();
--   END $probe$;

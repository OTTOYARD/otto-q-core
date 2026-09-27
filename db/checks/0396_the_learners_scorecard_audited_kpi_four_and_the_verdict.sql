-- 0396  **The learner's scorecard, audited KPI by KPI after G252. KPI 4 never counted a technician and divided by
--       bookings (G253); the dial verdict skipped any guardrail whose control read 0, so KPI 4 guarded nothing on any
--       G240 pair (G254). KPI 1, 3 and 5 read what they say; KPI 5 has a known blind spot and a small-sample swing.**
--
--       Written on 2026-09-27 (14:40-15:30 UTC, 9:40-10:30 AM CT) after 0527, from the day's full-day operator runs, the
--       dial pairs 76-81 and the whole event table. Read-only except where a section says it ran inside a rolled-back
--       transaction.

-- ══ §1 KPI 4'S NUMERATOR NEVER SAW A TECHNICIAN ════════════════════════════════════════════════════════════════════
--
--   "Human interventions per asset-turn" (CLAUDE.md 2.9) counted the run's events whose actor ottoq_kpi_touch_actor_types
--   calls a person (0213) plus decisions a person overrode (0391). The twin writes a technician's work on the visit's
--   atoms, never as an event, so the only person that has ever appeared in the event stream is the command centre.

\echo '=== 0396 §1(a) — every human-actor event held, by actor type ==='
SELECT e.actor_type, count(*) AS events, count(DISTINCT e.sim_run_id) AS runs,
       (SELECT string_agg(DISTINCT t, ', ') FROM (SELECT e2.event_type AS t FROM public.ottoq_events e2
          WHERE e2.actor_type = e.actor_type LIMIT 500) s) AS types
  FROM public.ottoq_events e
 WHERE e.actor_type IN (SELECT actor_type FROM public.ottoq_kpi_touch_actor_types WHERE human_actor)
 GROUP BY e.actor_type ORDER BY events DESC;
-- READ (2026-09-27 14:58 UTC): one row. command_center_operator, 26,126 events on 588 runs: deferred-service starts and
--   completions and technician approvals. depot_tech -- "the obvious name for a physical touch" in 0213's own note -- has
--   never been written.

\echo '=== 0396 §1(b) — work a person did on 6ddd827e, by lane, against what KPI 4 counted ==='
SELECT c.lane, a->>'svc' AS svc, COALESCE(a->>'performed_by', '(a technician)') AS performed_by, count(*) AS worked
  FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
  JOIN public.service_cadence_policy c ON c.svc = a->>'svc'
 WHERE vn.sim_run_id = '6ddd827e-b549-43cf-8154-4d1bfb20cabf'
   AND COALESCE(a->>'status', 'pending') <> 'cancelled' AND (a->>'started_at' IS NOT NULL OR a->>'done_at' IS NOT NULL)
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ (2026-09-27 15:02 UTC): in the lanes the engine's labour model gives a person (ottoq_start_concurrent_atoms: the
--   general technician pool for cabin and exterior work unless the charger's sensors do it; service technicians and
--   detail staff in the bays), 130 tasks -- cabin 90, exterior 18, detail 17, service bay 5. The charger's sensors did
--   208 inspections and triage checks; the automatic wash 14; the gate 124 readiness checks; the charging robot every
--   charge. KPI 4 read 0 touches over 498 bookings: 0.000.
--   Bay work records no start: on 6ddd827e every finished bay atom carries `done_at` and no `started_at` (deep clean 17,
--   exterior wash 14, mechanical PM 2, sensor calibration 2, fault repair 1), so a count of started atoms alone would
--   have missed every deep clean and repair.

-- ══ §2 ITS DENOMINATOR WAS G252'S, AND THE VERDICT DROPPED IT AT ZERO ══════════════════════════════════════════════
--
--   0184 divided by bookings in state `done` -- the count 0527 retired from KPI 2 because it moves with booking length.
--   And `ottoq_dial_experiment_verdict` judges a guardrail by `dir * (b - a) / NULLIF(abs(a), 0)`: a control reading 0
--   makes the change NULL, `avg` skips it, and nothing the treatment does can breach it (G254).

\echo '=== 0396 §2 — KPI 4 in the dial pairs as recorded (G240: 76, 78, 80; energy: 81) ==='
SELECT pair_id, left(experiment_id::text, 8) AS exp, metrics_a->>'touch_events_per_turn' AS control,
       metrics_b->>'touch_events_per_turn' AS treatment
  FROM public.ottoq_dial_pair_ledger WHERE pair_id IN (76, 78, 80, 81) ORDER BY pair_id;
-- READ (2026-09-27 14:40 UTC): G240's three pairs 0.000 / 0.000 -- the guardrail judged on no pair; the energy
--   experiment's 0.187 / 0.187 and its siblings, identical in both arms (its dial moves the battery, not bookings or
--   people), so no verdict has yet been moved by KPI 4 either way.

-- ══ §3 THE OTHER THREE, AUDITED ═════════════════════════════════════════════════════════════════════════════════
--
--   KPI 1 (asset hours) reads the dispatch records; KPI 3 (peak kW) the energy snapshots -- both what they say. KPI 5
--   reads the first itinerary leg actually started after a return, and three things were checked:
--   (a) CROSS-VISIT LEAKAGE: none. Its first-op search has no upper bound, but on 4bc19d29, 6ddd827e and c4afb873 no
--       return's first op falls after the car's next dispatch (0 of 485).
--   (b) BOOKKEEPING: none found, and the first attempt at the question was wrong in the other direction. On pair 76 the
--       leg p95 fell 54.0 -> 39.6 while a proxy from charge-session and atom starts rose 57.6 -> 67.8. Only 5 of 116
--       returns differ between the arms (the dispatch record is identical), and on all 5 the leg wait equals the charge
--       wait exactly: the treatment physically reordered who got a charger (two cars 18 minutes later, three 6-18
--       earlier). The 29 returns per arm where legs and the proxy disagree are the same 29 in both arms: inspection-lane
--       work on staging, flow-contract legs done in 4-5 minutes, which the proxy did not see. The proxy was wrong; the
--       KPI is left as is. What stays true is statistical: a p95 over ~115 returns moves on a handful of them.
--   (c) THE KNOWN BLIND SPOT (0501, G233): KPI 5 is time to the first op of any kind. On 4bc19d29 -- a software-release
--       day, every one of its 198 visits carrying an update -- 150 of 182 returns' first op was the over-the-air update
--       at the gate: KPI 5 read 0.7 minutes while 35 returns waited over two hours for a charger (p95 273.8). On
--       6ddd827e, no release: KPI 5 read 261.6, 34 returns over two hours, all 34 waiting for a charger (17 L2, mean 225
--       minutes; 17 DCFC, mean 248). The definition stays the brief's; 0529 makes `ottoq_kpi_charge_wait` travel with
--       every dial arm so the charger queue is in every pair's record.

\echo '=== 0396 §3(c) — first op after a return, by leg type, on the release day and the day after ==='
WITH runs AS (SELECT sim_run_id, left(sim_run_id::text, 8) AS run, sim_clock_current FROM public.ottoq_sim_runs
               WHERE left(sim_run_id::text, 8) IN ('4bc19d29', '6ddd827e')),
ret AS (SELECT x.run, d.sim_run_id, d.vehicle_id, d.actual_return_at FROM runs x
          JOIN public.ottoq_vehicle_dispatches d ON d.sim_run_id = x.sim_run_id
         WHERE d.actual_return_at IS NOT NULL AND d.actual_return_at <= x.sim_clock_current)
SELECT t.run, fl.leg_type, count(*) AS returns,
       count(*) FILTER (WHERE (SELECT min(s.started_at) FROM public.ocpp_sessions s WHERE s.sim_run_id = t.sim_run_id
                                 AND s.vehicle_id = t.vehicle_id AND s.started_at >= t.actual_return_at)
                              > t.actual_return_at + interval '2 hours') AS then_waited_over_2h_for_a_charge
  FROM ret t
  JOIN LATERAL (SELECT l.leg_type FROM public.ottoq_itinerary_legs l
                 WHERE l.sim_run_id = t.sim_run_id AND l.vehicle_id = t.vehicle_id AND l.leg_type <> ALL (ARRAY['taxi','stage'])
                   AND l.actual_start_sim >= t.actual_return_at ORDER BY l.actual_start_sim LIMIT 1) fl ON true
 GROUP BY 1, 2 ORDER BY 1, returns DESC;
-- READ (2026-09-27 15:31 UTC): 4bc19d29 software_update 150 (34 of them then waited over two hours for a charge),
--   inspect 11 (0), remote_diagnostics 8 (3), sensor_clean 5 (1), charge_l2 3 (0), wash 2 (1), service 1 (0),
--   item_retrieval 1 (1). 6ddd827e charge_l2 89 (17), charge_dcfc 73 (17), inspect 14 (2), remote_diagnostics 13 (2),
--   sensor_clean 8 (2), detail 1 (1), depart 1 (0), wash 1 (0): no software_update atom on any of its 226 visits (nor on
--   caf85837's 150 or c4afb873's 114). This count takes the first charge after a return with no bound at the next
--   dispatch; bounded, 38 of 6ddd827e's returns waited over two hours (the read that found it, 14:28 UTC).

-- ══ §4 THE FIX FOR G253: 0528 ═════════════════════════════════════════════════════════════════════════════════════
--
--   The numerator adds each atom of a service whose declared lane (`service_cadence_policy.lane`) a person works --
--   classified in the new `ottoq_kpi_touch_lanes`, data and not a list in the view -- started or finished and not
--   cancelled, unless it names a performer `ottoq_kpi_touch_actor_types` calls not a person (`charger_sensors`, added).
--   The denominator is the cars that came in: `vehicle.state_changed` to `arrived_at_gate`. On the harness arms that
--   count equals both the returns and the visits (116, 115, 215); on operator runs it is the fuller one (219 arrivals
--   against 208 returns on 6ddd827e: cars that start on the road have no dispatch row in the run).
--   Applied 20260927150822. Its V1 compared eleven reference runs; the comparison over every finished run was run
--   after the apply, below, from the definition 0528 snapshotted, one run per statement and 16 runs per transaction:
--   each run's read scans all its events two or three times, and 62 runs did not fit in one.

\echo '=== 0396 §4 — the booking audit and the untouched terms reproduce the pre-0528 view, run by run (rolled back) ==='
DO $cmp$
DECLARE v_def text; v_run uuid; o record; n record; v_n int := 0; v_bad text := '';
BEGIN
  SELECT definition INTO v_def FROM public.ottoq_schema_snapshots WHERE label = '0528_pre' AND object_kind = 'view';
  EXECUTE 'CREATE TEMP VIEW t_old_kpi4 AS ' || v_def;
  FOR v_run IN SELECT sim_run_id FROM public.ottoq_sim_runs
                WHERE run_by IN ('operator_demo', 'production_live', 'ab_harness') AND status NOT IN ('running', 'paused')
                ORDER BY sim_run_id LIMIT 16 OFFSET 0 LOOP          -- then OFFSET 16, 32, 48
    EXECUTE format('SELECT * FROM t_old_kpi4 WHERE sim_run_id = %L', v_run) INTO o;
    EXECUTE format('SELECT * FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = %L', v_run) INTO n;
    IF o.sim_run_id IS NULL AND n.sim_run_id IS NULL THEN CONTINUE; END IF;
    IF o.sim_run_id IS NULL OR n.bookings_done IS DISTINCT FROM o.turns OR n.bookings_not_a_turn IS DISTINCT FROM o.bookings_not_a_turn
       OR n.touch_events_operator IS DISTINCT FROM o.touch_events_operator OR n.touch_events_override IS DISTINCT FROM o.touch_events_override
       OR n.touch_events_override_flag_only IS DISTINCT FROM o.touch_events_override_flag_only
       OR (CASE WHEN n.bookings_done > 0 THEN round((n.touch_events_operator + n.touch_events_override)::numeric / n.bookings_done, 3) END)
          IS DISTINCT FROM o.touch_events_per_turn THEN
      v_bad := v_bad || left(v_run::text, 8) || ' ';
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RAISE EXCEPTION 'compared %, mismatched [%]', v_n, v_bad;   -- also drops the temp view
END $cmp$;
-- READ (2026-09-27 15:20 UTC, the four chunks): compared 15, 14, 15 and 12 -- 56 runs, 6 with no row in either view --
--   mismatched none. On them bookings_done is the old denominator, the operator, override and shield-default terms are
--   unchanged, and (operator + override) / bookings_done is the old headline exactly.
--   New readings: 6ddd827e 130 technician tasks on 219 cars in, 0.594 (was 0.000); 4bc19d29 92 on 198, 0.465; G240's
--   pair 76 1.060 in both arms, pair 78 0.598 against 0.590 (one fewer deep clean in the treatment), pair 80 0.765 in
--   both; the energy pair 81 1.712 in both (77 command-centre approvals and 291 tasks, 131 of them exterior -- its
--   night hours raise perimeter walkarounds). The one command reads 6ddd827e in 436 ms.

-- ══ §5 THE FIX FOR G254: 0529 ═════════════════════════════════════════════════════════════════════════════════════
--
--   A guardrail's change is 0 when the arms are equal, `dir * sign(b)` -- a full change in its direction -- when the
--   control is 0 and the treatment is not, and the relative change otherwise. Every weight key appears in the verdict's
--   guardrails with the pairs it was measured on, `pairs_from_zero` and `measured`; `guardrails.unmeasured` names the
--   keys measured on none. The primary's arithmetic is untouched. The arm metrics add the charge wait (0501).
--   Applied 20260927151819, forces_dial_restart FALSE (the verdict reads stored pairs; the metrics only gain keys), so
--   the dial floor stays at 0528's apply, 15:08:22 UTC. Its V3, planted and rolled back: six pairs in which the
--   treatment wins its primary 6 of 6 and takes touches per turn from 0 to 0.5. The pre-0529 arithmetic judges touches
--   on 0 of the 6 pairs, so the verdict would have been `treatment_wins` -- a promotion; now `guardrail_breach` on
--   touch_events_per_turn, from zero on all 6, with p95_time_to_service_min named unmeasured.

-- ══ §6 A PLANNING HAZARD IN EVERY KPI VIEW ══════════════════════════════════════════════════════════════════════════
--
--   Each KPI view aggregates per run. Read with the run as a constant or a parameter, the planner pushes the run into
--   every branch and stays on the per-run indexes (KPI 4: 55-219 ms a run). Read through a join -- a run list, or a
--   LATERAL over the dial ledger -- it aggregates the view over every run held first:

\echo '=== 0396 §6 — a lateral read of a per-run KPI view plans a scan of the whole event table ==='
EXPLAIN (COSTS OFF)
SELECT p.pair_id, arm.a, k.turns
  FROM public.ottoq_dial_pair_ledger p
  CROSS JOIN LATERAL (VALUES ('A', p.run_a), ('B', p.run_b)) AS arm(a, run)
  CROSS JOIN LATERAL (SELECT * FROM public.ottoq_kpi_touch_events_per_turn v WHERE v.sim_run_id = arm.run) k
 WHERE p.pair_id IN (76, 81);
-- READ (2026-09-27 15:31 UTC, the applied 0528 view): a hash join over a Finalize GroupAggregate fed by a Parallel Seq
--   Scan on ottoq_events -- all 1.8M rows -- and another on ottoq_visit_needs. It cost two dry-run timeouts of 0528 and
--   one cancelled read today. Every reader in the engine passes the run as a parameter (ottoq_kpi_five_raw, the dial arm
--   metrics, the run-dial capture); a bulk reader must loop one run per statement, as 0528's V1 and §4 above do.

-- 0394  **G251: a visit with nothing to charge could not have its cabin work started while its car waited for a bay.
--       The car sat on a staging stall until the deploy gate's 240-minute escape hatch released it with the work
--       undone. On validation run 6ddd827e three cars' interior inspections waited that way.**
--
--       Written on 2026-09-27 (12:40-13:30 UTC, 7:40-8:30 AM CT), from validation run 6ddd827e while it ran and after.
--       Read-only.

-- ══ §1 THE THREE, AND HOW THE GATE LET THEM GO ═══════════════════════════════════════════════════════════════════

\echo '=== 0394 §1 — deploy-gate overrides on the day''s two full-day runs, and what each left undone ==='
SELECT left(e.sim_run_id::text, 8) AS run, v.display_name AS car,
       to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS released_ct,
       (e.payload->>'held_min')::numeric AS held_min, e.payload->>'reason' AS reason, e.payload->'missing' AS missing,
       left(e.payload->>'note', 60) AS note
  FROM public.ottoq_events e JOIN public.vehicles v ON v.id = e.entity_id
 WHERE e.sim_run_id IN ('6ddd827e-b549-43cf-8154-4d1bfb20cabf', '4bc19d29-790c-4cb0-9e2e-ae090a7da57b')
   AND e.event_type = 'twin.deploy_gate_override'
 ORDER BY e.sim_run_id, e.sim_clock_at;
-- READ (2026-09-27 12:47 UTC, 6ddd827e at sim 2:13 PM CT): 6ddd827e 3 overrides, 4bc19d29 (the full day before 0521)
--   6. Every one is "escape hatch 3: released past the readiness gate so the twin cannot wedge; this is a DEFECT to
--   investigate, not a normal path", reason `must_do_work_open`, held 240.1-240.2 minutes. 4bc19d29's left bay and
--   cabin cleaning undone (interior_deep_clean 4, interior_tidy 1, exterior_wash 1). 6ddd827e's all left the interior
--   inspection undone -- Waymo-AV-016 (with its exterior wash), Waymo-AV-020 (with its wash) and Tesla-AV-041.
-- FINAL READ (2026-09-27 13:25 UTC, the run ended by the governor at 540 sim-minutes): 4 overrides, the three above
--   (released at sim 12:11, 12:26 and 1:01 PM CT) and Tesla-RT-002 at 4:14 PM, held 240.6 minutes for an interior deep
--   clean -- bay work waiting for a detail bay, the kind all six of 4bc19d29's were, and not this finding.

\echo '=== 0394 §1(b) — Waymo-AV-016 on 6ddd827e: its state and stall changes from the gate to the release ==='
SELECT to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago', 'HH24:MI:SS') AS sim_ct, e.event_type,
       e.payload->'diff'->'current_state'->>'to' AS to_state,
       (SELECT stall_code FROM public.stalls WHERE id = (e.payload->'diff'->'current_stall_id'->>'to')::uuid) AS to_stall
  FROM public.ottoq_events e JOIN public.vehicles v ON v.id = e.entity_id
 WHERE e.sim_run_id = '6ddd827e-b549-43cf-8154-4d1bfb20cabf' AND v.display_name = 'Waymo-AV-016'
   AND (e.event_type = 'twin.deploy_gate_override'
        OR (e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ?| ARRAY['current_state', 'current_stall_id']))
   AND e.sim_clock_at BETWEEN '2026-09-27 13:09:00+00' AND '2026-09-27 17:13:00+00'
 ORDER BY e.sim_clock_at, e.event_seq;
-- READ (2026-09-27 12:44 UTC): arrived 8:09:46 AM CT sim; at 8:11:23 the gate intake took it through
--   `arrived_at_gate` -> `charge_complete_holding` -> `staged_awaiting_service` in one statement (its visit has no
--   charge: an inspection, a readiness check and an exterior wash); parked on NASH-STG-I011 at 8:11:44, moved to
--   NASH-STG-B009 at 8:15:56; and there it stayed until 12:11:51, when `twin.deploy_gate_override` fired at 240.1
--   minutes with `missing` = exterior_wash and interior_inspection and moved it to `staged_for_departure`. The inspection
--   started at 12:12:25 -- in the exit catch-up, 35 seconds after the release -- and the wash was still pending when
--   read at about 1 PM sim.

-- ══ §2 WHY: THE CANDIDATE FILTER PRESUMES EVERY VISIT CHARGES ═══════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_advance_visit_atoms` chooses the cars whose atoms `ottoq_start_concurrent_atoms` may start. Cabin
--   work is admitted only for `charging_dcfc`, `charging_l2`, `charge_complete_holding` and `staged_for_departure`
--   (M3_cabin_at_charger: cabin work is a technician's at the charger, during the session; the last two are catch-ups
--   so nothing waits forever). The starter itself has no state test and holds cabin work only for a charging visit,
--   so it would give this inspection to a technician -- it is never asked. A no-charge visit's car spends no time
--   charging; it passes through `charge_complete_holding` in the same statement as the intake, and waits for its bay in
--   `staged_awaiting_service`, which admits exterior and digital work but not cabin work; and the readiness gate will
--   not move it to `staged_for_departure` with must-do work open. Only the escape hatch breaks the circle.
--   Why it shows now: until 0521 the charger's sensors credited such inspections at the intake moment, on cars that
--   were on no charger (G246's false credits) -- which is also why 4bc19d29's six releases name no inspection. The
--   trap was already there for other cabin work: on 4bc19d29 the one no-charge interior tidy started after 262 minutes.

\echo '=== 0394 §2 — cabin atoms by run and whether the visit charges: started, started after 2 hours, never started ==='
WITH runs AS (SELECT sim_run_id, left(sim_run_id::text, 8) AS run FROM public.ottoq_sim_runs
               WHERE left(sim_run_id::text, 8) IN ('4bc19d29', '6ddd827e')),
cab AS (
  SELECT r.run, x->>'svc' AS svc, (x->>'started_at')::timestamptz AS started_at, vn.arrived_at,
         NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) c WHERE c->>'svc' = 'charge') AS no_charge
    FROM runs r JOIN public.ottoq_visit_needs vn ON vn.sim_run_id = r.sim_run_id, jsonb_array_elements(vn.atoms) x
   WHERE x->>'concurrency' = 'cabin')
SELECT run, no_charge, svc, count(*) AS atoms, count(started_at) AS started,
       count(*) FILTER (WHERE extract(epoch FROM started_at - arrived_at) / 60 > 120) AS started_after_2h,
       count(*) FILTER (WHERE started_at IS NULL) AS never_started
  FROM cab GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ (2026-09-27 12:45 UTC, 6ddd827e at sim about 2 PM CT): on 6ddd827e, 11 interior inspections on no-charge visits,
--   all started, 3 of them after two hours (the three above); on 4bc19d29 3, none after two hours, and one no-charge
--   interior tidy after 262 minutes. The charging visits' cabin work waits for its charger by design and is not this.
-- FINAL READ (2026-09-27 13:25 UTC, 6ddd827e complete): 12 no-charge interior inspections, all started, 3 after two
--   hours -- the three the escape hatch released. The other no-charge cabin work on the run (1 interior tidy, 2 item
--   retrievals, 1 triage check) started within two hours: those visits' cars were not left waiting for a bay.

-- ══ §3 THE FIX: 0526 ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   The candidate filter also admits cabin work for a car in `staged_awaiting_service`, on a stall, whose visit has no
--   charge left to do -- the starter's own definition of a charging visit, negated. The starter then gives it to a
--   technician from the general pool. A charging visit still does its cabin work at the charger; the catch-ups stay.
--   forces_recert TRUE (the filter runs in every certified arm, and the technician pool moves), and it moves dial arms,
--   so it restarts the dial experiments: it waits for the end of the next dial window, so the G240 experiment's first
--   look is not thrown away for it.
--   Dry run (2026-09-27 13:22 UTC, 8:22 AM CT, no run live): P2, the patch, V1 and V3 all passed. V3's (a) run against
--   the UNPATCHED filter -- the same planted car, stall and visit, on 6ddd827e marked running inside the test -- leaves the
--   inspection `pending`, so the test tells the two filters apart; with the patch it goes `in_progress` with no
--   `performed_by`, a technician's.

-- ══ §4 THE FIRST FULL DAY AFTER 0526, PREDICTED BEFORE IT RUNS ══════════════════════════════════════════════════════
--
--   PREDICTED on the first live, seeded busy_day operator run after 0526: (a) no deploy-gate override names an interior
--   inspection, and every no-charge interior inspection starts within 30 minutes of its car's arrival (§2 with 30 for 120); (b) the charging
--   visits' cabin work is unchanged -- the sensors still do it at the charger, and no sensor start is off a charger
--   (0390 §4(a)(b) re-run); (c) overrides for bay work waiting for a bay are not this fix's, and are read, not predicted.
--   Read with §1 and §2 above, the run id put in place of 6ddd827e.
-- READ (2026-09-27 15:48 UTC, 10:48 AM CT; the run is 6e0352a0, the first live, seeded busy_day operator run after 0526,
--   stopped by the governor at 540 sim-minutes, sim 5:11 PM CT):
--   (a) HOLDS. Four deploy-gate overrides, none naming an interior inspection: Waymo-AV-024 at 3:11 PM (exterior wash),
--   Waymo-AV-037 at 3:19 (its charge, held 248.1 minutes -- a car the charger queue never reached, 0397 §5),
--   Zoox-AV-091 at 4:19 and Waymo-AV-021 at 5:00 (interior deep clean, each waiting for a detail bay). Every no-charge
--   interior inspection started within 30 minutes: 6 of 6, the longest 15.6 minutes (6ddd827e: 3 of 12 after two hours,
--   the three the escape hatch released); the one no-charge interior tidy in 2.4.
--   (b) HOLDS. 210 sensor starts, every one stamped with a DCFC or L2 stall the car had a charge session on: DCFC 87
--   done, 2 in progress, 1 returned to pending by 0519; L2 120 done. None on staging, in a bay or on no stall. The
--   charging visits' interior inspections were done by the sensors, 176 of 180 started.
--   (c) READ: the two deep-clean overrides are bay work waiting for a bay, the class 4bc19d29's six were.
--   G251 is validated on live traffic.

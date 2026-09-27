-- 0371  **G233: the wait for a charger, measured beside KPI 5 (0501).**
--
--       0368 §9 and §11 found KPI 5 (`p95_time_to_service`, recall complete to the first operation active) reading 0.7
--       minutes on validation run `394e1e83` while about 40 cars waited for a charger from 10:00 AM on. The first
--       operation is usually a digital or cabin task that starts at once, so the KPI is right by its definition and cannot
--       see the charger queue. 0501 adds `public.ottoq_kpi_charge_wait(run)` beside the five. Takes the run as a psql
--       variable:
--
--           \set run '<sim_run_id>'

-- ══ §1 HOW A VISIT'S WAIT IS COUNTED, SHOWN ON THE RUN ═════════════════════════════════════════════════════════════
--
--   A visit counts when it arrived (`arrived_at` at or before the run's clock) owing a charge (a `charge` atom). Its wait
--   runs from its arrival to its first charging session before the car's next dispatch. With no session: WAITING if
--   the atom is still open (no `status`, or not done/skipped/cancelled), otherwise closed without a session.

\echo '=== 0371 §1 — visits owing a charge, by outcome and by how the charge atom closed ==='
WITH h AS (SELECT r.sim_run_id AS run, r.sim_clock_current AS horizon FROM public.ottoq_sim_runs r WHERE r.sim_run_id = :'run'),
v AS (
  SELECT vn.visit_id, vn.vehicle_id, vn.arrived_at,
         (SELECT a FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge' LIMIT 1) AS ca
    FROM public.ottoq_visit_needs vn, h
   WHERE vn.sim_run_id = h.run AND vn.arrived_at IS NOT NULL AND vn.arrived_at <= h.horizon
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge')),
w AS (
  SELECT v.*, h.horizon,
         (SELECT min(o.started_at) FROM public.ocpp_sessions o
           WHERE o.sim_run_id = h.run AND o.vehicle_id = v.vehicle_id AND o.started_at >= v.arrived_at
             AND o.started_at < COALESCE((SELECT min(d.dispatched_at) FROM public.ottoq_vehicle_dispatches d
                                           WHERE d.sim_run_id = h.run AND d.vehicle_id = v.vehicle_id
                                             AND d.dispatched_at > v.arrived_at), 'infinity')) AS first_plug
    FROM v, h)
SELECT first_plug IS NOT NULL AS charged, COALESCE(ca->>'status', '(open)') AS atom_status,
       COALESCE(ca->>'closed_by', '-') AS closed_by, count(*) AS visits
  FROM w GROUP BY 1, 2, 3 ORDER BY 4 DESC;
-- READ on 394e1e83 (after the stop):
--     charged      (open)  -                   38   charging when the run stopped, or finished short of closing
--     charged      done    ottoq_satisfied     28
--     charged      done    -                   20
--     charged      done    session_completed    6
--     not charged  (open)  -                   42   still waiting when the run stopped
--     not charged  done    -                    1   closed without a session
--   The 42 are the cars 0368 §11 found parked to wait for a charger: `ottoq_close_run_needs` superseded their visits
--   at the stop (close_reason run_completed) and left the charge atoms open. A first cut filtered
--   `ca->>'status' NOT IN (...)`, which is NULL for an open atom, and lost all 42: the waiting cars are exactly the ones
--   a status filter that forgets NULL cannot see.

\echo '=== 0371 §2 — the companion, and KPI 5 beside it ==='
SELECT public.ottoq_kpi_charge_wait(:'run') AS charge_wait,
       public.ottoq_kpi_five(:'run')->>'p95_time_to_service_min' AS kpi5_p95_min;
-- READ on 394e1e83 (22:14 UTC, 5:14 PM CT, after the apply; the run stopped at sim 16:52:11 UTC): 135 visits owing a
--   charge, 92 charged (p50 16.2, p95 154.4, max 190.9 minutes), 42 waiting at the stop (p50 142.3, max 232.2 so far),
--   1 closed without a session, p95 floor over all 198.2 minutes. KPI 5's p95 for the same run: 0.7 minutes. The same
--   as the query behind 0501 read before it, field for field.
--   0501 = 20260926221345 (5:13 PM CT), stored statement md5 433506b143ca096ed35fc100dab10172, equal to the file's body;
--   forces_recert FALSE. EXECUTE for postgres, authenticated and service_role only (the schema's default privileges
--   would have granted anon; the first dry run's V1 caught it).
--   The door: otto-twin-control 1.9.2-charge-wait (v29, deployed source byte-identical to the repo file) returns it as
--   `charge_wait` beside the five on `/sim_runs/:id/kpis`; read live on 394e1e83 at 22:15 UTC it carried the same
--   figures and KPI 5's 0.7.

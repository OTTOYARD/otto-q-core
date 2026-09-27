-- 0375  **G238: a charge's itinerary leg and its service record close when the booking window ends, while the charge
--       goes on. G239: no service record has ever carried the energy a charge delivered.**
--
--       Found reading validation run `5344fc12` after its stop (busy_day, twin depot, 7:29-7:53 PM CT, 356 ticks, sim
--       clock 16:15:32 UTC), and checked against `b0fdc92b`. Read 2026-09-27 00:40-01:20 UTC, before the next run
--       purges them. Takes the run as a psql variable:
--
--           \set run '<sim_run_id>'

-- ══ §1 DONE CHARGE LEGS AGAINST THE SESSIONS THAT CHARGED ═══════════════════════════════════════════════════════
--
--   A charge leg is matched to the car's OCPP session on the run that overlaps it, nearest by start. The booking is the
--   leg's settled one, as `ottoq_trg_leg_done_sdr` picks it (not superseded first, then by window).

\echo '=== 0375 §1 — done charge legs closed 5+ minutes before their session ended, and why ==='
WITH legs AS (
  SELECT l.leg_id, l.vehicle_id, l.leg_type, l.to_stall_id, l.actual_start_sim, l.actual_end_sim
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run' AND l.leg_type IN ('charge_l2','charge_dcfc') AND l.status = 'done'),
j AS (
  SELECT l.*, s.stall_id AS s_stall, s.ended_at AS s_end,
         (SELECT count(*) FROM public.ottoq_service_detail_records sd WHERE sd.leg_id = l.leg_id) AS sdrs,
         (SELECT b.release_reason FROM public.ottoq_stall_bookings b WHERE b.leg_id = l.leg_id
           ORDER BY (b.state IN ('superseded','released','cancelled')), lower(b.during) LIMIT 1) AS booking_release
    FROM legs l
    LEFT JOIN LATERAL (SELECT os.stall_id, os.ended_at FROM public.ocpp_sessions os
                        WHERE os.sim_run_id = :'run' AND os.vehicle_id = l.vehicle_id
                          AND os.started_at <= l.actual_end_sim AND COALESCE(os.ended_at, 'infinity') >= l.actual_start_sim
                        ORDER BY abs(EXTRACT(epoch FROM os.started_at - l.actual_start_sim)) LIMIT 1) s ON true)
SELECT leg_type, count(*) AS done_legs,
       count(*) FILTER (WHERE s_end > actual_end_sim + interval '5 minutes') AS closed_early,
       count(*) FILTER (WHERE s_end > actual_end_sim + interval '5 minutes'
                          AND booking_release = 'window_elapsed_occupied') AS of_which_window_elapsed,
       count(*) FILTER (WHERE s_end > actual_end_sim + interval '5 minutes' AND s_stall = to_stall_id) AS same_stall,
       count(*) FILTER (WHERE s_end > actual_end_sim + interval '5 minutes' AND sdrs = 1) AS with_its_record,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM s_end - actual_end_sim) / 60)
              FILTER (WHERE s_end > actual_end_sim + interval '5 minutes'))::numeric, 1) AS p50_min_early,
       round(max(EXTRACT(epoch FROM s_end - actual_end_sim) / 60)::numeric, 1) AS max_min_early,
       round(sum(EXTRACT(epoch FROM s_end - actual_end_sim) / 60)
               FILTER (WHERE s_end > actual_end_sim + interval '5 minutes')) AS charger_minutes_after_the_record
  FROM j GROUP BY ROLLUP (leg_type) ORDER BY 1;
-- READ on 5344fc12: 67 done charge legs; 31 closed 5+ minutes before their session ended, and all 31 had their
--   booking released `window_elapsed_occupied`, on the session's own stall, each with its one service record.
--     charge_dcfc   8 of 27, a median 13.0 minutes early (max 99.0),  201 charger-minutes
--     charge_l2    23 of 40, a median 24.5 minutes early (max 117.9), 837 charger-minutes
--   1,038 charger-minutes in all, on a run of 195 sim-minutes. By how the session ended: 25 completed (807 minutes
--   after the record), 5 were still charging when the run stopped and were ended there (`sim_reset`, 219), and 1
--   ended on a fault (12). So 1,038 is a floor: the five would have gone on. On b0fdc92b: 36 of 76, all 36
--   `window_elapsed_occupied`, 1,280 charger-minutes (not split by session end).

-- ══ §2 THE MECHANISM ════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq.ottoq_release_expired_bookings` (md5 a6ef4307af4493ec005b082feb5587f5 at this read) ends every held or
--   active booking whose window has passed. An active one that ran its full window ends `done` /
--   `window_elapsed_occupied`, and since 0089 its `legs` CTE closes the leg it serves `done` with
--   `actual_end_sim = upper(during)`, the window's end. The leg going `done` fires `trg_0043_leg_done_sdr`, which
--   issues and signs the service record with the leg's times. A charge booking's window is the plan's estimate of the
--   charge. When the charge outlasts it, the leg, and the signed record, end at the estimate, and the session runs on.
--   `twin.ottoq_sim_stop_charge_session` would have closed the leg at the session's real end (it calls
--   `ottoq_itin_leg_close`), and it finds the leg already closed. `ottoq_emit_sdr` returns early for a leg that already
--   has a record, so the record cannot be corrected afterwards.
--
--   What this does NOT do: it does not free the charger in fact. The release leaves `stalls.current_vehicle_id` alone
--   (G80, G81), so the pointer gate still refuses the stall. What is wrong is the record of the charge (leg and
--   service record) and the calendar's own account of the charger for the rest of the session.
--
--   Two earlier decisions bear on the fix, and both stand. G81: "Do NOT fix it by re-extending the booking - that would
--   let a vehicle hold a stall indefinitely by not leaving." 0500 renews parking holds while the car is parked and says
--   "a charge overstay keeps its G81 stamp". So the booking's release stays. What can change is that a charge leg is
--   closed by its session and not by the window: the closer would leave a charge leg open while an OCPP session for
--   the same car on the same stall is open, and the session's stop closes it at its real end.

\echo '=== 0375 §2 — the closer and the session stop, as read ==='
SELECT p.oid::regprocedure AS fn, md5(pg_get_functiondef(p.oid)) AS md5,
       position('window_elapsed_occupied' IN pg_get_functiondef(p.oid)) > 0 AS names_window_elapsed_occupied,
       position('ottoq_itin_leg_close' IN pg_get_functiondef(p.oid)) > 0 AS closes_leg_by_helper,
       position('itinerary_legs' IN pg_get_functiondef(p.oid)) > 0 AS updates_legs_directly
  FROM pg_proc p
 WHERE p.oid IN ('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure,
                 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)'::regprocedure);
-- READ: the closer names `window_elapsed_occupied` and updates `ottoq_itinerary_legs` directly; the session stop
--   closes its leg through `ottoq_itin_leg_close`.

-- ══ §3 G239: THE RECORD OF A CHARGE CARRIES NO ENERGY ═══════════════════════════════════════════════════════════
--
--   `ottoq_emit_sdr` takes `p_energy_kwh` and `p_peak_kw` (default NULL), and its INSERT has no `ocpp_session_id`.
--   `ottoq_trg_leg_done_sdr`, the only live caller, passes neither. So a charge's service record says which stall,
--   which car, when, and under which tariff, and not how much energy. CLAUDE.md 2.6 describes the SDR as "signed,
--   tariffed, operator-attributed", the CDR analogue; a CDR's quantity is the energy.

\echo '=== 0375 §3 — every service record ever kept, by source, with energy, session, cost ==='
SELECT source_kind, data_source, count(*) AS records, count(energy_kwh) AS with_energy, count(ocpp_session_id) AS with_session,
       count(peak_kw) AS with_peak, count(total_cost_usd) AS with_cost, count(tariff_id) AS with_tariff,
       count(DISTINCT sim_run_id) AS runs, min(issued_at) AS first_issued, max(issued_at) AS last_issued
  FROM public.ottoq_service_detail_records
 GROUP BY 1, 2 ORDER BY 3 DESC;
-- READ (2026-09-27 01:05 UTC): `itinerary_leg`/twin 120,624 records over 529 runs (2026-08-30 to tonight), 0 with
--   energy, 0 with a session, 0 with a peak; `backfill_task`/production 51, 0 with energy. On 5344fc12 the 67 charge
--   records all carry a tariff and none carries a cost, a billable amount or an attribution. The one path that has
--   priced a record with energy is SCHEMA_V2's certification B4 (a schedule task, 41.7 kWh, $14.50), and no live
--   source uses it.
--
--   The table is run-scoped, so 120,624 is what survives, not every record ever issued; the claim it supports is "none
--   of the surviving records has energy", and since the writer has never been passed one, none ever had.

\echo '=== 0375 §3(b) — the energy the run delivered, against what its records say ==='
SELECT count(*) AS sessions, round(sum(energy_delivered_kwh)::numeric, 1) AS kwh_delivered,
       (SELECT count(*) FROM public.ottoq_service_detail_records sd
         WHERE sd.sim_run_id = :'run' AND sd.operation_code LIKE 'charge%') AS charge_records,
       (SELECT round(sum(sd.energy_kwh)::numeric, 1) FROM public.ottoq_service_detail_records sd
         WHERE sd.sim_run_id = :'run' AND sd.operation_code LIKE 'charge%') AS kwh_in_records
  FROM public.ocpp_sessions os
 WHERE os.sim_run_id = :'run';
-- READ on 5344fc12: 95 sessions delivered 2,317.8 kWh; the run's 67 charge records carry none of it. Matched from the
--   session side, 66 sessions belong to done charge legs and 29 were still charging when the run stopped (their legs
--   ended `amended`, which issues no record).

-- ══ §4 THE APPLY (0508), AND THE CANON UNDER IT ═════════════════════════════════════════════════════════════════
--
--   0508 (`a_charge_is_recorded_when_its_session_ends_with_the_energy_it_delivered`): the closer leaves an ACTIVE
--   charge leg open while an OCPP session for that car on the booking's stall is active (the booking still ends
--   `window_elapsed_occupied`, G81); the orphan sweep closes a swept session's charge leg at the session's end; and a
--   charge's record carries the energy and peak of the car's sessions that overlap the leg, and the session's id when
--   exactly one does.

\echo '=== 0375 §4 — 0508 as applied ==='
SELECT m.version, m.name, md5(m.statements[1]) AS stored_md5
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'a_charge_is_recorded_when_its_session_ends_with_the_energy_it_delivered';
-- READ: 20260927012721 (8:27 PM CT), md5 3e2b9c0d0c16db1d741aea872f34ce74, equal to the file's body; forces_recert
--   TRUE. Dry-run first with V3 passing on 5344fc12's own charges, rolled back: (a) the closer, a minute past a
--   window, ended the booking `window_elapsed_occupied` and left the leg open with no record, and the session's stop
--   12 min 58 s past the window closed it with one record of 5.893 kWh, the session's peak and its id; (b) the
--   control, a charge its session had closed, closed at its window as before with 0.723 kWh; (c) the orphan sweep
--   ended a planted running session at its own end and closed its leg there with 37.384 kWh. Applied with the same
--   V3 passing. The sweep began at once (verdict 448, grid_smoke/239001/6, passed 8:28 PM CT).

\echo '=== 0375 §4(b) — the canon since 0508, and what moved against its verdicts under 0504 ==='
WITH now_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, equal, verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at > '2026-09-27 01:27:21+00'
   ORDER BY scenario, seed, ticks, verdict_id DESC),
before_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE verdict_id BETWEEN 439 AND 447
   ORDER BY scenario, seed, ticks, verdict_id DESC)
SELECT n.scenario || '/' || n.seed || '/' || n.ticks AS col, b.verdict_id AS was, n.verdict_id AS now, n.equal,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(n.a) k
         WHERE (k LIKE 'h\_%' OR k IN ('fp','endst'))
           AND n.a->>k IS DISTINCT FROM b.a->>k) AS moved
  FROM now_v n LEFT JOIN before_v b USING (scenario, seed, ticks)
 ORDER BY 1;
-- READ: pending.

-- ══ §5 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) no done charge leg closes 5+ minutes before its session ends
--   (31 of 67 on 5344fc12), except a leg that was still `planned` when its window ran out; (b) every done charge leg's
--   record carries energy, and the records' kWh equals the kWh of the sessions they match; (c) bookings are unchanged:
--   charge bookings still end `window_elapsed_occupied` when the charge outlasts them (G81), so G240's window gap reads
--   as before; (d) no charge leg is left `active` at the stop without a running session.

\echo '=== 0375 §5(a) — §1 on the new run: done charge legs closed before their session ended ==='
--   Run §1: `closed_early` should read 0 (or only legs that were never opened).

\echo '=== 0375 §5(b) — done charge legs, their records, and the energy on both sides ==='
WITH legs AS (
  SELECT l.leg_id, l.vehicle_id, l.actual_start_sim, l.actual_end_sim
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run' AND l.leg_type IN ('charge_dcfc','charge_l2') AND l.status = 'done')
SELECT count(*) AS done_charge_legs,
       count(sd.sdr_id) AS with_record,
       count(sd.energy_kwh) AS record_with_energy,
       count(sd.ocpp_session_id) AS record_with_session,
       round(sum(sd.energy_kwh)::numeric, 1) AS kwh_in_records,
       round(sum((SELECT sum(os.energy_delivered_kwh) FROM public.ocpp_sessions os
                   WHERE os.vehicle_id = l.vehicle_id AND os.sim_run_id = :'run'
                     AND os.started_at < l.actual_end_sim AND os.ended_at > l.actual_start_sim))::numeric, 1) AS kwh_in_sessions
  FROM legs l
  LEFT JOIN public.ottoq_service_detail_records sd ON sd.leg_id = l.leg_id;
-- READ: pending.

\echo '=== 0375 §5(d) — charge legs still active at the stop, and whether a session was running ==='
SELECT l.status, count(*) AS legs,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ocpp_sessions os
                                        WHERE os.vehicle_id = l.vehicle_id AND os.sim_run_id = :'run'
                                          AND os.stopped_reason = 'sim_reset')) AS car_charging_at_the_stop
  FROM public.ottoq_itinerary_legs l
 WHERE l.sim_run_id = :'run' AND l.leg_type IN ('charge_dcfc','charge_l2') AND l.status IN ('active','amended')
 GROUP BY 1;
-- READ: pending.

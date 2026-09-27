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

\echo '=== 0375 §1(b) — G240: the charge booking windows against the plan and the session ==='
WITH legs AS (
  SELECT l.leg_id, l.vehicle_id, l.leg_type, l.actual_start_sim, l.actual_end_sim, l.planned_duration_s
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run' AND l.leg_type IN ('charge_l2','charge_dcfc') AND l.status = 'done'),
j AS (
  SELECT l.*, s.started_at AS s_start, s.ended_at AS s_end, lower(b.during) AS b_start, upper(b.during) AS b_end
    FROM legs l
    JOIN LATERAL (SELECT os.* FROM public.ocpp_sessions os
                   WHERE os.sim_run_id = :'run' AND os.vehicle_id = l.vehicle_id
                     AND os.started_at <= l.actual_end_sim AND COALESCE(os.ended_at, 'infinity') >= l.actual_start_sim
                   ORDER BY abs(EXTRACT(epoch FROM os.started_at - l.actual_start_sim)) LIMIT 1) s ON true
    JOIN LATERAL (SELECT bb.* FROM public.ottoq_stall_bookings bb WHERE bb.leg_id = l.leg_id
                   ORDER BY (bb.state IN ('superseded','released','cancelled')), lower(bb.during) LIMIT 1) b ON true
   WHERE s.stopped_reason = 'completed')
SELECT leg_type, count(*) AS completed,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM b_end - b_start)/60))::numeric,1) AS p50_window_min,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY planned_duration_s/60.0))::numeric,1) AS p50_planned_min,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM s_end - s_start)/60))::numeric,1) AS p50_session_min,
       count(*) FILTER (WHERE s_end > b_end) AS session_outlasts_window,
       count(*) FILTER (WHERE (b_end - b_start) < make_interval(secs => planned_duration_s) - interval '5 minutes') AS window_shorter_than_plan
  FROM j GROUP BY 1 ORDER BY 1;
-- READ on 5344fc12: charge_dcfc 21 completed, window 51.7 / plan 68.5 / session 50.9 minutes, 9 outlasting their
--   window, 9 windows short of the plan; charge_l2 31 completed, 49.0 / 67.3 / 62.7, 21 outlasting, 18 short.
--   Where the short windows come from is not established. Two guesses were measured and ruled out: of 43 enacted
--   charge bookings shorter than their leg's plan, 1 ends exactly where another car's booking on the stall begins (5
--   within a minute), so they are not clipped to the next promise; and 65 of 74 enacted windows start at the
--   enactment clock, a median 0.6 minutes before the leg's planned start, so they are not a stale plan window either.
--   `ottoq_decide_tick` passes the leg's planned window to `ottoq_record_enacted_booking`, so the sizing happens
--   inside the booking writer, which is the next place to read (G240).
--   Read next, the same evening: the writer sizes a charge it is not handed a window for with
--   `ottoq_charge_minutes_between(SoC now, the visit's target_soc (else 85), the stall's connector_max_kw, the car's
--   inlet limit, pack)` at 22 °C and 95% state of health, clamped to 15-480 minutes. The rated powers match the
--   chargers (L2 19.2 kW, DCFC 350 kW) and busy_day's charge_time multiplier is 1, so neither is the gap. Given each
--   completed session's own start SoC and target, that estimator against the real duration: DCFC a median ratio
--   1.00 (p90 1.22), L2 1.13 (p90 1.45). The target is not the main cause either: matched on sim time, 41 of 54
--   completed sessions charge to exactly their visit's target, 5 past it (about 107 charger-minutes) and 3 below it
--   (a DCFC cap). (A first match compared the visit's real-clock `created_at` with the session's sim start and found
--   no visits at all; the match above uses `arrived_at`.) So the windows run short because a nominal model, with no
--   knowledge of the car, the battery's temperature or its history, sizes every charge, and the calibration that
--   fixed the card's ETA in §6 (1.9 minutes median error against 12.6 for the plan) is the direction for the booking.

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
-- READ (2026-09-27 02:00 UTC): all nine columns passed under 0508, verdicts 448-456, the last certified 8:49 PM CT,
--   every one `equal = true`. Against 439-447: every busy_day and normal_day column moved all ten digests (endst h_bkg
--   h_cmd h_dec h_evt h_nrg h_prop h_rcl h_rule h_sdr); both grid_smoke columns moved endst h_evt h_sdr; `fp` moved in
--   none. So 0508 reaches the decisions as well as the records, which a leg that stays active can: the flow contract
--   re-times a plan only when no leg is active. Measured on arm A of two columns, 0504 against 0508:
--     busy_day/171717/12   commands 306 / 306, refused 31 / 31, sessions 87 / 88, kWh 1,554.1 / 1,549.4, decisions
--                          1,410 / 1,401 (amend_plan 782 / 768), done charge legs 86 / 80, their records with energy
--                          0 of 86 / 80 of 80
--     busy_day/171717/48   commands 947 / 907, refused 125 / 120, sessions 176 / 169, kWh 4,392.2 / 4,402.1,
--                          decisions 5,339 / 5,334 (amend_plan 3,454 / 3,485), done charge legs 169 / 167, with energy
--                          0 of 169 / 166 of 167
--   The done charge legs fall because a charge still running when an arm ends now ends `amended` with its session,
--   not `done` at its window; the one record of 167 without energy is a charge leg that overlapped no session. Which
--   decisions moved, one by one, is not traced here.

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

-- ══ §6 THE CARD'S CHARGE ETA (0509), BACKTESTED BEFORE IT WAS APPLIED ═══════════════════════════════════════════
--
--   Under 0508 a charge step stays current until its session ends, so 0507's `expected_end` (actual start plus
--   planned duration) would read in the past for every charge that outruns its plan. 0509 gives a running charge an
--   ETA from the planner's own charge model (`ottoq_estimate_charge_minutes`) from the car's SoC now to its target,
--   calibrated on the session as it runs: scaled by the minutes the session has actually taken over the minutes the
--   model gives for the SoC it has gained (1 until 2 points gained; held in [0.5, 5]). Its inputs are what a real depot
--   knows (charger rating, inlet limit, pack, state of health, start SoC and time, ambient, SoC now, target cap); it
--   reads no variability profile and no per-car curve card, so the twin's hidden perturbations are exactly what the
--   calibration has to learn, and it would run unchanged on real OCPP meter values.
--
--   The backtest: every completed session of 10+ minutes on the run, read at the meter value nearest its midpoint,
--   three ways against the minutes it actually had left: the calibrated model, the model alone (ratio 1), and the plan
--   (0507: actual start plus planned duration).

\echo '=== 0375 §6 — the ETA three ways at each completed session''s midpoint, against the real end ==='
WITH s AS (
  SELECT os.id, os.vehicle_id, os.stall_id, os.started_at, os.ended_at, os.soc_start, os.ambient_temp_c,
         ch.max_kw, v.inlet_max_kw, v.battery_capacity_kwh AS pack, COALESCE((v.config->>'battery_soh_pct')::numeric, 95) AS soh,
         st.stall_type::text AS stype,
         (SELECT (m.payload->>'target_soc_pct')::numeric FROM public.ottoq_ocpp_messages m
           WHERE m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction' LIMIT 1) AS target
    FROM public.ocpp_sessions os
    JOIN public.stalls st ON st.id = os.stall_id
    JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
    JOIN public.vehicles v ON v.id = os.vehicle_id
   WHERE os.sim_run_id = :'run' AND os.stopped_reason = 'completed'
     AND os.ended_at - os.started_at >= interval '10 minutes'),
mid AS (
  SELECT s.*, mv.sim_clock_at AS t_mid,
         (SELECT (e->>'value')::numeric FROM jsonb_array_elements(mv.payload->'sampledValue') e WHERE e->>'measurand' = 'SoC') AS soc_mid
    FROM s
    JOIN LATERAL (SELECT m.* FROM public.ottoq_ocpp_messages m
                   WHERE m.ocpp_session_id = s.id AND m.message_type = 'MeterValues'
                   ORDER BY abs(EXTRACT(epoch FROM m.sim_clock_at - (s.started_at + (s.ended_at - s.started_at) / 2))) LIMIT 1) mv ON true),
leg AS (
  SELECT mid.*, (SELECT l.actual_start_sim + make_interval(secs => l.planned_duration_s)
                   FROM public.ottoq_itinerary_legs l
                  WHERE l.sim_run_id = :'run' AND l.vehicle_id = mid.vehicle_id
                    AND l.leg_type IN ('charge_dcfc','charge_l2') AND l.actual_start_sim IS NOT NULL
                  ORDER BY abs(EXTRACT(epoch FROM l.actual_start_sim - mid.started_at)) LIMIT 1) AS plan_end
    FROM mid),
calc AS (
  SELECT leg.*,
         LEAST(leg.target, public.ottoq_target_soc_cap(leg.stype, leg.started_at)) AS tgt,
         EXTRACT(epoch FROM leg.t_mid - leg.started_at)/60 AS elapsed,
         public.ottoq_estimate_charge_minutes(leg.soc_start, leg.soc_mid, leg.max_kw, leg.inlet_max_kw, leg.pack,
                                              COALESCE(leg.ambient_temp_c,22)+5, leg.soh, 1.0) AS model_done
    FROM leg WHERE leg.soc_mid IS NOT NULL),
pred AS (
  SELECT calc.*,
         CASE WHEN soc_mid - soc_start >= 2 AND model_done > 0 THEN LEAST(5, GREATEST(0.5, elapsed / model_done)) ELSE 1 END AS ratio
    FROM calc),
fin AS (
  SELECT pred.stype, pred.ratio,
         EXTRACT(epoch FROM pred.ended_at - pred.t_mid)/60 AS actual_left,
         public.ottoq_estimate_charge_minutes(pred.soc_mid, pred.tgt, pred.max_kw, pred.inlet_max_kw, pred.pack,
                                              COALESCE(pred.ambient_temp_c,22)+5, pred.soh, pred.ratio) AS cal_left,
         public.ottoq_estimate_charge_minutes(pred.soc_mid, pred.tgt, pred.max_kw, pred.inlet_max_kw, pred.pack,
                                              COALESCE(pred.ambient_temp_c,22)+5, pred.soh, 1.0) AS raw_left,
         EXTRACT(epoch FROM pred.plan_end - pred.t_mid)/60 AS plan_left
    FROM pred)
SELECT stype, count(*) AS sessions, round(avg(ratio)::numeric, 2) AS avg_ratio,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(cal_left - actual_left)))::numeric, 1) AS p50_err_calibrated,
       round((percentile_cont(0.9) WITHIN GROUP (ORDER BY abs(cal_left - actual_left)))::numeric, 1) AS p90_err_calibrated,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(raw_left - actual_left)))::numeric, 1) AS p50_err_model_only,
       round((percentile_cont(0.9) WITHIN GROUP (ORDER BY abs(raw_left - actual_left)))::numeric, 1) AS p90_err_model_only,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(plan_left - actual_left)))::numeric, 1) AS p50_err_plan,
       round((percentile_cont(0.9) WITHIN GROUP (ORDER BY abs(plan_left - actual_left)))::numeric, 1) AS p90_err_plan,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY actual_left))::numeric, 1) AS p50_actual_left
  FROM fin GROUP BY ROLLUP (stype) ORDER BY 1;
-- READ on 5344fc12 (52 completed sessions of 10+ minutes; a median 31.4 minutes left at the midpoint), absolute
--   error in minutes, median / p90:
--                       calibrated     model alone    plan (0507)
--     charge_dcfc (22)   1.2 /  4.4     4.7 / 17.7     4.7 / 82.2
--     charge_l2   (30)   3.4 /  7.7     8.6 / 26.6    19.4 / 87.8
--     all         (52)   1.9 /  7.0     7.5 / 23.5    12.6 / 87.1
--   The calibration ratio averaged 0.93 on DCFC and 1.02 on L2, so the model's shape was close and the per-session
--   correction did most of the work at the tail. One run, the midpoint only; the live reading (0509's V3 and the
--   cockpits) is on the next validation run.

-- ══ §7 0509 AS APPLIED, AND READ LIVE ═══════════════════════════════════════════════════════════════════════════

\echo '=== 0375 §7 — 0509 as applied ==='
SELECT m.version, m.name, md5(m.statements[1]) AS stored_md5
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'a_charging_card_ends_when_the_charge_physics_says_it_will';
-- READ: 20260927020531 (9:05 PM CT), md5 9348c6d9c5cea2096b26216936ada869, equal to the file's body; forces_recert
--   FALSE (a cockpit read function). Dry-run first between runs (patch, V1, V2; V3 needs a live run), then applied four
--   minutes into validation run 964cf17b (sim 8:25 AM, 24 charging sessions) with V3 passing on the live cards.

\echo '=== 0375 §7(b) — on a live run: current steps by ETA source, and the minutes left on the physics ones ==='
WITH c AS (SELECT public.ottoq_depot_cards('11111111-1111-1111-1111-111111111111', NULL) AS j),
st AS (SELECT (c.j->>'sim_clock')::timestamptz AS clk, s
         FROM c, jsonb_array_elements(c.j->'vehicles') v, jsonb_array_elements(COALESCE(v->'card'->'steps','[]'::jsonb)) s
        WHERE s->>'status' = 'current')
SELECT count(*) FILTER (WHERE s->>'eta_source' = 'charge_physics') AS physics_steps,
       count(*) FILTER (WHERE s->>'eta_source' = 'plan') AS plan_steps,
       round(avg(EXTRACT(epoch FROM (s->>'expected_end')::timestamptz - clk)/60)
               FILTER (WHERE s->>'eta_source' = 'charge_physics')::numeric, 1) AS avg_min_left,
       count(*) FILTER (WHERE (s->>'over_plan_min') IS NOT NULL) AS past_plan
  FROM st;
-- READ on 964cf17b at sim 8:31:56 AM, just after the apply: contract 1.3; 31 current steps by the calibrated physics
--   (a mean 57.4 minutes left), 2 by the plan, none past plan yet; the whole read took about 0.13 s. In the cockpits:
--   PULSE at sim 8:36 AM showed 8 charging cards "DC fast charge until ~9:20 AM" and the like (the ~ marks an
--   estimate) beside bay steps on their plan times ("Wash bay until 8:44 AM"); OrchestrAV at 8:41 showed 10, the same
--   cars' estimates moved by a minute or two as each calibration took in five more minutes of its session (~10:02 ->
--   ~10:01 AM, ~9:48 -> ~9:50 AM, ~9:20 -> ~9:21 AM).

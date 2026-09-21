-- 0308  CHASE ASKED WHETHER OTTO-Q ORCHESTRATES AROUND HARDWARE FAULTS IN REAL TIME. **IT DOES,
--       AND THE MACHINERY IS MORE BUILT THAN I EXPECTED.** Tracing it end to end turned up a
--       LARGER ADJACENT FINDING that is not about faults at all: **a vehicle can occupy a charge
--       stall for its whole booked window, have that booking counted as a completed turn, and
--       never have a charging session started for it.** Root-caused to one gate.
--
-- Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8) on the magnitude queries.
-- Measured 2026-09-21 13:0x UTC (08:0x CT).
--
-- ══ 0. READ THIS BEFORE QUOTING ANY NUMBER IN THIS FILE ════════════════════
--
-- **THE MAGNITUDES BELOW DRIFTED WHILE I WAS MEASURING THEM AND ARE NOT SAFE TO QUOTE.** The
-- `0399` recert sweep was running throughout, generating pairs, so `ottoq_stall_bookings` grew
-- under the queries: completed DCFC charge turns at this depot read **362** in one query and
-- **484** six minutes later, and the matching session counts moved with them. That is CLAUDE.md's
-- *"cite the run, never the table"* observed rather than quoted — these are per-run working sets,
-- not totals.
--
-- **So this file publishes the MECHANISM, which is source-derived and stable, and defers the
-- MAGNITUDE to a single named run.** Everything in §1–§4 can be re-derived from function bodies
-- and does not move. Everything in §5 is a moment and is labelled as one.
--
-- ══ 1. WHAT EXISTS, AND IT IS THE THING ASKED FOR ══════════════════════════
--
-- **(a) Faults are injected mid-session, at a calibrated rate.**
-- `twin.ottoq_sim_advance_charge_sessions` deals a fault card per session via
-- `ottoq_twin_deal_fault_card(run, session, soc_start, target, clock)` and fires when
-- `will_fault` AND the pack has passed `trigger_soc` AND it is still short of target:
--
--     IF (v_fault_card->>'will_fault')::boolean
--        AND v_new_soc >= (v_fault_card->>'trigger_soc')::numeric
--        AND v_new_soc < v_target_soc - 0.5 THEN
--
-- It emits `MeterValues` carrying `fault_imminent`, increments `fault_count`, records
-- `last_fault_message`, and stops the session with reason `fault.<mode>`. **Six modes are
-- observed**, and the code names their provenance — *"Calibrated fault injection per ChargerHelp
-- mix"*: `communication_dropout`, `session_aborted_other`, `thermal_emergency`,
-- `station_hardware`, `connector_cable`, `ground_fault_safety`.
--
-- **(b) The charger is taken out of service WITH A DRAWN REPAIR DURATION.**
-- `twin.ottoq_sim_stop_charge_session` sets `station_state='Faulted'` plus `last_fault_code`,
-- `last_fault_at` and a `last_fault_payload` carrying `repair_minutes`, read from
-- `ottoq_variability_cards` — *"the fitted repair_days grid x staffed-depot x fault mode"*. So the
-- outage has a modelled length rather than being permanent, and `twin.ottoq_sim_recover_chargers`
-- is the other half.
--
-- **(c) The auto-reroute is explicit, and labelled as such in the source.**
--
--     -- S3a AUTO RE-ROUTE: fault interrupted the charge with the vehicle still under target →
--     -- re-queue so OTTO-Q reassigns a healthy charger; otherwise proceed to disposition.
--     v_requeue := (p_reason LIKE 'fault%' AND v_vehicle.current_soc < v_vehicle.target_soc - 5);
--
-- **(d) And there is a second, operator-initiated path that does exactly what Chase described.**
-- `twin.ottoq_report_charger_fault(charger, actor, fault_code, note)` — a depot tech confirming a
-- fault — marks the hardware Faulted, VACATES the stall, takes it out of the pool
-- (`status='maintenance'`), and calls `ottoq.ottoq_replan_after_charger_fault` per displaced
-- vehicle. That replanner is the clearest statement of the doctrine in the codebase: prefer a
-- healthy stall of the SAME class → `requeued_same_class`; else temp-stage it, *"never leave a
-- displaced vehicle without somewhere to be"* → `temp_parked_awaiting_charger`; else
-- `no_space_escalated`. It then sends a downlink (`proceed_to_stall` or `stage`) tagged
-- `plan_update='charger_fault_reroute'`.
--
-- **So the answer to the question as asked is yes.** What follows is where it stops short.
--
-- ══ 2. THE FIRST GAP, AND IT IS IN `ottoq_replan_after_charger_fault` ═══════
--
-- Its "healthy stall of the same class" query gates on the POINTER and the CHARGER:
--
--     AND s2.status = 'available' AND s2.current_vehicle_id IS NULL
--     AND (s2.reserved_by IS NULL OR COALESCE(s2.reservation_expires_at, p_clock) <= p_clock)
--     AND c2.station_state = 'Available'
--
-- **It never reads the CALENDAR.** CLAUDE.md's standing rule — earned three times in one night —
-- is that a stall is offerable only as the intersection of THREE gates: the pointer, the
-- `ottoq_stall_bookings` calendar, and the OCPP charger not being Faulted. This function checks
-- the first and third and skips the second, so it can reroute a displaced vehicle onto a stall the
-- calendar has already promised to someone else. The staging fallback checks the pointer only.
-- Same defect shape as `0250` and `0372`, in the one function whose whole job is recovery.
-- **Not yet observed causing a collision** — the EXCLUDE constraint on `ottoq_stall_bookings`
-- would refuse the overlapping booking downstream, which is the architecture containing it rather
-- than the function being right.
--
-- ══ 3. THE LARGER FINDING: WHAT STARTS A CHARGING SESSION UNDER `otto_q` ════
--
-- Exactly one function inserts into `ocpp_sessions`: `twin.ottoq_sim_start_charge_session`. It has
-- three callers:
--
--   public.ottoq_tick_invariance_reset_fleet     a test fixture
--   twin.ottoq_sim_auto_charge_assign_tick       called ONLY from public.ottoq_greedy_tick
--   twin.ottoq_sim_reconcile_charge_sessions     called from the tick
--
-- **`ottoq_sim_auto_charge_assign_tick` is reachable only from the GREEDY BASELINE.** Under the
-- `otto_q` policy the sole live path that starts a charging session is the reconciler. And the
-- reconciler's gate is this, in full:
--
--     WHERE v.home_depot_id = v_depot
--       AND v.current_state IN ('charging_dcfc','charging_l2')
--       AND v.current_stall_id IS NOT NULL
--       AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s
--                        WHERE s.vehicle_id = v.id AND s.status='active'
--                          AND s.id_token LIKE 'TWIN-%')
--
-- **It starts a session only for a vehicle ALREADY IN A CHARGING STATE.** It is a reconciler, not
-- an initiator: it repairs the case "the state machine says charging and no session exists". It
-- cannot help the case "the vehicle is sitting on a charge stall and its state was never moved to
-- charging", because that vehicle does not match its WHERE clause.
--
-- **This is the `perimeter_walkaround` shape exactly** (`0277`/`0383`): a gate keyed on one
-- enumerated field, and a population that never satisfies it, with no error anywhere — the engine
-- simply never acts. There the field was `concurrency='hold'`; here it is
-- `current_state IN ('charging_dcfc','charging_l2')`.
--
-- ══ 4. AND THE CONSEQUENCE IS PHYSICAL, NOT COSMETIC ═══════════════════════
--
-- **No session means no energy, and that is checkable rather than assumed.** Of every function
-- that writes `vehicles.current_soc`, the only in-run CHARGING path is
-- `twin.ottoq_sim_advance_charge_sessions`, which iterates active `ocpp_sessions`. The others are
-- cert-arm fixtures, the fleet-reset fixture, and `twin.ottoq_sim_advance_deployed_telemetry`
-- (a deployed vehicle's own drain/telemetry, not depot charging). So:
--
--     a charge booking with no overlapping session  ⇒  no energy delivered  ⇒  no SoC gain
--
-- A vehicle held a DC fast charger for its booked window — tens of minutes — and left with the
-- pack it arrived with, while the stall was unavailable to everyone else.
--
-- **AND KPI #2 IS EXONERATED, which must be said as plainly as the finding.** I suspected
-- `service_point_turns_per_point_per_day` was inflated by bookings that completed on the clock.
-- It is not. `ottoq_release_expired_bookings` distinguishes the two cases and the data carries it:
--
--     state='released', release_reason='window_elapsed'            never occupied
--     state='done',     release_reason='window_elapsed_occupied'   OCCUPIED, window elapsed
--
-- `ottoq_kpi_service_point_turns` counts `state='done'` as `turns_completed` and separately
-- publishes `released_never_occupied` as `release_reason='window_elapsed'`. So a turn requires
-- occupancy and the KPI is right. **The turn is real; the SERVICE is what did not happen** — which
-- is a sharper problem than a miscounted KPI, and it is invisible to a turns metric by
-- construction. 2.6's instruction is the remedy shape: *every completed operation terminates in an
-- SDR.* A charge turn with no session should be unable to produce one.
--
-- ══ 5. MAGNITUDE — A MOMENT, NOT A VALUE. DO NOT QUOTE THESE. ══════════════
--
-- Measured across 13 surviving runs at this depot while the sweep was adding more:
--
--   charge_dcfc  occupied completed turns  362 → 484 (drifted)  ~61% with NO overlapping session
--   charge_l2    occupied completed turns  854               ~42% with NO overlapping session
--   average booked window                  DCFC 31.3 min · L2 44.3 min
--
-- **The predicate was stress-tested before any of that was believed**, because a loose join is how
-- this repo usually gets a number wrong. Four widths, on the same population: session start inside
-- the window and same stall (strict) → any temporal OVERLAP, same stall → overlap, ANY stall →
-- that vehicle had any session at all in the run. **Loosening moved DCFC by 0 and L2 by 12 of
-- 856**, and the loosest column matched every booking, which proves the vehicles do have sessions
-- elsewhere in the same run and this is not missing data. Both tables are `class='engine'` and
-- purge together, so it is not a differential-purge artifact either.
--
-- **AND ONE ATTEMPTED CONFIRMATION FAILED, which is why §3 is a source finding and not an
-- evidence finding.** To test "the vehicle never entered a charging state" I looked for
-- `vehicle_state_change` rule evaluations with `to_state LIKE 'charging%'` inside each window. It
-- reads FALSE for **198 of the 200** bookings that DID have a session — so the witness is
-- near-zero in both directions and distinguishes nothing. The reason is mundane: that probe was
-- only wired on 2026-09-20 (`0387`) and `ottoq_rule_evaluations` is `class='engine'` and heavily
-- purged. **Absence in a young, purged table is not evidence of absence in the world**, and a
-- confirmation that cannot fail is not a confirmation.
--
-- ══ 6. WHAT IS OWED ════════════════════════════════════════════════════════
--
-- Three things, in order, and none of them is "change the reconciler's WHERE clause" — widening
-- that gate to start sessions for any vehicle on a charge stall would start charging vehicles the
-- state machine has not admitted to charging, which is the `0231` move of making a mechanism agree
-- with a claim by deleting the check.
--
--   1. **Re-derive §5 on ONE named run**, once the sweep is drained, on the twin depot, with the
--      run id quoted. Until then the magnitude is unknown, not "about half".
--   2. **Find what should move a vehicle to `charging_*` on arrival at a charge stall, and whether
--      it runs.** That is the actual defect site if §3 is right, and it is where the fault-reroute
--      case and the ordinary case meet.
--   3. **Make it structural, per 2.6:** a `charge_*` booking that reaches `done` with no session
--      and no energy should be a refusable or at least an asserted condition, not a silent one.
--      `ottoq_assert_*` is the established pattern.

-- The mechanism queries, so a reader can repeat every claim in §1-§4 without the drifting counts.
SELECT 'only inserter of ocpp_sessions' AS fact,
       string_agg(n.nspname||'.'||p.proname, ', ') AS value
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prosrc ~* 'INSERT\s+INTO\s+(public\.)?ocpp_sessions' AND n.nspname IN ('public','ottoq','twin')
UNION ALL
SELECT 'callers of ottoq_sim_start_charge_session',
       string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prosrc ~* 'ottoq_sim_start_charge_session' AND p.proname <> 'ottoq_sim_start_charge_session'
UNION ALL
SELECT 'callers of ottoq_sim_auto_charge_assign_tick (greedy-only is the finding)',
       string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prosrc ~* 'ottoq_sim_auto_charge_assign_tick' AND p.proname <> 'ottoq_sim_auto_charge_assign_tick'
UNION ALL
SELECT 'in-run paths that raise vehicles.current_soc',
       string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prosrc ~* 'UPDATE\s+(public\.)?vehicles' AND p.prosrc ~* 'current_soc\s*='
   AND n.nspname IN ('public','ottoq','twin');

-- The booking-state vocabulary that exonerates KPI #2. 'window_elapsed' is released and never
-- occupied; 'window_elapsed_occupied' is done and occupied. The KPI counts only the latter.
SELECT state, COALESCE(release_reason,'(null)') AS release_reason, count(*) AS n,
       count(*) FILTER (WHERE purpose IN ('charge_dcfc','charge_l2')) AS charge_bookings
  FROM public.ottoq_stall_bookings GROUP BY 1,2 ORDER BY n DESC;

-- OPEN-ITEM: under the otto_q policy the ONLY live path that starts a charging session is twin.ottoq_sim_reconcile_charge_sessions, whose gate admits a vehicle only if current_state IS ALREADY 'charging_dcfc'/'charging_l2' -- it is a reconciler, not an initiator. twin.ottoq_sim_auto_charge_assign_tick, which would assign, is reachable only from public.ottoq_greedy_tick. So a vehicle can occupy a charge stall for its full booked window, have the booking counted as a completed turn (correctly -- occupancy is real and KPI #2 is NOT inflated), and never be charged, because no session means no energy: the only in-run charging path iterates active ocpp_sessions. Magnitude is UNKNOWN, not "about half" -- the counts drifted 362 to 484 mid-measurement while the 0399 recert sweep added runs, and my attempt to confirm the cause from vehicle_state_change evaluations failed as a witness (false for 198 of 200 bookings that DID have a session, because that probe is one day old and the table is class='engine'). Owed: re-derive on one named run; find what should move a vehicle to charging_* on arrival and whether it runs; make a charge turn with no session an asserted condition per 2.6. Do NOT widen the reconciler's gate. Separately ottoq_replan_after_charger_fault, the fault recovery path, checks the pointer and the charger but NOT the calendar, against CLAUDE.md's three-gate rule. Tracked as G112.

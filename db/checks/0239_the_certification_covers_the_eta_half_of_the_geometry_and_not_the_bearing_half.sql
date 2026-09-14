-- ===========================================================================
-- 0239  THE CERTIFICATION COVERS THE ETA HALF OF THE TRIP GEOMETRY AND NOT
--       THE BEARING HALF
--
-- Found while writing db/canons/round43.md, immediately after 0319 was
-- convicted and fixed. 0319 was a deterministic draw salted with
-- gen_random_uuid(); the determinism pair caught it in a single run, and this
-- check asks the follow-up question that matters more than the fix:
--
--     WHY did the pair catch it, and would it catch the next one?
--
-- The answer is that it caught HALF of 0319 and the half it caught happened to
-- be enough. That is luck, and luck is not an instrument.
--
-- ---------------------------------------------------------------------------
-- WHAT A FIRST DRAFT CLAIMED, AND WHY IT WAS TOO STRONG
--
-- The first draft of the round-43 canon said the fourteen atoms cannot see
-- position determinism AT ALL, because no atom hashes ottoq_telemetry_packets
-- and that is where 0317 writes current_lat/current_lng. §A shows the premise
-- is true. §B shows the CONCLUSION does not follow, and the draft was corrected
-- before the round ran rather than after.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- §A  NO ATOM READS A TELEMETRY PACKET. The premise, asserted rather than
--     assumed: every function that computes a certification atom, checked for
--     any reference to the table the positions land in.
-- ---------------------------------------------------------------------------
SELECT 'A1 atom fns referencing ottoq_telemetry_packets' AS check,
       COALESCE(string_agg(p.proname, ', '), '(none)')   AS result
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin')
   AND p.proname IN ('ottoq_determinism_pair','ottoq_twin_run_digest',
                     'ottoq_boot_state_fingerprint','ottoq_hash_proposals',
                     'ottoq_hash_deferrals','ottoq_hash_recall_decisions',
                     'ottoq_hash_rule_evaluations','ottoq_hash_sdrs',
                     'ottoq_calibration_fingerprint','ottoq_capture_decision_snapshot',
                     'ottoq_frame_hash_payload')
   AND p.prosrc ILIKE '%ottoq_telemetry_packets%';
-- MEASURED 2026-09-14 17:30 UTC: (none). The packet stream is outside all
-- fourteen atoms.

-- The tables the atoms DO cover, for the record:
--   fp      ottoq_decision_snapshots      h_prop  ottoq_external_proposals
--   h_cmd   ottoq_vehicle_commands        h_defr  the deferral ledger
--   h_dec   ottoq_decisions               h_cal   the calibration registry
--   h_evt   ottoq_events                  h_rule  ottoq_rule_evaluations
--   h_bkg   ottoq_stall_bookings          h_rcl   ottoq_recall_decisions
--   h_nrg   ottoq_energy_commands         h_sdr   the SDR stream
--   endst   ottoq_boot_state_fingerprint at the last tick
--   ticks   the tick count

-- ---------------------------------------------------------------------------
-- §B  BUT THE GEOMETRY HAS ONE SOURCE, AND ONE OF ITS TWO OUTPUTS IS WIRED
--     INTO A TABLE THE ATOMS DO HASH.
--
--        ottoq_trip_geometry -> (bearing_deg, radius_km, progress, distance_km)
--          |- ottoq_vehicle_position   ST_Project(depot origin, distance, bearing)
--          |                             -> ottoq_telemetry_packets.current_lat/lng
--          `- ottoq_computed_eta_minutes  distance / speed x congestion
--                                         -> ottoq_vehicle_dispatches
--                                              .return_eta_minutes   [inside endst]
--
--     So distance_km IS certified, transitively. bearing_deg is not: it reaches
--     ottoq_vehicle_position and nothing else.
-- ---------------------------------------------------------------------------
SELECT 'B1 position delegates to the same geometry fn' AS check,
       (SELECT (p.prosrc ILIKE '%ottoq_trip_geometry%')::text
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='ottoq_vehicle_position') AS position_fn,
       (SELECT (p.prosrc ILIKE '%ottoq_trip_geometry%')::text
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='ottoq_computed_eta_minutes') AS eta_fn;
-- MEASURED: true / true. ONE source, two consumers -- not the G54
-- two-sources-of-truth class. That was checked before it was alleged.

-- Every reader of the position columns anywhere in the database:
SELECT 'B2 readers of current_lat / current_lng' AS check,
       COALESCE((SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname IN ('public','twin','ottoq')
                    AND (p.prosrc ~ 'current_lat' OR p.prosrc ~ 'current_lng')), '(none)') AS functions,
       COALESCE((SELECT string_agg(c.relname, ', ' ORDER BY c.relname)
                   FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE c.relkind IN ('v','m') AND n.nspname IN ('public','twin','ottoq')
                    AND pg_get_viewdef(c.oid) ~ '(current_lat|current_lng)'), '(none)') AS views;
-- MEASURED: functions = twin.ottoq_sim_emit_telemetry (the WRITER); views = none.
-- Written every tick, read by nothing. Per db/checks/0232 that is not the same
-- as dead -- the 3D layer and any operator map are exactly the consumers this
-- exists for -- but it does mean no downstream computation can notice if it is
-- wrong, which is the whole point of this file.

-- ---------------------------------------------------------------------------
-- §C  SO WHY WAS 0319 CAUGHT?
--
--     Because it broke BOTH halves at once. The salt was shared:
--
--       bearing_deg := seeded_random(seed, 'trip_bearing:'||vehicle||':'||<salt>)
--       radius_km   := sample_calibrated(..., 'trip_radius:' ||vehicle||':'||<salt>)
--
--     and <salt> was gen_random_uuid(). The random radius moved distance_km,
--     which moved the ETA, which moved ottoq_vehicle_dispatches, which endst
--     hashes. The pair failed on the ETA half.
--
--     A defect confined to the bearing -- a different salt, a different sort,
--     a projection bug in ST_Project's argument order -- would put every asset
--     somewhere different on the map in every arm, and ALL FOURTEEN ATOMS WOULD
--     AGREE. That is the gap, stated at its true width: not "position is
--     uncertified", but "one of the two numbers that determine position is
--     uncertified".
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- §D  THE FIX, AND WHY IT IS NOT IN ROUND 43
--
--     An atom over the telemetry position stream -- ordered on
--     (vehicle_id, sim_clock_at, packet_seq), digesting the rounded lat/lng and
--     nothing volatile. packet_id defaults to a generated uuid and packet_at is
--     NOW(): NEITHER may enter the digest, which is the 0137/0139/0216/0319
--     rule stated for the fourth time -- BEFORE MEASURING A VALUE, READ ITS
--     ASSIGNMENT.
--
--     Added MEASURED, not ENFORCED. Per CLAUDE.md 2.9a an atom is recorded in
--     validation_notes first and promoted into the verdict only after a flagship
--     round shows the arms agree on it (0139 / 0206 / 0217 / 0225 are the
--     precedents). Enforcing an unmeasured atom is db/checks/0161, by name.
--
--     And it is NOT applied during round 43. Any migration mid-round moves the
--     recert floor past every pair already banked and the round proves nothing
--     -- the 0308/0309/0311 lesson, from the other direction.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- §E  ONE MORE THING THE MAP SHOWS, PARKED HERE RATHER THAN FIXED HERE
--
--     ottoq_computed_eta_minutes takes the vehicle's speed as
--
--         SELECT COALESCE(avg(tp.speed_kmh), 35.2) ... WHERE tp.sim_clock_at <= p_sim_clock
--
--     -- a LIFETIME average over every packet the vehicle has emitted this run,
--     not its current speed. Chase's requirement is that an ETA should shift
--     when a vehicle hits traffic; an average over the whole trip is the most
--     heavily damped estimator available, and a vehicle that slows to a crawl in
--     the last ten minutes barely moves it. The time-of-day term
--     (ottoq_congestion_factor, 0.75 on two rush windows and 1.05 elsewhere,
--     contrast sourced to TomTom Nashville 2025 and shape pending R-14) shifts
--     the ETA by CLOCK but nothing yet shifts it by the vehicle's OWN recent
--     experience.
--
--     Not changed in this file and not in round 43: it changes the ETA, the ETA
--     is inside endst, and that is a canon move. It belongs in the window after
--     the round, with its own measurement of how much a windowed average
--     actually moves the number.
-- ---------------------------------------------------------------------------

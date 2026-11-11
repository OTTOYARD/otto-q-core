-- 0481  **The one-line changes no atom; a tripped transformer's cars finish on another one; and the lab's day fits on
--        about a twentieth of what is installed.** (0810, 0811; G531-G537)
--        Built and measured in the research lab on 2026-11-11, 04:42-05:06 UTC (10:42-11:06 PM CT on 11-10), on a copy
--        of production's engine: the 2026-11-04 export plus 0720, 0791 and 0794-0809 (0701 needs the vault's signing key,
--        which the lab does not hold, so the lab's engine hash is aae920a7 against production's e4521543, read 04:52 UTC;
--        production does not carry 0809). Rule 8: the twin depot only. Rule 12: one day per question, no sweep, no pairs
--        beyond the one comparison in (1). Lab days are research, not production runs. Results:
--        lab/research/p3_power/results/. Nothing here was applied to production.
--
-- ══ (1) THE CAPTURE CHANGES NOTHING THE CERTIFICATION HASHES ════════════════════════════════════════════════════════
--
--   Two arms started exactly as one arm of ottoq_determinism_pair (lab/engine/lib/lab_run.py), busy_day, seed 171717,
--   48 ticks of 30 sim-minutes, one in a database with 0810 and one without:
--     with 0810     run e7e66bcd   2.87 s a tick
--     without 0810  run c2529bca   2.86 s a tick
--   All fourteen atoms equal (fingerprint, commands, decisions, events, bookings, energy, proposals, deferrals,
--   calibration, rules, recalls, SDRs, tick count, end state). So 0810 is forces_recert FALSE on a measurement, not on
--   an argument.
--   The first attempt, on the bare 11-04 export with the five stray chargers decommissioned in the same file, differed
--   on the end state alone, in two sections: chargers.world (the decommissioning: ottoq_boot_state_fingerprint hashes
--   every charger row at the depot, 45 of them, in service or not) and visit_needs (G510's minted id, which that export
--   predates and 0794 fixes). That is why the decommissioning is its own file, 0811, classed forces_recert TRUE.
--
-- ══ (2) THE POSTS ADD UP TO THE SITE METER ON EVERY TICK ════════════════════════════════════════════════════════════
--
--   The capture reads each post's power by the site meter's own predicate. On the 2-minute day (run 4c87dd16, 420
--   ticks) and on the 48-tick day: the service node's DC sum equals site_energy_snapshots.total_ev_charging_kw on 420
--   of 420 and 48 of 48 ticks (worst difference 0.05 kW, the snapshot's rounding to one decimal).
SELECT count(*) AS ticks,
       count(*) FILTER (WHERE abs(s.total_ev_charging_kw - t.kw_dc) > 0.2) AS mismatched,
       round(max(abs(s.total_ev_charging_kw - t.kw_dc)), 3) AS worst_kw
  FROM public.site_energy_snapshots s
  JOIN public.ottoq_power_node_ticks t
    ON t.sim_clock_at = s."timestamp" AND t.node_code = 'SERVICE' AND t.sim_run_id = s.sim_run_id
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111';
--
-- ══ (3) A TRIPPED TRANSFORMER: THE CARS FINISH ELSEWHERE (RULE 9) ═══════════════════════════════════════════════════
--
--   48-tick day, run 0911c1cf: TX-A1 tripped at sim 12:00 UTC for 90 minutes. Five posts faulted, two with a car
--   charging (at 96% and at 93%). Both cars were on a post under another transformer at 12:30 (TX-A2's post 10, TX-C2's
--   post 30) and both ended at 100%. The five posts were Available again after 13:30.
--   2-minute day, run 4c87dd16: TX-B1 tripped at sim 19:00 UTC (2:00 PM CT) for 60 minutes. Four posts faulted (the
--   fifth was already down with a fault of the twin's own), one with a car at 75%. That car was charging again at 19:02
--   on TX-C2's post 30 and ended at 100% at 19:34.
SELECT o.vehicle_id, s.stall_code, n.parent_code AS transformer, o.started_at, o.ended_at, o.soc_start, o.soc_end, o.stopped_reason
  FROM public.ocpp_sessions o
  JOIN public.stalls s ON s.id = o.stall_id
  JOIN public.ottoq_power_nodes n ON n.charger_id = s.ocpp_charger_id
 WHERE o.vehicle_id IN (SELECT vehicle_id FROM public.ocpp_sessions WHERE stopped_reason = 'fault.operator_injected')
 ORDER BY o.vehicle_id, o.started_at;
SELECT node_code, tripped_at_sim, recovers_at_sim, posts_under_node, posts_faulted, sessions_stopped, cars_on_posts
  FROM public.ottoq_power_node_trips WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY tripped_at_sim;
--
-- ══ (4) THE PURGE TAKES THE WORKING ROWS AND LEAVES THE STUDY ═══════════════════════════════════════════════════════
--
--   ottoq_purge_prior_runs on the 48-tick trip day's database (rolled back afterwards): 60,123 rows purged, the run
--   deleted; ottoq_power_node_ticks 528 -> 0, ottoq_power_node_study 41 -> 41, ottoq_power_node_trips 1 -> 1, and
--   ottoq_power_one_line still answers from the study. ottoq_check_run_scope_registry reports nothing on the three
--   tables.
--
-- ══ (5) WHAT ONE DAY DREW (run 4c87dd16: busy_day, seed 171717, 116 cars, 2-minute ticks, 6:00 AM to 8:00 PM CT) ════
--
--   One lab day, one seed, the fleet as it is: a single reading, not a range, and a reading of this fleet, which is
--   small for thirty posts. It is not a ceiling and sets none (rule 13: the ceiling comes after the build is finished
--   and tested). It shows what the instrument reads.
--
--     node      installed   peak      busiest half hour   energy through   lost in the unit   hottest   this day fits on
--     SERVICE   17,500 kVA  1,018 kVA   619 kVA (3.5%)      4,465 kWh net       411 kWh (all 7)      -         -
--     TX-A1      2,500 kVA    259 kVA   181 kVA               808 kWh            58.5 kWh           41.4 C      300 kVA
--     TX-A2      2,500 kVA    218 kVA   154 kVA               931 kWh            58.5 kWh           41.2 C      300 kVA
--     TX-B1      2,500 kVA    324 kVA   254 kVA               715 kWh            58.5 kWh           41.2 C      300 kVA
--     TX-B2      2,500 kVA    298 kVA   180 kVA               778 kWh            58.5 kWh           41.1 C      300 kVA
--     TX-C1      2,500 kVA    261 kVA   172 kVA               799 kWh            58.5 kWh           41.2 C      300 kVA
--     TX-C2      2,500 kVA    260 kVA   161 kVA               858 kWh            58.5 kWh           41.3 C      300 kVA
--     TX-AUX     2,500 kVA    985 kVA   359 kVA             2,120 kWh            59.8 kWh           45.0 C    1,000 kVA
--
--   (a) The cars took 4,595 kWh. The busiest half hour at the service was 619 kVA, 3.5% of the 17,500 kVA installed.
--       No charger transformer passed 13% of its rating. "This day fits on" is the smallest size on the list for six of
--       the seven, so for those the list's floor decided, not the day.
--   (b) No post delivered more than 122.5 kW (35% of its 350 kW), across 170 sessions. Not investigated here: whether
--       the cars' charge curves set that or something else does. If it is the cars, a 350 kW post is never asked for
--       more than about a third of its rating by this fleet.
--   (c) G533, with a number. The twin's site meter read 3,790 kWh net for the day. On the grid side of the chargers
--       and transformers the same day is 4,465 kWh net: 675 kWh more, 17.8%. About 293 kWh of that is the posts'
--       conversion at 94%; 411 kWh is the seven transformers' own losses, nearly all of it the no-load part, which a
--       2,500 kVA unit pays every hour whether or not a car is charging (58.5 kWh each over 14 hours, against 715 to
--       931 kWh carried). Both rest on assumed constants (94% at every load; losses 1.0% of rating, split 1:5), marked
--       in ottoq_power_nodes.provenance and asked of Hermes in R-22. The direction does not depend on them: a
--       transformer sized for every nameplate at once spends energy all day on a depot that uses a few percent of it.
--   (d) Temperatures: the hottest winding reading of the day was 45.0 C (TX-AUX), against 110 C where insulation ages
--       at its normal rate; the air ran 18.6 to 27.9 C. Each unit used about 0.002 hours of insulation life in 14.
SELECT st.node_code, st.rated_kva, round(st.peak_kva) AS peak_kva, st.peak_30min_kva,
       round(st.energy_kwh_ac) AS kwh_through, round(st.loss_kwh, 1) AS kwh_lost, st.max_hot_spot_c,
       st.rightsize->>'smallest_kva_this_day_fits' AS this_day_fits_on, st.sim_run_id
  FROM public.ottoq_power_node_study st
 WHERE st.depot_id = '11111111-1111-1111-1111-111111111111' AND st.kind IN ('transformer', 'utility_service')
 ORDER BY st.last_clock_at DESC, st.node_code;
--
-- ══ (6) FOUND ON THE WAY ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   G536  The twin generates solar from a canopy that was decommissioned. ottoq_canopy_state holds canopy_1..4 at
--         150 kW AC each; CANOPY-04's structure row is 'decommissioned', retired_in 0010_unify_depot_layout (read in
--         production 2026-11-11 05:00 UTC). On the 48-tick day canopy_4 made 759 of the depot's 2,993 kWh of solar, a
--         quarter. The site meter, the bill, the battery's forecast and the Value tab's power bill all read it. The five
--         carports are titled "Solar Carport" and carry no solar figure. Which is true (no fourth array, or arrays on
--         the carports) is Chase's call; either answer changes the energy atom and the battery forecast's world, so it
--         is its own certified change with an ottoq_evidence_regimes row. Not built.
--   G537  The 3D yard draws one transformer in the battery compound and no primary switchgear, for a depot the one-line
--         gives seven transformers. Where seven pad-mounted units stand is a site-plan decision. Not built.

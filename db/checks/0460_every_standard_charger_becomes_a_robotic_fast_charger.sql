-- 0460  **Every standard charger at the twin depot becomes a robotic fast charger: thirty posts, each with its charge arm
--        and its cleaning arm, and no power ceiling below what they can draw. The renderer, 0759, 0763 and the three
--        writes that put them on, in order.** -> G481.
--        Chase, 2026-10-21 at 6:52 AM CT: "Still don't see the additional DCFC robotic, charging and overhead Robo, vacuum
--        for the rest of the stalls. I see it on the original 10, but we discussed swapping out all of the L2's or 90% of
--        the L2's for DCFC ever bought charging arm with overhead robovac ." Reads against gxdrcyphqjzjsuhxuqtg on
--        2026-10-21 between 7:08 and 7:22 AM CT (12:08:42 UTC, the first query's clock, to 12:22:19 UTC, read before the
--        migration was written). The writes in §4 are held by the connector for Chase's confirmation; none is reworded or
--        sent another way. Each is named with the statement that undoes it.
--
-- ══ §1 WHY ONLY TEN (reproduce: (1)) ═══════════════════════════════════════════════════════════════════════════════════
--
--   The twin depot is built as it always was: 10 fast chargers on canopy A and 30 standard chargers on canopies B and C
--   (1). 0759 (canopy B, ten more posts) was written on 2026-10-19 and never applied: its P0 refuses while 32 research
--   sweeps and 8 dial experiments are active at the depot, and pausing them is an UPDATE the connector holds for Chase.
--   Nothing converted canopy C at all. So the app drew the ten robots canopy A has, and could draw no more.
--
-- ══ §2 THE BUILD ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Thirty is the most the site holds at this arm design (0759 §1): ten posts a canopy on the 14-unit pitch. So "all of
--   the L2's" is thirty robotic posts and no standard charger.
--     ottoyarddepot-sim #152   the renderer's 30-post build (dcfc30), drawn when the twin layout's census reads 30 + 0.
--                              Filmed in the local cockpit on a served layout re-striped the same way: the 2D plan drew
--                              30 charge arms and 30 cleaning arms, DCFC-01..30, and a canopy C car's doors opened and
--                              the cleaning arm worked its cabin, side A then side B. Thirty cars docked on thirty posts
--                              at once in its driver test, touching no car and no structure.
--     0759                     canopy B re-striped (unchanged; its P1 premises all hold on live, read at 7:13 AM CT).
--     0763                     canopy C re-striped, NASH-L2-STALL-31..35 retired, and the depot's limits what is
--                              installed (§3). 16 tests on the scratch PostgreSQL, 0759 applied first
--                              (tests/test_thirty_post_base_sql.py).
--
-- ══ §3 THE POWER: NO CEILING ON THE FRONT END (reproduce: (2), (3), (4)) ═══════════════════════════════════════════
--
--   0763 as first written held the thirty posts to 2,400 kW of shared cabinets on today's 2,500 kW service, with the
--   settings of the research wing's arm 112 (2): forty posts held there met 939.8 car-hours against 940.5 with power to
--   spare, served 215 visits against 205 and peaked at 1,750.4 kW against 2,128.4, every car at 100% (one seed). Chase,
--   2026-10-21, on reading it: "never base variable allocation of resources or throughput or up time or energy consumption
--   based on a hard ceiling until we have everything built out ... The vehicles needs take absolute precedence, and any
--   energy needed is consumed, and we have to fit around that." So 0763 now sets the depot's limits to what is installed,
--   which no car can reach (4): 10,500 kW DC, thirty posts at their 350 kW rating; 12,250 kW service, those plus the
--   battery charging at its 1,500 kW rating and 250 kW of building (the most the energy snapshots have read is 228.2 kW).
--   No setting changes: the held-site settings stay off, because the depot holds no limit to divide. What the thirty
--   posts draw is what a ceiling is later set from, when testing resumes (rule 12), and the margin under that ceiling is
--   worked on the operator's side (the battery, the tariff), never on a vehicle (CLAUDE.md rule 13). The held site stays
--   the build-out dcfc30_cab2400 (2,400/2,500) for that work; the build-out dcfc30 is the depot as built.
--
-- ══ §4 THE WRITES, IN ORDER ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   (W1) The research pause, (W1) below: the 32 active sweeps at the twin depot to 'paused' (a sweep has no other state
--        that keeps it, and nothing re-opens the window while we build, CLAUDE.md rule 12), and the 8 active dial
--        experiments to 'abandoned' (a dial experiment has no paused state; every one of their pairs ran on the depot
--        as built, and 0759's and 0763's lineage rows move the dial floor). Their pairs stay in the pair ledger.
--        Undo: (U1).
--   (W2) 0759, through apply_migration, as written.
--   (W3) 0763, through apply_migration, once ottoyarddepot-sim #152 is live (Lovable: Publish, then Update). Until then
--        the app keeps drawing canopy C as standard chargers.
--   Then one demo run on the new depot, the way the app's Start does, read for: the census and the posts it serves; cars
--   charging on canopy B and canopy C posts with an arm cycle each; the cleaning arm's tidies there; rule 9 at departure.
--   Checking a change in one demo run is part of building it (rule 12), not testing.
--
-- ══ QUERIES ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) the twin depot's census, power and research state
SELECT (SELECT jsonb_object_agg(stall_type::text, n) FROM (SELECT stall_type, count(*) n FROM public.stalls
          WHERE depot_id = '11111111-1111-1111-1111-111111111111' GROUP BY 1) x) AS census,
       (SELECT dcfc_max_concurrent_kw || '/' || service_max_kw FROM public.depots
         WHERE id = '11111111-1111-1111-1111-111111111111') AS power,
       (SELECT count(*) FROM public.ottoq_throughput_sweeps
         WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active') AS active_sweeps,
       (SELECT count(*) FROM public.ottoq_dial_experiments
         WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active') AS active_dial_experiments,
       (SELECT name FROM public.ottoq_cert_lineage WHERE name LIKE '0759%' OR name LIKE '0763%' ORDER BY 1 LIMIT 1) AS applied;

-- (2) the arms the power rests on
SELECT a.arm_id, s.sweep_code, a.seed, a.buildout->>'buildout_code' AS buildout,
       a.arm_metrics->>'deployed_car_hours' AS car_hours, a.arm_metrics->>'peak_site_kw' AS peak_kw,
       a.scorecard->'throughput'->>'visits_served' AS visits_served,
       a.scorecard->'rule9'->>'left_below_target' AS below_target,
       a.scorecard->'rule9'->>'left_with_needed_work_open' AS work_open
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
 WHERE a.arm_id IN (95, 107, 112, 117) ORDER BY a.arm_id;

-- (3) arm 112's cell: the held site's settings, kept for the margin work after a ceiling is set (none is written now)
SELECT c.cell_code, c.fixed_params
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
 WHERE a.arm_id = 112;

-- (4) what is installed: the chargers' ratings, the battery's and the most the building has drawn
SELECT (SELECT jsonb_object_agg(max_kw, n) FROM (SELECT max_kw, count(*) n FROM public.ottoq_ocpp_chargers
          WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND decommissioned_at IS NULL GROUP BY 1) c) AS chargers_by_kw,
       (SELECT max_charge_kw FROM public.ottoq_bess_units WHERE depot_id = '11111111-1111-1111-1111-111111111111') AS bess_charge_kw,
       (SELECT max(building_load_kw) FROM public.site_energy_snapshots
         WHERE depot_id = '11111111-1111-1111-1111-111111111111') AS building_max_kw;

-- (W1) the research pause
UPDATE public.ottoq_throughput_sweeps
   SET status = 'paused',
       notes = COALESCE(notes || ' | ', '')
               || 'Paused 2026-10-21 for the twin depot''s 30-post base change (0759, 0763; db/checks/0460). Testing is off '
               || 'while we build (CLAUDE.md rule 12). A cell run after it runs on the 30-post depot.'
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active';
UPDATE public.ottoq_dial_experiments
   SET status = 'abandoned', concluded_at = now(),
       verdict = jsonb_build_object(
         'by', 'claude_code_2026_10_21', 'outcome', 'abandoned_base_change', 'check', 'db/checks/0460', 'finding', 'G481',
         'why', 'Chase, 2026-10-21: every standard charger at the twin depot becomes a robotic fast charger (0759, 0763). '
                || 'Every pair of this experiment ran on the depot as built, and a pair read across the base change would '
                || 'compare two depots (forces_dial_restart). Testing is off while we build (CLAUDE.md rule 12). Its pairs '
                || 'stay in the pair ledger as evidence.',
         'recreate_when', 'testing resumes on Chase''s word, on the 30-post depot')
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active';

-- (U1) undo (W1), before 0759 is applied (after it, the cells would run on a depot their earlier arms did not)
-- UPDATE public.ottoq_throughput_sweeps SET status = 'active'
--  WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'paused' AND notes LIKE '%db/checks/0460%';
-- UPDATE public.ottoq_dial_experiments SET status = 'active', concluded_at = NULL, verdict = NULL
--  WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND verdict->>'check' = 'db/checks/0460';

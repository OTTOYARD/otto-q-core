-- 0460  **Every standard charger at the twin depot becomes a robotic fast charger: thirty posts, each with its charge arm
--        and its cleaning arm, on today's 2.5 MW service. The renderer, 0759, 0763 and the three writes that put them
--        on, in order.** -> G481.
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
--     0763                     canopy C re-striped, NASH-L2-STALL-31..35 retired, the depot on 2,400 kW of shared DC
--                              cabinets behind today's 2,500 kW service, and four settings (§3). 17 tests on the scratch
--                              PostgreSQL, 0759 applied first (tests/test_thirty_post_base_sql.py).
--
-- ══ §3 THE POWER: ONE ARM, AND WHAT IT SAYS (reproduce: (2), (3)) ═════════════════════════════════════════════════════
--
--   Chase's worry on 2026-10-17 was "massive megawatt usage". Thirty 350 kW posts are 10.5 MW of nameplate. The research
--   wing's arms at forty posts, normal day, in tick, seed 686364201590009433 (2):
--     arm 95   dcfc40, power to spare (7,200 kW DC, 8,089 kW service)          940.5 car-hours, 205 visits, peak 2,128.4 kW
--     arm 107  dcfc40_cab2400, held at the engineering cap, old first reading 915.3 car-hours, 209 visits, peak 1,574.8 kW
--     arm 112  dcfc40_cab2400, held, the first reading fixed (0733)          939.8 car-hours, 215 visits, peak 1,750.4 kW
--   Every arm left every car at 100% with nothing open. Arm 107's 25.2-car-hour gap was the twin's own first-reading
--   error (G448), and arm 112 closed it to 0.7 (0.07%). One seed. So the 30-post depot keeps today's service and shares
--   2,400 kW of cabinets, with arm 112's cell as its settings (3): dc_power_sharing, dc_power_managed and
--   dc_power_first_reading 1, enforce_site_charge_cap 0 (deploy_peak_fraction 0.9 is already the default and
--   twin_answer_in_tick already 1 at the depot). Not dc_power_by_need (its arm, 117, ran without the first reading and read
--   the same as 107) or site_cap_gate_metered (measured only with the command lag). A slower charge is queueing, never a
--   shorter charge (rule 9). The nameplate grid stays the build-out dcfc30 (5,400/6,226 kW); 0763 §7 names the statement
--   that makes it the base.
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

-- (3) arm 112's cell: the settings 0763 writes
SELECT c.cell_code, c.fixed_params
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
 WHERE a.arm_id = 112;

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

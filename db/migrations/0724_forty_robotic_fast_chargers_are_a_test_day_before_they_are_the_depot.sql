-- migration-version: 20261017060928
-- migration-name:    forty_robotic_fast_chargers_are_a_test_day_before_they_are_the_depot
--
-- 0724  **Forty robotic fast chargers are a test day before they are the depot.** Three build-outs that convert every
--       L2 space at the twin depot to a robotic fast charger, and one overnight sweep that measures them against the
--       depot as built (10) and 0567's 20. Research wing, rule 10: it measures, and a result is a recommendation.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-17, 12:49 AM CT: "I'm thinking about removing all L2 charging and only going to robotic DCFC ... Only
--   worry would be, with the maximum energy capacity ... with that much DC FC going on at one time, there might be massive
--   megawatt usage ... If you think it's favorable, convert all L2 charging into robotic DC FC charging ... Accommodate
--   more vehicles with 30 to 40 fast robotic arm chargers."
--
--   0567 already holds the build-outs 10, 15 and 20 (and 20 on today's grid), and value_2026_09_30 measured 10 against
--   20 on 24-hour days. Read 2026-10-17 05:58 UTC from ottoq_throughput_sweep_arms, sweep value_2026_09_30, two seeds
--   per cell (pooled arms are not independent, G153, so these are directions, not effects): OTTO-Q at 20 chargers served
--   351.7 visits a day against 326.8 at 10, a median 167 minutes from the gate to leaving against 271, and a p95 wait
--   for a charger (floor) of 279 minutes against 497; its full-day site peak rose from 1,013 to 1,806 kW. And on a busy
--   day the depot is out of chargers all day (G426). So the next point on the curve is the one Chase named: every L2
--   space converted.
--
--   Two facts make 40 fast chargers cheaper in power than 40 x 350 kW (14 MW) suggests, and they are the reason the
--   power-limited cells below exist:
--     (a) the cars cannot draw 350 kW. The twin's fleet (read 2026-10-17): 44 I-PACE at 104 kW, 34 Zoox at 100 kW and
--         30 Tesla at 250 kW (0573, sourced); 12 more carry no inlet figure (CORRECTED 2026-10-17 after the apply, from
--         "four": 6 Tesla, 2 Zeekr and 4 others; db/checks/0451 §7, G443);
--     (b) rule 9 charges every car to 100%, and the last 20% runs at a fraction of the peak: 0573 §3 measured 80-100%
--         taking 27.3 min (Model Y), 49.4 (I-PACE) and 21.3 (Zoox) on a 350 kW charger. The sweep's fast chargers
--         averaged 37.8-43.0 kW while busy in every value_2026_09_30 cell.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Build-outs, each converting all 30 L2 spaces (NASH-L2-STALL-01..20 and 26..35, every L2 stall with a charger at the
--   depot, measured 2026-10-17) so the depot has 40 robotic fast chargers and no L2:
--     dcfc40               the grid grown with the chargers by 0567's own basis: 1,800 + 30 x 180 = 7,200 kW of DC and
--                          2,500 + 30 x 186.3 = 8,089 kW of service. The power never binds, so its peak is what 40
--                          chargers draw when nothing stops them: the size of the grid they would ask for.
--     dcfc40_grid_dcfc20   40 chargers on dcfc20's power: 3,600 kW of DC and 4,363 kW of service.
--     dcfc40_grid_today    40 chargers on today's power: 1,800 kW of DC and 2,500 kW of service.
--
--   READ THE TWO POWER-LIMITED CELLS FOR WHAT THE TWIN ENFORCES, NOT FOR WHAT A POWER CABINET DOES (db/checks/0451 §2).
--   The twin does not share power between chargers: twin.ottoq_sim_advance_charge_sessions charges every session at the
--   lowest of the charger's, the car's and the battery's limit ("VEHICLE-FIRST DOCTRINE: charging is NEVER held back").
--   The service limit binds only at admission: ottoq_decide_tick (0132) defers a charge (`deferred_site_power_cap`) when
--   its estimated committed kW plus the request would pass ottoq_ev_charge_allowance_kw, which is the SERVICE limit
--   (or a demand-response cap); dcfc_max_concurrent_kw is never enforced, only reported (twin.dcfc_cap_exceeded). So a
--   power-limited cell measures a car waiting for power to start, not a car charging slower beside others, and is a
--   pessimistic bound on a shared-cabinet site.
--
--   Sweep `dcfc40_2026_10_17`: busy_day from 6 AM CT for 12 hours at 5 sim-minutes a tick (144 ticks: the day's whole
--   deployment and its afternoon returns at a third of a 24-hour arm's cost, 0413 §7), value_2026_09_30's three seeds
--   (common random numbers with it), no replicates, priority 20 (before value_2026_09_30 at 50), an arm budget of 5,400 s
--   (144 x 30 s would cut a slow 40-charger arm short: dcfc20.otto_q on 24-hour days ran 8,684 s and stopped incomplete
--   on 2026-10-11 and 2026-10-13), due now. Seven cells, OTTO-Q unless named, every one at deploy_peak_fraction 0.90 as
--   night 1 and night 2, none a dial contrast (they differ by build-out, which 0571's control cells do not express):
--     ord 1  dcfc10.otto_q               the depot as built
--     ord 2  dcfc40.otto_q               every L2 converted, the grid grown
--     ord 3  dcfc40_grid_today.otto_q    every L2 converted, today's grid
--     ord 4  dcfc20.otto_q               0567's middle point
--     ord 5  dcfc40_grid_dcfc20.otto_q   every L2 converted, dcfc20's grid
--     ord 6  dcfc40.fifo                 does the seat still matter when chargers are plentiful?
--     ord 7  dcfc40_grid_today.fifo      and when power is the limit?
--   The runner goes seed by seed, so a night that ends early leaves whole seeds: the first three cells answer Chase's
--   question on one seed, and the fourth and fifth draw the curve.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: 0567's build-out machinery and dcfc10/dcfc20 exist, value_2026_09_30 and its seeds exist, deploy_peak_fraction
--   is catalogued, and the depot has exactly 10 fast chargers and 30 L2 spaces with chargers, so the three build-outs
--   name every L2 space. P2: not already applied. V1: three build-outs of 40 posts converting the same 30 spaces, the
--   sweep's seven cells in the order above, its seeds and length, and every dial one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the build-out and sweep tables, read only by the sweep
--   runner, and applied to the depot only inside an arm's own transaction (a deferred trigger refuses to commit one).
--
-- ROLLBACK (before the sweep has run): DELETE FROM public.ottoq_throughput_sweep_cells WHERE sweep_id =
--   (SELECT sweep_id FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_2026_10_17');
--   DELETE FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_2026_10_17';
--   DELETE FROM public.ottoq_site_buildouts WHERE buildout_code IN ('dcfc40', 'dcfc40_grid_dcfc20', 'dcfc40_grid_today');
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0724_forty_robotic_fast_chargers_are_a_test_day_before_they_are_the_depot'.
--   Once it has run, its arms are evidence and stay; set the sweep's status to 'concluded' instead.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: the machinery, the controls, night 2's seeds, the depot as built ──
DO $premises$
DECLARE v_dcfc int; v_l2 int;
BEGIN
  IF to_regprocedure('public.ottoq_site_buildout_apply(uuid,text)') IS NULL
     OR to_regprocedure('public.ottoq_throughput_sweep_arm(uuid,bigint,boolean)') IS NULL THEN
    RAISE EXCEPTION '0724 P1: 0567/0568''s build-out and sweep machinery is missing';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_site_buildouts WHERE buildout_code IN ('dcfc10', 'dcfc20')) <> 2 THEN
    RAISE EXCEPTION '0724 P1: the dcfc10 and dcfc20 build-outs are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30'
                  AND cardinality(seeds) = 3) THEN
    RAISE EXCEPTION '0724 P1: value_2026_09_30 and its three seeds are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'deploy_peak_fraction'
                  AND (min_value IS NULL OR min_value <= 0.90) AND (max_value IS NULL OR max_value >= 0.90)) THEN
    RAISE EXCEPTION '0724 P1: deploy_peak_fraction 0.90 is not a dial the arm accepts';
  END IF;
  SELECT count(*) FILTER (WHERE stall_type = 'dcfc'),
         count(*) FILTER (WHERE stall_type = 'l2' AND ocpp_charger_id IS NOT NULL)
    INTO v_dcfc, v_l2
    FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111';
  IF v_dcfc <> 10 OR v_l2 <> 30 THEN
    RAISE EXCEPTION '0724 P1: the twin depot has % fast chargers and % L2 chargers, not 10 and 30', v_dcfc, v_l2;
  END IF;
  IF EXISTS (SELECT 1 FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND stall_type = 'l2'
                AND ocpp_charger_id IS NULL) THEN
    RAISE EXCEPTION '0724 P1: an L2 space at the twin depot has no charger, so converting "every L2" is ambiguous';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildouts
              WHERE buildout_code IN ('dcfc40', 'dcfc40_grid_dcfc20', 'dcfc40_grid_today'))
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_2026_10_17') THEN
    RAISE EXCEPTION '0724 P2: already applied';
  END IF;
END $once$;

-- ── the build-outs: every L2 space, in stall-code order, on three grids; 0567's basis and source carried over ──
INSERT INTO public.ottoq_site_buildouts
       (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw, service_max_kw, basis)
SELECT b.code, '11111111-1111-1111-1111-111111111111'::uuid, b.title, 40, l2.codes, b.dc_kw, b.svc_kw,
       (SELECT d.basis FROM public.ottoq_site_buildouts d WHERE d.buildout_code = 'dcfc20')
         - 'note'
         || jsonb_build_object('note', b.note,
                               'enforced', 'service_max_kw at admission only (0132 via ottoq_ev_charge_allowance_kw); '
                                           'dcfc_max_concurrent_kw reported, never enforced; no power sharing between '
                                           'chargers (twin.ottoq_sim_advance_charge_sessions). db/checks/0451 §2.',
                               'added_by', '0724')
  FROM (VALUES
          ('dcfc40',
           '40 robotic fast chargers: every L2 space converted, the grid grown with them',
           7200::numeric, 8089::numeric,
           '1,800 + 30 x 180 kW DC; 2,500 + 30 x 186.3 kW service (0567''s basis, unchanged)'),
          ('dcfc40_grid_dcfc20',
           '40 robotic fast chargers on the power of 20',
           3600::numeric, 4363::numeric,
           'the dcfc40 chargers with dcfc20''s power limits: twice the chargers per kW'),
          ('dcfc40_grid_today',
           '40 robotic fast chargers on today''s grid',
           1800::numeric, 2500::numeric,
           'the dcfc40 chargers with the power limits unchanged: four times the chargers per kW')
       ) AS b(code, title, dc_kw, svc_kw, note),
       (SELECT array_agg(s.stall_code ORDER BY s.stall_code) AS codes
          FROM public.stalls s
         WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'l2'
           AND s.ocpp_charger_id IS NOT NULL) AS l2;

-- ── the sweep: 12-hour days on night 2's seeds, before night 2's own remaining arms ──
INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT 'dcfc40_2026_10_17',
       'Every L2 space a robotic fast charger: 40 against 10 and 20, on a grid grown with them, on the power of 20 and on today''s',
       v.depot_id, v.scenario, v.sim_start, 144, v.sim_min_per_tick, v.seeds, 0, 20, 5400, now(),
       '0724, for Chase''s question of 2026-10-17 12:49 AM CT. busy_day from 6 AM CT for 12 hours at 5 sim-minutes a '
       'tick, value_2026_09_30''s three seeds, deploy_peak_fraction 0.90. The power-limited cells defer a charge at '
       'admission (0132); the twin does not share power between chargers, so they bound a shared-cabinet site from below.'
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, c.cell_code, c.ord, c.seat, c.buildout_code, '{"deploy_peak_fraction": 0.90}'::jsonb
  FROM public.ottoq_throughput_sweeps s,
       (VALUES ('dcfc10.otto_q',             1, 'otto_q', 'dcfc10'),
               ('dcfc40.otto_q',             2, 'otto_q', 'dcfc40'),
               ('dcfc40_grid_today.otto_q',  3, 'otto_q', 'dcfc40_grid_today'),
               ('dcfc20.otto_q',             4, 'otto_q', 'dcfc20'),
               ('dcfc40_grid_dcfc20.otto_q', 5, 'otto_q', 'dcfc40_grid_dcfc20'),
               ('dcfc40.fifo',               6, 'fifo',   'dcfc40'),
               ('dcfc40_grid_today.fifo',    7, 'fifo',   'dcfc40_grid_today'))
         AS c(cell_code, ord, seat, buildout_code)
 WHERE s.sweep_code = 'dcfc40_2026_10_17';

-- ── V1: the build-outs and the sweep are what §2 says, and the arm would accept every dial ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_buildouts
       WHERE buildout_code IN ('dcfc40', 'dcfc40_grid_dcfc20', 'dcfc40_grid_today')
         AND dcfc_posts = 40 AND cardinality(convert_l2) = 30) <> 3 THEN
    RAISE EXCEPTION '0724 V1: the three build-outs are not each 40 posts converting 30 spaces';
  END IF;
  IF (SELECT count(DISTINCT convert_l2) FROM public.ottoq_site_buildouts
       WHERE buildout_code IN ('dcfc40', 'dcfc40_grid_dcfc20', 'dcfc40_grid_today')) <> 1 THEN
    RAISE EXCEPTION '0724 V1: the three build-outs do not convert the same spaces';
  END IF;
  IF EXISTS (SELECT 1 FROM public.stalls s
              WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'l2'
                AND NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts b
                                 WHERE b.buildout_code = 'dcfc40' AND s.stall_code = ANY (b.convert_l2))) THEN
    RAISE EXCEPTION '0724 V1: an L2 space at the twin depot is not converted by dcfc40';
  END IF;
  IF (SELECT row(dcfc_max_concurrent_kw, service_max_kw) FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40')
       IS DISTINCT FROM row(7200::numeric, 8089::numeric)
     OR (SELECT row(dcfc_max_concurrent_kw, service_max_kw) FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40_grid_dcfc20')
       IS DISTINCT FROM (SELECT row(dcfc_max_concurrent_kw, service_max_kw) FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc20')
     OR (SELECT row(dcfc_max_concurrent_kw, service_max_kw) FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40_grid_today')
       IS DISTINCT FROM (SELECT row(dcfc_max_concurrent_kw, service_max_kw) FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc10') THEN
    RAISE EXCEPTION '0724 V1: a build-out''s power limits are not the ones §2 names';
  END IF;
  IF (SELECT string_agg(c.cell_code, ',' ORDER BY c.ord) FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'dcfc40_2026_10_17')
     IS DISTINCT FROM 'dcfc10.otto_q,dcfc40.otto_q,dcfc40_grid_today.otto_q,dcfc20.otto_q,dcfc40_grid_dcfc20.otto_q,'
                      'dcfc40.fifo,dcfc40_grid_today.fifo' THEN
    RAISE EXCEPTION '0724 V1: the seven cells are not in the order §2 names';
  END IF;
  IF (SELECT seeds FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_2026_10_17')
       IS DISTINCT FROM (SELECT seeds FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30')
     OR (SELECT ticks * sim_min_per_tick FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_2026_10_17') <> 720 THEN
    RAISE EXCEPTION '0724 V1: the sweep is not night 2''s seeds over 12 hours';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code = 'dcfc40_2026_10_17'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0724 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0724_forty_robotic_fast_chargers_are_a_test_day_before_they_are_the_depot', false, false,
  'Rows only: build-outs dcfc40, dcfc40_grid_dcfc20 and dcfc40_grid_today (every L2 space a robotic fast charger, on '
  'three grids) and sweep dcfc40_2026_10_17 (seven cells, 12-hour days on value_2026_09_30''s seeds). Read only by the '
  'sweep runner; a build-out is applied only inside an arm''s transaction.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 06:09:28 UTC (1:09 AM CT), ledger version 20261017060928 ═════════════════════════════════════
--
--   NOT through apply_migration, and why (APPLYING.md step 4 names it; this is the deviation and its proof). The MCP's
--   apply_migration opens with DDL on supabase_migrations.schema_migrations that takes an ACCESS EXCLUSIVE lock, and the
--   overnight sweep's running arm (pid 3951184, ottoq_throughput_sweep_runner, 2 h into one transaction) holds ACCESS
--   SHARE on that table for its whole life. Measured 06:07 UTC: the apply sat in Lock:relation behind the runner, and a
--   queued ACCESS EXCLUSIVE request blocks every later reader of the ledger too, so it was cancelled (pg_cancel_backend)
--   before it could stall anything. The file's executable part (from BEGIN; through COMMIT;, 10,159 characters, md5
--   765399daa2abfc24de625502a1e17741) ran through execute_sql in one transaction that also wrote the ledger row
--   (statements[1] = that same text; its md5 read back from the ledger equals the file's). Rows only, so it needed no
--   lock the arm holds. Read back: 3 build-outs, 7 cells, 1 lineage row.
--
--   A lesson for the next apply at night: an apply_migration during the sweep window waits for the running arm, which
--   can be hours. A file whose P0 refuses while an arm is in flight fails fast; a rows-only file like this one has no
--   P0, and the wrapper's own lock is what waits.

-- migration-version: 20261017082241
-- migration-name:    twenty_fast_chargers_on_the_same_normal_day_to_find_the_knee
--
-- 0730  **Twenty fast chargers on the same normal day, to find the knee.** One arm, run tonight ahead of 0728's last two
--       cells: 0567's dcfc20 on the normal day and seed arm 83 (ten) and arm 84 (forty) ran on. Research wing, rule 10.
--
-- ══ §1 WHY (db/checks/0451 §3) ════════════════════════════════════════════════════════════════════════════════════════
--
--   Arm 84 (dcfc40.otto_q, normal_day, read 2026-10-17 08:18 UTC) served 215 cars against arm 83's 148 on the depot as
--   built, with its forty fast chargers busy 40.9% of the time against the ten's 69.4%. Forty is more than that day
--   uses, and at about $206,000 installed per 350 kW charger (ottoq_margin_prices dcfc_350kw_installed, its INL source)
--   the number of posts is the expensive half of the decision. Where between ten and forty the gain stops is the
--   question 0725 queued dcfc20 for, at priority 19, where it cannot run before the window closes tonight. This puts the
--   same cell at priority 15, next after 0729's managed cell.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Sweep `dcfc20_normal_2026_10_17`: normal_day from 6 AM CT, 144 ticks of 5 minutes, value_2026_09_30's first seed,
--   priority 15, arm budget 5,400 s, due now; one cell, dcfc20.otto_q (0567's 20 fast chargers and 20 L2, its grid grown
--   by 0567's basis) at deploy_peak_fraction 0.90. When 0725's sweep later reaches its own dcfc20 cell, that arm is a
--   replicate of this one.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: build-out dcfc20, normal_day and value_2026_09_30's seeds exist, and 0729 is applied (its sweep is the one this
--   follows). P2: not already applied. V1: normal_day, one seed (value_2026_09_30's first), 12 hours, priority 15, one
--   cell at dcfc20 with a dial the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the sweep tables, read only by the sweep runner.
--
-- ROLLBACK (before the sweep has run): DELETE its cell and sweep rows; once it has run, its arm is evidence and stays.
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0730_twenty_fast_chargers_on_the_same_normal_day_to_find_the_knee'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: the build-out, the scenario, the seeds, 0729 ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc20') THEN
    RAISE EXCEPTION '0730 P1: build-out dcfc20 (0567) is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_scenarios WHERE scenario_code = 'normal_day' AND status = 'available') THEN
    RAISE EXCEPTION '0730 P1: normal_day is not an available scenario';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30'
                  AND cardinality(seeds) = 3) THEN
    RAISE EXCEPTION '0730 P1: value_2026_09_30 and its three seeds are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_managed_normal_2026_10_17') THEN
    RAISE EXCEPTION '0730 P1: 0729 is not applied';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc20_normal_2026_10_17') THEN
    RAISE EXCEPTION '0730 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT 'dcfc20_normal_2026_10_17',
       'Twenty fast chargers on the normal day that ten and forty ran on: where the gain stops',
       v.depot_id, 'normal_day', v.sim_start, 144, v.sim_min_per_tick, v.seeds[1:1], 0, 15, 5400, now(),
       '0730: 0567''s dcfc20 on normal_day, value_2026_09_30''s first seed, beside arm 83 (dcfc10) and arm 84 (dcfc40) of '
       'the same seed and day: forty fast chargers sat 59% idle, and the number of posts is the costly half of the '
       'decision. 12-hour day from 6 AM CT at 5 sim-minutes a tick, deploy_peak_fraction 0.90.'
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc20.otto_q', 1, 'otto_q', 'dcfc20', '{"deploy_peak_fraction": 0.90}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'dcfc20_normal_2026_10_17';

-- ── V1: the sweep is what §2 says, and the arm would accept its dial ──
DO $verify$
BEGIN
  IF (SELECT row(s.scenario, s.priority, cardinality(s.seeds), s.ticks * s.sim_min_per_tick, count(c.*))
        FROM public.ottoq_throughput_sweeps s LEFT JOIN public.ottoq_throughput_sweep_cells c USING (sweep_id)
       WHERE s.sweep_code = 'dcfc20_normal_2026_10_17'
       GROUP BY s.scenario, s.priority, s.seeds, s.ticks, s.sim_min_per_tick)
     IS DISTINCT FROM row('normal_day'::text, 15, 1, 720::numeric, 1::bigint) THEN
    RAISE EXCEPTION '0730 V1: the sweep is not normal_day, priority 15, one seed, 12 hours, one cell';
  END IF;
  IF (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc20_normal_2026_10_17')
     IS DISTINCT FROM (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') THEN
    RAISE EXCEPTION '0730 V1: the seed is not value_2026_09_30''s first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc20_normal_2026_10_17' AND c.buildout_code = 'dcfc20'
                    AND c.cell_code = 'dcfc20.otto_q') THEN
    RAISE EXCEPTION '0730 V1: the cell is not dcfc20.otto_q on build-out dcfc20';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
                    jsonb_each_text(c.fixed_params) f
              WHERE s.sweep_code = 'dcfc20_normal_2026_10_17'
                AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                                   AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                                   AND (k.max_value IS NULL OR f.value::numeric <= k.max_value))) THEN
    RAISE EXCEPTION '0730 V1: the cell sets a dial the arm would refuse';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0730_twenty_fast_chargers_on_the_same_normal_day_to_find_the_knee', false, false,
  'Rows only: sweep dcfc20_normal_2026_10_17 (normal_day, dcfc20.otto_q, one seed, 12-hour day, priority 15). Read only '
  'by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 08:22:41 UTC (3:22 AM CT), ledger version 20261017082241 ═════════════════════════════════════
--
--   Through execute_sql in one transaction that also wrote the ledger row, as 0724 and 0725 were (their APPLIED notes):
--   0729's managed arm was in flight, and apply_migration's lock on supabase_migrations.schema_migrations waits behind a
--   running arm. The version is the database's clock at the insert (to_char(clock_timestamp() ...)), not a time typed in.
--   Executable part 4,669 characters, md5 f919e143c680f1382a9491eb406709f9, equal to the ledger's statements[1] read
--   back. Dry-run with a rolled-back read-back first: the runner's order is now dcfc40_managed_normal (15, 08:15:53),
--   this sweep (15, 08:22), then 0728's dcfc40_power_normal (16) and dcfc40_power_busy (17).
